import Foundation

/// Zentrale Zustandsmaschine. Verbindet Engine, Cleanup, Output und Fokus
/// und mutiert ausschließlich den AppState.
@MainActor
public final class DictationCoordinator {
    private var engine: TranscriptionEngine
    private var cleanup: TextCleanup
    private let delivery: TextDelivering
    private let focus: FocusInspecting
    private let appState: AppState

    private static let minHold: Duration = .milliseconds(300)

    /// Mindest-Watchdog für die Verarbeitungs-Phase
    /// (.finalizing / .cleaning / .delivering). Für längere Aufnahmen
    /// wird er proportional verlängert (`max(min, heldFor + buffer)`),
    /// weil Apple SpeechAnalyzer.finalize ungefähr proportional zur
    /// Audio-Länge braucht.
    private static let minProcessingWatchdog: Duration = .seconds(8)
    private static let processingWatchdogBuffer: Duration = .seconds(5)

    /// Hält den laufenden Stream-Task am Leben. Cancellation ist in Plan 1
    /// bewusst nicht implementiert — der Coordinator lebt so lange wie die App.
    private var streamTask: Task<Void, Never>?
    /// Watchdog-Task, der nach `processingWatchdog` einen Force-Reset
    /// auslöst, wenn das aktuelle Diktat nicht zurück nach .idle gelangt.
    private var watchdogTask: Task<Void, Never>?
    private var latestFinalText: String = ""
    private var pasteTargetFocused = false
    private var discardCurrent = false

