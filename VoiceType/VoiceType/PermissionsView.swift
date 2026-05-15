import SwiftUI
import VoiceTypeCore

/// Wird im Popover gezeigt, solange Berechtigungen fehlen.
struct PermissionsView: View {
    let permissions: Permissions
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Berechtigungen nötig")
                .font(.headline)

            // Hinweis: Der Status wird nur bei jeder body-Auswertung neu
            // gelesen, nicht live. „Erneut prüfen" mutiert permissionsGranted
            // im AppController und erzwingt so eine Neu-Auswertung.
            row("Mikrofon", permissions.microphoneStatus(),
                hint: "Für die Sprachaufnahme.")
            row("Bedienungshilfen", permissions.accessibilityStatus(),
                hint: "Für den globalen Hotkey und das Einfügen von Text. "
                    + "In Systemeinstellungen → Datenschutz & Sicherheit → "
                    + "Bedienungshilfen aktivieren.")

            Button("Systemeinstellungen öffnen") {
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Erneut prüfen", action: onRecheck)
        }
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder
    private func row(_ name: String, _ status: PermissionStatus, hint: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: status == .granted
                ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.callout).bold()
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
