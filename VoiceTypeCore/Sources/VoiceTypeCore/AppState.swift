import Foundation
import Observation

/// Single Source of Truth für alle Views. Wird ausschließlich vom
/// DictationCoordinator (Controller) mutiert; Views lesen nur.
@MainActor
@Observable
public final class AppState {
    public internal(set) var dictationState: DictationState = .loading
    public internal(set) var livePreview: String = ""
    // Plan-3-Gerüst: wird mit dem animierten Wellenform-Icon verdrahtet
    // (AudioCapturing → Coordinator → AppState). In Plan 1 noch ungenutzt.
    public internal(set) var micLevel: Float = 0
    public private(set) var log: [TranscriptEntry] = []

    public init() {}

    /// Hängt ein abgeschlossenes Diktat vorne an (neueste zuerst).
    /// Leerer/nur-Whitespace-Text wird ignoriert.
    public func addEntry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.insert(TranscriptEntry(text: trimmed), at: 0)
    }
}
