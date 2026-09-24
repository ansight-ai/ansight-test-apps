plugins { id("com.android.application") }

android {
    namespace = "dev.sdkless.notes"
    compileSdk = 34
    defaultConfig {
        applicationId = "ai.ansight.testapps.sdklessnotes"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "dev.sdkless.notes.StoreInstrumentation"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Intentionally no runtime dependencies, SDK plugins, or composite SDK builds.
