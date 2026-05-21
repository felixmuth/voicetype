// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceTypeParakeet",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceTypeParakeet", targets: ["VoiceTypeParakeet"]),
    ],
    dependencies: [
        .package(path: "../VoiceTypeCore"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "VoiceTypeParakeet",
            dependencies: [
                .product(name: "VoiceTypeCore", package: "VoiceTypeCore"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
