import Foundation
@preconcurrency import MLXLMCommon
import VoiceTypeCore
import OSLog

/// Lädt MLX-Modelle aus `mlx-community/<repo>` über MLXLMCommon's
/// `downloadModel(...)`, das intern HuggingFace's HubApi nutzt.
///
/// **Ablage**: MLXLMCommon's `defaultHubApi` schreibt in
/// `~/Library/Caches/models/<repo>/`. `ModelRegistry.folderURL(.mlx)`
/// zeigt auf denselben Pfad — kein Move/Copy nötig.
///
/// Anders als WhisperKit/Parakeet liegen MLX-Modelle damit im
/// Caches-Ordner statt in Application Support. macOS könnte den Cache
/// theoretisch unter Disk-Druck räumen — bei den paar GB hier in der
/// Praxis vernachlässigbar, und wir handhaben "Modell fehlt" eh sauber
/// über die Registry.
public struct MLXDownloader: ModelDownloading {
    private static let log = Logger(
        subsystem: "com.felixmuth.VoiceType",
        category: "MLXDownloader")

    public init() {}

    public func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        precondition(descriptor.kind == .mlx)
        Self.log.notice("MLX \(descriptor.id, privacy: .public) — Download startet")
        onProgress(0)
        do {
            let config = ModelConfiguration(id: descriptor.id)
            _ = try await MLXLMCommon.downloadModel(
                hub: defaultHubApi,
                configuration: config,
                progressHandler: { progress in
                    onProgress(progress.fractionCompleted)
                })
            onProgress(1)
            Self.log.notice("MLX \(descriptor.id, privacy: .public) — Download fertig")
        } catch {
            Self.log.error(
                "MLX \(descriptor.id, privacy: .public) — Download-Fehler: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        _ = folder   // unused — Download landet im default Hub-Cache
    }
}
