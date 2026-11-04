plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.nt_f.echowall"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.nt_f.echowall"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Releases are signed with Echo-Wall's own key, the same for every build, so a new version installs over the old
    // one (Android refuses an update signed with another key).  CI and a release build on the maintainer's PC give it
    // by ECHO_WALL_KEYSTORE (+ _PASSWORD, _ALIAS); anyone else's build falls back to the debug key, which installs fine
    // but cannot update a released Echo-Wall in place.
    val ks = System.getenv("ECHO_WALL_KEYSTORE")?.takeIf { it.isNotEmpty() && file(it).exists() }
    signingConfigs {
        if (ks != null) create("release") {
            storeFile = file(ks)
            storePassword = System.getenv("ECHO_WALL_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("ECHO_WALL_KEY_ALIAS") ?: "echowall"
            keyPassword = System.getenv("ECHO_WALL_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (ks != null) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}
