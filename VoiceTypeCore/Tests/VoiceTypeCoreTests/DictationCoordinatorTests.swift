import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct DictationCoordinatorTests {

    private func makeCoordinator() -> (
        DictationCoordinator, AppState, MockTranscriptionEngine,
        MockCleanup, MockTextDelivery, MockFocusInspector
    ) {
        let appState = AppState()
        let engine = MockTranscriptionEngine()
        let cleanup = MockCleanup()
        let delivery = MockTextDelivery()
        let focus = MockFocusInspector()
        let coordinator = DictationCoordinator(
            engine: engine, cleanup: cleanup, delivery: delivery,
            focus: focus, appState: appState)
        return (coordinator, appState, engine, cleanup, delivery, focus)
    }

    /// Wartet, bis sich der Zustand vom übergebenen Wert wegbewegt hat
    /// (max. 2 s), damit Tests nicht auf interne Tasks pollen müssen.
    private func waitUntilState(
        _ appState: AppState, leaves state: DictationState
    ) async {
        for _ in 0..<200 where appState.dictationState == state {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startMovesToRecordingAndStreamsLivePreview() async {
        let (coordinator, appState, engine, _, _, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        #expect(appState.dictationState == .recording)

        engine.emit("das ist", isFinal: false)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(appState.livePreview == "das ist")
    }

    @Test func happyPathDeliversCleanedTextAndLogsEntry() async {
        let (coordinator, appState, engine, cleanup, delivery, _) = makeCoordinator()
        appState.dictationState = .idle
        cleanup.transform = { $0.uppercased() }

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        engine.emit("hallo welt", isFinal: false)

        coordinator.endDictation(heldFor: .seconds(2))
        engine.emit("hallo welt", isFinal: true)
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)
        await waitUntilState(appState, leaves: .finalizing)
        await waitUntilState(appState, leaves: .cleaning)
        await waitUntilState(appState, leaves: .delivering)

        #expect(appState.dictationState == .idle)
        #expect(delivery.deliveredText == "HALLO WELT")
        #expect(appState.log.first?.text == "HALLO WELT")
        #expect(engine.stopCallCount == 1)
    }

    @Test func shortPressIsDiscarded() async {
        let (coordinator, appState, engine, _, delivery, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        coordinator.endDictation(heldFor: .milliseconds(100))
        engine.finishStream()
        await waitUntilState(appState, leaves: .finalizing)

        #expect(appState.dictationState == .idle)
        #expect(delivery.deliverCallCount == 0)
        #expect(appState.log.isEmpty)
        #expect(engine.stopCallCount == 1)
    }

    @Test func emptyFinalTranscriptIsNotDelivered() async {
        let (coordinator, appState, engine, _, delivery, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        coordinator.endDictation(heldFor: .seconds(2))
        engine.emit("   ", isFinal: true)
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)
        await waitUntilState(appState, leaves: .finalizing)

        #expect(appState.dictationState == .idle)
        #expect(delivery.deliverCallCount == 0)
        #expect(appState.log.isEmpty)
    }

    @Test func focusSnapshotControlsPasteFlag() async {
        let (coordinator, appState, engine, _, delivery, focus) = makeCoordinator()
        appState.dictationState = .idle
        focus.focused = true

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        focus.focused = false   // Fokuswechsel nach dem Start darf nichts ändern
        coordinator.endDictation(heldFor: .seconds(2))
        engine.emit("text", isFinal: true)
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)
        await waitUntilState(appState, leaves: .finalizing)
        await waitUntilState(appState, leaves: .cleaning)
        await waitUntilState(appState, leaves: .delivering)

        #expect(delivery.deliveredPaste == true)
    }

    @Test func streamErrorSurfacesAndReturnsToIdle() async {
        let (coordinator, appState, engine, _, delivery, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        engine.failStream(TranscriptionError.modelUnavailable)
        await waitUntilState(appState, leaves: .recording)

        if case .error = appState.dictationState {} else {
            Issue.record("expected error state, got \(String(describing: appState.dictationState))")
        }
        #expect(delivery.deliverCallCount == 0)
    }
}
