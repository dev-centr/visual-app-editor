package org.devcentr.vae

import org.devcentr.vae.rpc.RpcClient
import org.devcentr.vae.rpc.RpcError
import org.devcentr.vae.rpc.asList
import org.devcentr.vae.rpc.asMap
import org.devcentr.vae.rpc.str
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit

/**
 * Drives the real vae_service the way the plugin does. Runs when
 * VAE_SERVICE_TEST_CMD is set (CI sets it to `dart run <repo>/packages/service/bin/vae_service.dart`).
 */
class ServiceIntegrationTest {
    @Test fun editRoundTripThroughTheService() {
        val cmd = System.getenv("VAE_SERVICE_TEST_CMD")
        assumeTrue("VAE_SERVICE_TEST_CMD not set", !cmd.isNullOrBlank())
        val repo = File(System.getenv("VAE_REPO_ROOT") ?: "../..").canonicalFile
        val sample = kotlin.io.path.createTempDirectory("vae-ij").toFile()
        File(repo, "packages/service/test/sample_app").copyRecursively(sample)
        val p = ProcessBuilder(ServiceCommand.argv(cmd!!)).directory(repo).redirectError(ProcessBuilder.Redirect.INHERIT).start()
        val c = RpcClient(p.inputStream, p.outputStream)
        fun call(m: String, params: Map<String, Any?> = emptyMap()) = c.request(m, params).get(120, TimeUnit.SECONDS)
        try {
            call("initialize", mapOf("clientName" to "intellij-test"))
            val open = call("project/open", mapOf("root" to sample.path)).asMap()
            assertTrue(open["pages"].asList().any { it.asMap().str("name") == "HomePage" })
            val rel = "lib/pages/home_page.dart"
            // Unsaved buffer text: the plugin syncs before every edit.
            val buffer = File(sample, rel).readText().replace("Good morning", "Good evening")
            val synced = call("document/sync", mapOf("file" to rel, "source" to buffer)).asMap()
            assertEquals(true, synced["changed"])
            val tree = Node.from(call("document/tree", mapOf("file" to rel, "page" to "HomePage")).asMap()["root"])
            assertEquals("Scaffold", tree.type)
            val palette = call("toolkit/palette").asList().map { WidgetSpec.from(it) }
            val scaffold = palette.first { it.className == "Scaffold" }
            assertTrue(Props.rows(tree, scaffold).first { it.name == "backgroundColor" }.value.isEmpty())
            val r = call("document/edit", mapOf("file" to rel, "page" to "HomePage", "op" to mapOf("op" to "setArgument", "path" to tree.path, "name" to "backgroundColor", "value" to "Colors.amber"))).asMap()
            val next = r.str("source")!!
            assertTrue(next.contains("Good evening"))
            assertTrue(next.contains("backgroundColor: Colors.amber"))
            val change = TextDiff.minimal(buffer, next)!!
            assertEquals(next, TextDiff.apply(buffer, change))
            assertTrue("minimal diff, not a whole-file replace", change.oldEnd - change.start < 10)
            val presets = call("device/presets").asList().map { DevicePreset.from(it) }
            assertEquals(setOf("phone", "tablet", "desktop", "web"), presets.map { it.mode }.toSet())
            try {
                call("document/edit", mapOf("file" to rel, "page" to "HomePage", "op" to mapOf("op" to "removeNode", "path" to tree.path)))
                assertTrue("root removal must be rejected", false)
            } catch (e: ExecutionException) {
                assertTrue(e.cause is RpcError)
            }
            call("shutdown")
            assertTrue(p.waitFor(30, TimeUnit.SECONDS))
        } finally {
            c.close()
            p.destroy()
        }
    }
}
