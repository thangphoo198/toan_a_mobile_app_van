plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.van_test"
    // [FIX] Flutter SDK dang cai mac dinh compileSdkVersion=34, nhung
    // file_picker (moi them de chon file .bin cuc bo khi nap qua Bluetooth)
    // keo theo flutter_plugin_android_lifecycle doi hoi compileSdk >= 36 -
    // build that bai voi loi "CheckAarMetadataWorkAction" neu khong nang len.
    // Ep thang 36 (khong doi targetSdk/minSdk) - chi anh huong API nao dung
    // duoc LUC BIEN DICH, khong doi hanh vi runtime cua app tren may that.
    compileSdk = 36
    // Flutter mac dinh doi hoi NDK 28.2.13676358 (flutter.ndkVersion), nhung
    // sdkmanager.bat cua "Android CLI" moi bi crash khi tu tai ban do - loi
    // rieng cua toolchain. App nay khong dung code native/JNI nao, nen ep
    // dung thang ban NDK da cai san qua Android Studio SDK Manager (khong
    // qua sdkmanager.bat) thay vi de Flutter tu doi ban pin cung.
    ndkVersion = "30.0.16138531"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.van_test"
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
