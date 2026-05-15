import SwiftUI
import VoiceTypeCore

/// Animiertes Wellenform-Icon: drei graue statische Balken im Inaktiv-
/// Modus, fünf grüne animierte Balken im Aktiv-Modus (Hybrid bei
/// Aufnahme, reiner Rhythmus beim Verarbeiten).
struct WaveformIcon: View {
    let state: DictationState
    let level: Float

    private var isActive: Bool {
        switch state {
        case .recording, .finalizing, .cleaning, .delivering: return true
        case .idle, .loading, .error:                          return false
        }
    }
    private var isRecording: Bool { state == .recording }
    private var color: Color { isActive ? .green : .secondary }

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                    let heights = BarHeight.heights(
                        active: isActive,
                        recording: isRecording,
                        level: level,
                        phase: phase)
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color)
                                .frame(width: 2, height: h)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .clipped()
                }
            } else {
                TimelineView(.explicit([Date()])) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate
                    let heights = BarHeight.heights(
                        active: isActive,
                        recording: isRecording,
                        level: level,
                        phase: phase)
                    HStack(alignment: .center, spacing: 2) {
                        ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color)
                                .frame(width: 2, height: h)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .clipped()
                }
            }
        }
    }
}
