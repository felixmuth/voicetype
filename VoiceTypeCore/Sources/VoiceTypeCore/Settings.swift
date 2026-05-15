import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var pushToTalkKey: String = "fn"     // "fn", "f13", …
    public var language: String = "auto"        // "auto" | "de" | "en"
    public var cleanupEnabled: Bool = true
    public var clipboardCopy: Bool = true       // Transkript zusätzlich in die Zwischenablage
    public var launchAtLogin: Bool = false

    public init() {}
}

public final class SettingsStore: Sendable {
    private let fileURL: URL

    /// Standard-Ablage: ~/Library/Application Support/VoiceType/settings.json
    public static let defaultURL: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("VoiceType", isDirectory: true)
        .appendingPathComponent("settings.json")

    public init(fileURL: URL = SettingsStore.defaultURL) {
        self.fileURL = fileURL
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
