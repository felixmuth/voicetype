import AVFoundation

/// Wandelt AVAudioPCMBuffer in ein Zielformat um (z. B. das von
/// SpeechAnalyzer geforderte). Hält einen AVAudioConverter pro Formatpaar.
final class BufferConverter {
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?
    private var lastOutputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == outputFormat { return buffer }

        if converter == nil || lastInputFormat != inputFormat || lastOutputFormat != outputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            lastInputFormat = inputFormat
            lastOutputFormat = outputFormat
        }
        guard let converter else { throw TranscriptionError.modelUnavailable }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw TranscriptionError.modelUnavailable
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return output
    }
}
