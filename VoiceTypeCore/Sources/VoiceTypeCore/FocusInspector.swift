import AppKit
import ApplicationServices

/// Prüft on-demand, ob in der Vordergrund-App ein Textfeld den Fokus hat.
public struct FocusInspector: FocusInspecting {
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox",
    ]

    public init() {}

    public func isTextFieldFocused() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let element = focused,
            CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return false }
        let axElement = element as! AXUIElement

        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axElement, kAXRoleAttribute as CFString, &role) == .success,
            let roleString = role as? String else { return false }

        return Self.editableRoles.contains(roleString)
    }
}
