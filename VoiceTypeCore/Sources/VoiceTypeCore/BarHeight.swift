import Foundation

/// Reine, testbare Berechnung der Balken-Höhen für das animierte
/// Wellenform-Icon. Lautstärken-unabhängig: solange Sprache erkannt
/// wird, läuft eine konstante sin-Modulation; sonst sind alle Balken
/// auf `baseline` flach.
public enum BarHeight {
    public static let baseline: Double = 4    // pt — Höhe inaktiver Balken
    public static let maxRange: Double = 14   // pt — Spannweite über baseline
    /// Amplitude während aktiv erkannter Sprache (Min/Max um die Mitte).
    public static let speakingMinAmplitude: Double = 0.35
    public static let speakingAmplitudeRange: Double = 0.55
    public static let omega: Double = 2 * .pi * 2.0  // 2 Hz Grundfrequenz
    public static let phaseStride: Double = .pi / 3   // 60° Versatz pro Balken

    /// Liefert ein Array von Balken-Höhen (in pt).
    /// - `speaking`: true, wenn die VAD im DictationCoordinator gerade
    ///   Sprache erkannt hat (binär, nicht Lautstärke).
    /// - `phase`: aktuelle Zeit in Sekunden — bewegt die Wellenform.
    public static func heights(speaking: Bool, phase: TimeInterval) -> [Double] {
        guard speaking else {
            return Array(repeating: baseline, count: 5)
        }
        return (0..<5).map { index in
            let rhythm = 0.5 * (1 + sin(phase * omega + Double(index) * phaseStride))
            let amplitude = speakingMinAmplitude + speakingAmplitudeRange * rhythm
            return baseline + amplitude * maxRange
        }
    }
}
