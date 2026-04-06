plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.koray.artaircleaner"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.koray.artaircleaner"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        manifestPlaceholders["appAuthRedirectScheme"] = "com.koray.artaircleaner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    buildTypes {
        release {
            // Şimdilik debug imzası ile çalıştır
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            // Yeni Android Gradle Plugin sürümlerinde, shrinkResources sadece
            // minifyEnabled=true iken kullanılabilir. Burada açıkça kapatıyoruz.
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}
