import java.io.ByteArrayOutputStream
import javax.inject.Inject

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

/** The ABIs the core is built for, which are the ones the app is offered on: 64-bit ARM and x86_64, with no 32-bit support. `-Pabis=arm64-v8a` builds one, for a device or an emulator on Apple silicon. */
val coreAbis = providers.gradleProperty("abis").orElse("arm64-v8a,x86_64").map { it.split(",") }

val uploadKeystore = setting("ANDROID_UPLOAD_KEYSTORE_FILE", "groglogUploadKeystoreFile")

android {
    namespace = "cc.blit.groglog"
    compileSdk = 37
    ndkVersion = "30.0.16248370"

    defaultConfig {
        applicationId = "cc.blit.groglog"
        minSdk = 28
        targetSdk = 37
        // CI passes its run number, so each upload is higher than the last.
        versionCode = providers.gradleProperty("versionCode").orNull?.toInt() ?: 1
        versionName = marketingVersion
        // Only what the core is built for: a device would otherwise pick an ABI that JNA ships and the core does not.
        ndk { abiFilters += coreAbis.get() }
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
            // The model calls into the Rust core, which the tests load as a library built for this machine.
            it.systemProperty("jna.library.path", rootProject.file("../target/release").path)
        }
    }
}

kotlin {
    jvmToolchain(21)
}

/**
 * groglog-core, built with cargo-ndk for each ABI into `jniLibs`, and the Kotlin bindings uniffi generates from the built
 * library. Always a release build, so a debug app is not slowed by an unoptimised core.
 */
/** What the core is built from: the crates, their lockfile and the bindings generator. */
val coreSources = rootProject.fileTree("..") {
    include("core/**", "tools/**", "Cargo.toml", "Cargo.lock")
    exclude("core/out/**", "**/target/**")
}

abstract class CoreAndroid @Inject constructor(private val exec: ExecOperations) : DefaultTask() {
    @get:Input
    abstract val abis: ListProperty<String>

    @get:Input
    abstract val minSdk: Property<Int>

    @get:Internal
    abstract val workspace: DirectoryProperty

    @get:Internal
    abstract val ndk: DirectoryProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val sources: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val jniLibs: DirectoryProperty

    @get:OutputDirectory
    abstract val kotlin: DirectoryProperty

    @TaskAction
    fun build() {
        val root = workspace.get().asFile
        // rust-toolchain.toml adds its targets only when it installs the toolchain, so an existing install may lack them.
        // Only missing ones are added, and only through rustup: CI installs them up front, and a Rust without rustup is
        // left to report a missing target itself.
        val triples = mapOf("arm64-v8a" to "aarch64-linux-android", "x86_64" to "x86_64-linux-android")
        val wanted = abis.get().map { triples[it] ?: throw GradleException("No Rust target is known for the ABI $it") }
        val listed = ByteArrayOutputStream()
        val listing = runCatching {
            exec.exec {
                workingDir = root
                commandLine("rustup", "target", "list", "--installed")
                standardOutput = listed
                isIgnoreExitValue = true
            }
        }.getOrNull()
        val missing = wanted - listed.toString().lines().map(String::trim).toSet()
        if (listing?.exitValue == 0 && missing.isNotEmpty()) {
            exec.exec {
                workingDir = root
                commandLine(listOf("rustup", "target", "add") + missing)
            }
        }
        exec.exec {
            workingDir = root
            environment("ANDROID_NDK_HOME", ndk.get().asFile.path)
            commandLine(
                listOf("cargo", "ndk", "--platform", minSdk.get().toString(), "-o", jniLibs.get().asFile.path) +
                    abis.get().flatMap { listOf("-t", it) } +
                    listOf("build", "--release", "-p", "groglog-core"),
            )
        }
        val lib = jniLibs.get().dir(abis.get().first()).file("libgroglog_core.so").asFile
        kotlin.get().asFile.deleteRecursively()
        exec.exec {
            workingDir = root
            commandLine(
                "cargo", "run", "-q", "-p", "uniffi-bindgen", "--",
                "generate", "--library", lib.path, "--language", "kotlin", "--no-format",
                "--out-dir", kotlin.get().asFile.path,
            )
        }
    }
}

val coreAndroid = tasks.register<CoreAndroid>("coreAndroid") {
    abis.set(coreAbis)
    minSdk.set(android.defaultConfig.minSdk!!)
    workspace.set(rootProject.layout.projectDirectory.dir(".."))
    ndk.set(androidComponents.sdkComponents.ndkDirectory)
    jniLibs.set(layout.buildDirectory.dir("core/jniLibs"))
    kotlin.set(layout.buildDirectory.dir("core/kotlin"))
    sources.from(coreSources)
}

/** The core built for this machine, which the JVM tests load. */
val coreHost = tasks.register<Exec>("coreHost") {
    workingDir = rootProject.layout.projectDirectory.dir("..").asFile
    inputs.files(coreSources).withPathSensitivity(PathSensitivity.RELATIVE)
    outputs.dir(rootProject.layout.projectDirectory.dir("../target/release"))
    commandLine("cargo", "build", "--release", "-p", "groglog-core")
}

tasks.withType<Test>().configureEach { dependsOn(coreHost) }

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
        variant.sources.jniLibs?.addGeneratedSourceDirectory(coreAndroid, CoreAndroid::jniLibs)
        variant.sources.kotlin?.addGeneratedSourceDirectory(coreAndroid, CoreAndroid::kotlin)
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
    implementation(libs.jna) { artifact { type = "aar" } }

    testImplementation(libs.junit)
    // The host build of JNA, which carries the native dispatcher the JVM needs; the AAR above carries Android's.
    testImplementation(libs.jna)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(platform(libs.compose.bom))
    testImplementation(libs.compose.ui.test.junit4)
    testImplementation(libs.roborazzi)
    testImplementation(libs.roborazzi.compose)
}
