import SwiftUI

/// Token einer Live-Vorschau-Zeile. Reine Index-Identität: Wort an
/// Position N hat ID = N. Damit:
/// - Wort an einem Slot ändert text → `contentTransition(.opacity)`
///   crossfaded am selben Slot, kein Layout-Sprung.
/// - Neues Wort am Ende → Insertion-Transition (Fade + Offset).
/// - Wort fällt am Ende weg → Removal-Transition.
private struct PreviewToken: Identifiable, Equatable {
    let id: Int
    var text: String
}

/// Wort-Flow-Layout mit linksbündigem Zeilenumbruch.
///
/// Linksbündig ist Pflicht für Streaming-Text — zentrierte Zeilen
/// würden bei jedem neuen Wort die optische Mitte verschieben und
/// alles springt sichtbar zur Seite.
struct TextFlow: Layout {
    var hSpacing: CGFloat = 5
    var vSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        // WICHTIG: NIE `.infinity` als View-Breite zurückgeben — SwiftUI
        // gibt der View sonst unbegrenzten Platz, alle Tokens landen in
        // einer Zeile, und der parent's `.frame(width:)`-Modifier clippt
        // das von rechts → erste Wörter rutschen unsichtbar nach links.
        //
        // Wenn `proposal.width` finit ist: layout mit dieser Breite und
        // returne `min(proposal, maxLineWidth)`.
        // Wenn `proposal.width` nil oder `.infinity` ist: layout im
        // single-line-Modus und returne die intrinsische Breite (= alle
        // Tokens nebeneinander).
        let proposed = proposal.width
        if let p = proposed, p.isFinite {
            let lines = computeLines(in: p, subviews: subviews)
            let height = totalHeight(of: lines)
            let maxLineWidth = lines.map(\.totalWidth).max() ?? 0
            return CGSize(width: min(p, maxLineWidth), height: height)
        } else {
            let lines = computeLines(in: .infinity, subviews: subviews)
            let height = totalHeight(of: lines)
            let maxLineWidth = lines.map(\.totalWidth).max() ?? 0
            return CGSize(width: maxLineWidth, height: height)
        }
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize,
        subviews: Subviews, cache: inout ()
    ) {
        let lines = computeLines(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for item in line.items {
                let yOffset = (line.maxHeight - item.size.height) / 2
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + hSpacing
            }
            y += line.maxHeight + vSpacing
        }
    }

    private func computeLines(in width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !current.items.isEmpty {
                let wouldBe = current.totalWidth + hSpacing + size.width
                if wouldBe > width {
                    lines.append(current)
                    current = Line()
                }
            }
            current.totalWidth += (current.items.isEmpty ? 0 : hSpacing) + size.width
            current.items.append(.init(index: index, size: size))
            current.maxHeight = max(current.maxHeight, size.height)
        }
        if !current.items.isEmpty { lines.append(current) }
        return lines
    }

    private func totalHeight(of lines: [Line]) -> CGFloat {
        guard !lines.isEmpty else { return 0 }
        let textHeight = lines.reduce(0) { $0 + $1.maxHeight }
        let gaps = vSpacing * CGFloat(lines.count - 1)
        return textHeight + gaps
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }
    private struct Line {
        var items: [Item] = []
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
    }
}

/// Live-Vorschau mit Typewriter-Reveal.
///
/// Bekommt einen einzigen `text` aus dem `AppState` (= das aktuelle
/// committed Transkript). Hinkt dem Soll-Stand gestaffelt hinterher,
/// sodass neue Wörter sichtbar von links nach rechts erscheinen.
///
/// **Empty-State** während Recording: „Zuhören…" plus blinkender
/// Cursor — Overlay fühlt sich sofort responsiv an, deckt die
/// initiale ASR-Latenz ab.
struct AnimatedRevealText: View {
    let text: String
    let isRecording: Bool
    let font: Font
    /// Explizite verfügbare Breite. Wird vom Parent (`PreviewPill`)
    /// per `GeometryReader` gemessen und durchgereicht — sonst gibt
    /// SwiftUI dem Custom-Layout `TextFlow` in einer ScrollView eine
    /// unspecifizierte Breite, und alles wird auf eine Zeile gepackt
    /// statt linksbündig zu wrappen.
    var availableWidth: CGFloat
    var hSpacing: CGFloat = 5
    var vSpacing: CGFloat = 4

    /// Aktuell gerenderte Tokens („Ist"). Hinkt dem aus `text`
    /// abgeleiteten Token-Array („Soll") gestaffelt hinterher.
    @State private var tokens: [PreviewToken] = []
    @State private var cursorBlink: Bool = false
    /// Animator: bei jedem Update neu erstellt; der alte wird
    /// gecancelt, sodass nur eine Animation gleichzeitig läuft.
    @State private var animationTask: Task<Void, Never>?

