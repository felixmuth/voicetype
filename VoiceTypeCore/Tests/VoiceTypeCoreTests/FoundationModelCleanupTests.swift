import Testing
@testable import VoiceTypeCore

@Suite struct FoundationModelCleanupTests {

    @Test func acceptsNormalOutputTrimmed() {
        let raw = "das ist ein Test"
        let modelOutput = "  Das ist ein Test.  "
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: modelOutput) == "Das ist ein Test.")
    }

    @Test func emptyOutputFallsBackToRaw() {
        let raw = "das ist ein Test"
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: "") == raw)
    }

    @Test func whitespaceOnlyOutputFallsBackToRaw() {
        let raw = "das ist ein Test"
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: "   \n  ") == raw)
    }

    @Test func tooShortOutputFallsBackToRaw() {
        // raw 40 Zeichen, Modell-Ausgabe 10 Zeichen → cleanedLen*2 (20) < rawLen (40) → Fallback
        let raw = String(repeating: "a", count: 40)
        let modelOutput = String(repeating: "b", count: 10)
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: modelOutput) == raw)
    }

    @Test func tooLongOutputFallsBackToRaw() {
        // raw 10 Zeichen, Modell-Ausgabe 30 Zeichen → 30 > rawLen*2 (20) → Fallback
        let raw = String(repeating: "a", count: 10)
        let modelOutput = String(repeating: "b", count: 30)
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: modelOutput) == raw)
    }

    @Test func lowerBoundaryRatioIsAccepted() {
        // raw 10 Zeichen, Modell-Ausgabe 5 Zeichen → 5*2 == 10 (nicht < 10) → akzeptiert
        let raw = String(repeating: "a", count: 10)
        let modelOutput = String(repeating: "b", count: 5)
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: modelOutput) == modelOutput)
    }

    @Test func upperBoundaryRatioIsAccepted() {
        // raw 10 Zeichen, Modell-Ausgabe 20 Zeichen → 20 == 10*2 (nicht > 20) → akzeptiert
        let raw = String(repeating: "a", count: 10)
        let modelOutput = String(repeating: "b", count: 20)
        #expect(CleanupSanity.accepted(
            raw: raw, modelOutput: modelOutput) == modelOutput)
    }

    @Test func emptyRawReturnsEmptyRaw() {
        // Edge Case: leerer Rohtext → Rohtext zurück, Modell-Ausgabe ignoriert.
        #expect(CleanupSanity.accepted(
            raw: "", modelOutput: "anything") == "")
    }
}
