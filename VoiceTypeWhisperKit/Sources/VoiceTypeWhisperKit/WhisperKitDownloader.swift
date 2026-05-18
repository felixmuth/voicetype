import Foundation
import VoiceTypeCore
import WhisperKit

/// Lädt WhisperKit-CoreML-Modelle aus dem Argmax-HF-Repo
/// `argmaxinc/whisperkit-coreml` herunter. Schreibt das Modell-Bundle
/// nach `<parent-folder>/<variant>/...`, weil WhisperKit selbst die
/// `<variant>`-Subdirectory anlegt — `ModelRegistry.folder(for:)` zeigt
/// auf eben diesen Endordner.
public struct WhisperKitDownloader: ModelDownloading {
    public init() {}

    public func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        precondition(descriptor.kind == .whisperKit)
        // WhisperKit.download benutzt HubApi-Konvention und legt das
        // Bundle unter `<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>/`
        // ab. `folder` ist die exakte Ziel-URL (Registry-Pfad), also
        // müssen wir vier Ebenen hochgehen, um die korrekte downloadBase
        // zu erhalten: variant → whisperkit-coreml → argmaxinc → models.
        let downloadBase = folder
            .deletingLastPathComponent()   // variant
            .deletingLastPathComponent()   // whisperkit-coreml
            .deletingLastPathComponent()   // argmaxinc
            .deletingLastPathComponent()   // models
        _ = try await WhisperKit.download(
            variant: descriptor.id,
            downloadBase: downloadBase,
            progressCallback: { progress in
                onProgress(progress.fractionCompleted)
            })
    }
}
