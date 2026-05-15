import Foundation

/// Spracherkennungs-Engine. Streamt Teilergebnisse während der Aufnahme
/// und liefert genau ein `isFinal`-Ergebnis, bevor der Stream endet.
public protocol TranscriptionEngine: Sendable {
    /// Lädt/prüft Modelle. Wirft, wenn die Engine nicht nutzbar ist.
    func prepare() async throws
    /// Startet Aufnahme + Transkription. Der zurückgegebene Stream
    /// emittiert Teilergebnisse und zum Schluss ein `isFinal`-Ergebnis.
    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error>
    /// Stoppt die Aufnahme; der Stream finalisiert und endet danach.
    func stop() async
}

/// Poliert Rohtext auf. Wirft nie — bei Problemen wird der Rohtext
/// zurückgegeben (sanfte Degradierung, siehe Spec).
public protocol TextCleanup: Sendable {
    func cleanup(_ raw: String) async -> String
}

/// Liefert fertigen Text aus: fügt ihn ggf. ins fokussierte Feld ein
/// und/oder kopiert ihn in die Zwischenablage.
public protocol TextDelivering: Sendable {
    func deliver(_ text: String, pasteIntoFocusedField: Bool)
}

/// Prüft on-demand, ob gerade ein Textfeld den Fokus hat.
public protocol FocusInspecting: Sendable {
    func isTextFieldFocused() -> Bool
}

/// Mikrofon-Aufnahme als Puffer-Stream.
public protocol AudioCapturing: AnyObject, Sendable {
    func startStream() throws -> AsyncStream<CapturedAudio>
    func stop()
    /// Optionaler Callback, der bei jedem Audio-Buffer mit dem aktuellen
    /// RMS-Pegel (0…1) aufgerufen wird. Closure ist `@MainActor`-isoliert
    /// — Implementierer müssen vor dem Aufruf auf den MainActor hoppen.
    var onLevel: (@MainActor (Float) -> Void)? { get set }
}

/// Roh-Audiopuffer plus aktueller Pegel (RMS, 0…1) für den Visualizer.
public struct CapturedAudio: @unchecked Sendable {
    public let pcmBuffer: AnyObject   // AVAudioPCMBuffer; AnyObject hält den Core testbar
    public let level: Float
    public init(pcmBuffer: AnyObject, level: Float) {
        self.pcmBuffer = pcmBuffer
        self.level = level
    }
}

public enum TranscriptionError: Error, Equatable {
    case notPrepared
    case localeNotSupported
    case modelUnavailable
}
