import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct AppStateTests {
    @Test func startsInLoadingStateWithEmptyLog() {
        let state = AppState()
        #expect(state.dictationState == .loading)
        #expect(state.log.isEmpty)
        #expect(state.livePreview == "")
        #expect(state.micLevel == 0)
    }

    @Test func addEntryPrependsNewestFirst() {
        let state = AppState()
        state.addEntry("erster")
        state.addEntry("zweiter")
        #expect(state.log.count == 2)
        #expect(state.log.first?.text == "zweiter")
    }

    @Test func addEntryIgnoresEmptyText() {
        let state = AppState()
        state.addEntry("   ")
        #expect(state.log.isEmpty)
    }
}
