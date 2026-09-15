plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "ai.ansight.backgroundtranscription"
    compileSdk = 35

    defaultConfig {
        applicationId = "ai.ansight.testapps.backgroundtranscription"
        minSdk = 35
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets["main"].assets.srcDir("../../fixtures")

    lint {
        // API 35 is the subject of this spike; dependency versions mirror the SDK harness toolchain.
        disable += setOf("OldTargetApi", "GradleDependency")
    }
}

dependencies {
    implementation("ai.ansight:ansight-android:1.4.0")
    implementation("androidx.activity:activity-ktx:1.10.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}
