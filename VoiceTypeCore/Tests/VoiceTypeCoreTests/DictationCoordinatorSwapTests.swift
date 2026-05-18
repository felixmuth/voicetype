import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct DictationCoordinatorSwapTests {

    private func makeCoordinator(
        engine: TranscriptionEngine,
        cleanup: TextCleanup = MockCleanup()
    ) -> (DictationCoordinator, AppState, MockTextDelivery, MockFocusInspector) {
        let state = AppState()
        let delivery = MockTextDelivery()
        let focus = MockFocusInspector()
        let coord = DictationCoordinator(
            engine: engine, cleanup: cleanup,
            delivery: delivery, focus: focus, appState: state)
        return (coord, state, delivery, focus)
    }

    @Test func swapAppliesImmediatelyWhenIdle() async {
        let oldEngine = MockTranscriptionEngine()
        let newEngine = MockTranscriptionEngine()
        let (coord, state, _, _) = makeCoordinator(engine: oldEngine)
        await coord.prepare()
        #expect(state.dictationState == .idle)

        await coord.requestSwap(engine: newEngine)
        #expect(newEngine.prepareCallCount == 1)
        #expect(state.dictationState == .idle)
    }

    @Test func swapIsBufferedWhileRecordingAndAppliedAfterFinish() async {
        let oldEngine = MockTranscriptionEngine()
        let newEngine = MockTranscriptionEngine()
        let (coord, state, _, _) = makeCoordinator(engine: oldEngine)
        await coord.prepare()
        coord.startDictation()
        for _ in 0..<5 { await Task.yield() }
        #expect(state.dictationState == .recording)

        await coord.requestSwap(engine: newEngine)
        #expect(newEngine.prepareCallCount == 0, "swap must wait for idle")

        oldEngine.emit("hallo welt", isFinal: true)
        oldEngine.finishStream()
        coord.endDictation(heldFor: .seconds(1))
        await waitUntilIdle(state: state)
        #expect(newEngine.prepareCallCount == 1)
        #expect(state.dictationState == .idle)
    }

    @Test func swapPrepareFailureSurfacesError() async {
        let oldEngine = MockTranscriptionEngine()
        let brokenEngine = MockTranscriptionEngine()
        brokenEngine.prepareError = TranscriptionError.modelUnavailable
        let (coord, state, _, _) = makeCoordinator(engine: oldEngine)
        await coord.prepare()

        await coord.requestSwap(engine: brokenEngine)
        if case .error = state.dictationState {} else {
            Issue.record("expected .error after failed swap, got \(state.dictationState)")
        }

        // Smoke: nach prepare() ist die alte Engine wieder benutzbar
        await coord.prepare()
        coord.startDictation()
        for _ in 0..<5 { await Task.yield() }
        #expect(state.dictationState == .recording)
        #expect(oldEngine.prepareCallCount >= 2)
    }

    @Test func cleanupSwapAffectsNextDictationOutput() async {
        let engine = MockTranscriptionEngine()
        let oldCleanup = MockCleanup()
        let newCleanup = MockCleanup()
        newCleanup.transform = { _ in "neu" }
        let (coord, state, delivery, _) = makeCoordinator(
            engine: engine, cleanup: oldCleanup)
        await coord.prepare()

        await coord.requestSwap(cleanup: newCleanup)

        coord.startDictation()
        for _ in 0..<5 { await Task.yield() }
        engine.emit("rohtext", isFinal: true)
        engine.finishStream()
        coord.endDictation(heldFor: .seconds(1))
        await waitUntilIdle(state: state)
        #expect(delivery.deliveredText == "neu")
    }

    private func waitUntilIdle(state: AppState) async {
        for _ in 0..<200 {
            await Task.yield()
            if state.dictationState == .idle { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("did not reach .idle within time budget")
    }
}
