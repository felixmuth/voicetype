import Foundation
import Observation

/// Quelle, aus der ein Modell geladen wird. Tests injizieren einen Fake;
/// Production-Code übergibt `WhisperKitDownloader` bzw. `MLXDownloader`.
public protocol ModelDownloading: Sendable {
    func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}

/// Lädt, scannt und verwaltet Modell-Bundles auf Platte. UI bindet
/// direkt an `status`; tatsächlicher Download wird an einen
/// `ModelDownloading`-Wert delegiert.
@MainActor
@Observable
public final class ModelRegistry {

    public private(set) var status: [ModelDescriptor: ModelStatus] = [:]

    /// Standard-Ablage: `~/Library/Application Support/VoiceType/Models/`.
    public static var defaultRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceType", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    private let rootFolder: URL
    private let downloaders: [ModelDescriptor.Kind: ModelDownloading]
    private var inflight: [ModelDescriptor: Task<Void, Never>] = [:]

    public init(
        rootFolder: URL = ModelRegistry.defaultRoot,
        downloaders: [ModelDescriptor.Kind: ModelDownloading] = [:]
    ) {
        self.rootFolder = rootFolder
        self.downloaders = downloaders
        for d in ModelCatalog.whisperKitAll + ModelCatalog.mlxAll + ModelCatalog.parakeetAll {
            status[d] = .notInstalled
        }
    }

    /// Liefert den lokalen Modellordner.
    ///
    /// - Parameter even: wenn `true`, wird der Pfad auch dann zurückgegeben,
    ///   wenn das Modell noch nicht als installiert gilt (z. B. um vor
    ///   einem Download einen Zielordner zu erzeugen).
    public func folder(for descriptor: ModelDescriptor, even: Bool = false) -> URL? {
        let url = folderURL(for: descriptor)
        if even { return url }
        if case .installed = status[descriptor] { return url }
        return nil
    }

    public func refresh() async {
        for d in ModelCatalog.whisperKitAll + ModelCatalog.mlxAll + ModelCatalog.parakeetAll {
            status[d] = inspect(d)
        }
    }

    /// Idempotent: zweiter Aufruf für denselben Descriptor liefert den
    /// laufenden Download zurück, ohne neu zu starten.
    public func download(_ descriptor: ModelDescriptor) async {
        if let existing = inflight[descriptor] { return await existing.value }
        guard let downloader = downloaders[descriptor.kind] else {
            status[descriptor] = .failed(reason: "Kein Downloader registriert.")
            return
        }
        let folder = folderURL(for: descriptor)
        status[descriptor] = .installing(progress: 0)

        let task = Task { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)
            do {
                try await downloader.download(
                    descriptor: descriptor,
                    into: folder,
                    onProgress: { [weak self] p in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(descriptor, progress: p)
                        }
                    })
                self.status[descriptor] = self.inspect(descriptor)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: folder)
                self.status[descriptor] = .notInstalled
            } catch {
                self.status[descriptor] = .failed(reason: error.localizedDescription)
            }
            self.inflight[descriptor] = nil
        }
        inflight[descriptor] = task
        await task.value
    }

    public func cancelDownload(_ descriptor: ModelDescriptor) async {
        inflight[descriptor]?.cancel()
        await inflight[descriptor]?.value
    }

    public func delete(_ descriptor: ModelDescriptor) async throws {
        let folder = folderURL(for: descriptor)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        status[descriptor] = .notInstalled
    }

    // MARK: - intern

    private func updateProgress(_ d: ModelDescriptor, progress: Double) {
        if case .installing = status[d] {
            status[d] = .installing(progress: max(0, min(1, progress)))
        }
    }

    private func folderURL(for d: ModelDescriptor) -> URL {
        switch d.kind {
        case .whisperKit:
            // WhisperKit's interner Downloader benutzt HubApi-Konvention
            // und legt unter `<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>/`
            // ab — nicht direkt unter `<downloadBase>/<variant>/`.
            // Wir spiegeln genau diese Struktur, damit ein einmal
            // heruntergeladenes Bundle ohne Move/Symlink direkt
            // gefunden wird.
            return rootFolder
                .appendingPathComponent("whisperkit", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent("argmaxinc", isDirectory: true)
                .appendingPathComponent("whisperkit-coreml", isDirectory: true)
                .appendingPathComponent(d.id, isDirectory: true)
        case .mlx:
            // MLXLMCommon's `defaultHubApi` schreibt in
            // `~/Library/Caches/models/<repo>/`. Wir spiegeln genau
            // diesen Pfad, damit der `ParakeetDownloader` (= eigentlich
            // MLXDownloader) den HF-Snapshot direkt in `folder(for: d)`
            // ablegt — kein Move/Copy nötig.
            //
            // Konsequenz: MLX-Modelle liegen im Caches-Ordner statt in
            // Application Support (wie WhisperKit/Parakeet). Pragmatisch,
            // weil MLXLMCommon den Pfad fest verdrahtet hat und es ohne
            // direkten `Hub`-Import keine saubere Override-Möglichkeit
            // gibt.
            return FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("models", isDirectory: true)
                .appendingPathComponent(d.id, isDirectory: true)
        case .parakeet:
            // FluidAudio cached Parakeet-Bundles in seinem eigenen
            // Application-Support-Folder. Wir spiegeln genau diesen
            // Pfad, statt einen eigenen Folder zu nutzen — sonst
            // müssten wir nach jedem Download moven/kopieren.
            //
            // Wichtig: FluidAudio entfernt im Cache-Pfad den
            // `-coreml`-Suffix vom HF-Repo-Namen. Aus
            // „FluidInference/parakeet-tdt-0.6b-v3-coreml" wird
            // → „Models/parakeet-tdt-0.6b-v3".
            let last = d.id.components(separatedBy: "/").last ?? d.id
            let suffix = last.hasSuffix("-coreml")
                ? String(last.dropLast("-coreml".count))
                : last
            return FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FluidAudio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(suffix, isDirectory: true)
        }
    }

    private func inspect(_ d: ModelDescriptor) -> ModelStatus {
        let folder = folderURL(for: d)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return .notInstalled
        }
        let required: [String]
        switch d.kind {
        case .whisperKit:
            required = ["AudioEncoder.mlmodelc"]
        case .mlx:
            required = ["config.json"]
        case .parakeet:
            // FluidAudio's Cache enthält 4 .mlmodelc-Bundles
            // (Preprocessor, Encoder, Decoder, JointDecisionvX).
            // Encoder als Sentinel reicht — er wird mitten im
            // Download geschrieben, nicht zuerst.
            required = ["Encoder.mlmodelc"]
        }
        for name in required {
            let path = folder.appendingPathComponent(name).path
            if !FileManager.default.fileExists(atPath: path) {
                return .notInstalled
            }
        }
        return .installed(sizeOnDisk: folderSize(folder))
    }

    private func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey])
                .fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
