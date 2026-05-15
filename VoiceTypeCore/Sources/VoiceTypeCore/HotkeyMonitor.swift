import AppKit

/// Globaler Push-to-Talk-Monitor. Unterstützt Modifier-Tasten (fn, cmd,
/// shift, ctrl, opt) sowie Funktionstasten (f1–f20). Ruft beim Drücken
/// `onPress` und beim Loslassen `onRelease(heldFor:)` auf dem MainActor auf.
///
/// Benötigt die Berechtigung „Bedienungshilfen" (Accessibility).
@MainActor
public final class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var captureGlobalMonitor: Any?
    private var captureLocalMonitor: Any?
    private var isStarted = false
    private var pressedAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var hotkey: String

    public var onPress: (() -> Void)?
    public var onRelease: ((Duration) -> Void)?
    public var onCaptured: ((String) -> Void)?

    private static let modifierFlags: [String: NSEvent.ModifierFlags] = [
        "fn": .function, "cmd": .command, "shift": .shift,
        "ctrl": .control, "opt": .option,
        // "alt" entfernt: doppelter Eintrag auf .option würde dazu
        // führen, dass `hotkeyName` non-deterministisch entweder "opt"
        // oder "alt" zurückgibt (Dictionary-Iteration ist unsortiert).
        // Kanonischer Name für die Option-Taste ist "opt".
    ]
    private static let functionKeys: [String: UInt16] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80, "f20": 90,
    ]

    /// Auflösung „NSEvent-Eigenschaften → Hotkey-Name". Pure, testbar.
    /// - `keyCode`: nur relevant für Funktionstasten (F1–F20), nutzt
    ///   `isKeyDown == true` als Filter (Capture nimmt nur keyDown an).
    /// - `modifierFlags`: relevant für Modifier-Tasten (fn, cmd, shift, …).
    /// - Rückgabe: passender Hotkey-Name oder `nil`, falls nichts matcht.
    public static func hotkeyName(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isKeyDown: Bool
    ) -> String? {
        // Modifier hat Vorrang — Funktionstasten kommen nur in Betracht,
        // wenn KEIN reiner Modifier vorliegt.
        for (name, bit) in Self.modifierFlags where modifierFlags.contains(bit) {
            return name
        }
        guard isKeyDown else { return nil }
        for (name, code) in Self.functionKeys where code == keyCode {
            return name
        }
        return nil
    }

    public init(hotkey: String) {
        self.hotkey = hotkey.lowercased()
    }

    public func setHotkey(_ hotkey: String) {
        self.hotkey = hotkey.lowercased()
        pressedAt = nil
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        isStarted = false
        pressedAt = nil
    }

    private func handle(_ event: NSEvent) {
        // Während Capture-Modus keine regulären Trigger feuern lassen —
        // sonst würde ein Re-Capture des aktuellen Hotkeys gleichzeitig
        // startDictation auslösen.
        guard captureGlobalMonitor == nil else { return }
        if let targetMod = Self.modifierFlags[hotkey], event.type == .flagsChanged {
            updateState(isDown: event.modifierFlags.contains(targetMod))
        } else if let targetKey = Self.functionKeys[hotkey] {
            if event.type == .keyDown, event.keyCode == targetKey, !event.isARepeat {
                updateState(isDown: true)
            } else if event.type == .keyUp, event.keyCode == targetKey {
                updateState(isDown: false)
            }
        }
    }

    private func updateState(isDown: Bool) {
        if isDown, pressedAt == nil {
            pressedAt = clock.now
            onPress?()
        } else if !isDown, let start = pressedAt {
            let held = clock.now - start
            pressedAt = nil
            onRelease?(held)
        }
    }

    /// Beginnt einen Capture-Modus: globale Tastendrücke werden
    /// abgefangen, der erste passende Modifier oder F-Key wird per
    /// `onCaptured` zurückgegeben. Stoppt sich danach selbst.
    public func startCapture() {
        guard captureGlobalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        // Global feuert bei Events anderer Apps, Local bei Events
        // dieser App — AppKit garantiert wechselseitigen Ausschluss,
        // sodass handleCapture nie zweimal pro physischem Tastendruck
        // gerufen wird.
        captureGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleCapture(event)
        }
        captureLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleCapture(event)
            return event
        }
    }

    public func stopCapture() {
        if let captureGlobalMonitor { NSEvent.removeMonitor(captureGlobalMonitor) }
        if let captureLocalMonitor { NSEvent.removeMonitor(captureLocalMonitor) }
        captureGlobalMonitor = nil
        captureLocalMonitor = nil
    }

    private func handleCapture(_ event: NSEvent) {
        let name = Self.hotkeyName(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isKeyDown: event.type == .keyDown)
        guard let name else { return }
        // Fire-once: Callback und Monitore raus, BEVOR wir feuern.
        // Beide Capture-Monitore können in derselben Run-Loop-Iteration
        // ankommen — ohne diesen Schutz würde der zweite Treffer den
        // Callback erneut aufrufen.
        let callback = onCaptured
        onCaptured = nil
        stopCapture()
        callback?(name)
    }
}
