import SwiftUI
import VoiceTypeCore

/// Status-Bar-Label: Mikrofon-Silhouette aus dem App-Icon (Asset
/// `MenubarMic`, template-rendered → adaptiert sich an Light/Dark-
/// Modus). Bewusst KEIN TimelineView — eine 30-Hz-Animation im
/// Status-Bar-Rendering hat in Plan-3-Smoke-Tests einen
/// 100-%-CPU + linearem Memory-Wachstum-Loop verursacht (siehe
/// AudioCapture-Backpressure-Commit). Die animierte Wellenform lebt
/// im `OverlayContent`, das nur während der Aufnahme sichtbar ist.
///
/// UX-Farbschema:
/// - Aufnahme: grün (deutliches Signal, dass das Mikro live ist)
/// - Verarbeitung (finalizing/cleaning/delivering): primary (dunkel)
/// - Fehler: orange + Warn-Glyph statt Mic
/// - Inaktiv/Loading: secondary (dezent, default Menubar-Look)
struct MenuBarLabel: View {
    let state: DictationState

    var body: some View {
        Group {
            switch state {
            case .error:
                Image(systemName: "exclamationmark.triangle")
            default:
                Image("MenubarMic")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 18)
            }
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        switch state {
        case .recording:                              return .green
        case .finalizing, .cleaning, .delivering:    return .primary
        case .error:                                  return .orange
        case .idle, .loading:                         return .secondary
        }
    }
}
