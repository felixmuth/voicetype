import Testing
import Foundation
@testable import VoiceTypeCore

@Suite struct SettingsStoreTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("settings.json")
    }

    @Test func loadReturnsDefaultsWhenFileMissing() {
        let store = SettingsStore(fileURL: tempURL())
        #expect(store.load() == Settings())
    }

    @Test func saveThenLoadRoundTrips() throws {
        let url = tempURL()
        let store = SettingsStore(fileURL: url)
        var settings = Settings()
        settings.language = "de"
        settings.cleanupEngine = .off
        try store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func loadReturnsDefaultsWhenFileCorrupt() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        let store = SettingsStore(fileURL: url)
        #expect(store.load() == Settings())
    }
}
