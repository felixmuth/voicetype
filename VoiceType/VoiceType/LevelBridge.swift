import Foundation
import VoiceTypeCore

/// Forward-Indirektion für den Mikrofon-Level-Strom aus
/// `WhisperKitEngine`. Wird im `AppController.init` *vor* dem
/// `DictationCoordinator` instanziiert, damit der Engine-Factory-Aufruf
/// einen `onLevel`-Callback bekommen kann; danach setzt der
/// AppController den `coordinator` rein. Alle Level-Updates landen
/// dann am selben Punkt wie der AudioCapture-Pfad (Apple), sodass die
/// VAD-Hysterese (`isSpeaking`-Flag, Wellenform-Pulse) für beide
/// Engines konsistent ist.
@MainActor
final class LevelBridge {
    weak var coordinator: DictationCoordinator?

    func handle(_ level: Float) {
        coordinator?.updateMicLevel(level)
    }
}
