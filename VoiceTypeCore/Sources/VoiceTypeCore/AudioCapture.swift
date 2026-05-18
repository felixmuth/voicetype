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
    private var levelTickCounter: Int = 0

    public init() {}

    public func startStream() throws -> AsyncStream<CapturedAudio> {
        // Schutz gegen doppeltes Starten: AVAudioNode erlaubt nur einen Tap
        // pro Bus — ein zweiter installTap würde eine NSException werfen.
        // stop() ist auch dann sicher, wenn noch nichts läuft.
        stop()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Backpressure: wenn der Consumer (AppleSpeechEngine) hinterherhängt,
        // alten Audio-Buffer droppen statt unendlich queuen. Sonst frisst der
        // Stream RAM ohne Limit und der MainActor erstickt.
        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream(
            bufferingPolicy: .bufferingNewest(16))
        self.continuation = continuation
        levelTickCounter = 0

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.rms(of: buffer)
            self.continuation?.yield(CapturedAudio(pcmBuffer: buffer, level: level))
            // onLevel-Throttling: nur jeder 4. Buffer (~25 Hz bei 1024
            // Samples / 44.1 kHz) löst den MainActor-Hop aus. Vorher
            // produzierte jeder Buffer einen `Task { @MainActor }`, was
            // bei blockiertem MainActor zu Task-Stau, RAM-Wachstum und
            // 100 %-CPU-Loop führte.
            // Throttling auf jeden 2. Buffer (~22 Hz Update-Rate bei
            // 1024 Samples / 44.1 kHz) — feiner Kompromiss zwischen
            // Wellenform-Reaktivität und MainActor-Last.
            self.levelTickCounter &+= 1
            guard self.levelTickCounter % 2 == 0 else { return }
            if let captured = self.onLevel {
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
