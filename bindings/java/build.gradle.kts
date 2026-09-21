/*
 * Java (web3j) bindings for the OnRe diamond.
 *
 * Pipeline:
 *   1. `forgeBuild`       runs `pnpm build` at the repo root, which regenerates the merged diamond ABI
 *                         at ../../src/generated/abi.json (skip with -PforgeBuild=false when it is fresh).
 *   2. `stageAbi`         copies that ABI to build/abi/IDiamondProxy.json.
 *   3. `generateWrappers` runs web3j's SolidityFunctionWrapperGenerator on it.
 *   4. The generated source is compiled into the jar, together with the ABI file as a resource.
 *
 * Coordinates: com.onre.evm:onre-evm-java:<version> (see gradle.properties; -Pversion overrides).
 */

import javax.inject.Inject
import org.gradle.process.ExecOperations

plugins {
    `java-library`
    `maven-publish`
}

fun prop(name: String): String = providers.gradleProperty(name).get()
val web3jVersion = prop("web3jVersion")
val javaRelease = prop("javaRelease")
val javaPackage = prop("javaPackage")
val forgeBuild = prop("forgeBuild")

// bindings/java -> repo root
val repoRoot: File = rootDir.parentFile.parentFile
val gemforgeAbi: File = repoRoot.resolve("src/generated/abi.json")

val abiDir = layout.buildDirectory.dir("abi")
val generatedJavaDir = layout.buildDirectory.dir("generated/sources/web3j/java")

repositories {
    mavenCentral()
}

val codegen: Configuration = configurations.create("codegen")

dependencies {
    codegen("org.web3j:codegen:$web3jVersion")

    // Generated wrappers extend org.web3j.tx.Contract and expose web3j types in their API.
    api("org.web3j:core:$web3jVersion")

    testImplementation(platform("org.junit:junit-bom:5.13.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

java {
    withSourcesJar()
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(javaRelease.toInt())
    options.encoding = "UTF-8"
}

tasks.withType<Javadoc>().configureEach {
    // Generated code is not documented; do not fail the build over it.
    (options as StandardJavadocDocletOptions).addBooleanOption("Xdoclint:none", true)
}

// ---------------------------------------------------------------------------------------------
// 1. Forge / Gemforge build
// ---------------------------------------------------------------------------------------------

val forgeBuildTask = tasks.register<Exec>("forgeBuild") {
    group = "bindings"
    description = "Runs `pnpm build` (gemforge build + forge build) at the repository root."
    onlyIf("forgeBuild property is true") { forgeBuild.toBoolean() }
    workingDir = repoRoot
    commandLine("pnpm", "build")
    // Forge does its own incremental compilation; always delegate to it.
    outputs.upToDateWhen { false }
}

// ---------------------------------------------------------------------------------------------
// 2. ABI
// ---------------------------------------------------------------------------------------------

// `gemforge build` writes the merged ABI of the whole diamond (facet functions, events and errors)
// to src/generated/abi.json. It is copied under the wrapper's class name because web3j names the
// generated class after the ABI file.
val stageAbi = tasks.register<Copy>("stageAbi") {
    group = "bindings"
    description = "Copies src/generated/abi.json to build/abi/IDiamondProxy.json."
    dependsOn(forgeBuildTask)
    from(gemforgeAbi) {
        rename { "IDiamondProxy.json" }
    }
    into(abiDir)
    doFirst {
        check(gemforgeAbi.isFile) {
            "src/generated/abi.json not found. Run `pnpm build` at the repo root (or let the forgeBuild task run)."
        }
    }
}

// ---------------------------------------------------------------------------------------------
// 3. web3j code generation
// ---------------------------------------------------------------------------------------------

abstract class Web3jCodegenTask : DefaultTask() {
    @get:Inject
    abstract val execOperations: ExecOperations

    @get:InputFiles
    abstract val abiFiles: ConfigurableFileCollection

    @get:Classpath
    abstract val codegenClasspath: ConfigurableFileCollection

    @get:Input
    abstract val packageName: Property<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val out = outputDir.get().asFile
        out.deleteRecursively()
        out.mkdirs()
        abiFiles.files.sortedBy { it.name }.forEach { abi ->
            logger.lifecycle("web3j: generating ${abi.nameWithoutExtension}")
            execOperations.javaexec {
                classpath = codegenClasspath
                mainClass.set("org.web3j.codegen.SolidityFunctionWrapperGenerator")
                // The wrapper class is named after the ABI file. No -b: nothing is deployed from Java.
                args(
                    "--abiFile", abi.absolutePath,
                    "--outputDir", out.absolutePath,
                    "--package", packageName.get(),
                    "--javaTypes",
                )
            }
        }
    }
}

val generateWrappers = tasks.register<Web3jCodegenTask>("generateWrappers") {
    group = "bindings"
    description = "Generates web3j Java wrappers from the extracted ABIs."
    // A Copy task's output is its destination directory; feed the generator the files inside it.
    abiFiles.from(stageAbi.map { it.outputs.files.asFileTree })
    codegenClasspath.from(codegen)
    packageName.set(javaPackage)
    outputDir.set(generatedJavaDir)
}

// ---------------------------------------------------------------------------------------------
// 4. Packaging
// ---------------------------------------------------------------------------------------------

sourceSets {
    main {
        java.srcDir(generateWrappers)
    }
}

tasks.processResources {
    // Ship the ABI alongside the wrapper, e.g. for ABI-driven decoding: abi/IDiamondProxy.json
    from(stageAbi) {
        into("abi")
    }
}

tasks.test {
    useJUnitPlatform()
    systemProperty("bindings.package", javaPackage)
}

tasks.jar {
    manifest {
        attributes(
            "Implementation-Title" to project.name,
            "Implementation-Version" to project.version,
            "Web3j-Version" to web3jVersion,
        )
    }
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            pom {
                name.set("OnRe EVM bindings")
                description.set("web3j Java wrapper for the OnRe diamond (IDiamondProxy), including all facet events.")
                url.set("https://github.com/onre-finance/onre-evm")
                licenses {
                    license {
                        name.set("MIT")
                        url.set("https://github.com/onre-finance/onre-evm/blob/main/LICENSE.md")
                    }
                }
                scm {
                    url.set("https://github.com/onre-finance/onre-evm")
                    connection.set("scm:git:https://github.com/onre-finance/onre-evm.git")
                }
            }
        }
    }
    repositories {
        maven {
            name = "GitHubPackages"
            val slug = System.getenv("GITHUB_REPOSITORY") ?: "onre-finance/onre-evm"
            url = uri("https://maven.pkg.github.com/$slug")
            credentials {
                username = System.getenv("GITHUB_ACTOR") ?: providers.gradleProperty("gpr.user").orNull
                password = System.getenv("GITHUB_TOKEN") ?: providers.gradleProperty("gpr.key").orNull
            }
        }
    }
}
