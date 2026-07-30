plugins {
    alias(libs.plugins.kotlin.multiplatform) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.compose.compiler) apply false
}

val verifyFocusRuntimeSync by tasks.registering {
    group = "verification"
    description = "Verifies that the Kotlin bundle mirrors the canonical Swift focus-runtime.js."

    val canonicalRuntime = layout.projectDirectory.file(
        "Sources/FocusCore/Resources/focus-runtime.js",
    )
    val kotlinRuntime = layout.projectDirectory.file(
        "focus-core/src/commonMain/resources/focus-runtime.js",
    )

    inputs.files(canonicalRuntime, kotlinRuntime)

    doLast {
        check(canonicalRuntime.asFile.readBytes().contentEquals(kotlinRuntime.asFile.readBytes())) {
            "focus-runtime.js copies differ. Run ./Scripts/sync_focus_runtime.sh --sync and commit both files."
        }
    }
}

val verifyBilibiliApiContracts by tasks.registering {
    group = "verification"
    description = "Verifies the independently maintained cross-platform Bilibili API contract subset."

    val swiftContracts = layout.projectDirectory.file(
        "Sources/FocusCore/Resources/bilibili-api-contracts.json",
    )
    val kotlinContracts = layout.projectDirectory.file(
        "focus-core/src/commonMain/resources/bilibili-api-contracts.json",
    )

    inputs.files(swiftContracts, kotlinContracts)

    doLast {
        check(swiftContracts.asFile.readBytes().contentEquals(kotlinContracts.asFile.readBytes())) {
            "Bilibili API contract copies differ. Run " +
                "./Scripts/sync_bilibili_api_contracts.mjs --sync."
        }
    }
}

subprojects {
    tasks.matching {
        it.name == "check" ||
            it.name.startsWith("test") ||
            it.name.startsWith("assemble")
    }.configureEach {
        dependsOn(verifyFocusRuntimeSync)
        dependsOn(verifyBilibiliApiContracts)
    }
}
