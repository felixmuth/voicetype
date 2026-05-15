import SwiftUI
import VoiceTypeCore

/// Inhalt des Menüleisten-Popovers (schlank): aktueller Status, optional
/// der Cleanup-Hinweis, „Erneut versuchen" im Fehlerfall, „Fenster
/// öffnen…" und „Beenden". Verlauf-Liste lebt jetzt im Hauptfenster.
struct MenuContentView: View {
    let appState: AppState
    let onRetry: () -> Void
    // `var` mit Default ist hier nötig, damit der Parameter im
    // synthetisierten memberwise init landet — `let cleanupHint = nil`
    // würde ihn rausnehmen. Wird de-facto nie mutiert.
    var cleanupHint: String? = nil

    @Environment(\.openWindow) private var openWindow

    private var statusText: String {
        switch appState.dictationState {
        case .loading:     return "Modell lädt…"
        case .idle:        return "Bereit — Hotkey halten zum Diktieren"
        case .recording:   return "Aufnahme läuft…"
        case .finalizing:  return "Verarbeite…"
        case .cleaning:    return "Verarbeite…"
        case .delivering:  return "Füge ein…"
        case .error(let m): return m
        }
    }

    private var isError: Bool {
        if case .error = appState.dictationState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let cleanupHint {
                Text(cleanupHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if isError {
                Button("Erneut versuchen", action: onRetry)
            }

            Divider()

            Button("Fenster öffnen…") {
                openWindow(id: "main")
                NSApp.activate()
            }

            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}
