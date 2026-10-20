package org.devcentr.vae

import java.io.File

/** Turns the configured service command into a process argv, resolving Windows .bat/.cmd shims. */
object ServiceCommand {
    /** Splits a command line honouring double quotes ("C:\Program Files\x\y.exe" arg). */
    fun split(cmd: String): List<String> {
        val out = ArrayList<String>()
        val cur = StringBuilder()
        var quoted = false
        var has = false
        for (c in cmd) {
            when {
                c == '"' -> { quoted = !quoted; has = true }
                c.isWhitespace() && !quoted -> {
                    if (has) out += cur.toString()
                    cur.setLength(0)
                    has = false
                }
                else -> { cur.append(c); has = true }
            }
        }
        if (has) out += cur.toString()
        return out
    }

    fun resolveExecutable(name: String, windows: Boolean, path: String?, pathExt: String?): String? {
        val f = File(name)
        if (f.isAbsolute || name.contains('/') || name.contains('\\')) {
            if (f.isFile) return f.path
            if (windows) for (e in exts(pathExt)) File(name + e).takeIf { it.isFile }?.let { return it.path }
            return null
        }
        for (dir in (path ?: "").split(File.pathSeparatorChar).filter { it.isNotBlank() }) {
            if (windows) {
                for (e in listOf("") + exts(pathExt)) File(dir, name + e).takeIf { it.isFile && (e.isNotEmpty() || name.contains('.')) }?.let { return it.path }
            } else {
                File(dir, name).takeIf { it.isFile && it.canExecute() }?.let { return it.path }
            }
        }
        return null
    }

    private fun exts(pathExt: String?) = (pathExt ?: ".COM;.EXE;.BAT;.CMD").split(';').filter { it.isNotBlank() }.map { it.lowercase() }

    /** argv ready for ProcessBuilder; wraps batch shims with cmd.exe on Windows. */
    fun argv(cmd: String, windows: Boolean = isWindows, path: String? = System.getenv("PATH"), pathExt: String? = System.getenv("PATHEXT")): List<String> {
        val parts = split(cmd)
        require(parts.isNotEmpty()) { "Empty service command" }
        val exe = resolveExecutable(parts[0], windows, path, pathExt) ?: parts[0]
        val rest = parts.drop(1)
        return if (windows && (exe.endsWith(".bat", true) || exe.endsWith(".cmd", true))) listOf("cmd.exe", "/c", exe) + rest else listOf(exe) + rest
    }

    val isWindows: Boolean get() = System.getProperty("os.name").startsWith("Windows")

    /**
     * Default when nothing is configured: VAE_SERVICE env, then `vae_service` on PATH,
     * then the service sources inside the open project (working on this repo itself).
     */
    fun autodetect(projectRoot: String?): String? {
        System.getenv("VAE_SERVICE")?.takeIf { it.isNotBlank() }?.let { return it }
        resolveExecutable("vae_service", isWindows, System.getenv("PATH"), System.getenv("PATHEXT"))?.let { return "\"$it\"" }
        var dir = projectRoot?.let { File(it) }
        while (dir != null) {
            val bin = File(dir, "packages/service/bin/vae_service.dart")
            if (bin.isFile) return "dart run \"${bin.path}\""
            dir = dir.parentFile
        }
        return null
    }
}
