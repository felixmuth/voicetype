import SwiftUI
import VoiceTypeCore

/// Erstes Popover, solange Berechtigungen fehlen.
///
/// Atelier-Stil: kompakte Karte mit
/// - Header (Plum-Mark + Titel + Sub-Text in Mono)
/// - zwei nummerierten Schritten, jeweils mit Status (✓ oder Nummer)
/// - primärem CTA + sekundärem "Erneut prüfen"
struct PermissionsView: View {
    let permissions: Permissions
    let onRecheck: () -> Void

    var body: some View {
        let micGranted = permissions.microphoneStatus() == .granted
        let accGranted = permissions.accessibilityStatus() == .granted

        VStack(alignment: .leading, spacing: 0) {

            // Header
            header
                .padding(.bottom, 14)

            Divider()

            // Schritt 1 — Mikrofon
            step(
                number: 1,
                done: micGranted,
                title: "Mikrofon-Zugriff",
                description: "Nur aktiv, solange du den Hotkey hältst.")

            Divider()

            // Schritt 2 — Bedienungshilfen
            step(
                number: 2,
                done: accGranted,
                title: "Bedienungshilfen aktivieren",
                description: "Für den globalen Hotkey und das Einfügen ins Feld.")

            Divider()

            // Aktionen
            actionRow

        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Plum-Mark
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(
                    colors: [Theme.Plum.p500, Theme.Plum.p700],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Plum.p100)
                }

            Text("Willkommen bei voicetype")
                .font(Theme.display(15, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Step

    @ViewBuilder
    private func step(
        number: Int,
        done: Bool,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Nummer / Check
            ZStack {
                Circle()
                    .fill(done ? Theme.plum : Color.clear)
                    .overlay {
                        Circle()
                            .stroke(
                                done ? Color.clear : Color.primary.opacity(0.15),
                                lineWidth: 1)
                    }
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(Theme.mono(11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.ui(13, weight: .medium))
                    .foregroundStyle(done ? .secondary : .primary)
                    .strikethrough(done, color: .secondary.opacity(0.5))
                Text(description)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // Status-Mini-Label
            if done {
                Text("ERTEILT")
                    .font(Theme.mono(9.5, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Action-Row

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Erneut prüfen", action: onRecheck)
                .buttonStyle(.plain)
                .font(Theme.mono(10.5, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5))

            Spacer(minLength: 0)

            Button {
                if let url = URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Systemeinstellungen")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(Theme.ui(12, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.tight)
                        .fill(Theme.plumStrong))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
    }
}
