import Testing
import Foundation
@testable import VoiceTypeCore

@Suite struct SettingsMigrationTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
    }

    @Test func legacyCleanupEnabledTrueBecomesAppleFM() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"pushToTalkKey":"fn","language":"de","cleanupEnabled":true,"clipboardCopy":true,"launchAtLogin":false}"#
            .data(using: .utf8)!.write(to: url)

        let store = SettingsStore(fileURL: url)
        let loaded = store.load()

        #expect(loaded.cleanupEngine == .appleFoundationModels)
        #expect(loaded.transcriptionEngine == .apple)
        #expect(loaded.language == "de")
    }

    @Test func legacyCleanupEnabledFalseBecomesOff() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"pushToTalkKey":"fn","language":"auto","cleanupEnabled":false,"clipboardCopy":true,"launchAtLogin":false}"#
            .data(using: .utf8)!.write(to: url)

        let store = SettingsStore(fileURL: url)
        #expect(store.load().cleanupEngine == .off)
    }

    @Test func migrationIsPersistedSoSecondLoadIsCheap() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"cleanupEnabled":true}"#
            .data(using: .utf8)!.write(to: url)

        _ = SettingsStore(fileURL: url).load()
        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(raw.contains("cleanupEngine"))
        #expect(!raw.contains("cleanupEnabled"))
    }

    @Test func newSchemaRoundtripsUnchanged() throws {
        let url = tempURL()
        let store = SettingsStore(fileURL: url)
        var s = Settings()
        s.transcriptionEngine = .whisperKit
        s.whisperKitModelId = "openai_whisper-large-v3-turbo"
        s.cleanupEngine = .mlx
        // Gültige (nicht zurückgezogene) Katalog-ID — sonst klemmt der
        // Decoder sie beim Laden auf den Default und der Roundtrip
        // schlägt fehl.
        s.mlxModelId = "mlx-community/Qwen2.5-3B-Instruct-4bit"
        try store.save(s)
        #expect(store.load() == s)
    }
}
