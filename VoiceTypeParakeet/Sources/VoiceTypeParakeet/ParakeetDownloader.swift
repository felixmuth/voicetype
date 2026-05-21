import Foundation
import FluidAudio
import VoiceTypeCore
import OSLog

/// Lädt FluidAudio's Parakeet-CoreML-Bundles aus dem
/// HuggingFace-Repo `FluidInference/parakeet-tdt-0.6b-v{2,3}-coreml`
/// in den FluidAudio-Default-Cache.
///
/// FluidAudio's `AsrModels.downloadAndLoad(version:progressHandler:)`
/// liefert echten Download-Fortschritt über `DownloadProgress
/// .fractionCompleted` — wir reichen den 1:1 an unseren
/// `ModelRegistry`-Progress weiter.
///
/// Cache-Pfad: `~/Library/Application Support/FluidAudio/Models/<repo>`
/// (FluidAudio default). Unsere `ModelRegistry.folderURL(for: .parakeet)`
/// zeigt genau dorthin — kein Move/Copy nötig.
public struct ParakeetDownloader: ModelDownloading {
    private static let log = Logger(
        subsystem: "com.felixmuth.VoiceType",
        category: "ParakeetDownloader")

    public init() {}

    public func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        precondition(descriptor.kind == .parakeet)
        let version = Self.versionFor(id: descriptor.id)
        Self.log.notice("Parakeet \(descriptor.id, privacy: .public) — Download startet")
        onProgress(0)
        do {
            _ = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { progress in
                    onProgress(progress.fractionCompleted)
                })
            onProgress(1)
            Self.log.notice("Parakeet \(descriptor.id, privacy: .public) — Download fertig")
        } catch {
            Self.log.error("Parakeet \(descriptor.id, privacy: .public) — Download-Fehler: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        _ = folder   // unused — Download landet im FluidAudio-Cache
    }

    private static func versionFor(id: String) -> AsrModelVersion {
        id.contains("v2") ? .v2 : .v3
    }
}
