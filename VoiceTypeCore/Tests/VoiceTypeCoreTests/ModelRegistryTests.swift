import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct ModelRegistryTests {

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func writeMarker(into folder: URL, kind: ModelDescriptor.Kind) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        let marker = kind == .whisperKit
            ? folder.appendingPathComponent("AudioEncoder.mlmodelc")
            : folder.appendingPathComponent("config.json")
        try Data("placeholder".utf8).write(to: marker)
    }

    @Test func freshRegistryReportsNotInstalled() async {
        let registry = ModelRegistry(rootFolder: tempRoot(), downloaders: [:])
        await registry.refresh()
        // Nur WhisperKit ist per `rootFolder` isolierbar. MLX und Parakeet
        // liegen in fixen globalen Caches der jeweiligen Fremd-Libraries
        // (~/Library/Caches/models bzw. FluidAudios Application Support) —
        // ein dort bereits vorhandenes Modell würde diesen Test
        // umgebungsabhängig machen, deshalb hier nicht geprüft.
        #expect(registry.status[ModelCatalog.whisperKitDefault] == .notInstalled)
    }

    @Test func refreshDetectsInstalledModelOnDisk() async throws {
        let registry = ModelRegistry(rootFolder: tempRoot(), downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        try writeMarker(into: registry.folder(for: d, even: true)!, kind: .whisperKit)
        await registry.refresh()
        if case .installed(let size) = registry.status[d] {
            #expect(size > 0)
        } else {
            Issue.record("expected .installed, got \(String(describing: registry.status[d]))")
        }
    }

    @Test func folderReturnsNilUntilInstalled() async throws {
        let registry = ModelRegistry(rootFolder: tempRoot(), downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        await registry.refresh()
        #expect(registry.folder(for: d) == nil)
        try writeMarker(into: registry.folder(for: d, even: true)!, kind: .whisperKit)
        await registry.refresh()
        #expect(registry.folder(for: d) != nil)
    }

    @Test func downloadDrivesStatusFromInstallingToInstalled() async throws {
        let fake = FakeDownloader()
        let registry = ModelRegistry(
            rootFolder: tempRoot(), downloaders: [.whisperKit: fake])
        let d = ModelCatalog.whisperKitDefault

        let downloadTask = Task { await registry.download(d) }

        // bis der Fake fertigsignalisiert, sehen wir installing-Updates:
        try await waitUntil(timeoutMs: 500) {
            if case .installing = registry.status[d] { return true }
            return false
        }

        try writeMarker(into: registry.folder(for: d, even: true)!, kind: .whisperKit)
        fake.finishSuccess()
        await downloadTask.value

        if case .installed = registry.status[d] {} else {
            Issue.record("expected .installed, got \(String(describing: registry.status[d]))")
        }
    }

    @Test func downloadCancelLeavesStatusNotInstalled() async throws {
        let fake = FakeDownloader()
        let registry = ModelRegistry(
            rootFolder: tempRoot(), downloaders: [.whisperKit: fake])
        let d = ModelCatalog.whisperKitDefault

        let downloadTask = Task { await registry.download(d) }
        try await waitUntil(timeoutMs: 500) {
            if case .installing = registry.status[d] { return true }
            return false
        }

        await registry.cancelDownload(d)
        await downloadTask.value
        #expect(registry.status[d] == .notInstalled)
    }

    @Test func downloadFailurePropagatesReason() async throws {
        let fake = FakeDownloader()
        let registry = ModelRegistry(
            rootFolder: tempRoot(), downloaders: [.whisperKit: fake])
        let d = ModelCatalog.whisperKitDefault

        let downloadTask = Task { await registry.download(d) }
        try await waitUntil(timeoutMs: 500) {
            if case .installing = registry.status[d] { return true }
            return false
        }
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        fake.finishFailure(Boom())
        await downloadTask.value

        if case .failed(let reason) = registry.status[d] {
            #expect(reason == "boom")
        } else {
            Issue.record("expected .failed, got \(String(describing: registry.status[d]))")
        }
    }

    @Test func downloadWithoutRegisteredDownloaderFails() async {
        let registry = ModelRegistry(rootFolder: tempRoot(), downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        await registry.download(d)
        if case .failed = registry.status[d] {} else {
            Issue.record("expected .failed without downloader")
        }
    }

    @Test func mlxFolderIsInSharedHubCache() {
        let root = tempRoot()
        let registry = ModelRegistry(rootFolder: root, downloaders: [:])
        let d = ModelCatalog.mlxDefault
        let folder = registry.folder(for: d, even: true)!
        // MLXLMCommon verdrahtet `~/Library/Caches/models/<repo>/` fest.
        // Die Registry spiegelt genau diesen Pfad und ignoriert für
        // MLX-Modelle daher bewusst ihren `rootFolder`.
        let expected = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(d.id, isDirectory: true)
        #expect(folder.path == expected.path)
        #expect(!folder.path.hasPrefix(root.path))
    }

    @Test func whisperKitFolderMirrorsHubApiLayout() {
        let root = tempRoot()
        let registry = ModelRegistry(rootFolder: root, downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        let folder = registry.folder(for: d, even: true)!
        // WhisperKits HubApi-Downloader legt unter
        // `<root>/whisperkit/models/argmaxinc/whisperkit-coreml/<variant>/` ab.
        #expect(folder.path.hasPrefix(root.path))
        #expect(folder.path.hasSuffix(
            "/whisperkit/models/argmaxinc/whisperkit-coreml/\(d.id)"))
    }

    @Test func deleteRemovesInstalledModelFromDisk() async throws {
        let registry = ModelRegistry(rootFolder: tempRoot(), downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        try writeMarker(into: registry.folder(for: d, even: true)!, kind: .whisperKit)
        await registry.refresh()
        try await registry.delete(d)
        #expect(registry.status[d] == .notInstalled)
        #expect(registry.folder(for: d) == nil)
    }

    /// Wartet, bis `condition` true ist oder das Timeout abläuft.
    /// Polling-Intervall: 5 ms. Wirft, wenn der MainActor länger braucht
    /// als erlaubt — schützt Tests vor Hängern, ohne fragile fixed sleeps.
    private func waitUntil(
        timeoutMs: Int,
        condition: @MainActor () -> Bool
    ) async throws {
        let start = ContinuousClock().now
        while !condition() {
            try await Task.sleep(for: .milliseconds(5))
            if start.duration(to: ContinuousClock().now) > .milliseconds(timeoutMs) {
                Issue.record("condition not met within \(timeoutMs)ms")
                return
            }
        }
    }
}

/// Test-Doppelgänger: ruft sofort 10 % Progress und hält dann, bis der
/// Test `finishSuccess()` oder `finishFailure(_:)` aufruft.
final class FakeDownloader: ModelDownloading, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        onProgress(0.1)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.continuation = c
                lock.unlock()
            }
        } onCancel: {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(throwing: CancellationError())
        }
    }

    func finishSuccess() {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume()
    }
    func finishFailure(_ error: Error) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(throwing: error)
    }
}
