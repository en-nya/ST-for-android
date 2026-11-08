plugins {
    id("com.android.application")
}

android {
    namespace = "io.test.wx"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.test.wx"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        // THE WHOLE POINT of this project: get lib*.so extracted into
        // nativeLibraryDir so execve() can work. The AGP default
        // (useLegacyPackaging = false) leaves that directory EMPTY; verified
        // as a control: T1 then fails with error=2 ENOENT.
        jniLibs {
            useLegacyPackaging = true
        }
    }
}
