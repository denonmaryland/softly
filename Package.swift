// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Softly",
    platforms: [.macOS(.v14)],
    targets: [
        // Platform-independent logic: gestures, motion, waveform, transcript cleanup.
        // Builds and tests on Linux too.
        .target(name: "DictationCore"),
        // whisper.cpp with Metal, published by ggml-org (release b5454, 2026-10-06).
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
        .executableTarget(
            name: "Softly",
            dependencies: ["DictationCore", "whisper"],
            linkerSettings: [
                // whisper.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"]),
    ]
)
