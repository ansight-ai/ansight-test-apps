pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "modal-surface-evidence"
include(":app")

val sdkRoot = providers.gradleProperty("ansightSdkRoot").orNull
    ?: "../../../ansight-sdk/src/android"
val sdkDirectory = file(sdkRoot)
require(sdkDirectory.isDirectory) {
    "Ansight SDK checkout not found at $sdkDirectory. Pass -PansightSdkRoot=/path/to/ansight-sdk/src/android."
}
includeBuild(sdkDirectory) {
    dependencySubstitution {
        substitute(module("ai.ansight:ansight-android")).using(project(":ansight"))
    }
}
