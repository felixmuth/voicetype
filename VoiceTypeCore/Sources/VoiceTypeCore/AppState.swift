import Foundation
import Observation

/// Single Source of Truth für alle Views. Wird ausschließlich vom
/// DictationCoordinator (Controller) mutiert; Views lesen nur.
@MainActor
@Observable
public final class AppState {
    public internal(set) var dictationState: DictationState = .loading
    /// Aktueller committed Transkripttext (= das, was die Engine bisher
    /// als fest gilt, z. B. Parakeet's `manager.confirmedTranscript`).
    /// Wächst monoton während einer Aufnahme, wird beim Reset
    /// (idle / discard) auf "" gesetzt. UI rendert ihn 1:1.
    public internal(set) var livePreview: String = ""
    // Plan-3-Gerüst: wird mit dem animierten Wellenform-Icon verdrahtet
    // (AudioCapturing → Coordinator → AppState). In Plan 1 noch ungenutzt.
    public internal(set) var micLevel: Float = 0
    /// Voice-Activity-Detection-Status. Wird vom `DictationCoordinator`
    /// per Threshold + Release-Delay aus dem rohen Mikrofon-Pegel
    /// abgeleitet; die UI (Wellenform, Pulse) reagiert binär — entweder
    /// gleichmäßig animiert während Sprache, oder ruhig.
    public internal(set) var isSpeaking: Bool = false
    public private(set) var log: [TranscriptEntry] = []

    /// Wird vom AppController gesetzt, wenn die gewünschte Engine nicht
    /// verfügbar ist (Modell fehlt, prepare() schlug fehl, etc.) — die
    /// App läuft dann mit dem Fallback (typischerweise Apple Speech).
    /// `nil` bedeutet: gewählte Engine läuft.
    public var engineFallbackHint: String?

    /// Spiegelt die *tatsächlich laufende* Engine — wird vom
    /// AppController nach jedem erfolgreichen Swap aktualisiert. Die UI
    /// vergleicht den Wert mit `settings.transcriptionEngine`, um den
    /// Aktivierungs-Footer zu rendern (Plan 4 § 7.3).
    public var activeTranscriptionEngine: TranscriptionEngineKind = .apple

    /// Spiegelt das tatsächlich laufende Cleanup — wird vom AppController
    /// nach jedem Swap aktualisiert.
    public var activeCleanupEngine: CleanupEngineKind = .appleFoundationModels

    public init() {}

    /// Hängt ein abgeschlossenes Diktat vorne an (neueste zuerst).
    /// Leerer/nur-Whitespace-Text wird ignoriert.
    public func addEntry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.insert(TranscriptEntry(text: trimmed), at: 0)
    }
}
