// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceTypeWhisperKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceTypeWhisperKit", targets: ["VoiceTypeWhisperKit"]),
    ],
    dependencies: [
        .package(path: "../VoiceTypeCore"),
        .package(url: "https://github.com/argmaxinc/WhisperKit",
                 from: "0.18.0"),
    ],
    targets: [
        .target(
            name: "VoiceTypeWhisperKit",
            dependencies: [
                .product(name: "VoiceTypeCore", package: "VoiceTypeCore"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
    ]
)
