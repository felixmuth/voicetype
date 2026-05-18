import SwiftUI
import VoiceTypeCore

/// Klick-durchlässiges Aufnahme-Overlay am unteren Bildschirmrand.
///
/// Atelier-Layout (links → rechts):
/// - **Bar** (4 pt): vertikaler Plum-Strich, dehnt sich mit der Karte
/// - **Slot** (26 pt): Wellenform (rec) / Drei Punkte (cleanup) / Alert
/// - **Text** (fließend): die Live-Vorschau aus `appState.livePreview`
/// - **Status** (mono, optional): „Cleanup" / „Fehler" rechts
///
/// Wachstum: Karte startet einzeilig. Sobald die Live-Vorschau über
/// eine Zeile hinausgeht, wächst die Karte nach unten — der
/// `OverlayWindowController` resized das umgebende Panel synchron mit
/// (Top-Edge bleibt fix). Cap bei 5 Zeilen — danach scrollt der Text
/// mit, der Anfang verschwindet oben (`truncationMode(.head)`).
struct OverlayContent: View {
    let appState: AppState
    /// Callback an den `OverlayWindowController`: hier kommt die
    /// natürliche Größe des outer-Cards rein. Der Controller mappt
    /// die Höhe auf das NSPanel-Frame (Top-Edge anchored).
    var onSizeChange: (CGSize) -> Void = { _ in }

    private var isProcessing: Bool {
        switch appState.dictationState {
        case .finalizing, .cleaning, .delivering: return true
        default: return false
        }
    }

    private var isError: Bool {
        if case .error = appState.dictationState { return true }
        return false
    }

    var body: some View {
        outerCard
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: OverlayContentSizeKey.self,
                            value: geo.size)
                })
            .onPreferenceChange(OverlayContentSizeKey.self) { size in
                onSizeChange(size)
            }
    }

    private var outerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            // Bar links — dehnt sich vertikal mit der Karte
            barIndicator

            // Slot: Wellenform / Drei Punkte / Alert-Icon
            statusSlot
                .frame(width: 26, height: 22)

            // Live-Text in eigener Stadium-Pille — wächst mehrzeilig
            previewText
                .frame(maxWidth: .infinity)

            // Status-Label rechts (nur bei processing / error)
            if let label = statusLabel {
                Text(label)
                    .font(Theme.mono(10.5, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(isError ? Theme.warn : Color.secondary)
                    .padding(.leading, 12)
                    .padding(.vertical, 2)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 1)
                    }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.soft)
                .fill(.thinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.soft)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        // `fixedSize` vertikal: Karte nimmt natürliche Höhe an
        // (1 Zeile = klein, 5 Zeilen = größer) — der PreferenceKey
        // berichtet diese Höhe an den Controller.
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Bar

    private var barIndicator: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Theme.barColor(for: appState.dictationState))
            .frame(width: 4)
            .frame(minHeight: 26, maxHeight: .infinity)
            .opacity(isError ? 1.0 : 0.85)
            .modifier(BarBreathe(active: appState.dictationState == .recording))
    }

    // MARK: - Status-Slot

    @ViewBuilder
    private var statusSlot: some View {
        if isError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.warn)
        } else if isProcessing {
            ProcessingPulse()
        } else {
            // Aufnahme oder idle/loading — die WaveformIcon-Komponente
            // weiß selbst, ob sie animieren soll (active vs. inactive).
            WaveformIcon(
                state: appState.dictationState,
                isSpeaking: appState.isSpeaking)
        }
    }

    // MARK: - Preview-Text

    private var previewText: some View {
        // PreviewPill kapselt das mehrzeilige Live-Feld:
        // - 1–5 Zeilen: Pille wächst mit Text, Card wächst mit Panel
        // - >5 Zeilen: Pille bleibt bei 5-Zeilen-Höhe, Inhalt scrollt
        //   automatisch nach unten, Oberkante verblasst mit Gradient
        //   (sanftes Fade-Out statt „…"-Abbruch)
        let preview = appState.livePreview
        let display = preview.isEmpty ? "\u{00A0}" : preview
        return PreviewPill(text: display)
    }

    // MARK: - Status-Label

    private var statusLabel: String? {
        switch appState.dictationState {
        case .error: return "Fehler"
        default:     return nil
        }
    }
}

