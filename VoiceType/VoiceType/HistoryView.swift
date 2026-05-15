import SwiftUI
import VoiceTypeCore

/// Volle Verlaufs-Liste — eine Row pro `TranscriptEntry` (neueste oben),
/// mit Zeitstempel, Text und „Kopieren"-Knopf.
struct HistoryView: View {
    let appState: AppState

    var body: some View {
        Group {
            if appState.log.isEmpty {
                ContentUnavailableView(
                    "Noch keine Transkriptionen",
                    systemImage: "waveform",
                    description: Text("Halte den Hotkey, um zu diktieren."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.log) { entry in
                            row(for: entry)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Verlauf")
    }

    @ViewBuilder
    private func row(for entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
