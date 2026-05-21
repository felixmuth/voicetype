import Foundation
import Speech
import AVFoundation

/// TranscriptionEngine auf Basis von SpeechAnalyzer/SpeechTranscriber
/// (macOS 26, on-device, streaming). Konsumiert ein AudioCapturing.
public actor AppleSpeechEngine: TranscriptionEngine {
    private let audioCapture: AudioCapturing
    private let language: String          // "auto" | "de" | "en"

    /// Hartes Lifecycle-Pärchen: SpeechTranscriber und SpeechAnalyzer
    /// werden für **jedes** Diktat frisch instanziiert. Wir können einen
    /// `SpeechTranscriber` nicht über zwei `SpeechAnalyzer`-Instanzen
    /// hinweg teilen — Apple's interner `setWorkers(...)`-Pfad triggert
    /// dann einen Breakpoint-Trap (siehe `MenuBarLabel`-Bugfix-Commit
    /// für den zugehörigen Crash-Report). `prepare()` validiert nur
    /// Locale-Verfügbarkeit + Asset-Install.
    private var localeReady = false
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private let converter = BufferConverter()

    public init(audioCapture: AudioCapturing, language: String) {
        self.audioCapture = audioCapture
        self.language = language
    }

    private func resolveLocale() -> Locale {
        switch language {
        case "de": return Locale(identifier: "de-DE")
        case "en": return Locale(identifier: "en-US")
        default:   return Locale.current
        }
    }

    /// Validiert die Locale und installiert das Asset, falls nötig.
    /// Erstellt keine wiederverwendbaren Engine-Instanzen — die werden
    /// in `start()` pro Diktat frisch aufgesetzt.
    public func prepare() async throws {
        let locale = resolveLocale()

        let supported = await SpeechTranscriber.supportedLocales
            .map { $0.identifier(.bcp47) }
        guard supported.contains(locale.identifier(.bcp47)) else {
            throw TranscriptionError.localeNotSupported
        }

        let installed = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }
        if !installed.contains(locale.identifier(.bcp47)) {
            // Asset-Install benötigt ein Probe-Transcriber-Exemplar.
            // Wir verwerfen es nach dem Download — `start()` baut einen
            // frischen.
            let probe = SpeechTranscriber(
                locale: locale,
                preset: .progressiveTranscription)
            if let request = try await AssetInventory
                .assetInstallationRequest(supporting: [probe]) {
                try await request.downloadAndInstall()
            }
        }

        localeReady = true
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard localeReady else { throw TranscriptionError.notPrepared }
        let locale = resolveLocale()
        // `.progressiveTranscription`-Preset emittiert Apple-seitig
        // partial Results live während der Aufnahme. Der default
        // `.transcription`-Preset batched alle Updates erst beim
        // `analyzer.finalize()` (verifiziert über headless Smoke +
        // Body-Render-Timestamps).
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer
            .bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            // Ohne kompatibles Audioformat kann der Analyzer nichts empfangen —
            // sofort scheitern statt still alle Buffer zu verwerfen.
            throw TranscriptionError.modelUnavailable
        }
        // Backpressure: SpeechAnalyzer ist langsamer als die Audio-Tap-Rate.
        // Ohne Limit würde die Queue zwischen Audio-Stream und Analyzer
        // unbegrenzt wachsen (Symptom: RAM-Anstieg, MainActor-Stau).
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(16))
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder

        try await analyzer.start(inputSequence: inputSequence)

        // Audio → Analyzer.
        // BufferConverter ist nicht Sendable und muss in den unstrukturierten
        // Task übertragen werden. Das ist sicher, weil ausschließlich dieser
        // eine Task `converter` aufruft — ein zweites start() vor stop() wäre
        // eine Protokollverletzung.
        struct SendableConverter: @unchecked Sendable { let value: BufferConverter }
        let audioStream = try audioCapture.startStream()
        let sendableConverter = SendableConverter(value: converter)
        Task { [inputBuilder, sendableConverter] in
            for await captured in audioStream {
                guard let pcm = captured.pcmBuffer as? AVAudioPCMBuffer else { continue }
                if let converted = try? sendableConverter.value.convert(pcm, to: analyzerFormat) {
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                }
            }
        }

        // Analyzer-Ergebnisse → TranscriptionUpdate.
        //
        // SpeechTranscriber feuert pro Utterance ZUERST mehrere non-final
        // Updates mit wachsendem partial-Text, DANN einen einzelnen
        // `result.isFinal=true`-Eintrag, der die Utterance abschließt.
        // Bei längeren Aufnahmen mit Pausen wiederholt sich dieser
        // Zyklus mehrmals.
        //
        // Wir akkumulieren intern: bereits finalisierte Segmente
        // bilden den committed Anteil; das laufende partial wird
        // pro Update angehängt. Die UI rendert genau diesen
        // kombinierten Text.
        return AsyncThrowingStream { continuation in
            Task {
                var accumulated = ""   // committed seit Aufnahmebeginn
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if result.isFinal {
                            // Segment abgeschlossen — in den Akkumulator
                            if !text.isEmpty {
                                accumulated = accumulated.isEmpty
                                    ? text
                                    : accumulated + " " + text
                            }
                            continuation.yield(TranscriptionUpdate(text: accumulated))
                        } else {
                            // Laufende Hypothese der aktuellen Utterance —
                            // an akkumulierten Stand anhängen, damit die UI
                            // immer den vollen aktuellen Text sieht.
                            let combined: String
                            if accumulated.isEmpty {
                                combined = text
                            } else if text.isEmpty {
                                combined = accumulated
                            } else {
                                combined = accumulated + " " + text
                            }
                            continuation.yield(TranscriptionUpdate(text: combined))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func stop() async {
        audioCapture.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        if let analyzer {
            // Apple's `finalizeAndFinishThroughEndOfInput` kann in seltenen
            // Fällen hängen (z. B. wenn der Audio-Render-Thread noch eine
            // Buffer-Drain durchführt). Mit 2 s Timeout brechen wir ab,
            // damit der DictationCoordinator nicht für immer in .finalizing
            // sitzt und der nächste Hotkey-Press das Diktat blockiert.
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                _ = await group.next()
                group.cancelAll()
            }
        }
        analyzer = nil
    }
}
