import SwiftUI
import VoiceTypeCore
import ServiceManagement

// Disambiguate: SwiftUI also defines a `Settings` Scene type.
typealias Settings = VoiceTypeCore.Settings

@main
struct VoiceTypeApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            if controller.permissionsGranted {
                MenuContentView(
                    appState: controller.appState,
                    onRetry: { controller.retry() },
                    cleanupHint: controller.cleanupHint)
            } else {
                PermissionsView(
                    permissions: controller.permissions,
                    onRecheck: { controller.recheckPermissions() })
            }
        } label: {
            WaveformIcon(
                state: controller.appState.dictationState,
                level: controller.appState.micLevel)
        }
        .menuBarExtraStyle(.window)

        Window("VoiceType", id: "main") {
            MainView(controller: controller)
        }
        .defaultSize(width: 720, height: 480)
    }
}

/// Verdrahtet alle Kern-Bausteine und hält sie am Leben.
@MainActor
@Observable
final class AppController {
    let appState = AppState()
    let permissions = Permissions()
    let cleanupHint: String?
    var permissionsGranted = false
    private let settingsStore = SettingsStore()
    var settings: Settings {
        didSet {
            try? settingsStore.save(settings)
            if oldValue.pushToTalkKey != settings.pushToTalkKey {
                hotkey.setHotkey(settings.pushToTalkKey)
            }
            if oldValue.launchAtLogin != settings.launchAtLogin {
                applyLoginAtLogin(settings.launchAtLogin)
            }
        }
    }
    var loginErrorMessage: String?
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor
    private let overlayController: OverlayWindowController

    init() {
        let settings = settingsStore.load()
        self.settings = settings
        let audioCapture = AudioCapture()
        let engine = AppleSpeechEngine(
            audioCapture: audioCapture, language: settings.language)

        // Cleanup-Implementierung wählen und Verfügbarkeits-Hinweis erfassen.
        // Plan 2: Bei aktiviertem Cleanup nutzen wir FoundationModelCleanup,
        // das intern auf Rohtext zurückfällt, wenn das Modell nicht verfügbar
        // ist — und parallel den Hinweis liefert, den die UI anzeigt.
        let cleanup: TextCleanup
        let hint: String?
        if settings.cleanupEnabled {
            let fmCleanup = FoundationModelCleanup()
            hint = fmCleanup.availabilityHint
            cleanup = fmCleanup
        } else {
            hint = nil
            cleanup = PassthroughCleanup()
        }
        cleanupHint = hint

        coordinator = DictationCoordinator(
            engine: engine,
            cleanup: cleanup,
            delivery: TextOutput(clipboardEnabled: settings.clipboardCopy),
            focus: FocusInspector(),
            appState: appState)

        // Mikrofon-Pegel → Coordinator → AppState (Plan 3).
        // `audioCapture.onLevel` ist `@MainActor`-isoliert (Plan-3-Task-1-Fix),
        // also direkt im Closure-Body — kein Task-Hop nötig.
        audioCapture.onLevel = { [coordinator] level in
            coordinator.updateMicLevel(level)
        }

        hotkey = HotkeyMonitor(hotkey: settings.pushToTalkKey)

        hotkey.onPress = { [coordinator] in coordinator.startDictation() }
        hotkey.onRelease = { [coordinator] held in
            coordinator.endDictation(heldFor: held)
        }

        self.overlayController = OverlayWindowController(appState: appState)

        Task {
            if permissions.microphoneStatus() == .notDetermined {
                _ = await permissions.requestMicrophone()
            }
            recheckPermissions()
        }
    }

    /// Prüft die Berechtigungen neu; bei vollständiger Freigabe wird die
    /// Engine vorbereitet und der Hotkey-Monitor gestartet.
    func recheckPermissions() {
        permissionsGranted = permissions.allGranted
        guard permissionsGranted else { return }
        Task {
            await coordinator.prepare()
            hotkey.start()
        }
    }

    /// Erholung aus dem .error-Zustand: Engine erneut vorbereiten.
    func retry() {
        Task { await coordinator.prepare() }
    }

    /// Startet den Hotkey-Capture-Modus. Der übergebene Closure wird mit
    /// dem neu erkannten Hotkey-Namen aufgerufen, wenn der Nutzer eine
    /// passende Taste drückt. Stoppt den Capture-Monitor beim Erfolg.
    func hotkeyCaptureBegin(_ completion: @escaping (String) -> Void) {
        hotkey.stopCapture()   // Defensive: clean slate falls vorheriger Capture noch lebt.
        hotkey.onCaptured = { [weak self] name in
            self?.hotkey.stopCapture()
            self?.hotkey.onCaptured = nil
            completion(name)
        }
        hotkey.startCapture()
    }

    /// Bricht einen laufenden Hotkey-Capture ab — z. B. wenn der User die
    /// SettingsView schließt ohne Taste zu drücken. Stoppt die Monitore
    /// und löscht den Pending-Callback.
    func cancelHotkeyCapture() {
        hotkey.stopCapture()
        hotkey.onCaptured = nil
    }

    /// Wendet die „Beim Login starten"-Einstellung via SMAppService an.
    /// Bei Fehler wird der Toggle in der UI zurückgesetzt und ein Alert
    /// (durch die View) gezeigt. Re-Entrancy-Schutz, weil das Rollback
    /// `settings.didSet` erneut triggert.
    private func applyLoginAtLogin(_ enabled: Bool) {
        guard !isApplyingLogin else { return }
        isApplyingLogin = true
        defer { isApplyingLogin = false }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            var rollback = settings
            rollback.launchAtLogin = !enabled
            settings = rollback
            loginErrorMessage = error.localizedDescription
        }
    }

    private var isApplyingLogin = false
}
