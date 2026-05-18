import SwiftUI
import AppKit
import VoiceTypeCore
import ServiceManagement
import VoiceTypeWhisperKit

// Disambiguate: SwiftUI also defines a `Settings` Scene type.
typealias Settings = VoiceTypeCore.Settings

@main
struct VoiceTypeApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            // MenuBarExtra zeigt IMMER MenuContentView — bei fehlenden
            // Berechtigungen wechselt es intern auf den Permission-Banner-
            // Modus. Vorher hatten wir hier PermissionsView vs. MenuContent
            // — das hat Tahoes Liquid-Glass-Backdrop auf die größte je
            // gezeigte Popover-Höhe „gemerkt" und einen sichtbaren Rahmen
            // hinterlassen, wenn dann das kleinere Popover folgte.
            MenuContentView(
                appState: controller.appState,
                onRetry: { controller.retry() },
                hotkeyName: controller.settings.pushToTalkKey,
                cleanupHint: controller.cleanupHint,
                permissionsMissing: !controller.permissionsGranted)
        } label: {
            // Status-Bar-Label + unsichtbarer Auto-Opener für das
            // Permission-Window (siehe PermissionsAutoOpener-Doc).
            MenuBarLabel(state: controller.appState.dictationState)
                .background(
                    PermissionsAutoOpener(controller: controller))
        }
        .menuBarExtraStyle(.window)

        Window("VoiceType", id: "main") {
            MainView(controller: controller)
        }
        .defaultSize(width: 720, height: 480)
        .restorationBehavior(.disabled)

        // Eigenständiges Permission-Onboarding-Window. Wird vom
        // PermissionsAutoOpener beim Start automatisch aufgemacht
        // (wenn Berechtigungen fehlen) und beim Erfüllen geschlossen.
        Window("Berechtigungen", id: "permissions") {
            PermissionsView(
                permissions: controller.permissions,
                onRecheck: { controller.recheckPermissions() })
        }
        .defaultSize(width: 480, height: 380)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }

}

// MARK: - PermissionsAutoOpener

