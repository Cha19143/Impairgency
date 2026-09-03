plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    compileOptions {
        // flutter_local_notifications schedules with java.time, which needs
        // desugaring below API 26. Without it the build fails at
        // checkDebugAarMetadata with a message that names the plugin but not
        // the fix.
        isCoreLibraryDesugaringEnabled = true
    }

    namespace = "ph.impairgency.app"
    // Pinned rather than taken from flutter.compileSdkVersion: androidx
    // fragment 1.7 and the newer TensorFlow Lite artifacts both require 34+,
    // and the AAR metadata check fails with twenty separate messages that each
    // name a library and none of which name this line.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ph.impairgency.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 23 is what firebase_auth and flutter_local_notifications need.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// tflite_flutter 0.11 pulls TensorFlow Lite 2.11, whose three artifacts all
// declare the namespace org.tensorflow.lite. AGP 9 rejects that outright:
//
//   Namespace 'org.tensorflow.lite' is used in multiple modules and/or
//   libraries
//
// 2.16.1 gives each artifact its own namespace. The plugin's Dart API is
// unchanged between them.
configurations.configureEach {
    resolutionStrategy {
        force("org.tensorflow:tensorflow-lite:2.16.1")
        force("org.tensorflow:tensorflow-lite-api:2.16.1")
        force("org.tensorflow:tensorflow-lite-gpu:2.16.1")
        force("org.tensorflow:tensorflow-lite-gpu-api:2.16.1")
    }
}
