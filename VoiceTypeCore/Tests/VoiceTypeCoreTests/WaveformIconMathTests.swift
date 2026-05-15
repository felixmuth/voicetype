import Testing
@testable import VoiceTypeCore

@Suite struct WaveformIconMathTests {

    @Test func inactiveProducesThreeFlatBars() {
        let h = BarHeight.heights(active: false, recording: false, level: 0.5, phase: 1.23)
        #expect(h.count == 3)
        #expect(h.allSatisfy { $0 == BarHeight.baseline })
    }

    @Test func activeProducesFiveBars() {
        let h = BarHeight.heights(active: true, recording: true, level: 0.5, phase: 0)
        #expect(h.count == 5)
    }

    @Test func activeRecordingAtZeroLevelStillWiggles() {
        // Selbst bei level=0 sorgt die Mindest-Amplitude dafür, dass
        // mindestens ein Balken sichtbar höher ist als baseline.
        let h = BarHeight.heights(active: true, recording: true, level: 0, phase: 0)
        #expect(h.max()! > BarHeight.baseline)
    }

    @Test func higherLevelProducesHigherBars() {
        // Bei recording-Mode skaliert level die Amplitude → max(level=1)
        // muss höher sein als max(level=0).
        let low  = BarHeight.heights(active: true, recording: true, level: 0,   phase: 0).max()!
        let high = BarHeight.heights(active: true, recording: true, level: 1.0, phase: 0).max()!
        #expect(high > low)
    }

    @Test func processingModeUsesConstantAmplitude() {
        // Im Verarbeitungs-Modus (active=true, recording=false) wird level
        // ignoriert — Werte für level=0 und level=1 sind identisch.
        let a = BarHeight.heights(active: true, recording: false, level: 0,   phase: 0.5)
        let b = BarHeight.heights(active: true, recording: false, level: 1.0, phase: 0.5)
        #expect(a == b)
    }
}
