import Foundation

public enum DictationState: Equatable, Sendable {
    case loading      // Engine wärmt beim Start auf
    case idle         // bereit
    case recording    // Taste gehalten, Audio streamt
    case finalizing   // Taste los, finales Transkript wird abgeholt
    case cleaning     // Cleanup-Pass
    case delivering   // Text wird eingefügt
    case error(String)
}

/// Snapshot der Live-Transkription während einer Aufnahme.
///
/// Engines liefern ihren aktuellen committed Stand (z. B. Parakeet
/// `manager.confirmedTranscript`); die UI rendert das 1:1. Es gibt
/// keine Draft-/Volatile-Komponente mehr — der gesamte Text ist
/// gleich behandelt.
///
/// Stream-Ende ist implizit (`continuation.finish()`); das letzte
/// Update vor dem Finish trägt den finalen Text.
public struct TranscriptionUpdate: Equatable, Sendable {
    public let text: String
    public init(text: String = "") {
        self.text = text
    }
}

/// Ein abgeschlossenes Diktat im Verlauf.
public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}
