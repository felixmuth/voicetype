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

    public static let parakeetAll: [ModelDescriptor] = [
        .init(kind: .parakeet,
              id: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
              displayName: "Parakeet TDT v3 0.6B (multilingual)",
              approxSizeBytes: 700_000_000,
              isDefault: true),
        .init(kind: .parakeet,
              id: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
              displayName: "Parakeet TDT v2 0.6B (Englisch)",
              approxSizeBytes: 700_000_000,
              isDefault: false),
    ]

    public static let mlxAll: [ModelDescriptor] = [
        // Qwen 2.5 3B Instruct (4-bit) — derzeitiger Cleanup-Default.
        // ~1.8 GB, schnelle Inferenz, solides Deutsch.
        //
        // Gemma 3 4B war ursprünglich als Default geplant, lädt aber
        // mit der aktuellen mlx-swift-examples-Version (2.25.7) nicht:
        // die Gemma3-Implementierung erwartet ein vocab_size=262144,
        // das offizielle Repo bringt aber 262208 mit
        // (lm_head.scales shape mismatch). Sobald wir auf eine neuere
        // mlx-swift-examples-Version upgraden können — was aktuell am
        // swift-transformers-Pin von WhisperKit 0.14 hängt — kommt
        // Gemma 3 zurück.
        .init(kind: .mlx,
              id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
              displayName: "Qwen 2.5 3B Instruct (4-bit)",
              approxSizeBytes: 1_800_000_000,
              isDefault: true),
    ]

    public static var whisperKitDefault: ModelDescriptor {
        whisperKitAll.first(where: \.isDefault)!
    }

    public static var mlxDefault: ModelDescriptor {
        mlxAll.first(where: \.isDefault)!
    }

    public static var parakeetDefault: ModelDescriptor {
        parakeetAll.first(where: \.isDefault)!
    }

    public static func whisperKit(id: String) -> ModelDescriptor? {
        whisperKitAll.first { $0.id == id }
    }

    public static func mlx(id: String) -> ModelDescriptor? {
        mlxAll.first { $0.id == id }
    }

    public static func parakeet(id: String) -> ModelDescriptor? {
        parakeetAll.first { $0.id == id }
    }
}
