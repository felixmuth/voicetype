import SwiftUI
import VoiceTypeCore

/// Wellenform-Icon mit drei sichtbaren Zuständen:
/// - **Aufnahme + Sprache** (`.recording`, `isSpeaking=true`):
///   grün, sin-animierte Wellenform + sanfte Atem-Pulsation
///   (unabhängig von Lautstärke — binärer VAD-Status)
/// - **Aufnahme + Stille** (`.recording`, `isSpeaking=false`):
///   grün, alle Balken flach, kein Pulse — User sieht klar, dass die
///   App seine Stimme gerade nicht hört
/// - **Verarbeitung** (`.finalizing`/`.cleaning`/`.delivering`):
///   dunkler, statischer Look (Overlay zeigt parallel einen Spinner)
/// - **Inaktiv** (`.idle`/`.loading`/`.error`): dezent grau
struct WaveformIcon: View {
    let state: DictationState
    let isSpeaking: Bool

    private var isRecording: Bool { state == .recording }
    private var isProcessing: Bool {
        switch state {
        case .finalizing, .cleaning, .delivering: return true
        default: return false
        }
    }
    private var color: Color {
        if isRecording { return Theme.plum }
        if isProcessing { return .primary }
        return .secondary
    }

    var body: some View {
        Group {
            if isRecording {
                // 24 Hz reichen für sichtbar glatte Bewegung und Pulse.
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let scale: Double = isSpeaking
                        ? (1.07 + 0.07 * sin(t * 2 * .pi * 2.0))   // 1.0–1.14 @ 2 Hz
                        : 1.0
                    bars(phase: t)
                        .scaleEffect(scale)
                }
            } else {
                bars(phase: 0)
            }
        }
        // Sanfter Übergang zwischen Sprache und Stille: ohne diese
        // animation snappen Balken und Pulse hart, sobald die VAD den
        // Status wechselt. Greift nur bei isSpeaking-Wechseln —
        // TimelineView-Frame-Updates (phase) bleiben sofort sichtbar.
        .animation(.easeInOut(duration: 0.25), value: isSpeaking)
    }

    @ViewBuilder
    private func bars(phase: TimeInterval) -> some View {
        let heights = BarHeight.heights(speaking: isSpeaking, phase: phase)
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: h)
            }
        }
        .frame(width: 28, height: 22)
        .clipped()
    }
}
