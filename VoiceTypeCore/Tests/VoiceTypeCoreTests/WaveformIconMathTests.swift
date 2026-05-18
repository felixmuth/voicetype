import Testing
@testable import VoiceTypeCore

@Suite struct WaveformIconMathTests {

    @Test func notSpeakingProducesFiveFlatBars() {
        let h = BarHeight.heights(speaking: false, phase: 1.23)
        #expect(h.count == 5)
        #expect(h.allSatisfy { $0 == BarHeight.baseline })
    }

    @Test func speakingProducesFiveBars() {
        let h = BarHeight.heights(speaking: true, phase: 0)
        #expect(h.count == 5)
    }

    @Test func speakingProducesAtLeastOneBarAboveBaseline() {
        let bars = (0..<10).map { i -> Double in
            BarHeight.heights(speaking: true, phase: Double(i) * 0.1).max()!
        }
        #expect(bars.max()! > BarHeight.baseline)
    }

    @Test func speakingAmplitudeIsLevelIndependent() {
        // Die neue API kennt keinen Level mehr — gleicher Phase →
        // gleiche Heights, unabhängig von irgendeiner Lautstärke-Quelle.
        let a = BarHeight.heights(speaking: true, phase: 0.5)
        let b = BarHeight.heights(speaking: true, phase: 0.5)
        #expect(a == b)
    }
}
