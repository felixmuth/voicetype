import AppKit
import SwiftUI
import VoiceTypeCore

/// Besitzt einen klick-durchlässigen `NSPanel` und steuert dessen
/// Sichtbarkeit anhand von `appState.dictationState`. Re-positioniert
/// das Panel bei Screen-Konfigurations-Änderungen.
@MainActor
final class OverlayWindowController: NSObject {
    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayContent>
    private let appState: AppState
    private var isCurrentlyVisible = false

    init(appState: AppState) {
        self.appState = appState
        self.hostingView = NSHostingView(rootView: OverlayContent(appState: appState))
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: style,
            backing: .buffered,
            defer: true)
        super.init()

        panel.contentView = hostingView
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.alphaValue = 0   // unsichtbar starten

        observeState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleScreenChange() {
        if isCurrentlyVisible { reposition() }
    }

    private func observeState() {
        let active = Self.isActiveState(appState.dictationState)
        if active != isCurrentlyVisible {
            active ? fadeIn() : fadeOut()
        }
        withObservationTracking {
            _ = appState.dictationState
        } onChange: {
            Task { @MainActor in self.observeState() }
        }
    }

    private static func isActiveState(_ state: DictationState) -> Bool {
        switch state {
        case .recording, .finalizing, .cleaning, .delivering: return true
        case .idle, .loading, .error:                          return false
        }
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let frame = screen.visibleFrame
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
    }

    private func fadeIn() {
        isCurrentlyVisible = true
        reposition()
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        isCurrentlyVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}
