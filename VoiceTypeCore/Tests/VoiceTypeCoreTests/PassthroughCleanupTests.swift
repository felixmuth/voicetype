import Testing
@testable import VoiceTypeCore

@Suite struct PassthroughCleanupTests {
    @Test func returnsInputUnchanged() async {
        let cleanup = PassthroughCleanup()
        let result = await cleanup.cleanup("ähm das ist ein test")
        #expect(result == "ähm das ist ein test")
    }
}
