import SwiftUI
import VoiceTypeCore

/// Verlauf-Ansicht im Atelier-Stil.
///
/// Aufbau:
/// - **Stat-Strip** oben: drei Kennzahlen (heute / gesamt / Wörter)
///   getrennt durch Hairlines
/// - **Day-Gruppen**: Header in Mono ("HEUTE", "GESTERN", oder Datum)
/// - **Einträge**: Time-Mono links · Text in der Mitte · Copy-Knopf
///   rechts (erscheint beim Hover)
///
/// `TranscriptEntry` hat nur `id`, `timestamp`, `text` — keine
/// erfundenen Source-/Cleanup-Felder.
struct HistoryView: View {
    let appState: AppState

    var body: some View {
        Group {
            if appState.log.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedByDay, id: \.0) { day, entries in
                            dayHeader(for: day)
                            ForEach(entries) { entry in
                                entryRow(entry)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.plum.opacity(0.6))
            VStack(spacing: 6) {
                Text("Noch keine Diktate")
                    .font(Theme.display(18, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Halte den Hotkey, um zu diktieren.")
                    .font(Theme.ui(13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Day Header

    private func dayHeader(for date: Date) -> some View {
        Text(dayLabel(date).uppercased())
            .font(Theme.mono(10, weight: .medium))
            .tracking(1.8)
            .foregroundStyle(.secondary)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: TranscriptEntry) -> some View {
        EntryRow(entry: entry)
    }

    // MARK: - Helpers

    /// Gruppiert die (chronologisch absteigend sortierten) Einträge
    /// nach Kalendertag. Ergebnis: [(Tag, [Einträge dieses Tages])].
    private var groupedByDay: [(Date, [TranscriptEntry])] {
        let calendar = Calendar.current
        let sorted = appState.log.sorted { $0.timestamp > $1.timestamp }
        var result: [(Date, [TranscriptEntry])] = []
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.timestamp)
            if let last = result.last, last.0 == day {
                result[result.count - 1].1.append(entry)
            } else {
                result.append((day, [entry]))
            }
        }
        return result
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Heute" }
        if cal.isDateInYesterday(date) { return "Gestern" }
        return date.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide))
    }
}

// MARK: - Entry Row als eigene View (für Hover-State)

private struct EntryRow: View {
    let entry: TranscriptEntry
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Zeit (mono, fixed width)
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(Theme.mono(11))
                .foregroundStyle(.tertiary)
                .frame(width: 48, alignment: .leading)
                .padding(.top, 2)

            // Body
            Text(entry.text)
                .font(Theme.ui(14))
                .lineSpacing(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            // Copy-Knopf (erscheint beim Hover)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Kopieren")
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
