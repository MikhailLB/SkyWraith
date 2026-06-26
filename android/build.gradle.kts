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

    // --------------------------------------------------------
    // Force every Android library subproject to compile against
    // the same compileSdk our app uses (36). Some packages still
    // declare compileSdk = 34 but their transitive deps require
    // 36 — without this override CheckAarMetadata aborts.
    //
    // Must be registered BEFORE the evaluationDependsOn(":app")
    // block below — otherwise the target subprojects are already
    // evaluated and Gradle rejects the afterEvaluate hook.
    // --------------------------------------------------------
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
