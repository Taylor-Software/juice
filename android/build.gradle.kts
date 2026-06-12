allprojects {
    repositories {
        google()
        mavenCentral()
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

// file_picker 11.x skips applying the Kotlin Android plugin on AGP 9+,
// assuming AGP's built-in Kotlin is enabled. This project keeps
// android.builtInKotlin=false (flutter_gemma and large_file_handler still
// apply KGP themselves, which AGP 9 forbids alongside built-in Kotlin), so
// without this its Kotlin sources never compile and the release build fails
// resolving FilePickerPlugin. Apply KGP for it, mirroring the jvmTarget its
// own (skipped) kotlinOptions block would have set.
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