// MARK: - PreviewPill (Stadium-Feld mit Auto-Scroll + Fade-Top)

/// Vorschau-Pille: bis 5 Zeilen wächst sie mit, danach bleibt sie
/// fix in der Höhe — der Inhalt scrollt sanft nach unten, die
/// Oberkante verblasst per Gradient-Mask. Kein abruptes „…" mehr.
private struct PreviewPill: View {
    let text: String

    /// Maximale Pille-Höhe (≈ 5 Zeilen Text bei 16pt + lineSpacing 2).
    private let maxHeight: CGFloat = 110
    /// Höhe der Fade-Zone oben (in pt, absolut — nicht prozentual,
    /// sonst würde bei 1-zeiligem Text die erste Zeile verblassen).
    private let fadeZone: CGFloat = 22
    /// 1-Zeilen-Mindesthöhe; wird vor dem ersten PreferenceKey-
    /// Callback als Anfangswert genommen, damit die Pille beim
    /// Auftauchen nicht 0pt hoch ist.
    private let minHeight: CGFloat = 24

    /// Tatsächliche Texthöhe, vom GeometryReader-PreferenceKey gemeldet.
    @State private var contentHeight: CGFloat = 24

    var body: some View {
        let visibleHeight = max(minHeight, min(contentHeight, maxHeight))
        let needsFade = contentHeight > maxHeight + 0.5

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(text)
                    .font(Theme.ui(16))
                    .lineSpacing(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(
                                    key: PreviewTextHeightKey.self,
                                    value: g.size.height)
                        })
                    .id("bottom")
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(height: visibleHeight)
            .animation(.easeOut(duration: 0.25), value: visibleHeight)
            .onPreferenceChange(PreviewTextHeightKey.self) { h in
                contentHeight = h
            }
            .onChange(of: text) { _, _ in
                // Bei jedem Live-Update sanft nach unten scrollen.
                // Nur ab >5 Zeilen sichtbar — bei kürzerem Text ist
                // der Scroll-Range null, der Aufruf bleibt billig.
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .mask {
            // Gradient-Mask nur aktiv, wenn der Text die Pille überschritten
            // hat — sonst würde die erste Zeile sichtbar verblassen.
            if needsFade {
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black]),
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: fadeZone)
                    Color.black
                }
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PreviewTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Pulsierender Kreis (Processing-Indikator)

/// Einzelner Plum-Kreis, der in Größe und Opacity sanft atmet —
/// ruhiger als drei Punkte, klares Signal "es läuft etwas".
private struct ProcessingPulse: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            // Period: 1.4 s, Sinus-Welle von 0 bis 1
            let omega = 2 * Double.pi / 1.4
            let s = (sin(omega * t) + 1) / 2

            // Scale 0.7 → 1.0, Opacity 0.45 → 1.0
            let scale = 0.7 + 0.3 * s
            let opacity = 0.45 + 0.55 * s

            Circle()
                .fill(Theme.plum)
                .frame(width: 14, height: 14)
                .scaleEffect(scale)
                .opacity(opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Bar-Atmung (nur während Aufnahme)

/// Dezenter Atem-Effekt: Opacity wandert sanft zwischen 0.55 und 1.0
/// — nur bei `.recording`, alle anderen States bleiben statisch bei 0.85.
private struct BarBreathe: ViewModifier {
    let active: Bool
    @State private var phase: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (phase ? 1.0 : 0.55) : 0.85)
            .animation(
                active
                    ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                    : .default,
                value: phase)
            .onAppear { if active { phase = true } }
            .onChange(of: active) { _, newValue in phase = newValue }
    }
}

// MARK: - PreferenceKey

/// Berichtet die natürliche Größe der Outer-Card an den
/// `OverlayWindowController`, der das NSPanel synchron resized.
private struct OverlayContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
