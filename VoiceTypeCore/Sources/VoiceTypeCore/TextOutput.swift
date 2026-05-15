import AppKit
import ApplicationServices

/// Liefert Text aus: fügt ihn (falls gewünscht) ins fokussierte Feld der
/// Vordergrund-App ein und kopiert ihn in die Zwischenablage.
public struct TextOutput: TextDelivering {
    private let clipboardEnabled: Bool

    public init(clipboardEnabled: Bool = true) {
        self.clipboardEnabled = clipboardEnabled
    }

    public func deliver(_ text: String, pasteIntoFocusedField: Bool) {
        if pasteIntoFocusedField {
            insertIntoFocusedField(text)
        }
        if clipboardEnabled {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func insertIntoFocusedField(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let element = focused,
            CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return }
        let axElement = element as! AXUIElement

        var current: CFTypeRef?
        let existing = (AXUIElementCopyAttributeValue(
            axElement, kAXValueAttribute as CFString, &current) == .success)
            ? (current as? String ?? "") : ""

        // Plan 1: Text wird ans Feldende angehängt. Cursor-genaues Einfügen
        // (kAXSelectedTextAttribute) ist bewusst auf eine spätere Iteration vertagt.
        let newValue = existing + text
        _ = AXUIElementSetAttributeValue(
            axElement, kAXValueAttribute as CFString, newValue as CFString)
    }
}
