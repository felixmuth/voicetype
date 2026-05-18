import SwiftUI
import AppKit
import VoiceTypeCore

/// Design-Tokens für das "Atelier"-Theme: gedeckter Aubergine-Akzent
/// gegen warme Anthrazit/Linen-Backgrounds. Adaptiv für Light/Dark.
///
/// Bewusst keine Custom-Fonts — SF Pro (Default) mit Weight-Varianten,
/// SF Mono für technische Metadaten. Spart Font-Asset-Import-Aufwand.
enum Theme {

    // MARK: - Plum-Skala

    /// Feste Plum-Stufen für Gradients und Foreground-on-Plum-Inhalte.
    enum Plum {
        static let p100 = Color(hex: 0xE6DAEC)
        static let p200 = Color(hex: 0xCBB6D9)
        static let p300 = Color(hex: 0xA88BBE)
        static let p400 = Color(hex: 0x8869A2)
        static let p500 = Color(hex: 0x6F5290)
        static let p600 = Color(hex: 0x5A3F78)
        static let p700 = Color(hex: 0x432C5C)
        static let p900 = Color(hex: 0x1A1129)
    }

    /// Adaptiver Hauptakzent: Plum-600 in Light, Plum-300 in Dark.
    /// Heller im Dark Mode, damit der Kontrast zum Hintergrund passt.
    static let plum = Color(light: 0x5A3F78, dark: 0xA88BBE)

    /// Gedeckter Akzent für Verarbeitungs-Indikatoren.
    static let plumSoft = Color(light: 0x8869A2, dark: 0x8869A2).opacity(0.65)

    /// Tiefer Plum für CTA-Buttons.
    static let plumStrong = Color(light: 0x432C5C, dark: 0x6F5290)

    /// Sehr dezenter Plum-Hintergrund für aktive Sidebar-Indicators.
    static let plumWash = Color(light: 0x6F5290, dark: 0xA88BBE).opacity(0.1)

    // MARK: - Status

    /// Fehler-Ton: warmes Terracotta statt grelles Rot.
    static let warn = Color(light: 0xB5523F, dark: 0xC66B5A)

    // MARK: - Typography

    /// Display-Font für Headlines.
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Mono für technische Metadaten (Hotkeys, Zeitstempel).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// UI-Standard für Body.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: - Radii / Spacing

    enum Radius {
        static let tight: CGFloat = 4
        static let soft: CGFloat = 8
        static let card: CGFloat = 14
        static let panel: CGFloat = 18
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - State → Bar-Farbe

    /// Bar-Farbe im Overlay je nach DictationState.
    static func barColor(for state: DictationState) -> Color {
        switch state {
        case .recording:                           return plum
        case .finalizing, .cleaning, .delivering:  return plumSoft
        case .error:                               return warn
        case .loading, .idle:                      return Color.secondary.opacity(0.4)
        }
    }
}

// MARK: - Color helpers

extension Color {
    /// Erstellt eine `Color` aus einem hex-Integer (0xRRGGBB).
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Adaptive Farbe mit getrennten Light/Dark-Werten (hex 0xRRGGBB).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            let hex = isDark ? dark : light
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
}
