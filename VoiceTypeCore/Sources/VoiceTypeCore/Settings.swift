import Foundation

public enum TranscriptionEngineKind: String, Codable, Sendable {
    case apple
    case whisperKit
}

public enum CleanupEngineKind: String, Codable, Sendable {
    case off
    case appleFoundationModels
    case mlx
}

public struct Settings: Codable, Equatable, Sendable {
    public var pushToTalkKey: String = "fn"
    public var language: String = "auto"
    public var clipboardCopy: Bool = true
    public var launchAtLogin: Bool = false

    public var transcriptionEngine: TranscriptionEngineKind = .apple
    public var whisperKitModelId: String = "openai_whisper-large-v3"
    /// Default ist `.off`: reines Transkribieren ohne LLM-Modifikation.
    /// FoundationModelCleanup tendiert dazu, Fragen zu beantworten statt
    /// sie als Fragen zu transkribieren — wer das Cleanup will, kann es
    /// in Settings einschalten.
    public var cleanupEngine: CleanupEngineKind = .off
    public var mlxModelId: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    public init() {}
}

/// Altes Schema (bis einschließlich Plan 3). Wird beim Laden erkannt
/// und einmalig auf das neue Schema gemappt — die migrierte Datei wird
/// atomar zurückgeschrieben, sodass dieser Pfad pro Datei nur einmal
/// genommen wird.
private struct LegacySettings: Decodable {
    var pushToTalkKey: String?
    var language: String?
    var cleanupEnabled: Bool?
    var clipboardCopy: Bool?
    var launchAtLogin: Bool?
}

public final class SettingsStore: Sendable {
    private let fileURL: URL

    /// Standard-Ablage: ~/Library/Application Support/VoiceType/settings.json
    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceType", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public init(fileURL: URL = SettingsStore.defaultURL) {
        self.fileURL = fileURL
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else {
            return Settings()
        }
        // Legacy-Erkennung: eine alte Datei enthält den Key `cleanupEnabled`
        // (Bool) und keinen `cleanupEngine` (String). JSONDecoder würde sie
        // sonst klaglos als modernes Schema akzeptieren — alle neuen Felder
        // fielen auf Defaults, die Migration würde nie laufen.
        if isLegacy(data: data),
           let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            let migrated = Self.migrate(legacy)
            try? save(migrated)   // best effort; nicht erneut lesen
            return migrated
        }
        if let modern = try? JSONDecoder().decode(Settings.self, from: data) {
            return modern
        }
        return Settings()
    }

    private func isLegacy(data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return object["cleanupEnabled"] != nil && object["cleanupEngine"] == nil
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    fileprivate static func migrate(_ legacy: LegacySettings) -> Settings {
        var s = Settings()
        if let v = legacy.pushToTalkKey { s.pushToTalkKey = v }
        if let v = legacy.language { s.language = v }
        if let v = legacy.clipboardCopy { s.clipboardCopy = v }
        if let v = legacy.launchAtLogin { s.launchAtLogin = v }
        if let v = legacy.cleanupEnabled {
            s.cleanupEngine = v ? .appleFoundationModels : .off
        }
        return s
    }

}
