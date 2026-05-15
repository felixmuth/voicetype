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
    private var isStarted = false
    private var pressedAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var hotkey: String

    public var onPress: (() -> Void)?
    public var onRelease: ((Duration) -> Void)?

    private static let modifierFlags: [String: NSEvent.ModifierFlags] = [
        "fn": .function, "cmd": .command, "shift": .shift,
        "ctrl": .control, "opt": .option, "alt": .option,
    ]
    private static let functionKeys: [String: UInt16] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80, "f20": 90,
    ]

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
}
