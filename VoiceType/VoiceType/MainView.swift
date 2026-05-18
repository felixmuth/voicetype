import SwiftUI
import VoiceTypeCore

/// Wurzelview des Hauptfensters im Atelier-Stil.
///
/// Schmale Icon-Rail (76 pt) links + Detail-Bereich rechts.
/// Aktiver Tab wird durch einen Plum-Strich am linken Rand markiert.
struct MainView: View {
    let controller: AppController
    @State private var selection: MainSection = .history

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .tint(Theme.plum)
    }

    // MARK: - Rail

    private var rail: some View {
        VStack(spacing: 4) {
            ForEach(MainSection.allCases) { section in
                RailItem(
                    section: section,
                    isActive: section == selection,
                    action: { selection = section })
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .frame(width: 76)
        .background(Theme.plumWash.opacity(0.3))
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .history:
            HistoryView(appState: controller.appState)
        case .settings:
            SettingsView(controller: controller)
        }
    }
}

// MARK: - Section enum

enum MainSection: String, CaseIterable, Identifiable {
    case history, settings
    var id: String { rawValue }
    var label: String {
        switch self {
        case .history:  return "Log"
        case .settings: return "Set"
        }
    }
    var systemImage: String {
        switch self {
        case .history:  return "list.bullet"
        case .settings: return "slider.horizontal.3"
        }
    }
}

// MARK: - Rail-Item

private struct RailItem: View {
    let section: MainSection
    let isActive: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 16, weight: .regular))
                    .frame(width: 22, height: 22)

                Text(section.label.uppercased())
                    .font(Theme.mono(8.5, weight: .medium))
                    .tracking(1.4)
            }
            .frame(width: 56, height: 50)
            .foregroundStyle(
                isActive ? Theme.plum :
                isHovered ? .primary : .secondary
            )
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tight)
                    .fill(isHovered && !isActive
                          ? Color.primary.opacity(0.05)
                          : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isActive {
                    Rectangle()
                        .fill(Theme.plum)
                        .frame(width: 2, height: 24)
                        .offset(x: -10)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
