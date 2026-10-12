plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

/** A signing value from the environment (CI) or a Gradle property (a laptop's ~/.gradle/gradle.properties). */
fun setting(env: String, property: String) =
    providers.environmentVariable(env).orElse(providers.gradleProperty(property))

val uploadKeystore = setting("ANDROID_UPLOAD_KEYSTORE_FILE", "groglogUploadKeystoreFile")

android {
    namespace = "cc.blit.groglog"
    compileSdk = 37

    defaultConfig {
        applicationId = "cc.blit.groglog"
        minSdk = 28
        targetSdk = 37
        // CI passes its run number, so each upload is higher than the last.
        versionCode = providers.gradleProperty("versionCode").orNull?.toInt() ?: 1
        versionName = "1.0"
    }

    signingConfigs {
        if (uploadKeystore.isPresent) {
            create("upload") {
                storeFile = file(uploadKeystore.get())
                storePassword = setting("ANDROID_UPLOAD_KEYSTORE_PASSWORD", "groglogUploadKeystorePassword").get()
                keyAlias = setting("ANDROID_UPLOAD_KEY_ALIAS", "groglogUploadKeyAlias").get()
                keyPassword = setting("ANDROID_UPLOAD_KEY_PASSWORD", "groglogUploadKeyPassword").get()
            }
        }
    }

    buildTypes {
        release {
            // Unsigned without the upload key: Play refuses it, but the build is still checked.
            signingConfig = signingConfigs.findByName("upload")
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all {
            // Robolectric's Android 16 sandbox reaches into JDK internals that Java 21 keeps closed by default.
            it.jvmArgs("--add-opens=java.base/jdk.internal.access=ALL-UNNAMED")
        }
    }
}

kotlin {
    jvmToolchain(21)
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
    arg("room.generateKotlin", "true")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.core)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    implementation(libs.datastore.preferences)
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)
    implementation(libs.kotlinx.serialization.json)

    testImplementation(libs.junit)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.kotlinx.coroutines.test)
}
