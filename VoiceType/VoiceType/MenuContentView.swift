import SwiftUI
import VoiceTypeCore

/// Menüleisten-Popover im Atelier-Stil.
///
/// Aufbau (top-down):
/// - Status-Block: Plum-Bar links + Status-Text + dezenter Sub-Text
/// - Hotkey-Anzeige (Push-to-Talk-Taste)
/// - Optional Cleanup-Hint / Retry-Button bei Fehler
/// - Aktionen: Fenster öffnen, Beenden
struct MenuContentView: View {
    let appState: AppState
    let onRetry: () -> Void
    /// Hotkey-Anzeigename (z. B. „F5", „⌃⌥V"). Optional — wenn nil,
    /// wird die Zeile weggelassen.
    var hotkeyName: String? = nil
    /// `var` mit Default, damit der Parameter im synthetisierten
    /// memberwise init landet — `let cleanupHint = nil` würde ihn
    /// rausnehmen. Wird de-facto nie mutiert.
    var cleanupHint: String? = nil
    /// Wenn `true`: zeigt einen prominenten Permission-Banner statt
    /// dem normalen Status-Block. Klick öffnet das `permissions`-Window.
    var permissionsMissing: Bool = false

    @Environment(\.openWindow) private var openWindow

    private var statusText: String {
        switch appState.dictationState {
        case .loading:      return "Modell lädt…"
        case .idle:         return "Bereit"
        case .recording:    return "Aufnahme läuft"
        case .finalizing:   return "Verarbeite…"
        case .cleaning:     return "Verarbeite…"
        case .delivering:   return "Füge ein…"
        case .error(let m): return m
        }
    }

    private var statusSubText: String? {
        switch appState.dictationState {
        case .idle:      return "Hotkey halten zum Diktieren"
        case .recording: return "Loslassen zum Einfügen"
        default:         return nil
        }
    }

    private var isError: Bool {
        if case .error = appState.dictationState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Bei fehlenden Berechtigungen: Permission-Banner statt Status
            if permissionsMissing {
                permissionBanner
                    .padding(.bottom, 14)
                Divider()
            } else {
                // Normaler Status-Block
                statusBlock
                    .padding(.bottom, 14)
                Divider()
            }

            // Hotkey-Row (nur wenn von außen gesetzt UND Permissions da)
            if let hotkeyName, !permissionsMissing {
                hotkeyRow(hotkeyName)
                Divider()
            }

            // Cleanup-Hint (selten — nur wenn FoundationModels nicht verfügbar)
            if let cleanupHint {
                hintRow(cleanupHint)
                Divider()
            }

            // Aktionen
            VStack(alignment: .leading, spacing: 0) {
                if isError {
                    actionRow(
                        label: "Erneut versuchen",
                        systemImage: "arrow.clockwise",
                        action: onRetry)
                }

                actionRow(
                    label: "Fenster öffnen",
                    systemImage: "macwindow",
                    shortcut: "⌘O") {
                        openWindow(id: "main")
                        NSApp.activate()
                    }

                actionRow(
                    label: "Beenden",
                    systemImage: "power",
                    shortcut: "⌘Q",
                    muted: true) {
                        NSApplication.shared.terminate(nil)
                    }
            }
            .padding(.top, 6)
        }
        .padding(18)
        .frame(minWidth: 360, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Permission-Banner

    private var permissionBanner: some View {
        Button {
            openWindow(id: "permissions")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                // Warn-Bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Theme.warn)
                    .frame(width: 3, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Berechtigungen fehlen")
                        .font(Theme.display(14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text("Klicken zum Einrichten")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.plum)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status-Block

    private var statusBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            // Bar links
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.barColor(for: appState.dictationState))
                .frame(width: 3, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(Theme.display(14, weight: .medium))
                    .foregroundStyle(isError ? Theme.warn : .primary)
                if let sub = statusSubText {
                    Text(sub)
                        .font(Theme.mono(10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Hotkey-Row

    private func hotkeyRow(_ name: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("PUSH-TO-TALK")
                .font(Theme.mono(10, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HotkeyBadge(name: name)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Hint-Row

    private func hintRow(_ text: String) -> some View {
        Text(text)
            .font(Theme.ui(11.5))
            .foregroundStyle(Theme.warn)
            .padding(.vertical, 10)
    }

    // MARK: - Action-Row

    @ViewBuilder
    private func actionRow(
        label: String,
        systemImage: String,
        shortcut: String? = nil,
        muted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(label)
                    .font(Theme.ui(13))
                    .foregroundStyle(muted ? .secondary : .primary)
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut)
                        .font(Theme.mono(10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hotkey-Badge

/// Kleine Mono-Pille für die Hotkey-Anzeige.
private struct HotkeyBadge: View {
    let name: String

    var body: some View {
        Text(name.uppercased())
            .font(Theme.mono(11.5, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
    }
}
