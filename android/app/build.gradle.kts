plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("KAGO_ANDROID_KEYSTORE")
val releaseKeystorePassword = System.getenv("KAGO_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("KAGO_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("KAGO_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "net.usekago.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "net.usekago.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // arm64 only (nearly every phone): one APK with one versionCode, so every
        // new version installs over the previous one. Do not use --split-per-abi:
        // it adds 1000*ABI to the versionCode and breaks in-place updates.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        // versionCode = major*10000 + minor*100 + patch (pubspec.yaml build
        // number, checked by test/version_test.dart).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("kagoRelease") {
                storeFile = file(requireNotNull(releaseKeystorePath))
                storePassword = requireNotNull(releaseKeystorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeyPassword)
            }
        }
    }

    buildTypes {
        release {
            // KaGoVpnService.resolvePackage is called only from JNI.
            proguardFiles("proguard-rules.pro")
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("kagoRelease")
            } else if (System.getenv("KAGO_ANDROID_DEBUG_SIGNING") == "true") {
                // Тестовая сборка (CI без ключа): подпись debug-ключом, чтобы APK можно было установить.
                // Не для публикации: ключ одноразовый, обновление поверх такой сборки не установится.
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            // Only arm64: the Flutter plugin and plugins would otherwise add
            // x86_64/armv7 copies (the x86_64 core alone is ~56 MB).
            excludes += listOf("lib/x86_64/**", "lib/x86/**", "lib/armeabi-v7a/**")
            // Compress native libraries in the APK: the Go core shrinks from
            // ~53 MB to about half. Android extracts them once at install.
            useLegacyPackaging = true
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

// The Mihomo core is built from source (tool/build_android_native.*) and not
// kept in git: a release APK without it, or with a stale copy from elsewhere,
// must not be produced silently.
val mihomoCoreLib = file("src/main/jniLibs/arm64-v8a/libkago_mihomo_bridge.so")
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        check(mihomoCoreLib.isFile) {
            "Нет ядра Mihomo: сначала соберите его (tool/build_android_native.sh или .ps1)."
        }
    }
}
