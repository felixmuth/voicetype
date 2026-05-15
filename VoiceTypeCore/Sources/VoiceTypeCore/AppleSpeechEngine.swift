import Foundation
import Speech
import AVFoundation

/// TranscriptionEngine auf Basis von SpeechAnalyzer/SpeechTranscriber
/// (macOS 26, on-device, streaming). Konsumiert ein AudioCapturing.
public actor AppleSpeechEngine: TranscriptionEngine {
    private let audioCapture: AudioCapturing
    private let language: String          // "auto" | "de" | "en"

    private var transcriber: SpeechTranscriber?
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

    public func prepare() async throws {
        let locale = resolveLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        let supported = await SpeechTranscriber.supportedLocales
            .map { $0.identifier(.bcp47) }
        guard supported.contains(locale.identifier(.bcp47)) else {
            throw TranscriptionError.localeNotSupported
        }

        let installed = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }
        if !installed.contains(locale.identifier(.bcp47)) {
            if let request = try await AssetInventory
                .assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        self.transcriber = transcriber
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard let transcriber else { throw TranscriptionError.notPrepared }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let analyzerFormat = await SpeechAnalyzer
            .bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            // Ohne kompatibles Audioformat kann der Analyzer nichts empfangen —
            // sofort scheitern statt still alle Buffer zu verwerfen.
            throw TranscriptionError.modelUnavailable
        }
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
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

        // Analyzer-Ergebnisse → TranscriptionUpdate
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(TranscriptionUpdate(
                            text: String(result.text.characters),
                            isFinal: result.isFinal))
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
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
    }
}
