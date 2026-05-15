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

/// Ein Teil- oder Endergebnis der Spracherkennung.
public struct TranscriptionUpdate: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
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
