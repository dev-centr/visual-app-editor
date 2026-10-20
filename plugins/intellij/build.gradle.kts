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
    // No signing or publishing configured: see docs publishing guide.
}

tasks {
    test {
        useJUnit()
    }
}
