plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.roborazzi)
}

/** A signing value from the environment (CI) or a Gradle property (a laptop's ~/.gradle/gradle.properties). */
fun setting(env: String, property: String) =
    providers.environmentVariable(env).orElse(providers.gradleProperty(property))

/** The version both apps carry, from MARKETING_VERSION in project.yml. */
val marketingVersion = Regex("""MARKETING_VERSION: (\S+)""").find(rootProject.file("../project.yml").readText())!!.groupValues[1]

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
        versionName = marketingVersion
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
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    buildFeatures {
        compose = true
    }

    androidResources {
        generateLocaleConfig = true
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
            // `-Pshots=DIR` renders the screenshot tests into DIR; without it they are skipped.
            it.systemProperty("groglog.shots", providers.gradleProperty("shots").getOrElse(""))
        }
    }
}

kotlin {
    jvmToolchain(21)
}

/** The website's privacy policy, packaged so the Health Connect rationale shows the same text offline. */
abstract class PrivacyPolicy : DefaultTask() {
    @get:InputFile
    abstract val source: RegularFileProperty

    @get:OutputDirectory
    abstract val output: DirectoryProperty

    @TaskAction
    fun copy() {
        source.get().asFile.copyTo(output.get().file("privacy.html").asFile, overwrite = true)
    }
}

val privacyPolicy = tasks.register<PrivacyPolicy>("privacyPolicy") {
    source.set(rootProject.layout.projectDirectory.file("../site/public/privacy.html"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(privacyPolicy, PrivacyPolicy::output)
    }
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
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.health.connect)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.work.runtime.ktx)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.core)
    implementation(libs.compose.material.icons.extended)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
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
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
}
