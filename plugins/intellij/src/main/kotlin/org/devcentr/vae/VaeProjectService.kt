package org.devcentr.vae

import com.intellij.notification.NotificationGroupManager
import com.intellij.notification.NotificationType
import com.intellij.openapi.Disposable
import com.intellij.openapi.application.ApplicationManager
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.components.Service
import com.intellij.openapi.diagnostic.logger
import com.intellij.openapi.editor.Document
import com.intellij.openapi.fileEditor.FileDocumentManager
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.VirtualFile
import org.devcentr.vae.rpc.RpcClient
import org.devcentr.vae.rpc.RpcError
import org.devcentr.vae.rpc.asList
import org.devcentr.vae.rpc.asMap
import org.devcentr.vae.rpc.str
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

/** What the tool window shows. Immutable snapshot, published on the EDT. */
data class ViewState(
    val file: VirtualFile? = null,
    val relPath: String? = null,
    val pages: List<String> = emptyList(),
    val page: String? = null,
    val root: Node? = null,
    val palette: List<WidgetSpec> = emptyList(),
    val presets: List<DevicePreset> = emptyList(),
    val device: String? = null,
    val status: String = "Open a .dart, .tsx or .jsx file",
    val error: String? = null,
)

/**
 * Owns one `vae_service` process per IDE project and keeps it in sync with
 * the editor buffer. All service calls run off the EDT; document changes are
 * applied with [WriteCommandAction] so they are undoable as one step.
 */
@Service(Service.Level.PROJECT)
class VaeProjectService(private val project: Project) : Disposable {
    private val log = logger<VaeProjectService>()
    private var process: Process? = null
    private var rpc: RpcClient? = null
    private var openRoot: String? = null
    private val stderrTail = StringBuffer()
    private val listeners = CopyOnWriteArrayList<(ViewState) -> Unit>()

    @Volatile var state = ViewState()
        private set

    fun addListener(parent: Disposable, l: (ViewState) -> Unit) {
        listeners += l
        com.intellij.openapi.util.Disposer.register(parent) { listeners -= l }
        l(state)
    }

    private fun publish(s: ViewState) {
        state = s
        ApplicationManager.getApplication().invokeLater({ for (l in listeners) l(s) }, project.disposed)
    }

    private fun background(what: String, f: () -> Unit) {
        ApplicationManager.getApplication().executeOnPooledThread {
            try {
                f()
            } catch (e: Exception) {
                val msg = errorText(e)
                log.info("$what failed: $msg")
                publish(state.copy(error = msg, status = "$what failed"))
            }
        }
    }

    private fun errorText(e: Throwable): String {
        val c = if (e is ExecutionException && e.cause != null) e.cause!! else e
        return when (c) {
            is RpcError -> c.message ?: "error ${c.code}"
            else -> c.message ?: c.toString()
        } + stderrTail.toString().takeLast(800).let { if (it.isBlank() || rpc?.isClosed != true) "" else "\n$it" }
    }

    private fun call(method: String, params: Map<String, Any?> = emptyMap()): Any? {
        val c = rpc ?: throw IllegalStateException("Service not running")
        return try {
            c.request(method, params).get(60, TimeUnit.SECONDS)
        } catch (e: ExecutionException) {
            throw e.cause ?: e
        }
    }

    // ---- lifecycle -------------------------------------------------------

    @Synchronized
    private fun ensureService(projectRoot: String) {
        if (rpc != null && rpc?.isClosed == false && process?.isAlive == true) return
        stop()
        val settings = VaeSettings.get().state
        val cmd = settings.serviceCommand.ifBlank { ServiceCommand.autodetect(project.basePath) ?: "" }
        if (cmd.isBlank()) {
            throw IllegalStateException("No Visual App Editor service configured. Set it in Settings | Tools | Visual App Editor (a vae_service executable or `dart run <repo>/packages/service/bin/vae_service.dart`).")
        }
        val argv = ServiceCommand.argv(cmd)
        publish(state.copy(status = "Starting ${argv.joinToString(" ")}", error = null))
        val p = try {
            ProcessBuilder(argv).directory(File(projectRoot)).start()
        } catch (e: Exception) {
            throw IllegalStateException("Could not start the service (${argv.joinToString(" ")}): ${e.message}")
        }
        process = p
        stderrTail.setLength(0)
        Thread({
            p.errorStream.bufferedReader().forEachLine { line ->
                stderrTail.append(line).append('\n')
                if (stderrTail.length > 4000) stderrTail.delete(0, stderrTail.length - 4000)
            }
        }, "vae-service-stderr").apply { isDaemon = true; start() }
        rpc = RpcClient(p.inputStream, p.outputStream) { method, params -> onNotification(method, params) }
        call("initialize", initializeParams(settings))
        openRoot = null
    }

    private fun initializeParams(s: VaeSettings.S): Map<String, Any?> {
        val out = linkedMapOf<String, Any?>("clientName" to "intellij")
        val react = s.reactAdapterCommand.trim()
        if (react.isNotEmpty()) {
            val argv = ServiceCommand.argv(react)
            out["externalAdapters"] = listOf(mapOf("id" to "react", "extensions" to listOf(".tsx", ".jsx"), "command" to argv))
            // adapters/react/dist/cli.js -> adapters/react/toolkits/*.sdl
            val cli = argv.lastOrNull { it.endsWith(".js") }?.let { File(it) }
            val kits = cli?.parentFile?.parentFile?.let { File(it, "toolkits") }
            val sdl = kits?.listFiles { f -> f.name.endsWith(".sdl") }?.map { it.readText() }.orEmpty()
            if (sdl.isNotEmpty()) out["manifests"] = sdl
        }
        return out
    }

