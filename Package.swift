// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VoiceInput",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "VoiceInputCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "VoiceInput",
            dependencies: ["VoiceInputCore"],
            path: "Sources/VoiceInputLauncher",
            linkerSettings: [
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "VoiceInputChecks",
            dependencies: ["VoiceInputCore"],
            path: "Tests/VoiceInputChecks",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
