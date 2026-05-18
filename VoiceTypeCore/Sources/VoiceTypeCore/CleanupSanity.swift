import Foundation

/// Pure Heuristik: entscheidet, ob die Ausgabe eines LLM-basierten
/// Cleanups akzeptiert oder durch den Rohtext ersetzt wird. Wird von
/// `FoundationModelCleanup` und `MLXCleanup` gleichermaßen genutzt —
/// sodass die Längen-/Whitespace-Regeln engineunabhängig identisch
/// sind.
public enum CleanupSanity {
    /// - Leere oder reine Whitespace-Ausgabe → Rohtext
    /// - Längenverhältnis < 50 % oder > 200 % der Rohlänge → Rohtext
    /// - Sonst → getrimmte Modell-Ausgabe
    public static func accepted(raw: String, modelOutput: String) -> String {
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
