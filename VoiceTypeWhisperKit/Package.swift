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
        // Pin auf 0.14.x: die letzte WhisperKit-Reihe, die noch
        // swift-transformers 0.1.x verwendet. Notwendig, weil MLX
        // (mlx-swift-examples) seinerseits gegen swift-transformers
        // 0.1.x resolved — neuere WhisperKit (0.15+) fordert 1.1.x
        // und kollidiert dann unauflösbar mit MLX.
        .package(url: "https://github.com/argmaxinc/WhisperKit",
                 "0.14.0"..<"0.15.0"),
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
