import Foundation
import FoundationModels

/// Bereinigt diktierten Rohtext mechanisch über Apples Foundation Models
/// (macOS 26, on-device). Fällt bei jedem Problem auf den Rohtext zurück —
/// `cleanup(_:)` wirft nie.
public struct FoundationModelCleanup: TextCleanup {

    private static let instructions = """
        Du bereinigst diktierten Text mechanisch. Erlaubt: Füllwörter \
        entfernen (ähm, äh, öh, …), Zeichensetzung setzen und korrigieren, \
        Groß-/Kleinschreibung korrigieren, offensichtliche Versprecher \
        und unmittelbare Wortwiederholungen glätten. Verboten: \
        umformulieren, Wortwahl ändern, Sätze umbauen, Inhalt hinzufügen \
        oder weglassen, übersetzen, kommentieren. Antworte ausschließlich \
        mit dem bereinigten Text — keine Einleitung, keine \
        Anführungszeichen, kein „Hier ist…". Behalte die Sprache des \
        Originals bei.
        """

    private static let timeoutSeconds: Double = 5

    public init() {}

    /// `nil` = Modell verfügbar. Sonst deutscher Hinweistext für die UI.
    public var availabilityHint: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "Cleanup nicht verfügbar — Apple Intelligence aktivieren."
            case .deviceNotEligible:
                return "Cleanup nicht verfügbar — auf diesem Gerät nicht unterstützt."
            case .modelNotReady:
                return "Cleanup nicht verfügbar — Modell lädt noch."
            @unknown default:
                return "Cleanup nicht verfügbar."
            }
        }
    }

    public func cleanup(_ raw: String) async -> String {
        // Modell-Verfügbarkeit vor jedem Aufruf prüfen — bei „nicht verfügbar"
        // sofort Rohtext zurück, ohne respond zu versuchen.
        guard case .available = SystemLanguageModel.default.availability else {
            return raw
        }
        do {
            let modelOutput = try await withTimeout(seconds: Self.timeoutSeconds) {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(to: raw)
                return response.content
            }
            return Self.acceptedOutput(raw: raw, modelOutput: modelOutput)
        } catch {
            // Timeout, GenerationError, oder beliebiger Systemfehler →
            // sanfte Degradierung auf den unveränderten Rohtext.
            return raw
        }
    }

    /// Pure: entscheidet, ob die Modell-Ausgabe akzeptiert wird.
    /// - Leere oder reine Whitespace-Ausgabe → Rohtext
    /// - Längenverhältnis < 50 % oder > 200 % der Rohlänge → Rohtext
    /// - Sonst → getrimmte Modell-Ausgabe
    static func acceptedOutput(raw: String, modelOutput: String) -> String {
        let trimmed = modelOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        let rawLen = raw.count
        guard rawLen > 0 else { return raw }
        let cleanedLen = trimmed.count
        if cleanedLen * 2 < rawLen { return raw }
        if cleanedLen > rawLen * 2 { return raw }
        return trimmed
    }
}

private enum CleanupError: Error { case timeout }

/// Führt eine async-Operation mit Timeout aus. Wer zuerst fertig wird,
/// gewinnt; beim Loser wird Cancellation angefordert. Bei Überschreitung
/// wirft die Funktion `CleanupError.timeout`.
///
/// Hinweis: Cancellation von `LanguageModelSession.respond(to:)` ist
/// kooperativ. Honoriert die Runtime sie nicht, läuft die Inferenz im
/// Hintergrund bis zum Ende weiter und ihr Ergebnis wird stillschweigend
/// verworfen. In VoiceType ist das harmlos: der Aufrufer hat den Rohtext
/// bereits zurückerhalten, Diktate laufen seriell, und höchstens ein
/// solcher Orphan-Task kann gleichzeitig existieren.
private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CleanupError.timeout
        }
        guard let result = try await group.next() else {
            throw CleanupError.timeout
        }
        group.cancelAll()
        return result
    }
}
