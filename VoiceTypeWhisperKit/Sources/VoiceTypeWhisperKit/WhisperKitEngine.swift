import Foundation
import VoiceTypeCore
import WhisperKit

/// TranscriptionEngine auf Basis von WhisperKit (0.18+). Lädt Modelle
/// niemals selbst aus dem Netz — der `modelFolder` muss bereits
/// vollständig befüllt sein (das macht `WhisperKitDownloader` aus der
/// `ModelRegistry`-Pipeline).
///
/// Streaming via Argmax' `AudioStreamTranscriber`: kontinuierliche
/// Realtime-Loop, eingebaute VAD, Sliding-Window über
/// `clipTimestamps`-Mechanismus, plus Segment-Confirmation (ältere
/// Segmente werden „committed", neuere bleiben „unconfirmed"). Der
/// Mikrofon-Zugriff erfolgt durch WhisperKit's eigenen `AudioProcessor`
/// — der von uns sonst genutzte `AudioCapture` wird im WhisperKit-Pfad
/// nicht gestartet. Der `bufferEnergy`-Strom aus dem Streamer wird über
/// `onLevel` an den Coordinator weitergereicht, damit Wellenform und
/// VAD-Pulse weiter funktionieren.
///
/// Liegt in einem eigenen SPM-Package, weil WhisperKit gegen
/// `swift-transformers 1.1.x` resolved, mlx-swift-examples gegen
/// `1.0.x`/`0.1.x` — beide gleichzeitig im gleichen Package-Graph
/// erzeugen einen Resolver-Konflikt.
public actor WhisperKitEngine: TranscriptionEngine {

    private let modelFolder: URL
    private let language: String
    private let onLevel: (@Sendable (Float) -> Void)?

    private var pipe: WhisperKit?
    private var streamer: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
    /// Letzter aus dem State-Callback abgeleiteter Vorschau-Text.
    /// Beim `stop()` wird der als finales Update gefeuert, damit der
    /// DictationCoordinator ihn als `latestFinalText` einsammelt und
    /// an die Cleanup-/Delivery-Pipeline weiterreicht.
    private var lastPreview: String = ""

    /// - Parameter onLevel: wird vom AudioStreamTranscriber-State-Callback
    ///   bei jedem Audio-Buffer-Update aus `bufferEnergy.last` gefeuert.
    ///   Wir reichen es 1:1 an den DictationCoordinator weiter, der dort
    ///   den `isSpeaking`-Flag + Wellenform-Animation ableitet.
    public init(
        modelFolder: URL,
        language: String,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) {
        self.modelFolder = modelFolder
        self.language = language
        self.onLevel = onLevel
    }

    public func prepare() async throws {
        do {
            // `tokenizerFolder = modelFolder` zwingt WhisperKit, den
            // Tokenizer aus unserem lokalen Bundle (tokenizer.json
            // direkt neben den .mlmodelc-Files) zu laden — sonst
            // versucht es einen 120-s-Hub-Call gegen
            // `openai/whisper-large-v3`, der typischerweise hängt.
            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                tokenizerFolder: modelFolder,
                verbose: false,
                logLevel: .error,
                download: false)
            pipe = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.modelUnavailable
        }
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard let pipe = pipe, let tokenizer = pipe.tokenizer else {
            throw TranscriptionError.notPrepared
        }
        lastPreview = ""

        let lang: String? = language == "auto" ? nil : language
        // `withoutTimestamps: false` ist Pflicht — der Streamer braucht
        // Segment-Timestamps, um `clipTimestamps` (Sliding-Window-Start)
        // zu setzen.
        // `skipSpecialTokens: true` filtert Whisper-Steuer-Tokens
        // (`<|startoftranscript|>`, `<|de|>`, `<|0.26|>`,
        // `<|endoftext|>`) aus dem ausgegebenen `segment.text` —
        // Default ist `false`, was sonst die Tokens 1:1 in der
        // Live-Vorschau erscheinen lässt.
        let options = DecodingOptions(
            language: lang,
            skipSpecialTokens: true,
            withoutTimestamps: false)

        let (stream, continuation) =
            AsyncThrowingStream<TranscriptionUpdate, Error>.makeStream()
        self.continuation = continuation

        // Closure-State: hier landen die State-Updates des Streamers.
        // Wir kapseln das in einem class wrapper, damit das Closure
        // sowohl `lastPreview` aktualisieren als auch an die
        // `WhisperKitEngine` zurückreichen kann.
        let levelCallback = self.onLevel
        let previewSink = PreviewSink()
        // WhisperKits Sub-Komponenten sind aktuell nicht Sendable.
        // Wir bündeln sie in einem @unchecked Sendable Container —
        // die Übergabe an den AudioStreamTranscriber-Actor erfolgt
        // nur einmalig hier, danach lebt jede Komponente exklusiv im
        // Streamer; keine Race-Conditions möglich.
        let components = WhisperComponents(
            audioEncoder: pipe.audioEncoder,
            featureExtractor: pipe.featureExtractor,
            segmentSeeker: pipe.segmentSeeker,
            textDecoder: pipe.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: pipe.audioProcessor)
        let streamer = AudioStreamTranscriber(
            audioEncoder: components.audioEncoder,
            featureExtractor: components.featureExtractor,
            segmentSeeker: components.segmentSeeker,
            textDecoder: components.textDecoder,
            tokenizer: components.tokenizer,
            audioProcessor: components.audioProcessor,
            decodingOptions: options,
            // `requiredSegmentsForConfirmation: 0` → jedes vom
            // Streamer fertig dekodierte Segment wandert sofort in
            // `confirmedSegments` und ist damit „committed". WhisperKit
            // re-transkribiert nur noch Audio NACH
            // `lastConfirmedSegmentEndSeconds` → committedText kann
            // sich nie mehr ändern. Vorher (Default 2) blieben die
            // letzten 2 Segmente in `unconfirmedSegments` hängen und
            // wurden jeden Zyklus neu inferiert (oft mit minimal
            // verändertem Wortlaut) → Vorschau-Flicker.
            requiredSegmentsForConfirmation: 0,
            silenceThreshold: 0.3,
            useVAD: true,
            stateChangeCallback: { _, newState in
                // bufferEnergy: letzter Eintrag ≈ aktuelle relative
                // Mikrofon-Energie (0–1, normalisiert auf min-Energy
                // im rolling window). Direkt an den Coordinator-Level
                // weiterreichen — dort macht die VAD-Logik den Rest.
                if let level = newState.bufferEnergy.last {
                    levelCallback?(level)
                }
                let preview = Self.compose(newState: newState)
                // Zwischen zwei Transcribe-Cycles hat der Streamer
                // kurz alle Text-Felder geleert (currentText="",
                // unconfirmedSegments=[], BEVOR die neuen Segmente
                // landen). Würden wir den Empty yielden, blinkt die
                // UI auf "" zurück und der Coordinator droht beim
                // Stop einen leeren Final-String einzusammeln.
                // Daher: leere Zwischenstände einfach skippen.
                guard !preview.isEmpty else { return }
                previewSink.set(preview)
                // Live-Update an die UI. Nicht `isFinal`, damit der
                // Coordinator den Text in `composePreview(partial:)`
                // routet und nicht in `appendFinalSegment(...)`.
                continuation.yield(TranscriptionUpdate(
                    text: preview, isFinal: false))
            })
        self.streamer = streamer

        // Wir spawnen das Starten des Streamers in einem Task, weil
        // `startStreamTranscription()` erst zurückkehrt, wenn die
        // Realtime-Loop endet — und die endet erst beim Stop.
        streamTask = Task { [streamer, continuation] in
            do {
                try await streamer.startStreamTranscription()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        // Wir merken uns die Sink, damit `stop()` den letzten Preview
        // als Final-Update verschicken kann.
        previewSinks[ObjectIdentifier(streamer)] = previewSink
        return stream
    }

    public func stop() async {
        // Vor dem Stopp: kompletten Audio-Buffer snapshoten — der
        // Realtime-Loop hat die letzten 1–2 s typischerweise nicht
        // mehr transkribiert (Loop-Iteration läuft alle ~1 s, fn-
        // Release fällt meistens dazwischen).
        let fullBuffer: [Float]
        if let pipe = pipe {
            fullBuffer = Array(pipe.audioProcessor.audioSamples)
        } else {
            fullBuffer = []
        }
        if let streamer {
            await streamer.stopStreamTranscription()
        }
        streamTask = nil

        // Silence-Gate: Whisper halluziniert bei reiner Stille
        // gerne Trainings-Phrasen (z. B. „Vielen Dank",
        // „Untertitel von Stephanie Geiges"). Bevor wir den Final-
        // Pass starten, prüfen wir die Peak-Amplitude des Buffers.
        // Float-Samples sind -1…+1. Echte Sprache liegt bei
        // Peak ≥ 0.05; Raum-Stille typischerweise < 0.02.
        let peak = fullBuffer.lazy.map { abs($0) }.max() ?? 0
        let silenceThreshold: Float = 0.02
        guard peak >= silenceThreshold else {
            // Kein Final-Yield nötig — Coordinator behandelt
            // leeren Stream-Tail wie eine zu kurze Aufnahme:
            // `finishAfterStream` sieht latestFinalText="" und
            // springt direkt zurück nach .idle, ohne Cleanup
            // oder Delivery zu triggern.
            if let key = streamer.map(ObjectIdentifier.init) {
                previewSinks.removeValue(forKey: key)
            }
            continuation?.finish()
            continuation = nil
            streamer = nil
            return
        }

        // Final-Pass: ganzen Buffer einmal frisch transkribieren.
        // Das ist akkurater als der Streamer-State (der seinen
        // letzten 1–2 s vermisst) und ersetzt die Pseudo-1.5-s-
        // Wartezeit, die wir vorher hatten. Beim large-v3 kostet
        // das pro Sekunde Audio ~0.3–0.5 s — der Coordinator-
        // Watchdog (`max(8 s, heldFor + 5 s)`) deckt das ab.
        var final = ""
        if let pipe = pipe {
            let opts = DecodingOptions(
                language: language == "auto" ? nil : language,
                skipSpecialTokens: true,
                withoutTimestamps: true)
            // `WhisperKit` ist nicht Sendable; gleicher Trick wie
            // bei den Sub-Komponenten — @unchecked-Box für den
            // Async-Sprung.
            struct SendablePipe: @unchecked Sendable { let value: WhisperKit }
            let boxed = SendablePipe(value: pipe)
            if let result = try? await boxed.value.transcribe(
                audioArray: fullBuffer, decodeOptions: opts).first {
                final = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Letzten Streamer-Stand als Fallback ziehen, falls
        // pipe.transcribe leer zurückkommt (z. B. Buffer zu kurz
        // oder Whisper hat geworfen).
        if final.isEmpty,
           let key = streamer.map(ObjectIdentifier.init),
           let sink = previewSinks[key] {
            final = sink.get()
        }
        if let key = streamer.map(ObjectIdentifier.init) {
            previewSinks.removeValue(forKey: key)
        }

        continuation?.yield(TranscriptionUpdate(text: final, isFinal: true))
        continuation?.finish()
        continuation = nil
        streamer = nil
    }

    // MARK: - Helpers

    /// Komponiert die Vorschau aus zwei State-Bestandteilen:
    /// - `confirmedSegments`: committed Segmente. Mit
    ///   `requiredSegmentsForConfirmation: 0` landen Segmente direkt
    ///   hier — sie ändern sich nie mehr. Wächst monoton.
    /// - `currentText`: laufende Hypothese des aktuell aktiven
    ///   Decode-Passes (Audio NACH dem letzten committed Segment).
    ///   Diese hängt am Tail und „flickert" zwar während der Inferenz,
    ///   wird beim Abschluss aber zu einem committed Segment, das
    ///   stehen bleibt.
    ///
    /// `unconfirmedSegments` wird bewusst ignoriert — mit
    /// `requiredSegmentsForConfirmation: 0` ist es immer leer, und
    /// selbst falls WhisperKit hier doch was reinpackt, würde es nur
    /// zwischen Cycles flickern.
    private static func compose(newState: AudioStreamTranscriber.State) -> String {
        let confirmed = newState.confirmedSegments
            .map(\.text).joined(separator: " ")
        // AudioStreamTranscriber setzt `currentText` bei VAD-Stille
        // hartgecodet auf "Waiting for speech..." — wegfiltern, sonst
        // landet das in der UI und u. U. im Cleanup-/Delivery-Pfad.
        let live = newState.currentText == "Waiting for speech..."
            ? ""
            : newState.currentText
        return [confirmed, live]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Box für den letzten Preview-String. Wird vom (nicht-isolierten)
    /// Streamer-State-Callback geschrieben und vom `stop()`-Pfad
    /// gelesen. `OSAllocatedUnfairLock` sorgt für threadsafe Zugriff,
    /// ohne dass wir den ganzen Callback zum Actor hin awaiten müssen.
    private final class PreviewSink: @unchecked Sendable {
        private let lock = NSLock()
        private var value = ""
        func set(_ s: String) { lock.lock(); value = s; lock.unlock() }
        func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
    }
    /// Map vom Streamer-Identity zur Preview-Sink. Erlaubt dem
    /// `stop()`-Pfad, exakt die Sink des aktuellen Streamers zu
    /// holen, auch wenn `start()` zweimal hintereinander gerufen
    /// würde (defensiv).
    private var previewSinks: [ObjectIdentifier: PreviewSink] = [:]
}

/// Bündelt WhisperKit's Sub-Komponenten als @unchecked Sendable.
/// Notwendig, weil WhisperKit (Stand 0.18) seine Protokolle nicht
/// als `Sendable` markiert — wir müssen sie aber zwischen unserem
/// Actor (`WhisperKitEngine`) und dem WhisperKit-eigenen Actor
/// (`AudioStreamTranscriber`) herumreichen. Sicher, weil jede
/// Komponente nach der Übergabe exklusiv im Streamer-Actor lebt.
private struct WhisperComponents: @unchecked Sendable {
    let audioEncoder: any AudioEncoding
    let featureExtractor: any FeatureExtracting
    let segmentSeeker: any SegmentSeeking
    let textDecoder: any TextDecoding
    let tokenizer: any WhisperTokenizer
    let audioProcessor: any AudioProcessing
}
