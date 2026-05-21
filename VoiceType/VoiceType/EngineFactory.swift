import Foundation
import VoiceTypeCore
import VoiceTypeWhisperKit
import VoiceTypeParakeet
import VoiceTypeMLX

/// Wählt die laufende Engine + Cleanup aus den Settings + dem aktuellen
/// Modell-Status der ModelRegistry. Pure Function — wird im AppController
/// sowohl beim Start als auch nach Setting-Changes und Download-Erfolg
/// aufgerufen.
///
/// Liegt im App-Target (nicht in VoiceTypeCore), weil sie
/// `WhisperKitEngine` konkret instanziiert — und diese Klasse lebt im
/// separaten VoiceTypeWhisperKit-Package (Plan 4 / MLX-Split).
@MainActor
enum EngineFactory {

    /// - Returns: (engine, fallbackHint). `fallbackHint != nil` heißt:
    ///   die gewünschte Engine konnte nicht erzeugt werden, wir fallen
    ///   auf Apple Speech zurück und die UI zeigt den Hint.
    static func makeTranscription(
        settings: Settings,
        registry: ModelRegistry,
        audioCapture: AudioCapturing,
        whisperKitOnLevel: @escaping @Sendable (Float) -> Void
    ) -> (engine: TranscriptionEngine, fallbackHint: String?) {
        switch settings.transcriptionEngine {
        case .apple:
            return (AppleSpeechEngine(
                audioCapture: audioCapture, language: settings.language), nil)

        case .whisperKit:
            guard let desc = ModelCatalog.whisperKit(id: settings.whisperKitModelId),
                  let folder = registry.folder(for: desc) else {
                return (AppleSpeechEngine(
                    audioCapture: audioCapture, language: settings.language),
                        "WhisperKit-Modell nicht installiert — Apple Speech aktiv.")
            }
            // WhisperKit benutzt seinen eigenen AudioProcessor —
            // unser AudioCapture wird im WhisperKit-Pfad nicht
            // gestartet. Der Level-Callback bridged stattdessen
            // den `bufferEnergy`-Strom aus dem Streamer-State zurück
            // an den Coordinator (Wellenform + VAD-Pulse).
            return (WhisperKitEngine(
                modelFolder: folder,
                language: settings.language,
                onLevel: whisperKitOnLevel), nil)

        case .parakeet:
            guard let desc = ModelCatalog.parakeet(id: settings.parakeetModelId),
                  let folder = registry.folder(for: desc) else {
                return (AppleSpeechEngine(
                    audioCapture: audioCapture, language: settings.language),
                        "Parakeet-Modell nicht installiert — Apple Speech aktiv.")
            }
            // Parakeet konsumiert unseren AudioCapture-Stream und
            // konvertiert selbst auf 16 kHz mono. Der Pegel kommt
            // direkt aus dem AudioCapture, daher kein separater
            // Level-Callback nötig — AudioCapture's eigener
            // `onLevel`-Pfad wird vom Coordinator schon bedient.
            // Version-Mapping passiert in der Engine selbst (v2 vs v3
            // anhand des Model-ID-Suffix) — wir importieren FluidAudio
            // hier nicht, weil dessen eigene `ModelRegistry`-Klasse
            // mit unserer kollidieren würde.
            return (ParakeetEngine(
                audioCapture: audioCapture,
                modelFolder: folder,
                modelId: desc.id), nil)
        }
    }

    /// - Returns: (cleanup, hint). `hint != nil` heißt: Cleanup degradiert
    ///   auf Passthrough — Grund im Hint.
    static func makeCleanup(
        settings: Settings,
        registry: ModelRegistry
    ) -> (cleanup: TextCleanup, hint: String?) {
        switch settings.cleanupEngine {
        case .off:
            return (PassthroughCleanup(), nil)

        case .appleFoundationModels:
            let fm = FoundationModelCleanup()
            if let hint = fm.availabilityHint {
                // Modell nicht verfügbar → Passthrough mit Erklärung
                return (PassthroughCleanup(), hint)
            }
            return (fm, nil)

        case .mlx:
            // Modell muss installiert sein, sonst Passthrough mit Hint.
            guard let desc = ModelCatalog.mlx(id: settings.mlxModelId),
                  let folder = registry.folder(for: desc) else {
                return (PassthroughCleanup(),
                        "MLX-Modell nicht installiert — Cleanup deaktiviert.")
            }
            return (MLXCleanup(modelFolder: folder, modelId: desc.id), nil)
        }
    }

    /// Spiegelt, welche Engine *effektiv* läuft — relevant für
    /// `AppState.activeTranscriptionEngine`. Wenn ein Fallback aktiv ist,
    /// läuft Apple Speech; sonst die Wahl.
    static func activeTranscription(
        for settings: Settings, fallbackHint: String?
    ) -> TranscriptionEngineKind {
        fallbackHint == nil ? settings.transcriptionEngine : .apple
    }

    /// Spiegelt das effektiv laufende Cleanup. Bei Fallback (Hint != nil)
    /// läuft Passthrough → `.off`.
    static func activeCleanup(
        for settings: Settings, hint: String?
    ) -> CleanupEngineKind {
        hint == nil ? settings.cleanupEngine : .off
    }
}
