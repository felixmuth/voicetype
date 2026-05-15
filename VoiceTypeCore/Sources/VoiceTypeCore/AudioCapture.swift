import AVFoundation

/// Nimmt das Mikrofon über AVAudioEngine auf und liefert die Puffer als
/// AsyncStream. Pro Puffer wird der RMS-Pegel (0…1) mitgegeben.
///
/// Threading: `startStream()`/`stop()` werden vom MainActor aufgerufen, der
/// Tap-Callback läuft auf dem Audio-Render-Thread. `continuation` wird damit
/// von zwei Threads berührt. In Plan 1 ist das sicher, weil der einzige
/// Aufrufer (AppleSpeechEngine über den DictationCoordinator) start/stop
/// strikt serialisiert und `yield` nach `finish()` ein dokumentierter No-op
/// ist. `@unchecked Sendable` ist genau dieser kontrollierten Nutzung wegen
/// gerechtfertigt.
public final class AudioCapture: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<CapturedAudio>.Continuation?
    public var onLevel: (@MainActor (Float) -> Void)?

    public init() {}

    public func startStream() throws -> AsyncStream<CapturedAudio> {
        // Schutz gegen doppeltes Starten: AVAudioNode erlaubt nur einen Tap
        // pro Bus — ein zweiter installTap würde eine NSException werfen.
        // stop() ist auch dann sicher, wenn noch nichts läuft.
        stop()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream()
        self.continuation = continuation

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = Self.rms(of: buffer)
            self?.continuation?.yield(CapturedAudio(pcmBuffer: buffer, level: level))
            // onLevel auf MainActor liefern — die Closure ist
            // `@MainActor`-isoliert, also über einen Task auf den
            // MainActor hoppen statt GCD-Mix.
            let captured: (@MainActor (Float) -> Void)? = self?.onLevel
            if let captured {
                Task { @MainActor in captured(level) }
            }
        }

        engine.prepare()
        try engine.start()
        return stream
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        let samples = channelData[0]
        for i in 0..<frames { sum += samples[i] * samples[i] }
        return min(1, (sum / Float(frames)).squareRoot() * 6)
    }
}
