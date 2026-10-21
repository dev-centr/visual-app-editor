import org.jetbrains.intellij.platform.gradle.tasks.VerifyPluginTask

plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.intellij.platform")
}

group = "org.devcentr"
version = providers.gradleProperty("pluginVersion").get()

kotlin {
    jvmToolchain(25)
    compilerOptions {
        // Don't emit bridges for platform interface defaults (avoids verifier deprecation noise).
        jvmDefault.set(org.jetbrains.kotlin.gradle.dsl.JvmDefaultMode.NO_COMPATIBILITY)
    }
}

val localPlatform = providers.gradleProperty("platformLocalPath").orNull?.takeIf { it.isNotBlank() }

dependencies {
    testImplementation("junit:junit:4.13.2")

    intellijPlatform {
        if (localPlatform != null) local(localPlatform) else intellijIdea(providers.gradleProperty("platformVersion"))
    }
}

intellijPlatform {
    pluginConfiguration {
        version = providers.gradleProperty("pluginVersion")
        changeNotes = providers.fileContents(rootProject.layout.projectDirectory.file("../../CHANGELOG.adoc")).asText.map { adoc ->
            // Newest date's rows of the CHANGELOG.adoc table ("| date" then "| text") as HTML.
            // Self-contained lambda (no script references) for the configuration cache.
            val esc = { s: String ->
                s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                    .replace(Regex("(https?://[^\\s\\[]+)\\[([^\\]]+)]"), "<a href=\"$1\">$2</a>")
                    .replace(Regex("`([^`]+)`"), "<code>$1</code>")
                    .replace(Regex("\\*([^*]+)\\*"), "<b>$1</b>")
            }
            val dateRow = Regex("^\\| (\\d{4}-\\d{2}-\\d{2})\\s*$")
            val lines = adoc.lines().map { it.trimEnd() }
            val rows = lines.indices.mapNotNull { i ->
                dateRow.find(lines[i])?.let { m -> m.groupValues[1] to lines.getOrNull(i + 1)?.removePrefix("| ").orEmpty() }
            }
            val newest = rows.firstOrNull()?.first
            val out = StringBuilder()
            if (newest != null) {
                out.append("<b>").append(newest).append("</b><ul>")
                rows.filter { it.first == newest }.forEach { out.append("<li>").append(esc(it.second)).append("</li>") }
                out.append("</ul>")
            }
            out.append("<p><a href=\"https://docs.devcentr.org/visual-app-editor/changelog.html\">Full changelog</a></p>").toString()
        }
        ideaVersion {
            sinceBuild = providers.gradleProperty("pluginSinceBuild")
            untilBuild = provider { null }
        }
    }
    pluginVerification {
        failureLevel = listOf(
            VerifyPluginTask.FailureLevel.COMPATIBILITY_PROBLEMS,
            VerifyPluginTask.FailureLevel.INVALID_PLUGIN,
            VerifyPluginTask.FailureLevel.MISSING_DEPENDENCIES,
        )
        ides {
            recommended()
        }
    }
    // Used by the release workflow (.github/workflows/release.yml). signPlugin is
    // skipped when CERTIFICATE_CHAIN / PRIVATE_KEY are not set.
    signing {
        certificateChain = providers.environmentVariable("CERTIFICATE_CHAIN")
        privateKey = providers.environmentVariable("PRIVATE_KEY")
        password = providers.environmentVariable("PRIVATE_KEY_PASSWORD")
    }
    publishing {
        token = providers.environmentVariable("JETBRAINS_MARKETPLACE_TOKEN")
    }
}

tasks {
    test {
        useJUnit()
    }
}
