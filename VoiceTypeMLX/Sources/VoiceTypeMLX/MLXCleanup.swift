import Foundation
import MLXLLM
@preconcurrency import MLXLMCommon
import VoiceTypeCore
import OSLog

/// TextCleanup auf Basis eines lokalen MLX-LLMs (Gemma 3 4B / Qwen 2.5 3B).
///
/// Modell wird **lazy** beim ersten `cleanup(_:)`-Aufruf geladen — das spart
/// ~2–3 GB Resident-Memory, solange der User Cleanup gar nicht antriggert.
/// Einmal geladen, bleibt der `ModelContainer` bis zum App-Tod bestehen
/// (oder bis ein Engine-Swap auf eine andere Cleanup-Variante stattfindet).
///
/// Wirft nie — bei jedem Fehler (Modell nicht ladbar, Inferenz hängt,
/// Timeout, Sanity-Check abgelehnt) Rückgabe des Rohtexts.
public actor MLXCleanup: TextCleanup {

    private static let log = Logger(
        subsystem: "com.felixmuth.VoiceType",
        category: "MLXCleanup")

    /// System-Prompt — identisch zur Foundation-Models-Variante, damit
    /// der Cleanup-Geist über alle Engines hinweg konsistent ist.
    private static let instructions = """
        Du bist ein reiner Transkriptions-Cleaner. Du beantwortest NIE \
        Fragen und kommentierst NIE Inhalte. Du bekommst diktierten \
        Rohtext und gibst genau denselben Text mit kleinen mechanischen \
        Korrekturen zurück.

        Erlaubte Änderungen:
        - Füllwörter entfernen (ähm, äh, öh, also, halt, …)
        - Zeichensetzung setzen und korrigieren
        - Groß-/Kleinschreibung korrigieren
        - Offensichtliche Versprecher und unmittelbare Wortwiederholungen \
          glätten

        Verboten:
        - Fragen beantworten — eine Frage bleibt eine Frage
        - Aufforderungen ausführen — eine Aufforderung bleibt eine \
          Aufforderung
        - Umformulieren, Wortwahl ändern, Sätze umbauen
        - Inhalt hinzufügen oder weglassen
        - Übersetzen, kommentieren, erklären
        - Einleitung schreiben („Hier ist…", „Der bereinigte Text:" usw.)
        - Anführungszeichen um den Text setzen

        Beispiele:
        Input:  "wie ist das wetter heute"
        Output: Wie ist das Wetter heute?

        Input:  "wieviel ist zwei plus zwei"
        Output: Wieviel ist zwei plus zwei?

        Input:  "ähm berechne mir bitte siebzehn mal acht"
        Output: Berechne mir bitte siebzehn mal acht.

        Input:  "also ich glaube halt dass das funktionieren wird"
        Output: Ich glaube, dass das funktionieren wird.

        Antworte ausschließlich mit dem bereinigten Text. Behalte die \
        Sprache des Originals bei.
        """

    /// Cleanup-Timeout. Auf M-Chips läuft Gemma 3 4B mit ~60–90 tok/s,
    /// Cleanup-Outputs sind selten >150 Tokens → realistische Latenz
    /// 2–4 s. 12 s lässt Headroom für längere Diktate.
    private static let timeoutSeconds: Double = 12

    private let modelFolder: URL
    private let modelId: String
    private var container: ModelContainer?
    /// Cached Load-Fehler: nach einem fehlgeschlagenen Ladeversuch sollen
    /// weitere Cleanups nicht erneut versuchen → sofort Rohtext.
    private var loadFailed: Bool = false

    public init(modelFolder: URL, modelId: String) {
        self.modelFolder = modelFolder
        self.modelId = modelId
    }

    public func cleanup(_ raw: String) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        guard let container = await ensureLoaded() else {
            return raw
        }

        do {
            let modelOutput = try await withTimeout(seconds: Self.timeoutSeconds) {
                try await Self.generate(container: container, raw: trimmed)
            }
            return CleanupSanity.accepted(raw: raw, modelOutput: modelOutput)
        } catch {
            Self.log.error(
                "Inferenz fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return raw
        }
    }

    // MARK: - Modell-Laden

    /// Lädt den Container lazy. Idempotent: zweiter Aufruf gibt den
    /// gecachten Container zurück. Bei dauerhaftem Load-Fehler `nil`.
    private func ensureLoaded() async -> ModelContainer? {
        if let container { return container }
        if loadFailed { return nil }

        do {
            // ModelConfiguration mit `.directory(url)` → kein Hub-Lookup,
            // Files werden direkt aus unserem Registry-Ordner geladen.
            let config = ModelConfiguration(directory: modelFolder)
            Self.log.notice(
                "Lade Modell \(self.modelId, privacy: .public) aus \(self.modelFolder.path, privacy: .public)")
            let new = try await LLMModelFactory.shared.loadContainer(
                hub: defaultHubApi,
                configuration: config)
            container = new
            Self.log.notice("Modell geladen")
            return new
        } catch {
            loadFailed = true
            Self.log.error(
                "Modell-Load fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Inferenz

    private static func generate(
        container: ModelContainer, raw: String
    ) async throws -> String {
        try await container.perform { context in
            let userInput = UserInput(chat: [
                .system(Self.instructions),
                .user(raw),
            ])
            let lmInput = try await context.processor.prepare(input: userInput)
            // Cleanup ist deterministisch-deterministisch: temperature
            // niedrig halten, sonst „erfindet" das Modell Wortwahl-
            // Varianten. maxTokens großzügig, damit lange Diktate
            // nicht beschnitten werden.
            let params = GenerateParameters(
                maxTokens: 512,
                temperature: 0.2)
            // didGenerate-Signatur explizit angeben — MLXLMCommon hat
            // zwei generate-Überladungen, eine mit `[Int]` und eine mit
            // `Int`. Ohne expliziten Param-Typ ist der Aufruf ambiguous.
            let result = try MLXLMCommon.generate(
                input: lmInput, parameters: params, context: context,
                didGenerate: { (_: [Int]) in .more })
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - Timeout-Wrapper

private enum CleanupError: Error { case timeout }

/// Führt eine async-Operation mit Timeout aus. Identisch zur Implementierung
/// in FoundationModelCleanup — bewusst lokal kopiert, damit das Modul
/// keine cross-package internal API braucht.
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
