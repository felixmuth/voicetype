import SwiftUI
import VoiceTypeCore

/// Inhalt des Menüleisten-Popovers: aktueller Status, letzte
/// Transkriptionen, Beenden — plus optional ein dezenter Hinweis, wenn
/// das Cleanup-Modell nicht verfügbar ist.
struct MenuContentView: View {
    let appState: AppState
    let onRetry: () -> Void
    // `var` mit Default ist hier nötig, damit der Parameter im
    // synthetisierten memberwise init landet — `let cleanupHint = nil`
    // würde ihn rausnehmen. Wird de-facto nie mutiert.
    var cleanupHint: String? = nil

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

            if isError {
                Button("Erneut versuchen", action: onRetry)
            }

            if let cleanupHint {
                Text(cleanupHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !appState.log.isEmpty {
                Divider()
                Text("Zuletzt").font(.caption).foregroundStyle(.tertiary)
                ForEach(appState.log.prefix(3)) { entry in
                    Text(entry.text)
                        .font(.callout)
                        .lineLimit(2)
                }
            }

            Divider()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}
