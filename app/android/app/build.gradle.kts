import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// Firebase is optional for local contributors. Apply Google Services only for
// a real config; missing or placeholder files must not make debug builds fail.
val googleServicesFile = file("google-services.json")
val hasFirebaseConfig = googleServicesFile.isFile && Regex(
    "\\\"mobilesdk_app_id\\\"\\s*:\\s*\\\"1:[0-9]+:android:[0-9a-fA-F]+\\\"",
).containsMatchIn(googleServicesFile.readText()) && Regex(
    "\\\"package_name\\\"\\s*:\\s*\\\"xyz\\.qingliao\\.app\\\"",
).containsMatchIn(googleServicesFile.readText())
if (hasFirebaseConfig) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle("Firebase config not found; building without Firebase Analytics")
}

// Release signing (Nekoko LLC). Credentials live in android/key.properties
// (git-ignored). When absent, release falls back to debug signing so CI and
// fresh clones still build.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val sentryDsn = providers.environmentVariable("SENTRY_DSN").orNull.orEmpty()
val sentryEnvironment = providers.environmentVariable("SENTRY_ENVIRONMENT").orNull ?: "production"

android {
    namespace = "xyz.qingliao.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // 轻聊 keeps the 0.x applicationId so it upgrades in place; the Kotlin
        // namespace stays xyz.qingliao.app (source package only).
        applicationId = "xyz.qingliao.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The prebuilt TDLib (tdjson) artifacts target API 23. The manifest-aware
        // helper installs jniLibs/<abi>/libtdjson.so for Gradle to bundle.
        // The owned video-message recorder uses Flutter's CameraX backend,
        // whose supported Android floor is API 24.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["sentryDsn"] = sentryDsn
        manifestPlaceholders["sentryEnvironment"] = sentryEnvironment
        // arm64-only APK: plugin AARs otherwise merge every ABI's .so.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    sourceSets {
        getByName("main") {
            // Flutter owns src/main/assets during builds; keep this stable source
            // for Android Developer Verification while packaging it as an APK asset.
            assets.srcDir("src/developerVerification/assets")
        }
    }

    packaging {
        jniLibs {
            // The APK is distributed directly from CI. Store native libraries
            // compressed so the arm64 APK is small enough for Telegram upload;
            // Android will extract them at install time.
            useLegacyPackaging = true
            // FVP/MDK/FFmpeg is not used on Android (ExoPlayer is). Shipping
            // those .so files blew the arm64 APK past the 50 MB budget.
            excludes += listOf(
                "**/libffmpeg.so",
                "**/libmdk.so",
                "**/libass.so",
                "**/libfvp.so",
                "lib/armeabi/**",
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Signed with the Nekoko LLC release key when android/key.properties
            // is present; otherwise debug-signed so CI / fresh clones still build.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // ntgcalls (and other native plugins) resolve their Java classes by name
            // from native code via JNI (GetStaticMethodID); R8 obfuscation renames
            // those classes → JniAbort/SIGABRT at runtime in release (debug doesn't
            // minify, so it ran fine). The Java/Kotlin surface here is tiny — the APK
            // is almost entirely native .so + Dart AOT, which R8 can't shrink — so
            // disabling minification costs ~nothing and avoids release-only JNI crashes.
            isMinifyEnabled = false
            isShrinkResources = false
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

dependencies {
    implementation("androidx.webkit:webkit:1.14.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // FlutterFragmentActivity and the local_auth launch theme require AppCompat.
    implementation("androidx.appcompat:appcompat:1.8.0")
    // Edge-to-edge: WindowCompat.setDecorFitsSystemWindows.
    implementation("androidx.core:core-ktx:1.18.0")
    // MediaSession + MediaStyle notification for the system music controls.
    implementation("androidx.media:media:1.7.1")
    // Android's system passkey picker. The Play Services adapter keeps the
    // same Credential Manager API working on pre-Android 14 devices.
    implementation("androidx.credentials:credentials:1.6.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.6.0")
    // Mithka Pro subscriptions. Product prices and billing periods are owned by
    // Play Console; the client always displays the localized ProductDetails.
    // ntgcalls — a from-scratch C++ Telegram-calls engine (WebRTC + opus + libvpx
    // statically bundled inside a self-contained libntgcalls.so per ABI). This is
    // the real media transport behind the CallMediaEngine seam; CallMediaPlugin
    // drives its 1:1 P2P API from the TDLib callStateReady payload.
}
