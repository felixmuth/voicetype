// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceTypeMLX",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceTypeMLX", targets: ["VoiceTypeMLX"]),
    ],
    dependencies: [
        .package(path: "../VoiceTypeCore"),
        // Apples MLX-Swift-Stack inkl. MLXLLM (Gemma/Qwen/Llama-Adapter)
        // und MLXLMCommon (downloadModel + ChatSession-Generate).
        // Eigenes Package, damit der WhisperKit-Resolver nicht kollidiert.
        // Wir benutzen NUR die public APIs von MLXLMCommon — kein direkter
        // `Hub`-Import nötig, weil swift-transformers `Hub` nicht als
        // Library-Product exposed.
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git",
                 from: "2.25.0"),
    ],
    targets: [
        .target(
            name: "VoiceTypeMLX",
            dependencies: [
                .product(name: "VoiceTypeCore", package: "VoiceTypeCore"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ]
        ),
    ]
)
