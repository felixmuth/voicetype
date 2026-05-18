import AppKit
import SwiftUI
import VoiceTypeCore

/// Besitzt einen klick-durchlässigen `NSPanel` und steuert dessen
/// Sichtbarkeit anhand von `appState.dictationState`. Re-positioniert
/// das Panel bei Screen-Konfigurations-Änderungen.
///
/// Das Panel wächst dynamisch nach unten, wenn die Live-Vorschau über
/// eine Zeile hinausgeht: `OverlayContent` meldet seine natürliche
/// Größe via PreferenceKey hier rein, und wir setzen den NSPanel-Frame
/// mit Top-Edge-Anchor — Cap bei 5 Zeilen (~190 pt), darunter
/// fungiert die min-Höhe als Untergrenze.
@MainActor
final class OverlayWindowController: NSObject {
    private let panel: NSPanel
    private let hostingController: NSHostingController<OverlayContent>
    private let appState: AppState
    private var isCurrentlyVisible = false
    /// Y-Koordinate der TOP-Kante des Panels (in Screen-Koordinaten —
    /// macOS rechnet bottom-up). Wird beim `reposition()` festgelegt
    /// und bei `contentSizeChanged(...)` als Anker verwendet:
    /// `origin.y = topEdgeY - height`, sodass das Panel beim Wachsen
    /// nach unten ausläuft, während die Top-Kante stehen bleibt.
    private var topEdgeY: CGFloat = 0
    /// Cache der zuletzt gesetzten Panel-Höhe, damit `contentSizeChanged`
    /// nur bei echten Änderungen ein `setFrame` triggert — vermeidet
    /// SwiftUI ↔ AppKit-Oszillation (wenn der Resize selbst ein neues
    /// Layout triggert, das wieder eine minimal andere Höhe meldet).
    private var lastAppliedHeight: CGFloat = 0

    /// Feste Panel-Breite. Wachstum ist ausschließlich vertikal.
    private static let panelWidth: CGFloat = 540
    /// Min-Höhe (1-zeiliger Vorschau-Zustand inkl. Bar/Slot/Padding).
    /// Schlankes Atelier-Layout horizontal — daher knapper als die
    /// alte 110-pt-Vertikal-Karte.
    private static let minPanelHeight: CGFloat = 70

    init(appState: AppState) {
        self.appState = appState
        // Bootstrap-Rendering ohne Resize-Callback (self gibt's noch nicht).
        // Nach super.init wird die echte rootView mit Callback gesetzt.
        self.hostingController = NSHostingController(
            rootView: OverlayContent(appState: appState))
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: style,
            backing: .buffered,
            defer: true)
        super.init()

        // Echte rootView mit Resize-Callback installieren.
        hostingController.rootView = OverlayContent(
            appState: appState,
            onSizeChange: { [weak self] size in
                self?.contentSizeChanged(size)
            })
        panel.contentViewController = hostingController
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.alphaValue = 0

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

    /// Setzt das Panel auf die Startgröße (min height) zurück, zentriert
    /// horizontal, mit konstantem Abstand zum Bildschirmrand. Verankert
    /// die Top-Kante für die nachfolgenden Wachstums-Resizes.
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - Self.panelWidth / 2
        let y = frame.minY + 80
        let initSize = NSSize(width: Self.panelWidth, height: Self.minPanelHeight)
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: initSize),
                       display: true)
        topEdgeY = y + Self.minPanelHeight
        lastAppliedHeight = Self.minPanelHeight
    }

    /// Wird vom `OverlayContent`-PreferenceKey aufgerufen, sobald die
    /// natürliche View-Größe sich ändert (typisch: Vorschau wächst von
    /// 1 auf 2 Zeilen, von 2 auf 3, …). Wir mappen `height` auf einen
    /// neuen NSPanel-Frame mit Top-Edge-Anchor.
    private func contentSizeChanged(_ size: CGSize) {
        guard isCurrentlyVisible else { return }
        let measured = ceil(size.height)
        // Untergrenze: Startgröße. Obergrenze: SwiftUI's `lineLimit(5)`
        // begrenzt schon die natürliche Höhe — wir brauchen hier keinen
        // expliziten Cap. Falls SwiftUI doch mal überschießt, schadet
        // ein größerer Panel-Frame nicht (Text wäre einfach mehr als
        // 5 Zeilen, was wir per truncationMode(.head) ausschließen).
        let newHeight = max(Self.minPanelHeight, measured)
        // Oszillation vermeiden — kleinere Drift (Sub-Pixel) ignorieren.
        guard abs(newHeight - lastAppliedHeight) >= 1 else { return }
        let oldFrame = panel.frame
        let newOriginY = topEdgeY - newHeight
        let newFrame = NSRect(
            x: oldFrame.origin.x,
            y: newOriginY,
            width: Self.panelWidth,
            height: newHeight)
        lastAppliedHeight = newHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        }
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
