plugins {
    //id("com.android.application") versions 
    //id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    //id("dev.flutter.flutter-gradle-plugin")

        id("com.android.application") version "8.3.2" apply false
        id("org.jetbrains.kotlin.android") version "1.9.23" apply false
        id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
}

apply {
     plugin("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.offgrid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973" // <-- This line was changed

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }        

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.offgrid"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdkVersion flutter.minSdkVersion
	    minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-nearby:19.3.0")
}
