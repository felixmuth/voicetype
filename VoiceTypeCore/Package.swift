// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceTypeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceTypeCore", targets: ["VoiceTypeCore"]),
    ],
    targets: [
        .target(name: "VoiceTypeCore"),
        .testTarget(
            name: "VoiceTypeCoreTests",
            dependencies: ["VoiceTypeCore"]
        ),
    ]
)
