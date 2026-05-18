import Foundation

/// Statische Modell-Liste. Erweiterungen erfolgen ausschließlich per
/// App-Update — kein Server-Discovery, kein freier HF-Repo-Input.
public enum ModelCatalog {

    public static let whisperKitAll: [ModelDescriptor] = [
        .init(kind: .whisperKit,
              id: "openai_whisper-large-v3",
              displayName: "Whisper large-v3",
              approxSizeBytes: 3_000_000_000,
              isDefault: true),
        .init(kind: .whisperKit,
              id: "openai_whisper-large-v3-turbo",
              displayName: "Whisper large-v3-turbo",
              approxSizeBytes: 1_600_000_000,
              isDefault: false),
    ]

    public static let mlxAll: [ModelDescriptor] = [
        .init(kind: .mlx,
              id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
              displayName: "Qwen 2.5 7B Instruct (4-bit)",
              approxSizeBytes: 4_000_000_000,
              isDefault: true),
        .init(kind: .mlx,
              id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
              displayName: "Qwen 2.5 3B Instruct (4-bit)",
              approxSizeBytes: 1_800_000_000,
              isDefault: false),
        .init(kind: .mlx,
              id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
              displayName: "Llama 3.2 3B Instruct (4-bit)",
              approxSizeBytes: 1_800_000_000,
              isDefault: false),
    ]

    public static var whisperKitDefault: ModelDescriptor {
        whisperKitAll.first(where: \.isDefault)!
    }

    public static var mlxDefault: ModelDescriptor {
        mlxAll.first(where: \.isDefault)!
    }

    public static func whisperKit(id: String) -> ModelDescriptor? {
        whisperKitAll.first { $0.id == id }
    }

    public static func mlx(id: String) -> ModelDescriptor? {
        mlxAll.first { $0.id == id }
    }
}
