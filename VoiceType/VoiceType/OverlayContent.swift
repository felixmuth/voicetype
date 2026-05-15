import SwiftUI
import VoiceTypeCore

/// Pillen-Inhalt für das klick-durchlässige Aufnahme-Overlay: links das
/// animierte Wellenform-Icon (größer als in der Menüleiste), rechts der
/// Live-Vorschau-Text aus `appState.livePreview`.
struct OverlayContent: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            WaveformIcon(
                state: appState.dictationState,
                level: appState.micLevel)
                .frame(width: 36, height: 24)

            Text(appState.livePreview)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .animation(.default, value: appState.livePreview)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 440)
    }
}