    private fun onNotification(method: String, params: Map<String, Any?>) {
        if (method == "window/logMessage" && params.str("type") == "error") {
            NotificationGroupManager.getInstance().getNotificationGroup("Visual App Editor")
                .createNotification(params.str("message") ?: "Service error", NotificationType.ERROR)
                .notify(project)
        }
    }

    @Synchronized
    private fun stop() {
        val c = rpc
        rpc = null
        if (c != null && !c.isClosed) runCatching { c.request("shutdown").get(2, TimeUnit.SECONDS) }
        c?.close()
        process?.let { p ->
            if (!p.waitFor(2, TimeUnit.SECONDS)) p.descendants().forEach { it.destroy() }.also { p.destroy() }
        }
        process = null
        openRoot = null
    }

    fun restart() {
        background("Restart") {
            stop()
            state.file?.let { loadNow(it) }
        }
    }

    override fun dispose() {
        stop()
    }

    // ---- documents -------------------------------------------------------

    private fun projectRootFor(vf: VirtualFile): String? {
        var d = vf.parent
        while (d != null) {
            if (d.findChild("pubspec.yaml") != null || d.findChild("package.json") != null) return d.path
            d = d.parent
        }
        return null
    }

    private fun supported(vf: VirtualFile) = vf.extension?.lowercase() in setOf("dart", "tsx", "jsx")

    fun load(vf: VirtualFile?) {
        if (vf == null || !supported(vf)) {
            publish(state.copy(file = null, relPath = null, root = null, pages = emptyList(), page = null, status = "Open a .dart, .tsx or .jsx file", error = null))
            return
        }
        background("Load") { loadNow(vf) }
    }

    private fun documentText(vf: VirtualFile): Pair<Document?, String> = ApplicationManager.getApplication().runReadAction(com.intellij.openapi.util.Computable<Pair<Document?, String>> {
        val d = FileDocumentManager.getInstance().getDocument(vf)
        d to (d?.text ?: String(vf.contentsToByteArray(), vf.charset))
    })

    private fun loadNow(vf: VirtualFile, pageName: String? = null) {
        val root = projectRootFor(vf) ?: run {
            publish(state.copy(file = vf, root = null, status = "No pubspec.yaml or package.json above ${vf.name}", error = null))
            return
        }
        ensureService(root)
        var palette = state.palette
        var presets = state.presets
        var device = state.device
        if (openRoot != root) {
            val open = call("project/open", mapOf("root" to root)).asMap()
            openRoot = root
            palette = call("toolkit/palette").asList().map { WidgetSpec.from(it) }
            presets = call("device/presets").asList().map { DevicePreset.from(it) }
            device = open["config"].asMap().str("device")
        }
        val rel = File(vf.path).relativeTo(File(root)).invariantSeparatorsPath
        val (_, text) = documentText(vf)
        val synced = call("document/sync", mapOf("file" to rel, "source" to text)).asMap()
        val pages = synced["pages"].asList().mapNotNull { it.asMap().str("name") }
        val page = pageName?.takeIf { it in pages } ?: state.page?.takeIf { it in pages && state.file == vf } ?: pages.firstOrNull()
        val tree = page?.let { Node.from(call("document/tree", mapOf("file" to rel, "page" to it)).asMap()["root"]) }
        publish(
            ViewState(
                file = vf, relPath = rel, pages = pages, page = page, root = tree, palette = palette, presets = presets, device = device,
                status = if (page == null) "No pages (widgets/components) in ${vf.name}" else "$page  ·  ${vf.name}", error = null,
            ),
        )
    }

    fun selectPage(name: String) {
        val vf = state.file ?: return
        background("Load") { loadNow(vf, name) }
    }

    fun refresh() {
        state.file?.let { vf -> background("Refresh") { loadNow(vf, state.page) } }
    }

    /** Sends one edit op for the current page and applies the result to the IDE document (undoable). */
    fun edit(label: String, op: Map<String, Any?>) {
        val s = state
        val vf = s.file ?: return
        val rel = s.relPath ?: return
        val page = s.page ?: return
        background(label) {
            val (doc, text) = documentText(vf)
            call("document/sync", mapOf("file" to rel, "source" to text))
            val r = call("document/edit", mapOf("file" to rel, "page" to page, "op" to op)).asMap()
            val next = r.str("source") ?: return@background
            applyToDocument(vf, doc, text, next, label)
            val tree = r["page"].asMap()["root"]?.let { Node.from(it) } ?: s.root
            publish(state.copy(root = tree, status = "$label  ·  ${vf.name}", error = null))
        }
    }

    private fun applyToDocument(vf: VirtualFile, doc: Document?, before: String, after: String, label: String) {
        val change = TextDiff.minimal(before, after) ?: return
        ApplicationManager.getApplication().invokeAndWait {
            val d = doc ?: FileDocumentManager.getInstance().getDocument(vf) ?: return@invokeAndWait
            if (d.text != before) throw IllegalStateException("${vf.name} changed while editing; try again")
            WriteCommandAction.runWriteCommandAction(project, "Visual App Editor: $label", "visual-app-editor", {
                d.replaceString(change.start, change.oldEnd, change.text)
            })
        }
    }

    fun setDevice(id: String) {
        VaeSettings.get().state.devicePreset = id
        publish(state.copy(device = id))
        // Persist in the project's visual_app_editor.sdl too, so the desktop app agrees.
        if (openRoot != null) background("Device") { call("project/setConfig", mapOf("device" to id)) }
    }

}
