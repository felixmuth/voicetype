import Foundation
import AVFoundation
import FluidAudio
import VoiceTypeCore
import OSLog

/// TranscriptionEngine auf Basis von FluidInference/FluidAudio
/// (Parakeet TDT 0.6B v3/v2, CoreML, ANE-beschleunigt).
///
/// **Architektur (rein Vollbuffer-basiert):**
/// 1. AudioCapture liefert Mikrofon-Buffer → wir konvertieren auf
///    16 kHz mono Float32 und sammeln die Samples in
///    `audioBufferSamples`.
/// 2. **Live-Preview-Loop** alle 1.2 s: transkribiert den bisher
///    gesammelten Audio-Buffer einmal frisch via `livePreviewAsr`
///    (eigener AsrManager, eigener Decoder-State pro Pass). Yieldet
///    das Ergebnis, sofern es länger ist als der zuletzt geyieldete
///    Stand.
/// 3. Beim `stop()`: finaler Pass über den vollständigen Buffer via
///    `finalAsr` — derselbe Code-Pfad, aber in eigener Aktor-Mailbox,
///    damit der Stop nicht hinter dem Live-Loop warten muss.
///
/// **Bewusst nicht verwendet**: FluidAudio's `SlidingWindowAsrManager`.
/// Dessen streaming-Decoder-State ist nach Pausen unzuverlässig
/// (siehe FluidAudio-eigenen Kommentar in `AsrManager+TokenProcessing.swift:100`).
/// Wir umgehen das, indem wir jeden Pass mit frischem Decoder-State
/// über den ganzen Buffer fahren — derselbe Pfad, den deren Batch-CLI
/// auch nutzt.
///
/// Liegt in einem eigenen SPM-Package, weil FluidAudio gegen
/// `swift-transformers` resolved und sich sonst mit dem
/// WhisperKit-Resolver beißt.
public actor ParakeetEngine: TranscriptionEngine {

    private static let log = Logger(
        subsystem: "com.felixmuth.VoiceType",
        category: "ParakeetEngine")

    private let audioCapture: AudioCapturing
    private let modelFolder: URL
    private let modelId: String
    private let onLevel: (@Sendable (Float) -> Void)?

    /// FluidAudio-`AsrModelVersion` aus unserer Modell-ID ableiten —
    /// .v2 für English-only, .v3 für multilingual.
    private var modelVersion: AsrModelVersion {
        modelId.contains("v2") ? .v2 : .v3
    }

    private var models: AsrModels?
    /// AsrManager für den finalen Pass beim `stop()`.
    private var finalAsr: AsrManager?
    /// Zweiter AsrManager dediziert für den Live-Preview-Loop —
    /// teilt sich das gleiche Models-Bundle (`loadModels` ist nur
    /// ein Referenz-Assign), läuft aber in seiner eigenen Aktor-
    /// Mailbox, damit Live-Pässe nicht hinter dem `finalAsr` warten
    /// müssen, wenn der gerade beim Stop transkribiert.
    private var livePreviewAsr: AsrManager?
    private var feedTask: Task<Void, Never>?
    /// Periodischer Live-Preview-Loop: alle ~1.2 s transkribiert er
    /// den gesamten bisherigen Audio-Buffer einmal frisch.
    private var livePreviewTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?
    /// Gesamtes Mikrofon-Audio in 16 kHz Float32.
    private var audioBufferSamples: [Float] = []
    /// Letzter an die UI geyieldeter Text — wir yielden nur dann
    /// einen neuen Stand, wenn er **länger** ist (kein Backwards-
    /// Reveal in der UI, kein Flackern bei kürzeren Re-Transkribierungen).
    private var lastYieldedText: String = ""

    /// Wir konvertieren jede AudioCapture-Buffer von der nativen
    /// Mikrofon-Sample-Rate auf das von Parakeet erwartete Format
    /// (16 kHz, mono, Float32, non-interleaved).
    private let bufferConverter = BufferConverter()
    private let targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false)!
    }()

    public init(
        audioCapture: AudioCapturing,
        modelFolder: URL,
        modelId: String,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) {
        self.audioCapture = audioCapture
        self.modelFolder = modelFolder
        self.modelId = modelId
        self.onLevel = onLevel
    }

    public func prepare() async throws {
        do {
            let loaded = try await AsrModels.load(
                from: modelFolder,
                version: modelVersion)
            self.models = loaded
            // Persistenter Final-Pass-Manager.
            let final = AsrManager(config: .default)
            try await final.loadModels(loaded)
            self.finalAsr = final
            // Zweiter Manager für den Live-Preview-Loop.
            let live = AsrManager(config: .default)
            try await live.loadModels(loaded)
            self.livePreviewAsr = live
        } catch {
            throw TranscriptionError.modelUnavailable
        }
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard models != nil else { throw TranscriptionError.notPrepared }
        audioBufferSamples = []
        audioBufferSamples.reserveCapacity(16_000 * 30)   // ~30s @ 16 kHz
        lastYieldedText = ""

        let (stream, continuation) =
            AsyncThrowingStream<TranscriptionUpdate, Error>.makeStream()
        self.continuation = continuation

        let format = self.targetFormat

        // ─── Audio rein → audioBufferSamples ─────────────────────
        let audioStream = try audioCapture.startStream()
        let levelCallback = self.onLevel

        struct SendableConverter: @unchecked Sendable {
            let value: BufferConverter
        }
        let sendableConverter = SendableConverter(value: bufferConverter)

        feedTask = Task { [weak self] in
            for await captured in audioStream {
                levelCallback?(captured.level)
                guard let pcm = captured.pcmBuffer as? AVAudioPCMBuffer else { continue }
                guard let converted = try? sendableConverter.value.convert(
                    pcm, to: format) else { continue }
                // Samples für die Inferenz mitschneiden. `converted` ist
                // 16 kHz mono Float32 non-interleaved.
                if let channelData = converted.floatChannelData?[0] {
                    let count = Int(converted.frameLength)
                    let copy = Array(UnsafeBufferPointer(start: channelData, count: count))
                    await self?.appendAudioSamples(copy)
                }
            }
        }

        // ─── Live-Preview-Loop ────────────────────────────────────
        // Alle 1.2 s den ganzen Audio-Buffer einmal frisch
        // transkribieren — die UI wird damit kontinuierlich
        // aktualisiert. Wir nutzen denselben Code-Pfad wie beim Stop,
        // nur auf dediziertem AsrManager.
        if let live = livePreviewAsr {
            livePreviewTask = Task { [weak self, live] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1200))
                    if Task.isCancelled { return }
                    await self?.runFreshPass(asr: live, isFinal: false)
                }
            }
        }
        Self.log.notice("Recording gestartet (Vollbuffer-Modus)")

        return stream
    }

    public func stop() async {
        audioCapture.stop()
        feedTask?.cancel()
        feedTask = nil
        // Live-Preview-Loop zuerst stoppen, damit er nicht parallel
        // zum finalen Pass läuft (würde sich um ANE-Slots streiten).
        livePreviewTask?.cancel()
        livePreviewTask = nil

        // Finaler Pass über den GANZEN Buffer.
        if let finalAsr {
            await runFreshPass(asr: finalAsr, isFinal: true)
        }

        continuation?.finish()
        continuation = nil
        audioBufferSamples = []
        lastYieldedText = ""
    }

    // MARK: - Helpers

    /// Hängt 16-kHz-mono-Float-Samples aus dem `feedTask` an den
    /// Buffer an. Wird vom `feedTask` per `await` aufgerufen — die
    /// Aktor-Isolation des `ParakeetEngine` serialisiert die Appends,
    /// sodass keine Race-Condition mit `stop()` oder dem Loop möglich
    /// ist.
    private func appendAudioSamples(_ samples: [Float]) {
        audioBufferSamples.append(contentsOf: samples)
    }

    /// Fresh-Pass: transkribiert den aktuellen Audio-Buffer einmal
    /// frisch mit eigenem Decoder-State und yieldet das Ergebnis.
    /// - `isFinal=false`: nur yielden, wenn das Ergebnis **länger**
    ///   ist als der zuletzt geyieldete Stand. Verhindert Backwards-
    ///   Reveal in der UI.
    /// - `isFinal=true`: immer yielden — das ist der Stop-Pass und
    ///   liefert den finalen Text für den Coordinator.
    private func runFreshPass(asr: AsrManager, isFinal: Bool) async {
        guard audioBufferSamples.count >= 16_000 * 1 else {
            // <1 s Audio — bei isFinal=true trotzdem leer yielden,
            // damit der Coordinator weiß, dass nichts erkannt wurde.
            if isFinal {
                continuation?.yield(TranscriptionUpdate(text: ""))
            }
            return
        }
        let snapshot = audioBufferSamples

        let text: String
        do {
            var state = TdtDecoderState.make()
            let result = try await asr.transcribe(
                snapshot, decoderState: &state, language: nil)
            text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            Self.log.error(
                "transcribe fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            if isFinal {
                // Auch beim Fehler ein leeres Final-Update senden,
                // damit der Coordinator nicht hängt.
                continuation?.yield(TranscriptionUpdate(text: lastYieldedText))
            }
            return
        }

        if isFinal {
            Self.log.notice(
                "stop() final-len=\(text.count, privacy: .public)")
            lastYieldedText = text
            continuation?.yield(TranscriptionUpdate(text: text))
            return
        }

        // Live-Pass: nur yielden, wenn länger als bisheriger Stand.
        guard text.count > lastYieldedText.count else {
            Self.log.notice(
                "live-pass skip — len=\(text.count, privacy: .public) <= prior=\(self.lastYieldedText.count, privacy: .public)")
            return
        }
        Self.log.notice(
            "live-pass yield — len=\(text.count, privacy: .public) > prior=\(self.lastYieldedText.count, privacy: .public)")
        lastYieldedText = text
        continuation?.yield(TranscriptionUpdate(text: text))
    }
}