/// Unsichtbarer Helper, der das `permissions`-Window automatisch
/// öffnet, sobald `controller.permissionsGranted == false` (beim App-
/// Start) — und es schließt, sobald die Berechtigungen erteilt sind.
///
/// Sitzt als `.background()` auf dem MenuBarLabel, weil das die einzige
/// View ist, die garantiert beim App-Start sofort gerendert wird (das
/// MenuBarExtra-Popover wird erst beim Klick gerendert).
private struct PermissionsAutoOpener: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                if !controller.permissionsGranted {
                    openWindow(id: "permissions")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .onChange(of: controller.permissionsGranted) { _, granted in
                if granted {
                    dismissWindow(id: "permissions")
                } else {
                    openWindow(id: "permissions")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}

/// Verdrahtet alle Kern-Bausteine und hält sie am Leben.
@MainActor
@Observable
final class AppController {
    let appState = AppState()
    let permissions = Permissions()
    /// Modell-Registry mit Production-Downloadern für WhisperKit.
    /// (MLX-Downloader ist auf Plan 5 vertagt — siehe Spec § 14.)
    let registry: ModelRegistry
    var cleanupHint: String?
    var permissionsGranted = false
    var loginErrorMessage: String?

    private let settingsStore = SettingsStore()
    private let audioCapture: AudioCapture
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor
    private let overlayController: OverlayWindowController
    /// Bridge für den WhisperKit-Level-Callback. Wird einmal im init
    /// erzeugt, in EngineFactory-Closures kapselt — beim Swap auf
    /// eine neue WhisperKit-Instanz nutzt der nächste Engine
    /// denselben Bridge-Eintrag (coordinator weak referenziert).
    private let levelBridge = LevelBridge()
    private var isApplyingLogin = false
    /// Verhindert, dass `settings.didSet` durch interne State-Mirror-
    /// Updates erneut den Engine-Swap triggert.
    private var isHandlingSettingsChange = false

    var settings: Settings {
        didSet { handleSettingsChange(old: oldValue) }
    }

    init() {
        let loaded = settingsStore.load()
        self.settings = loaded
        let audioCapture = AudioCapture()
        self.audioCapture = audioCapture
        let registry = ModelRegistry(
            downloaders: [.whisperKit: WhisperKitDownloader()])
        self.registry = registry

        // Forward-Bridge ist als Instance-Variable angelegt, damit
        // `swapEngineIfReady()` bei späteren Swaps denselben Bridge
        // wiederverwenden kann. Coordinator wird unten nach Init
        // weak in die Bridge gelegt.
        let bridge = self.levelBridge
        let whisperKitOnLevel: @Sendable (Float) -> Void = { level in
            Task { @MainActor in bridge.handle(level) }
        }
        let (engine, fallback) = EngineFactory.makeTranscription(
            settings: loaded, registry: registry, audioCapture: audioCapture,
            whisperKitOnLevel: whisperKitOnLevel)
        let (cleanup, hint) = EngineFactory.makeCleanup(
            settings: loaded, registry: registry)
        cleanupHint = hint

        coordinator = DictationCoordinator(
            engine: engine,
            cleanup: cleanup,
            delivery: TextOutput(clipboardEnabled: loaded.clipboardCopy),
            focus: FocusInspector(),
            appState: appState)
        levelBridge.coordinator = coordinator

        appState.engineFallbackHint = fallback
        appState.activeTranscriptionEngine =
            EngineFactory.activeTranscription(for: loaded, fallbackHint: fallback)
        appState.activeCleanupEngine =
            EngineFactory.activeCleanup(for: loaded, hint: hint)

        audioCapture.onLevel = { [coordinator] level in
            coordinator.updateMicLevel(level)
        }

        hotkey = HotkeyMonitor(hotkey: loaded.pushToTalkKey)
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

        // Accessibility-Permission liefert kein Live-Event. Wir prüfen
        // deshalb so lange im Hintergrund, bis alle Berechtigungen da
        // sind — und triggern parallel auf jedes App-Foreground-Event
        // (z. B. Rückkehr aus System Settings) einen sofortigen Recheck,
        // damit der User keinen "Erneut prüfen"-Knopf braucht.
        startPermissionWatcher()
        observeAppActivation()

        Task { [registry] in
            await registry.refresh()
            // Falls beim Start ein zwischenzeitlich (extern) installiertes
            // Modell entdeckt wird, das aktuelle Setting trifft → swap.
            self.swapEngineIfReady()
            self.swapCleanupIfReady()
        }

        startRegistryObservation()
    }

    private func startPermissionWatcher() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self else { return }
                if self.permissionsGranted { return }
                if self.permissions.allGranted {
                    self.recheckPermissions()
                }
            }
        }
    }

    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recheckPermissions() }
        }
    }

    /// Prüft die Berechtigungen neu; beim **Wechsel** auf "alle granted"
    /// wird die Engine vorbereitet und der Hotkey-Monitor gestartet.
    /// Wird sowohl vom UI-Button als auch vom Polling-Watcher und vom
    /// didBecomeActive-Observer aufgerufen — der `wasGranted`-Vergleich
    /// verhindert, dass `prepare()` bei jedem Foreground-Wechsel erneut
    /// läuft.
    func recheckPermissions() {
        let wasGranted = permissionsGranted
        permissionsGranted = permissions.allGranted
        guard permissionsGranted, !wasGranted else { return }
        Task {
            await coordinator.prepare()
            hotkey.start()
        }
    }

    /// Erholung aus dem .error-Zustand: Engine erneut vorbereiten.
    func retry() {
        Task { await coordinator.prepare() }
    }

    // MARK: - Settings-Änderungen + Live-Swap

    private func handleSettingsChange(old: Settings) {
        guard !isHandlingSettingsChange else { return }
        try? settingsStore.save(settings)

        if old.pushToTalkKey != settings.pushToTalkKey {
            hotkey.setHotkey(settings.pushToTalkKey)
        }
        if old.launchAtLogin != settings.launchAtLogin {
            applyLoginAtLogin(settings.launchAtLogin)
        }
        if old.transcriptionEngine != settings.transcriptionEngine
            || old.whisperKitModelId != settings.whisperKitModelId {
            swapEngineIfReady()
        }
        if old.cleanupEngine != settings.cleanupEngine
            || old.mlxModelId != settings.mlxModelId {
            swapCleanupIfReady()
        }
    }

    /// Idempotent: kann sowohl vom Setting-Change als auch vom
    /// Registry-Observer aufgerufen werden — falls die gewählte Engine
    /// bereits aktiv ist, ist `requestSwap` schon ein No-Op (Identität).
    private func swapEngineIfReady() {
        let bridge = self.levelBridge
        let whisperKitOnLevel: @Sendable (Float) -> Void = { level in
            Task { @MainActor in bridge.handle(level) }
        }
        let (new, hint) = EngineFactory.makeTranscription(
            settings: settings, registry: registry, audioCapture: audioCapture,
            whisperKitOnLevel: whisperKitOnLevel)
        appState.engineFallbackHint = hint
        Task { [coordinator, settings, hint] in
            await coordinator.requestSwap(engine: new)
            appState.activeTranscriptionEngine =
                EngineFactory.activeTranscription(for: settings, fallbackHint: hint)
        }
    }

    private func swapCleanupIfReady() {
        let (new, hint) = EngineFactory.makeCleanup(
            settings: settings, registry: registry)
        cleanupHint = hint
        Task { [coordinator, settings, hint] in
            await coordinator.requestSwap(cleanup: new)
            appState.activeCleanupEngine =
                EngineFactory.activeCleanup(for: settings, hint: hint)
        }
    }

    /// Beobachtet `registry.status` via Observation-Tracking. Sobald sich
    /// der Status irgendeines Modells ändert, prüfen wir, ob die aktuelle
    /// Settings-Wahl jetzt frisch installiert ist — und triggern den Swap.
    /// Re-installiert sich nach jedem `onChange` selbst, weil
    /// `withObservationTracking` nur das nächste Change-Event auslöst.
    private func startRegistryObservation() {
        observeStatusChange()
    }

    private func observeStatusChange() {
        _ = withObservationTracking {
            _ = self.registry.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.swapEngineIfReady()
                self.swapCleanupIfReady()
                self.observeStatusChange()   // reinstall watcher
            }
        }
    }

    // MARK: - Hotkey-Capture (unverändert aus Plan 3)

    func hotkeyCaptureBegin(_ completion: @escaping (String) -> Void) {
        hotkey.stopCapture()
        hotkey.onCaptured = { [weak self] name in
            self?.hotkey.stopCapture()
            self?.hotkey.onCaptured = nil
            completion(name)
        }
        hotkey.startCapture()
    }

    func cancelHotkeyCapture() {
        hotkey.stopCapture()
        hotkey.onCaptured = nil
    }

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
            isHandlingSettingsChange = true
            var rollback = settings
            rollback.launchAtLogin = !enabled
            settings = rollback
            isHandlingSettingsChange = false
            loginErrorMessage = error.localizedDescription
        }
    }
}
