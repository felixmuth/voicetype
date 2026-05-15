import SwiftUI
import VoiceTypeCore

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
            Image(systemName: controller.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
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
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor

    init() {
        let settings = settingsStore.load()
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
        hotkey = HotkeyMonitor(hotkey: settings.pushToTalkKey)

        hotkey.onPress = { [coordinator] in coordinator.startDictation() }
        hotkey.onRelease = { [coordinator] held in
            coordinator.endDictation(heldFor: held)
        }

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

    /// Statisches SF-Symbol je Zustand (Animation kommt in einem späteren Plan).
    var menuBarSymbol: String {
        switch appState.dictationState {
        case .recording:            return "waveform.circle.fill"
        case .loading, .error:      return "waveform.circle"
        default:                    return "waveform"
        }
    }
}
