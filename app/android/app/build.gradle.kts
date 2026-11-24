import java.util.Properties

// Release signing: a key.properties file (local builds) or MUSIC_KEYSTORE_* environment
// variables (CI). Without either, release builds fall back to the debug key.
val keyProps = Properties().apply {
    val f = file(System.getenv("MUSIC_KEY_PROPERTIES") ?: "${System.getProperty("user.home")}/.config/music-signing/key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signing(name: String, env: String): String? = System.getenv(env) ?: keyProps.getProperty(name)

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.v3ai.music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.v3ai.music"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val store = signing("storeFile", "MUSIC_KEYSTORE_FILE")
            if (store != null) {
                storeFile = file(store)
                storePassword = signing("storePassword", "MUSIC_KEYSTORE_PASSWORD")
                keyAlias = signing("keyAlias", "MUSIC_KEY_ALIAS") ?: "music"
                keyPassword = signing("keyPassword", "MUSIC_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val release = signingConfigs.getByName("release")
            signingConfig = if (release.storeFile != null) release else signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
