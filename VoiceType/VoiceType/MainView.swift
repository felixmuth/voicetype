import SwiftUI
import VoiceTypeCore

/// Wurzelview des Hauptfensters: NavigationSplitView mit Sidebar
/// (Verlauf / Einstellungen) und Detail-Bereich.
struct MainView: View {
    let controller: AppController
    @State private var selection: Section = .history

    enum Section: String, CaseIterable, Identifiable {
        case history, settings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .history:  return "Verlauf"
            case .settings: return "Einstellungen"
            }
        }
        var systemImage: String {
            switch self {
            case .history:  return "clock"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection {
            case .history:
                HistoryView(appState: controller.appState)
            case .settings:
                SettingsView(controller: controller)
            }
        }
    }
}
