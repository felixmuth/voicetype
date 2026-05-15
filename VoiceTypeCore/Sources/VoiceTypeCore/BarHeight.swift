import Foundation

/// Reine, testbare Berechnung der Balken-Höhen für das animierte
/// Wellenform-Icon. Wird sowohl vom Menüleisten-Icon als auch vom
/// Overlay-Inhalt verwendet.
public enum BarHeight {
    public static let baseline: Double = 4    // pt — Höhe inaktiver Balken
    public static let maxRange: Double = 14   // pt — Spannweite über baseline
    public static let processingAmplitude: Double = 0.6
    public static let recordingMinAmplitude: Double = 0.5
    public static let levelGain: Double = 1.6
    public static let omega: Double = 2 * .pi * 2.0  // 2 Hz Grundfrequenz
    public static let phaseStride: Double = .pi / 3   // 60° Versatz pro Balken

    /// Liefert ein Array von Balken-Höhen (in pt) für den gegebenen
    /// Animations-Zustand.
    /// - `active`: einer von { recording, finalizing, cleaning, delivering }.
    /// - `recording`: nur `recording` aktiv (Pegel-Skalierung erlaubt).
    /// - `level`: aktueller `appState.micLevel`, 0…1.
    /// - `phase`: aktuelle Zeit in Sekunden (für die Animation).
    public static func heights(active: Bool, recording: Bool, level: Float, phase: TimeInterval) -> [Double] {
        let count = active ? 5 : 3
        guard active else {
            return Array(repeating: baseline, count: count)
        }
        return (0..<count).map { index in
            let rhythm = 0.5 * (1 + sin(phase * omega + Double(index) * phaseStride))
            let rawAmplitude: Double
            if recording {
                let levelScaled = Double(level) * levelGain
                rawAmplitude = rhythm * max(recordingMinAmplitude, levelScaled)
            } else {
                rawAmplitude = rhythm * processingAmplitude
            }
            // Clamp auf 1.0 — sonst überlaufen Balken die 18-pt-Frame
            // im Menüleisten-Icon, wenn level*levelGain > 1.
            let amplitude = min(1.0, rawAmplitude)
            return baseline + amplitude * maxRange
        }
    }
}