    // Reveal-Geschwindigkeit (alle Werte in Millisekunden):
    private let baseWordDelayMs = 35
    private let perCharDelayMs = 10
    private let maxWordDelayMs = 160
    private let catchUpGapThreshold = 8
    private let catchUpSpeedFactor = 0.5

    var body: some View {
        Group {
            if tokens.isEmpty {
                placeholderView
            } else {
                tokenFlow
            }
        }
        // WICHTIG: immer eine harte width-Constraint setzen — sonst
        // bekommt `TextFlow` eine `.infinity`-Proposal und packt alles
        // in eine Zeile (die nach rechts rausläuft). Fallback 400 deckt
        // den initialen Render-Pass ab, bevor `availableWidth` aus dem
        // `GeometryReader` der Pille ankommt.
        .frame(width: availableWidth > 0 ? availableWidth : 400,
               alignment: .leading)
        .accessibilityLabel(text)
        .onAppear {
            cursorBlink = true
            syncTokens(animated: false)
        }
        .onChange(of: text) { _, _ in syncTokens(animated: true) }
        .onChange(of: isRecording) { _, recording in
            cursorBlink = recording
        }
        .onDisappear { animationTask?.cancel() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var placeholderView: some View {
        if isRecording {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Zuhören…")
                    .font(font)
                    .foregroundStyle(.tertiary)
                cursor
            }
        } else {
            Text(" ")
                .font(font)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var tokenFlow: some View {
        TextFlow(hSpacing: hSpacing, vSpacing: vSpacing) {
            ForEach(tokens) { token in
                Text(token.text)
                    .font(font)
                    .foregroundStyle(.primary)
                    .id(token.id)
                    .contentTransition(.opacity)
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .offset(x: 8)),
                        removal: .opacity
                            .combined(with: .scale(scale: 0.9))))
            }
            if isRecording {
                cursor
            }
        }
    }

    private var cursor: some View {
        Text("▌")
            .font(font)
            .foregroundStyle(.secondary)
            .opacity(cursorBlink ? 0.85 : 0.2)
            .animation(
                .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                value: cursorBlink)
    }

    // MARK: - Animation

    private func syncTokens(animated: Bool) {
        let target = Self.tokenize(text)
        animationTask?.cancel()

        guard animated else {
            tokens = target
            return
        }

        animationTask = Task { @MainActor in
            await animateTo(target: target)
        }
    }

    /// Hauptloop des Reveals:
    /// 1. Gemeinsame Slots bestimmen (gleiche ID — text darf sich
    ///    ändern; das wird im selben Slot via contentTransition
    ///    animiert, kein Layout-Sprung).
    /// 2. Auf gemeinsamen Slots Text angleichen, falls geändert.
    /// 3. Überschüssige Tail-Tokens entfernen (falls Soll kürzer ist).
    /// 4. Fehlende Tokens einzeln mit Delay anhängen.
    @MainActor
    private func animateTo(target: [PreviewToken]) async {
        // 1. Common prefix nur über ID.
        var commonLen = 0
        for i in 0..<min(tokens.count, target.count) {
            if tokens[i].id == target[i].id {
                commonLen = i + 1
            } else {
                break
            }
        }

        // 2. Text-Änderungen auf gemeinsamen Slots animieren.
        for i in 0..<commonLen where tokens[i].text != target[i].text {
            withAnimation(.easeInOut(duration: 0.25)) {
                tokens[i].text = target[i].text
            }
        }

        // 3. Tail entfernen, falls überzählig.
        if tokens.count > commonLen {
            withAnimation(.easeOut(duration: 0.18)) {
                tokens = Array(tokens.prefix(commonLen))
            }
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
        }

        // 4. Fehlende Tokens einzeln anhängen.
        while tokens.count < target.count {
            if Task.isCancelled { return }
            let nextToken = target[tokens.count]
            withAnimation(.easeOut(duration: 0.22)) {
                tokens.append(nextToken)
            }
            let gap = target.count - tokens.count
            let speedFactor: Double =
                gap > catchUpGapThreshold ? catchUpSpeedFactor : 1.0
            let rawDelay =
                Double(baseWordDelayMs + nextToken.text.count * perCharDelayMs)
                * speedFactor
            let delayMs = min(Int(rawDelay), maxWordDelayMs)
            try? await Task.sleep(for: .milliseconds(delayMs))
        }
    }

    // MARK: - Helpers

    /// Splittet den Text an Whitespace und vergibt fortlaufende
    /// Index-IDs. Ein Wort am Slot N hat ID = N.
    private static func tokenize(_ s: String) -> [PreviewToken] {
        s.split(whereSeparator: { $0.isWhitespace })
            .enumerated()
            .map { PreviewToken(id: $0.offset, text: String($0.element)) }
    }
}
