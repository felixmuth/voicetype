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
                    onRetry: { controller.retry() })
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
    var permissionsGranted = false
    private let settingsStore = SettingsStore()
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor

    init() {
        let settings = settingsStore.load()
        let audioCapture = AudioCapture()
        let engine = AppleSpeechEngine(
            audioCapture: audioCapture, language: settings.language)
        coordinator = DictationCoordinator(
            engine: engine,
            cleanup: PassthroughCleanup(),          // Plan 1: kein Cleanup
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
