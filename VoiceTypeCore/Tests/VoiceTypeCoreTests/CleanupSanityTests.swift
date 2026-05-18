import Testing
@testable import VoiceTypeCore

@Suite struct CleanupSanityTests {
    @Test func emptyOutputFallsBackToRaw() {
        #expect(CleanupSanity.accepted(raw: "abc", modelOutput: "") == "abc")
    }

    @Test func whitespaceOnlyOutputFallsBackToRaw() {
        #expect(CleanupSanity.accepted(raw: "abc", modelOutput: "  \n ") == "abc")
    }

    @Test func tooShortOutputFallsBackToRaw() {
        let raw = String(repeating: "a", count: 40)
        let out = String(repeating: "b", count: 10)
        #expect(CleanupSanity.accepted(raw: raw, modelOutput: out) == raw)
    }

    @Test func tooLongOutputFallsBackToRaw() {
        let raw = String(repeating: "a", count: 10)
        let out = String(repeating: "b", count: 30)
        #expect(CleanupSanity.accepted(raw: raw, modelOutput: out) == raw)
    }

    @Test func normalOutputIsTrimmed() {
        #expect(CleanupSanity.accepted(
            raw: "hallo welt", modelOutput: "  Hallo Welt.  ") == "Hallo Welt.")
    }

    @Test func emptyRawReturnsEmptyRaw() {
        #expect(CleanupSanity.accepted(raw: "", modelOutput: "anything") == "")
    }
}
