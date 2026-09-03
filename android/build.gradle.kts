allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter plugins declare a mix of Java levels - flutter_tts says 11,
// tflite_flutter says 1.8 - while Kotlin picks up whatever the JDK offers.
// Gradle refuses the mismatch outright:
//
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (17)
//
// The plugins cannot be edited from here, so every subproject is pinned to 17.
// This block has to come *before* the evaluationDependsOn(":app") below:
// afterEvaluate registers a callback, and once a project has been evaluated
// Gradle rejects the registration entirely.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
            // Plugins pin their own compileSdk, often years behind what their
            // own transitive AndroidX dependencies now require. tflite_flutter
            // pulls androidx.fragment 1.7, which demands 34+, and the AAR
            // metadata check then fails inside the *plugin's* module where the
            // app's compileSdk has no effect.
            android.compileSdkVersion(36)
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions.jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
                )
            }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
