plugins {
    id("com.android.application")
}

android {
    namespace = "io.test.wx"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.test.wx"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        // The WHOLE POINT of this test: get lib*.so extracted to nativeLibraryDir
        // so we can execve() it. With the AGP default (extractNativeLibs=false) the
        // directory stays empty.
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
