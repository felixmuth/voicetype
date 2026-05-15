import Foundation

/// Zentrale Zustandsmaschine. Verbindet Engine, Cleanup, Output und Fokus
/// und mutiert ausschließlich den AppState.
@MainActor
public final class DictationCoordinator {
    private let engine: TranscriptionEngine
    private let cleanup: TextCleanup
    private let delivery: TextDelivering
    private let focus: FocusInspecting
    private let appState: AppState

    private static let minHold: Duration = .milliseconds(300)

    /// Hält den laufenden Stream-Task am Leben. Cancellation ist in Plan 1
    /// bewusst nicht implementiert — der Coordinator lebt so lange wie die App.
    private var streamTask: Task<Void, Never>?
    private var latestFinalText: String = ""
    private var pasteTargetFocused = false
    private var discardCurrent = false

    public init(
        engine: TranscriptionEngine,
        cleanup: TextCleanup,
        delivery: TextDelivering,
        focus: FocusInspecting,
        appState: AppState
    ) {
        self.engine = engine
        self.cleanup = cleanup
        self.delivery = delivery
        self.focus = focus
        self.appState = appState
    }

    /// Engine vorbereiten; bei Erfolg geht der Zustand auf `.idle`.
    public func prepare() async {
        do {
            try await engine.prepare()
            appState.dictationState = .idle
        } catch {
            appState.dictationState = .error("Engine nicht verfügbar")
        }
    }

    /// Hotkey gedrückt.
    public func startDictation() {
        // Plan-1-Einschränkung: Ein neuer Tastendruck während .cleaning /
        // .delivering wird verworfen. Das Spec sieht hier paralleles Diktat
        // vor — das erfordert aber, dass der Coordinator überlappende Diktate
        // mit je eigenem Zustand führt. Bewusst auf Plan 2 vertagt, wo das
        // asynchrone Foundation-Model-Cleanup das Zeitfenster relevant macht.
        guard appState.dictationState == .idle else { return }
        latestFinalText = ""
        discardCurrent = false
        pasteTargetFocused = focus.isTextFieldFocused()   // Snapshot beim Drücken
        appState.livePreview = ""
        appState.dictationState = .recording

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.engine.start()
                for try await update in stream {
                    if update.isFinal {
                        self.latestFinalText = update.text
                    } else {
                        self.appState.livePreview = update.text
                    }
                }
                await self.finishAfterStream()
            } catch {
                self.appState.dictationState = .error("Transkription fehlgeschlagen")
            }
        }
    }

    /// Hotkey losgelassen. `heldFor` ist die gemessene Haltedauer.
    public func endDictation(heldFor: Duration) {
        guard appState.dictationState == .recording else { return }
        discardCurrent = heldFor < Self.minHold
        appState.dictationState = .finalizing
        Task { await engine.stop() }   // Engine finalisiert; Stream endet danach
    }

    /// Wird aufgerufen, wenn der Engine-Stream regulär geendet hat.
    private func finishAfterStream() async {
        // Audio ist gestoppt — Pegel zurücksetzen, sonst zeigt das
        // Wellenform-Icon/Overlay den letzten Wert bis zum nächsten Diktat.
        appState.micLevel = 0
        // Bei zu kurzem Tastendruck: alles verwerfen.
        if discardCurrent {
            appState.livePreview = ""
            appState.dictationState = .idle
            return
        }

        let raw = latestFinalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            appState.livePreview = ""
            appState.dictationState = .idle
            return
        }

        appState.dictationState = .cleaning
        let cleaned = await cleanup.cleanup(raw)

        appState.dictationState = .delivering
        delivery.deliver(cleaned, pasteIntoFocusedField: pasteTargetFocused)
        appState.addEntry(cleaned)

        appState.livePreview = ""
        appState.dictationState = .idle
    }

    /// Mikrofonpegel-Update. Wird vom `onLevel`-Callback der
    /// `AudioCapturing`-Implementierung über den `AppController`
    /// hier durchgereicht — so bleibt die Invariante „nur der
    /// Coordinator mutiert AppState" gewahrt.
    @MainActor public func updateMicLevel(_ level: Float) {
        appState.micLevel = level
    }
}
