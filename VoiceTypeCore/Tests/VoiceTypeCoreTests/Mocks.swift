import Foundation
@testable import VoiceTypeCore

/// Steuerbare TranscriptionEngine: der Test schiebt Updates rein und
/// entscheidet, ob/wann der Stream endet bzw. mit Fehler abbricht.
///
/// Events (`emit`/`finishStream`/`failStream`), die *vor* `start()` ankommen,
/// werden gepuffert und beim `start()` der Reihe nach nachgereicht. So sind
/// die Tests unabhängig vom genauen Scheduling der internen Tasks des
/// Coordinators.
final class MockTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    var prepareError: Error?
    var startError: Error?
    private(set) var prepareCallCount = 0
    private(set) var stopCallCount = 0
    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?

    private enum Event {
        case update(TranscriptionUpdate)
        case finish
        case fail(Error)
    }
    private var buffered: [Event] = []

    func prepare() async throws {
        prepareCallCount += 1
        if let prepareError { throw prepareError }
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        if let startError { throw startError }
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            for event in self.buffered { self.apply(event) }
            self.buffered.removeAll()
        }
    }

    func stop() async { stopCallCount += 1 }

    // Test-Steuerung:
    /// Backward-Compat-Helper: simuliert Apple-Speech-Verhalten.
    /// `isFinal=true` schiebt das Segment in den internen
    /// Akkumulator; `isFinal=false` hängt das partial-Wort an den
    /// Akkumulator. Yieldet jedes Mal den kombinierten Text.
    private var accumulatedStable = ""
    func emit(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined: String
        if isFinal {
            if !trimmed.isEmpty {
                accumulatedStable = accumulatedStable.isEmpty
                    ? trimmed
                    : accumulatedStable + " " + trimmed
            }
            combined = accumulatedStable
        } else {
            if accumulatedStable.isEmpty {
                combined = trimmed
            } else if trimmed.isEmpty {
                combined = accumulatedStable
            } else {
                combined = accumulatedStable + " " + trimmed
            }
        }
        deliver(.update(TranscriptionUpdate(text: combined)))
    }
    func finishStream() { deliver(.finish) }
    func failStream(_ error: Error) { deliver(.fail(error)) }

    private func deliver(_ event: Event) {
        if continuation != nil {
            apply(event)
        } else {
            buffered.append(event)
        }
    }

    private func apply(_ event: Event) {
        switch event {
        case .update(let update): continuation?.yield(update)
        case .finish: continuation?.finish()
        case .fail(let error): continuation?.finish(throwing: error)
        }
    }
}

/// Cleanup-Mock: ersetzt den Text durch ein konfigurierbares Ergebnis.
final class MockCleanup: TextCleanup, @unchecked Sendable {
    var transform: @Sendable (String) -> String = { $0 }
    private(set) var receivedInput: String?
    func cleanup(_ raw: String) async -> String {
        receivedInput = raw
        return transform(raw)
    }
}

/// Output-Mock: merkt sich, was ausgeliefert wurde.
final class MockTextDelivery: TextDelivering, @unchecked Sendable {
    private(set) var deliveredText: String?
    private(set) var deliveredPaste: Bool?
    private(set) var deliverCallCount = 0
    func deliver(_ text: String, pasteIntoFocusedField: Bool) {
        deliveredText = text
        deliveredPaste = pasteIntoFocusedField
        deliverCallCount += 1
    }
}

/// Fokus-Mock: liefert einen festen Wert.
final class MockFocusInspector: FocusInspecting, @unchecked Sendable {
    var focused: Bool = false
    func isTextFieldFocused() -> Bool { focused }
}