    /// Beim Live-Swap (Plan 4) gepufferte Engine, die nach Diktat-Ende
    /// angewendet wird. Cleanup wird sofort getauscht und braucht keinen
    /// Puffer — kein Stream-Vertrag.
    private var pendingEngineSwap: TranscriptionEngine?

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
        appState.isSpeaking = false
        lastSpeechAt = nil
        appState.dictationState = .recording

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await self.engine.start()
                for try await update in stream {
                    if update.isFinal {
                        self.appendFinalSegment(update.text)
                        self.appState.livePreview = self.latestFinalText
                    } else {
                        self.appState.livePreview = self.composePreview(partial: update.text)
                    }
                }
                await self.finishAfterStream()
            } catch {
                self.appState.dictationState = .error("Transkription fehlgeschlagen")
            }
        }
    }

    /// Hängt ein neues finales Segment an `latestFinalText` an, mit
    /// einem Leerzeichen-Trenner. Leere Segmente werden ignoriert.
    private func appendFinalSegment(_ segment: String) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if latestFinalText.isEmpty {
            latestFinalText = trimmed
        } else {
            latestFinalText += " " + trimmed
        }
    }

    /// Komponiert die Live-Vorschau aus bereits finalisierten Segmenten
    /// plus laufendem partiellen Text.
    private func composePreview(partial: String) -> String {
        let trimmedPartial = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if latestFinalText.isEmpty { return trimmedPartial }
        if trimmedPartial.isEmpty { return latestFinalText }
        return latestFinalText + " " + trimmedPartial
    }

    /// Hotkey losgelassen. `heldFor` ist die gemessene Haltedauer.
    public func endDictation(heldFor: Duration) {
        guard appState.dictationState == .recording else { return }
        discardCurrent = heldFor < Self.minHold
        appState.dictationState = .finalizing
        startWatchdog(forRecordingOfLength: heldFor)
        Task { await engine.stop() }   // Engine finalisiert; Stream endet danach
    }

    /// Startet einen Timer, der nach Ablauf einen Force-Reset auf .idle
    /// macht — falls die Pipeline (Engine.stop oder Cleanup-Inferenz)
    /// hängt. Timeout skaliert mit Aufnahme-Länge: ein 30-s-Diktat
    /// braucht für Apple-Speech-Finalisierung deutlich länger als ein
    /// 1-s-Diktat.
    private func startWatchdog(forRecordingOfLength heldFor: Duration) {
        let timeout = max(
            Self.minProcessingWatchdog,
            heldFor + Self.processingWatchdogBuffer)
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            // Nur eingreifen, wenn wir tatsächlich noch hängen.
            switch self.appState.dictationState {
            case .finalizing, .cleaning, .delivering:
                self.appState.livePreview = ""
                self.appState.micLevel = 0
                self.streamTask = nil
                self.appState.dictationState = .idle
            default:
                break
            }
        }
    }

    /// Wird aufgerufen, wenn der Engine-Stream regulär geendet hat.
    private func finishAfterStream() async {
        // Audio ist gestoppt — Pegel zurücksetzen, sonst zeigt das
        // Wellenform-Icon/Overlay den letzten Wert bis zum nächsten Diktat.
        appState.micLevel = 0
        appState.isSpeaking = false
        lastSpeechAt = nil
        // Bei zu kurzem Tastendruck: alles verwerfen.
        if discardCurrent {
            appState.livePreview = ""
            await returnToIdleOrApplyPendingSwap()
            return
        }

        let raw = latestFinalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            appState.livePreview = ""
            await returnToIdleOrApplyPendingSwap()
            return
        }

        appState.dictationState = .cleaning
        let cleaned = await cleanup.cleanup(raw)

        appState.dictationState = .delivering
        delivery.deliver(cleaned, pasteIntoFocusedField: pasteTargetFocused)
        appState.addEntry(cleaned)

        appState.livePreview = ""
        await returnToIdleOrApplyPendingSwap()
    }

    /// Schlusspfad jedes Diktats (egal ob verworfen, leer oder
    /// erfolgreich): entweder direkt .idle, oder — falls in der
    /// Zwischenzeit ein Engine-Swap angefordert wurde — den anwenden.
    private func returnToIdleOrApplyPendingSwap() async {
        // streamTask hat sich selbst beendet; Reference loslassen, sonst
        // sieht der nächste startDictation einen "alive"-Stale-Reference
        // und das könnte einen Race mit der Cancel-Logik geben.
        streamTask = nil
        // Watchdog cancel — wir sind regulär durchgekommen.
        watchdogTask?.cancel()
        watchdogTask = nil
        if let pending = pendingEngineSwap {
            pendingEngineSwap = nil
            await applyEngineSwap(pending)   // setzt State selbst
        } else {
            appState.dictationState = .idle
        }
    }

    /// Mikrofonpegel-Update. Wird vom `onLevel`-Callback der
    /// `AudioCapturing`-Implementierung über den `AppController`
    /// hier durchgereicht — so bleibt die Invariante „nur der
    /// Coordinator mutiert AppState" gewahrt.
    ///
    /// Daraus leiten wir den binären `isSpeaking`-Flag ab:
    /// - sobald `level >= speechThreshold`: speaking=true, Hold-Timer
    ///   wird neu gesetzt
    /// - wenn `level` darunter bleibt und der Hold-Timer abläuft:
    ///   speaking=false
    /// Hold-Delay verhindert Flackern bei kurzen Atempausen mitten im
    /// Sprechen, ohne dass „aufhören zu sprechen" gefühlt verzögert
    /// wirkt.
    private static let speechThreshold: Float = 0.03
    private static let speechReleaseDelay: Duration = .milliseconds(180)
    private let speechClock = ContinuousClock()
    private var lastSpeechAt: ContinuousClock.Instant?

    @MainActor public func updateMicLevel(_ level: Float) {
        appState.micLevel = level
        let now = speechClock.now
        if level >= Self.speechThreshold {
            lastSpeechAt = now
            if !appState.isSpeaking { appState.isSpeaking = true }
        } else if let last = lastSpeechAt,
                  last.duration(to: now) > Self.speechReleaseDelay {
            if appState.isSpeaking { appState.isSpeaking = false }
            lastSpeechAt = nil
        } else if lastSpeechAt == nil, appState.isSpeaking {
            appState.isSpeaking = false
        }
    }

    /// Tauscht Engine und/oder Cleanup aus (Plan 4).
    ///
    /// - Cleanup hat keinen Stream-Vertrag und wird **immer sofort**
    ///   getauscht — wirkt aber natürlich erst auf das nächste
    ///   Cleanup, das vom Coordinator angestoßen wird.
    /// - Engine-Swap: in `.idle/.loading/.error` sofort, sonst gepuffert
    ///   und nach `finishAfterStream()` angewendet.
    public func requestSwap(
        engine: TranscriptionEngine? = nil,
        cleanup: TextCleanup? = nil
    ) async {
        if let cleanup { self.cleanup = cleanup }
        guard let engine else { return }
        if canSwapEngineNow {
            await applyEngineSwap(engine)
        } else {
            pendingEngineSwap = engine
        }
    }

    private var canSwapEngineNow: Bool {
        switch appState.dictationState {
        case .idle, .loading, .error: return true
        case .recording, .finalizing, .cleaning, .delivering: return false
        }
    }

    private func applyEngineSwap(_ new: TranscriptionEngine) async {
        await engine.stop()
        appState.dictationState = .loading
        do {
            try await new.prepare()
            engine = new
            appState.dictationState = .idle
        } catch {
            appState.dictationState = .error("Engine-Wechsel fehlgeschlagen")
            // alte `engine`-Referenz bleibt erhalten — kein Reassign.
        }
    }
}
