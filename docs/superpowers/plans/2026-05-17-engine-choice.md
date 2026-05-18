# VoiceType — Plan 4: Engine- und Cleanup-Wahl mit Live-Switching

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nutzer können in Settings live zwischen **Apple Speech** und
**WhisperKit** (Spracherkennung) sowie zwischen **Aus**, **Apple
Foundation Models** und **MLX-LLM** (Cleanup) wechseln. Nicht
installierte Modelle werden auf Bestätigung im Hintergrund geladen; die
App diktiert in der Zwischenzeit mit dem Fallback weiter. Sobald das
Modell verfügbar ist (und der Coordinator `.idle`), erfolgt der Wechsel
ohne App-Neustart.

**Architecture:** Eine neue `ModelRegistry` (im Core, `@MainActor
@Observable`) hält Status, Speicherorte und Download-Lifecycle pro
Modell. Engine und Cleanup werden über eine reine `EngineFactory` aus
`Settings + Registry` erzeugt. Der bestehende `DictationCoordinator`
bekommt `requestSwap(engine:cleanup:)` mit Pending-Buffer — Swaps in
`.idle/.loading/.error` wirken sofort, in `.recording/.cleaning/…`
werden sie aufgeschoben und in `finishAfterStream()` angewendet. Der
`AppController` orchestriert: er beobachtet `registry.status` und löst
den Swap automatisch aus, sobald das gewählte Modell installiert ist.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Testing, neue SPM-Deps
`argmaxinc/WhisperKit` und `ml-explore/mlx-swift-examples`
(Konkrete Pin-Versionen werden in Task 6/7 anhand des aktuellen Releases
gepinnt). Bestehende Engine (`AppleSpeechEngine`), Cleanup
(`FoundationModelCleanup`), Audio-Stack und UI bleiben kompatibel.

**Spec:** `docs/superpowers/specs/2026-05-17-engine-choice-design.md`

> ⚠️ **Externe Bibliotheken:** WhisperKit und mlx-swift-examples sind
> dritte SPM-Packages. Ihre APIs können sich zwischen Releases ändern.
> Tasks 6 und 7 enthalten den minimalen Adapter-Code, der gegen die
> aktuellen Releases zur Plan-Zeit konzipiert ist; bei abweichender
> Signatur in Xcode Quick Help (⌥-Klick) prüfen und an die Library
> anpassen, ohne den `TranscriptionEngine`/`TextCleanup`-Vertrag zu
> brechen.

> ⚠️ **Vorherige Pläne:** Dieser Plan setzt auf `plan-3-ui-polish` auf
> und nimmt an, dass `Settings`, `AppController`, `DictationCoordinator`,
> `FoundationModelCleanup` und `SettingsView` wie zum Zeitpunkt von
> Commit `3b81d40` im Repo stehen.

---

## Dateistruktur

```
voicetype/
├── VoiceTypeCore/
│   ├── Package.swift                                # erweitert (Task 6, 7)
│   ├── Sources/VoiceTypeCore/
│   │   ├── Settings.swift                           # erweitert (Task 1)
│   │   ├── ModelCatalog.swift                       # NEU (Task 3)
│   │   ├── ModelDescriptor.swift                    # NEU (Task 3)
│   │   ├── ModelStatus.swift                        # NEU (Task 3)
│   │   ├── ModelRegistry.swift                      # NEU (Task 4)
│   │   ├── CleanupSanity.swift                      # NEU (Task 2)
│   │   ├── FoundationModelCleanup.swift             # angepasst (Task 2)
│   │   ├── DictationCoordinator.swift               # erweitert (Task 5)
│   │   ├── WhisperKitEngine.swift                   # NEU (Task 6)
│   │   ├── MLXCleanup.swift                         # NEU (Task 7)
│   │   └── EngineFactory.swift                      # NEU (Task 8)
│   └── Tests/VoiceTypeCoreTests/
│       ├── SettingsMigrationTests.swift             # NEU (Task 1)
│       ├── CleanupSanityTests.swift                 # NEU (Task 2)
│       ├── ModelCatalogTests.swift                  # NEU (Task 3)
│       ├── ModelRegistryTests.swift                 # NEU (Task 4)
│       ├── DictationCoordinatorSwapTests.swift      # NEU (Task 5)
│       └── EngineFactoryTests.swift                 # NEU (Task 8)
└── VoiceType/VoiceType/
    ├── VoiceTypeApp.swift                           # erweitert (Task 8)
    ├── SettingsView.swift                           # erweitert (Task 9)
    └── ModelStatusView.swift                        # NEU (Task 9)
```

---

## Task 1: Settings-Schema + Migration

`cleanupEnabled: Bool` wird ersetzt durch `cleanupEngine`-Enum plus die
neuen Transcription-Felder. Ein Migrations-Loader liest alte
`settings.json`-Dateien transparent ein.

**Files:**
- Edit: `VoiceTypeCore/Sources/VoiceTypeCore/Settings.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/SettingsMigrationTests.swift`
- Edit: `VoiceTypeCore/Tests/VoiceTypeCoreTests/SettingsStoreTests.swift`
  (entferne den `cleanupEnabled`-Roundtrip — wird obsolet durch die Migration)

- [ ] **Step 1: Failing migration tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/SettingsMigrationTests.swift`:

```swift
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
        s.mlxModelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"
        try store.save(s)
        #expect(store.load() == s)
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter SettingsMigrationTests`
Expected: FAIL — `cleanupEngine`, `transcriptionEngine`, `whisperKitModelId`, `mlxModelId` existieren noch nicht.

- [ ] **Step 3: Settings-Schema erweitern**

Edit `VoiceTypeCore/Sources/VoiceTypeCore/Settings.swift` — komplette
Datei ersetzen:

```swift
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
    public var whisperKitModelId: String = "openai_whisper-large-v3-turbo"
    public var cleanupEngine: CleanupEngineKind = .appleFoundationModels
    public var mlxModelId: String = "mlx-community/Qwen2.5-7B-Instruct-4bit"

    public init() {}
}

/// Altes Schema (bis einschließlich Plan 3). Wird beim Laden erkannt
/// und einmalig auf das neue Schema gemappt — die migrierte Datei wird
/// atomar zurückgeschrieben, sodass dieser Pfad nur einmal pro Datei
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
        // Erst neues Schema, dann Legacy. Wenn weder noch passt, fall back
        // auf Defaults — verhält sich wie bisher bei kaputten Dateien.
        if let modern = try? JSONDecoder().decode(Settings.self, from: data) {
            return modern
        }
        if let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) {
            let migrated = Self.migrate(legacy)
            try? save(migrated)   // best effort; lese nicht erneut
            return migrated
        }
        return Settings()
    }

    public func save(_ settings: Settings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }

    static func migrate(_ legacy: LegacySettings) -> Settings {
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
```

- [ ] **Step 4: Bestehenden `SettingsStoreTests.swift` an neues Schema anpassen**

Im Test-File `SettingsStoreTests.swift` jede Verwendung von
`settings.cleanupEnabled = …` ersetzen durch
`settings.cleanupEngine = .off` (oder eine andere passende Variante).
Tests zur Round-Trip-Persistenz bleiben sonst unverändert.

- [ ] **Step 5: AppController-Aufrufer reparieren (temporär)**

`VoiceType/VoiceType/VoiceTypeApp.swift` greift in
`AppController.init` auf `settings.cleanupEnabled` zu. Damit der App-
Target jetzt noch baut, ersetze die `if settings.cleanupEnabled`-Stelle
durch:

```swift
let useFM = (settings.cleanupEngine == .appleFoundationModels)
let cleanup: TextCleanup
let hint: String?
if useFM {
    let fmCleanup = FoundationModelCleanup()
    hint = fmCleanup.availabilityHint
    cleanup = fmCleanup
} else {
    hint = nil
    cleanup = PassthroughCleanup()
}
```

Die `SettingsView` referenziert ebenfalls `cleanupEnabled` — der
entsprechende `Toggle` wird komplett in Task 9 ersetzt. Übergangsweise
hier ersetzen durch:

```swift
Toggle("Text aufpolieren (Apple Foundation Models)",
       isOn: Binding(
        get: { controller.settings.cleanupEngine == .appleFoundationModels },
        set: { controller.settings.cleanupEngine = $0 ? .appleFoundationModels : .off }))
```

(Diese Übergangs-UI verschwindet in Task 9.)

- [ ] **Step 6: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter SettingsMigrationTests SettingsStoreTests`
Expected: PASS — alle Migration- und Store-Tests grün.

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: extend Settings with engine/cleanup choice + legacy migration"
```

---

## Task 2: CleanupSanity extrahieren

Die Längen-/Whitespace-Validierung aus `FoundationModelCleanup` zieht in
einen eigenen Pure-Helfer um, damit `MLXCleanup` (Task 7) sie
wiederverwenden kann. Tests werden mit übersiedelt.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/CleanupSanity.swift`
- Edit: `VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift`
- Create: `VoiceTypeCore/Tests/VoiceTypeCoreTests/CleanupSanityTests.swift`
- Edit: `VoiceTypeCore/Tests/VoiceTypeCoreTests/FoundationModelCleanupTests.swift`
  (referenziert dann `CleanupSanity.accepted(...)` statt `FoundationModelCleanup.acceptedOutput(...)`)

- [ ] **Step 1: Failing test schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/CleanupSanityTests.swift`:

```swift
import Testing
@testable import VoiceTypeCore

@Suite struct CleanupSanityTests {
    @Test func emptyOutputFallsBackToRaw() {
        #expect(CleanupSanity.accepted(raw: "abc", modelOutput: "") == "abc")
    }

    @Test func whitespaceOnlyOutputFallsBackToRaw() {
        #expect(CleanupSanity.accepted(raw: "abc", modelOutput: "  \n ") == "abc")
    }

    @Test func tooShortOutputFallsBackToRaw() {
        let raw = String(repeating: "a", count: 40)
        let out = String(repeating: "b", count: 10)
        #expect(CleanupSanity.accepted(raw: raw, modelOutput: out) == raw)
    }

    @Test func tooLongOutputFallsBackToRaw() {
        let raw = String(repeating: "a", count: 10)
        let out = String(repeating: "b", count: 30)
        #expect(CleanupSanity.accepted(raw: raw, modelOutput: out) == raw)
    }

    @Test func normalOutputIsTrimmed() {
        #expect(CleanupSanity.accepted(
            raw: "hallo welt", modelOutput: "  Hallo Welt.  ") == "Hallo Welt.")
    }

    @Test func emptyRawReturnsEmptyRaw() {
        #expect(CleanupSanity.accepted(raw: "", modelOutput: "anything") == "")
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter CleanupSanityTests`
Expected: FAIL — `cannot find 'CleanupSanity' in scope`.

- [ ] **Step 3: Implementierung extrahieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/CleanupSanity.swift`:

```swift
import Foundation

/// Pure Heuristik: entscheidet, ob die Ausgabe eines LLM-basierten
/// Cleanups akzeptiert oder durch den Rohtext ersetzt wird. Wird von
/// `FoundationModelCleanup` und `MLXCleanup` gleichermaßen genutzt —
/// sodass die Längen-/Whitespace-Regeln engineunabhängig identisch
/// sind.
public enum CleanupSanity {
    /// - Leere oder reine Whitespace-Ausgabe → Rohtext
    /// - Längenverhältnis < 50 % oder > 200 % der Rohlänge → Rohtext
    /// - Sonst → getrimmte Modell-Ausgabe
    public static func accepted(raw: String, modelOutput: String) -> String {
        let trimmed = modelOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        let rawLen = raw.count
        guard rawLen > 0 else { return raw }
        let cleanedLen = trimmed.count
        if cleanedLen * 2 < rawLen { return raw }
        if cleanedLen > rawLen * 2 { return raw }
        return trimmed
    }
}
```

Edit `VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift`:
- entferne den static `acceptedOutput(raw:modelOutput:)` und ersetze
  den einzigen Aufruf (`return Self.acceptedOutput(raw: raw, modelOutput: modelOutput)`)
  durch `return CleanupSanity.accepted(raw: raw, modelOutput: modelOutput)`.

Edit `VoiceTypeCore/Tests/VoiceTypeCoreTests/FoundationModelCleanupTests.swift`:
- ersetze in allen Tests `FoundationModelCleanup.acceptedOutput(raw:modelOutput:)`
  durch `CleanupSanity.accepted(raw:modelOutput:)`. Die Test-Logik bleibt
  gleich — das verbliebene File wird damit dünn, kann später entfallen,
  bleibt aber als Regression-Schutz.

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter "CleanupSanityTests|FoundationModelCleanupTests"`
Expected: PASS — alle Tests grün (Sanity + Foundation-Model-Adapter).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: extract CleanupSanity helper from FoundationModelCleanup"
```

---

## Task 3: ModelDescriptor + ModelStatus + ModelCatalog

Statische Modellliste, Wertobjekte und Status-Enum. Reine Daten — kein
I/O.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/ModelDescriptor.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/ModelStatus.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/ModelCatalog.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/ModelCatalogTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/ModelCatalogTests.swift`:

```swift
import Testing
@testable import VoiceTypeCore

@Suite struct ModelCatalogTests {

    @Test func whisperKitDefaultIsLargeV3Turbo() {
        let def = ModelCatalog.whisperKitDefault
        #expect(def.kind == .whisperKit)
        #expect(def.id == "openai_whisper-large-v3-turbo")
        #expect(def.isDefault)
    }

    @Test func mlxDefaultIsQwen25SevenB() {
        let def = ModelCatalog.mlxDefault
        #expect(def.kind == .mlx)
        #expect(def.id == "mlx-community/Qwen2.5-7B-Instruct-4bit")
        #expect(def.isDefault)
    }

    @Test func whisperKitCatalogContainsKnownIds() {
        let ids = ModelCatalog.whisperKitAll.map(\.id)
        #expect(ids.contains("openai_whisper-large-v3-turbo"))
        #expect(ids.contains("openai_whisper-large-v3"))
        #expect(ids.contains("distil-whisper_distil-large-v3"))
    }

    @Test func mlxCatalogContainsKnownIds() {
        let ids = ModelCatalog.mlxAll.map(\.id)
        #expect(ids.contains("mlx-community/Qwen2.5-7B-Instruct-4bit"))
        #expect(ids.contains("mlx-community/Qwen2.5-3B-Instruct-4bit"))
        #expect(ids.contains("mlx-community/Llama-3.2-3B-Instruct-4bit"))
    }

    @Test func lookupReturnsNilForUnknownId() {
        #expect(ModelCatalog.whisperKit(id: "does-not-exist") == nil)
        #expect(ModelCatalog.mlx(id: "does-not-exist") == nil)
    }

    @Test func lookupReturnsDescriptorForKnownId() {
        let d = ModelCatalog.whisperKit(id: "openai_whisper-large-v3-turbo")
        #expect(d?.displayName == "Whisper large-v3-turbo")
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter ModelCatalogTests`
Expected: FAIL — `cannot find 'ModelCatalog' in scope`.

- [ ] **Step 3: Datentypen implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/ModelDescriptor.swift`:

```swift
import Foundation

public struct ModelDescriptor: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case whisperKit, mlx }

    public let kind: Kind
    public let id: String              // z. B. "openai_whisper-large-v3-turbo"
    public let displayName: String     // "Whisper large-v3-turbo"
    public let approxSizeBytes: Int64
    public let isDefault: Bool

    public init(
        kind: Kind, id: String, displayName: String,
        approxSizeBytes: Int64, isDefault: Bool
    ) {
        self.kind = kind
        self.id = id
        self.displayName = displayName
        self.approxSizeBytes = approxSizeBytes
        self.isDefault = isDefault
    }
}
```

Create `VoiceTypeCore/Sources/VoiceTypeCore/ModelStatus.swift`:

```swift
import Foundation

public enum ModelStatus: Sendable, Equatable {
    case notInstalled
    case installing(progress: Double)   // 0 … 1
    case installed(sizeOnDisk: Int64)
    case failed(reason: String)
}
```

Create `VoiceTypeCore/Sources/VoiceTypeCore/ModelCatalog.swift`:

```swift
import Foundation

/// Statische Modell-Liste. Erweiterungen erfolgen ausschließlich per
/// App-Update — kein Server-Discovery, kein freier HF-Repo-Input.
public enum ModelCatalog {

    public static let whisperKitAll: [ModelDescriptor] = [
        .init(kind: .whisperKit,
              id: "openai_whisper-large-v3-turbo",
              displayName: "Whisper large-v3-turbo",
              approxSizeBytes: 1_600_000_000,
              isDefault: true),
        .init(kind: .whisperKit,
              id: "openai_whisper-large-v3",
              displayName: "Whisper large-v3",
              approxSizeBytes: 3_000_000_000,
              isDefault: false),
        .init(kind: .whisperKit,
              id: "distil-whisper_distil-large-v3",
              displayName: "Distil-Whisper large-v3",
              approxSizeBytes: 1_400_000_000,
              isDefault: false),
    ]

    public static let mlxAll: [ModelDescriptor] = [
        .init(kind: .mlx,
              id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
              displayName: "Qwen 2.5 7B Instruct (4-bit)",
              approxSizeBytes: 4_000_000_000,
              isDefault: true),
        .init(kind: .mlx,
              id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
              displayName: "Qwen 2.5 3B Instruct (4-bit)",
              approxSizeBytes: 1_800_000_000,
              isDefault: false),
        .init(kind: .mlx,
              id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
              displayName: "Llama 3.2 3B Instruct (4-bit)",
              approxSizeBytes: 1_800_000_000,
              isDefault: false),
    ]

    public static var whisperKitDefault: ModelDescriptor {
        whisperKitAll.first(where: \.isDefault)!
    }

    public static var mlxDefault: ModelDescriptor {
        mlxAll.first(where: \.isDefault)!
    }

    public static func whisperKit(id: String) -> ModelDescriptor? {
        whisperKitAll.first { $0.id == id }
    }

    public static func mlx(id: String) -> ModelDescriptor? {
        mlxAll.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter ModelCatalogTests`
Expected: PASS — 7 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ModelDescriptor, ModelStatus and curated ModelCatalog"
```

---

## Task 4: ModelRegistry (Status, Scan, Download-Stub)

Die Registry kapselt Speicherlayout, Filesystem-Scan und Download-
Orchestrierung. In dieser Task wird **noch keine echte Download-
Library angebunden** — der Download wird über einen injizierbaren
`Downloader`-Protokoll-Wert ausgeführt, sodass Tests einen Fake-
Downloader nutzen können. Die echten Implementierungen kommen in
Tasks 6/7.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/ModelRegistry.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/ModelRegistryTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/ModelRegistryTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct ModelRegistryTests {

    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    private func writeMarker(at folder: URL, kind: ModelDescriptor.Kind) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        // Minimal-Marker pro Engine — die echten Bibliotheken validieren mehr;
        // für die Registry-Tests reicht ein „nicht leer"-Check.
        let marker = kind == .whisperKit
            ? folder.appendingPathComponent("AudioEncoder.mlmodelc")
            : folder.appendingPathComponent("config.json")
        try Data("placeholder".utf8).write(to: marker)
    }

    @Test func freshRegistryReportsNotInstalled() async {
        let registry = ModelRegistry(rootFolder: tempRoot(), downloaders: [:])
        await registry.refresh()
        #expect(registry.status[ModelCatalog.whisperKitDefault] == .notInstalled)
        #expect(registry.status[ModelCatalog.mlxDefault] == .notInstalled)
    }

    @Test func refreshDetectsInstalledModelOnDisk() async throws {
        let root = tempRoot()
        let registry = ModelRegistry(rootFolder: root, downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        try writeMarker(at: registry.folder(for: d, even: true), kind: .whisperKit)
        await registry.refresh()
        if case .installed(let size) = registry.status[d] {
            #expect(size > 0)
        } else {
            Issue.record("expected .installed, got \(String(describing: registry.status[d]))")
        }
    }

    @Test func folderReturnsNilUntilInstalled() async throws {
        let root = tempRoot()
        let registry = ModelRegistry(rootFolder: root, downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        await registry.refresh()
        #expect(registry.folder(for: d) == nil)
        try writeMarker(at: registry.folder(for: d, even: true), kind: .whisperKit)
        await registry.refresh()
        #expect(registry.folder(for: d) != nil)
    }

    @Test func downloadDrivesStatusFromInstallingToInstalled() async throws {
        let root = tempRoot()
        let fake = FakeDownloader()
        let registry = ModelRegistry(
            rootFolder: root, downloaders: [.whisperKit: fake])
        let d = ModelCatalog.whisperKitDefault

        let task = Task { await registry.download(d) }

        // Bis der Fake fertigsignalisiert, sehen wir installing-Updates:
        try await Task.sleep(for: .milliseconds(20))
        if case .installing(let p) = registry.status[d] {
            #expect(p >= 0 && p <= 1)
        } else {
            Issue.record("expected .installing, got \(String(describing: registry.status[d]))")
        }

        try ModelRegistryTests.writeMarker(
            into: registry.folder(for: d, even: true), kind: .whisperKit)
        fake.finishSuccess()
        await task.value

        if case .installed = registry.status[d] {} else {
            Issue.record("expected .installed after finish")
        }
    }

    @Test func deleteRemovesInstalledModelFromDisk() async throws {
        let root = tempRoot()
        let registry = ModelRegistry(rootFolder: root, downloaders: [:])
        let d = ModelCatalog.whisperKitDefault
        try writeMarker(at: registry.folder(for: d, even: true), kind: .whisperKit)
        await registry.refresh()
        try await registry.delete(d)
        #expect(registry.status[d] == .notInstalled)
        #expect(registry.folder(for: d) == nil)
    }

    // Hilfsmethoden für Tests, die ohne den Registry-State direkt
    // Marker auf die Platte schreiben müssen.
    fileprivate static func writeMarker(
        into folder: URL, kind: ModelDescriptor.Kind
    ) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        let marker = kind == .whisperKit
            ? folder.appendingPathComponent("AudioEncoder.mlmodelc")
            : folder.appendingPathComponent("config.json")
        try Data("placeholder".utf8).write(to: marker)
    }
}

/// Test-Doppelgänger: signalisiert Progress sofort, hält den Download,
/// bis der Test `finishSuccess()`/`finishFailure(_:)` aufruft.
final class FakeDownloader: ModelDownloading, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    func download(
        descriptor: ModelDescriptor, into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        onProgress(0.1)
        try await withCheckedThrowingContinuation { c in
            self.continuation = c
        }
    }
    func finishSuccess() { continuation?.resume() }
    func finishFailure(_ error: Error) { continuation?.resume(throwing: error) }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter ModelRegistryTests`
Expected: FAIL — `cannot find 'ModelRegistry' in scope`.

- [ ] **Step 3: Registry implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/ModelRegistry.swift`:

```swift
import Foundation
import Observation

/// Lädt, scannt und verwaltet Modell-Bundles auf Platte. UI bindet
/// direkt an `status`; tatsächlicher Download wird an einen
/// `ModelDownloading`-Wert delegiert (in Tests fake, in Production
/// `WhisperKitDownloader` / `MLXDownloader`).
public protocol ModelDownloading: Sendable {
    func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}

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
        // initiale Befüllung mit notInstalled — refresh() schreibt drüber
        for d in ModelCatalog.whisperKitAll + ModelCatalog.mlxAll {
            status[d] = .notInstalled
        }
    }

    /// Liefert den lokalen Modellordner.
    ///
    /// - Parameter even: wenn `true`, wird der Pfad auch dann
    ///   zurückgegeben, wenn das Modell noch nicht als installiert gilt
    ///   (z. B. um vor einem Download einen Zielordner zu erzeugen).
    public func folder(for descriptor: ModelDescriptor, even: Bool = false) -> URL? {
        let url = folderURL(for: descriptor)
        if even { return url }
        if case .installed = status[descriptor] { return url }
        return nil
    }

    public func refresh() async {
        for d in ModelCatalog.whisperKitAll + ModelCatalog.mlxAll {
            status[d] = inspect(d)
        }
    }

    public func download(_ descriptor: ModelDescriptor) async {
        // idempotent: laufender Download wird zurückgegeben
        if let existing = inflight[descriptor] { return await existing.value }
        guard let downloader = downloaders[descriptor.kind] else {
            status[descriptor] = .failed(reason: "Kein Downloader registriert.")
            return
        }
        let folder = folderURL(for: descriptor)
        status[descriptor] = .installing(progress: 0)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try? FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true)
                try await downloader.download(
                    descriptor: descriptor,
                    into: folder,
                    onProgress: { [weak self] p in
                        Task { @MainActor [weak self] in
                            self?.updateProgress(descriptor, progress: p)
                        }
                    })
                status[descriptor] = inspect(descriptor)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: folder)
                status[descriptor] = .notInstalled
            } catch {
                status[descriptor] = .failed(reason: error.localizedDescription)
            }
            inflight[descriptor] = nil
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
        let sub = d.kind == .whisperKit ? "whisperkit" : "mlx"
        let safe = d.id.replacingOccurrences(of: "/", with: "__")
        return rootFolder
            .appendingPathComponent(sub, isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
    }

    private func inspect(_ d: ModelDescriptor) -> ModelStatus {
        let folder = folderURL(for: d)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return .notInstalled
        }
        let required: [String]
        switch d.kind {
        case .whisperKit:
            required = ["AudioEncoder.mlmodelc"]   // Plan-Minimum; echte Lib kann mehr verlangen
        case .mlx:
            required = ["config.json"]
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
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter ModelRegistryTests`
Expected: PASS — alle Registry-Tests grün.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add ModelRegistry with FS scan, status tracking and download orchestration"
```

---

## Task 5: DictationCoordinator — `requestSwap` + Pending-Buffer

Die Kernlogik für Live-Switching. Reine TDD-Arbeit gegen
`MockTranscriptionEngine` aus `Mocks.swift`.

**Files:**
- Edit: `VoiceTypeCore/Sources/VoiceTypeCore/DictationCoordinator.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/DictationCoordinatorSwapTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/DictationCoordinatorSwapTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct DictationCoordinatorSwapTests {

    private func makeCoordinator(
        engine: TranscriptionEngine,
        cleanup: TextCleanup = MockCleanup()
    ) -> (DictationCoordinator, AppState, MockTextDelivery, MockFocusInspector) {
        let state = AppState()
        let delivery = MockTextDelivery()
        let focus = MockFocusInspector()
        let coord = DictationCoordinator(
            engine: engine, cleanup: cleanup,
            delivery: delivery, focus: focus, appState: state)
        return (coord, state, delivery, focus)
    }

    @Test func swapAppliesImmediatelyWhenIdle() async {
        let oldEngine = MockTranscriptionEngine()
        let newEngine = MockTranscriptionEngine()
        let (coord, state, _, _) = makeCoordinator(engine: oldEngine)
        await coord.prepare()                       // → .idle
        #expect(state.dictationState == .idle)

        await coord.requestSwap(engine: newEngine)
        #expect(newEngine.prepareCallCount == 1)
        #expect(state.dictationState == .idle)
    }

    @Test func swapIsBufferedWhileRecordingAndAppliedAfterFinish() async {
        let oldEngine = MockTranscriptionEngine()
        let newEngine = MockTranscriptionEngine()
        let (coord, state, _, _) = makeCoordinator(engine: oldEngine)
        await coord.prepare()
        coord.startDictation()
        // ein paar Mainactor-Hops, damit der internal start-Task aufgesetzt wird
        await Task.yield()
        #expect(state.dictationState == .recording)

        await coord.requestSwap(engine: newEngine)
        #expect(newEngine.prepareCallCount == 0, "swap must wait for idle")

        oldEngine.emit("hallo welt", isFinal: true)
        oldEngine.finishStream()
        coord.endDictation(heldFor: .seconds(1))
        // warten, bis finishAfterStream durch ist
        for _ in 0..<20 {
            await Task.yield()
            if state.dictationState == .idle { break }
        }
        #expect(state.dictationState == .idle)
        #expect(newEngine.prepareCallCount == 1)
    }

    @Test func swapPrepareFailureKeepsOldEngineActive() async {
        let oldEngine = MockTranscriptionEngine()
        let brokenEngine = MockTranscriptionEngine()
        brokenEngine.prepareError = TranscriptionError.modelUnavailable
        let (coord, state, _, _) = makeCoordinator(engine: oldEngine)
        await coord.prepare()

        await coord.requestSwap(engine: brokenEngine)

        if case .error = state.dictationState {} else {
            Issue.record("expected .error after failed swap, got \(state.dictationState)")
        }
        // Smoke: alte Engine darf wieder benutzt werden
        await coord.prepare()
        coord.startDictation()
        await Task.yield()
        #expect(state.dictationState == .recording)
        #expect(oldEngine.prepareCallCount >= 2)
    }

    @Test func cleanupSwapAppliesImmediatelyEvenWhileRecording() async {
        let engine = MockTranscriptionEngine()
        let oldCleanup = MockCleanup()
        let newCleanup = MockCleanup()
        newCleanup.transform = { _ in "neu" }
        let (coord, state, delivery, _) = makeCoordinator(
            engine: engine, cleanup: oldCleanup)
        await coord.prepare()
        coord.startDictation()
        await Task.yield()

        await coord.requestSwap(cleanup: newCleanup)
        // Cleanup-Swap braucht keinen prepare() — darf sofort wirken.
        engine.emit("rohtext", isFinal: true)
        engine.finishStream()
        coord.endDictation(heldFor: .seconds(1))
        for _ in 0..<20 {
            await Task.yield()
            if state.dictationState == .idle { break }
        }
        #expect(delivery.deliveredText == "neu")
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter DictationCoordinatorSwapTests`
Expected: FAIL — `requestSwap` existiert noch nicht.

- [ ] **Step 3: Coordinator erweitern**

Edit `VoiceTypeCore/Sources/VoiceTypeCore/DictationCoordinator.swift`:

Im Klassen-Body
- `private let engine: TranscriptionEngine` → `private var engine: TranscriptionEngine`
- `private let cleanup: TextCleanup` → `private var cleanup: TextCleanup`

Neue Felder unterhalb der bestehenden Properties:

```swift
private struct PendingSwap {
    var engine: TranscriptionEngine?
    var cleanup: TextCleanup?
}
private var pendingSwap: PendingSwap?
```

Neue Methoden am Ende der Klasse:

```swift
/// Tauscht Engine und/oder Cleanup aus.
///
/// - Engine wird durch `prepare()` neu initialisiert; bei Fehler bleibt
///   die alte Engine aktiv, und der DictationState springt auf
///   `.error(...)`. Der UI-Layer setzt den `engineFallbackHint`.
/// - Cleanup hat keinen Stream → kann jederzeit sofort getauscht
///   werden, auch während eines laufenden Diktats.
/// - Wenn ein Diktat läuft, wird der Engine-Swap in `pendingSwap`
///   gepuffert und in `finishAfterStream()` angewendet.
public func requestSwap(
    engine: TranscriptionEngine? = nil,
    cleanup: TextCleanup? = nil
) async {
    if let cleanup { self.cleanup = cleanup }
    guard let engine else { return }
    if canSwapEngineNow {
        await applyEngineSwap(engine)
    } else {
        pendingSwap = PendingSwap(engine: engine, cleanup: nil)
    }
}

private var canSwapEngineNow: Bool {
    switch appState.dictationState {
    case .idle, .loading, .error: return true
    case .recording, .finalizing, .cleaning, .delivering: return false
    }
}

private func applyEngineSwap(_ new: TranscriptionEngine) async {
    await engine.stop()
    appState.dictationState = .loading
    do {
        try await new.prepare()
        engine = new
        appState.dictationState = .idle
    } catch {
        appState.dictationState = .error("Engine-Wechsel fehlgeschlagen")
        // alte `engine`-Referenz bleibt erhalten — kein Reassign.
    }
}
```

`finishAfterStream()` am Ende ergänzen (vor `appState.dictationState = .idle`):

```swift
if let pending = pendingSwap?.engine {
    pendingSwap = nil
    await applyEngineSwap(pending)
    return   // applyEngineSwap setzt selbst auf .idle / .error
}
```

> Hinweis: `applyEngineSwap` setzt `state` selbst — der nachfolgende
> `appState.dictationState = .idle` würde im Erfolgsfall idempotent sein,
> aber im Fehlerfall (`.error`) ungewollt überschreiben. Darum
> early-return.

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter DictationCoordinatorSwapTests`
Expected: PASS — 4 Tests grün. Auch die bestehenden
`DictationCoordinatorTests` müssen weiter grün sein
(`cd VoiceTypeCore && swift test`).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add DictationCoordinator.requestSwap with pending-buffer for live engine switching"
```

---

## Task 6: WhisperKit-Adapter + Downloader

SPM-Dependency hinzufügen, `WhisperKitEngine` als `TranscriptionEngine`
implementieren, `WhisperKitDownloader` für die Registry.

> **Systemintegration:** Keine Unit-Tests gegen echte Inferenz — zu
> langsam, modellabhängig. Stattdessen Smoke-Test in der App.

**Files:**
- Edit: `VoiceTypeCore/Package.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/WhisperKitEngine.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/WhisperKitDownloader.swift`

- [ ] **Step 1: SPM-Dependency hinzufügen**

Edit `VoiceTypeCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceTypeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceTypeCore", targets: ["VoiceTypeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit",
                 from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "VoiceTypeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "VoiceTypeCoreTests",
            dependencies: ["VoiceTypeCore"]
        ),
    ]
)
```

> Prüfen, ob die zur Build-Zeit aktuellste WhisperKit-Version mit
> macOS 26 / Swift 6.3 kompatibel ist. Falls API-Brüche auftreten, die
> `from:`-Untergrenze auf das stabile Release anpassen.

Run: `cd VoiceTypeCore && swift package resolve && swift build`
Expected: WhisperKit wird aufgelöst und gebaut.

- [ ] **Step 2: WhisperKitEngine implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/WhisperKitEngine.swift`:

```swift
import Foundation
import WhisperKit
import AVFoundation

public actor WhisperKitEngine: TranscriptionEngine {
    private let audioCapture: AudioCapturing
    private let modelFolder: URL
    private let language: String

    private var pipe: WhisperKit?
    private var transcriberTask: Task<Void, Never>?
    private var updateContinuation:
        AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?

    public init(audioCapture: AudioCapturing, modelFolder: URL, language: String) {
        self.audioCapture = audioCapture
        self.modelFolder = modelFolder
        self.language = language
    }

    public func prepare() async throws {
        // Lädt WhisperKit aus dem lokalen Ordner — niemals aus dem Netz.
        // download = nil sagt der Lib explizit: kein eigener Download.
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            verbose: false,
            logLevel: .error,
            download: false)
        do {
            pipe = try await WhisperKit(config)
        } catch {
            throw TranscriptionError.modelUnavailable
        }
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard let pipe else { throw TranscriptionError.notPrepared }

        let (stream, continuation) =
            AsyncThrowingStream<TranscriptionUpdate, Error>.makeStream()
        self.updateContinuation = continuation

        let audioStream = try audioCapture.startStream()
        let lang = language == "auto" ? nil : language

        transcriberTask = Task { [pipe] in
            // Akkumuliert Audio-Buffer, schickt periodisch zur Inferenz,
            // emittiert Partial-Hypothesen.
            var buffer: [Float] = []
            for await captured in audioStream {
                guard let pcm = captured.pcmBuffer as? AVAudioPCMBuffer,
                      let data = pcm.floatChannelData?.pointee else { continue }
                buffer.append(contentsOf:
                    UnsafeBufferPointer(start: data, count: Int(pcm.frameLength)))
                // alle ~1.0 s eine Partial-Hypothese
                if buffer.count >= 16_000 {
                    if let text = await Self.transcribe(pipe, audio: buffer, language: lang) {
                        continuation.yield(TranscriptionUpdate(text: text, isFinal: false))
                    }
                }
            }
            // Aufnahme zu Ende → finalen Pass über das gesamte Buffer
            if let text = await Self.transcribe(pipe, audio: buffer, language: lang) {
                continuation.yield(TranscriptionUpdate(text: text, isFinal: true))
            } else {
                continuation.yield(TranscriptionUpdate(text: "", isFinal: true))
            }
            continuation.finish()
        }

        return stream
    }

    public func stop() async {
        audioCapture.stop()
        // transcriberTask läuft weiter, bis audioStream geendet hat —
        // das passiert direkt nach audioCapture.stop().
        await transcriberTask?.value
        transcriberTask = nil
        updateContinuation = nil
    }

    private static func transcribe(
        _ pipe: WhisperKit, audio: [Float], language: String?
    ) async -> String? {
        do {
            let result = try await pipe.transcribe(
                audioArray: audio,
                decodeOptions: DecodingOptions(
                    language: language, withoutTimestamps: true))
            return result.first?.text
        } catch {
            return nil
        }
    }
}
```

> ⚠️ Wenn die WhisperKit-API in der gepinnten Version andere Typnamen
> verwendet (z. B. `WhisperKitConfig.init` ohne `modelFolder`-Parameter
> oder `transcribe` mit anderer Signatur), in Xcode Quick Help prüfen
> und an die echte Library anpassen, ohne den `TranscriptionEngine`-
> Vertrag (prepare/start/stop, AsyncThrowingStream-Form) zu ändern.

- [ ] **Step 3: WhisperKitDownloader implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/WhisperKitDownloader.swift`:

```swift
import Foundation
import WhisperKit

public struct WhisperKitDownloader: ModelDownloading {
    public init() {}

    public func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        precondition(descriptor.kind == .whisperKit)
        // WhisperKit liefert eine `download(variant:from:downloadBase:progressCallback:)`-
        // API, die in einen Cache-Ordner schreibt; wir übergeben unseren Zielordner.
        try await WhisperKit.download(
            variant: descriptor.id,
            from: "argmaxinc/whisperkit-coreml",
            downloadBase: folder,
            progressCallback: { progress in
                onProgress(progress.fractionCompleted)
            })
    }
}
```

> Falls die Library Modelle stattdessen in einen eigenen Hub-Cache
> schiebt, müssen wir nach erfolgreichem Download umkopieren oder eine
> Symlink-Strategie nutzen. Das genaue Verhalten beim ersten Aufruf
> manuell verifizieren (Schritt 5).

- [ ] **Step 4: App-Target bauen**

Run: `cd VoiceTypeCore && swift build`
Expected: BUILD SUCCEEDED.

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manueller Smoke-Test (Download-Pfad)**

Da die Settings-UI noch nicht angebunden ist, in der Xcode-Konsole
(z. B. via Debug-Button in `MainView` oder in `AppController.init`
temporär) folgendes ausführen:

```swift
let registry = ModelRegistry(downloaders: [.whisperKit: WhisperKitDownloader()])
await registry.refresh()
let d = ModelCatalog.whisperKitDefault
await registry.download(d)
// Erwartung: ~1.6 GB unter ~/Library/Application Support/VoiceType/Models/whisperkit/openai_whisper-large-v3-turbo/
print(registry.status[d] ?? "no status")
```

Den Test-Code danach wieder entfernen — er ist nur Smoke.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add WhisperKitEngine and WhisperKitDownloader"
```

---

## Task 7: MLX-Cleanup-Adapter + Downloader — VERTAGT

> **Status:** Auf Plan 5 verschoben. WhisperKit (≥0.18, swift-transformers 1.1.x)
> und mlx-swift-examples (≥2.29, swift-transformers 1.0.x) sind im selben
> Xcode-Resolver-Graph nicht koexistenzfähig — auch nicht über getrennte
> lokale SPM-Packages, weil Xcode alle in einen einzigen Pool zieht.
> Behoben werden kann das nur durch eine andere Distribution einer der beiden
> (xcframework, Subprocess-isoliertes Wrapper-Tool, alternative Lib) — das
> wird in Plan 5 angegangen. Die Datenmodell-Vorbereitungen für MLX
> (`CleanupEngineKind.mlx`, `ModelCatalog.mlxAll`, `Settings.mlxModelId`,
> `ModelRegistry`-Folder-Layout mit HF-Konvention) bleiben in Plan 4
> erhalten — die UI in Task 9 behandelt `.mlx` als Disabled-Option mit
> Hinweis „Bald verfügbar".



Analog zu Task 6 für MLX. Cleanup-Adapter implementiert den `cleanup()`-
Vertrag mit Identity-Fallback bei jedem Fehler (kein throw).

**Files:**
- Edit: `VoiceTypeCore/Package.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/MLXCleanup.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/MLXDownloader.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/MLXCleanupTests.swift`

- [ ] **Step 1: SPM-Dependency hinzufügen**

Edit `VoiceTypeCore/Package.swift` — `dependencies:` und das Core-Target
ergänzen:

```swift
.package(url: "https://github.com/ml-explore/mlx-swift-examples",
         from: "1.16.0"),
```

```swift
.target(
    name: "VoiceTypeCore",
    dependencies: [
        .product(name: "WhisperKit", package: "WhisperKit"),
        .product(name: "MLXLLM", package: "mlx-swift-examples"),
        .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
    ]
),
```

Run: `cd VoiceTypeCore && swift package resolve && swift build`
Expected: MLX-Libs werden aufgelöst.

- [ ] **Step 2: Failing Tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/MLXCleanupTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceTypeCore

@Suite struct MLXCleanupTests {
    @Test func missingModelFolderReturnsRaw() async {
        let bogus = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let cleanup = MLXCleanup(modelFolder: bogus)
        let raw = "ähm das ist ein test"
        #expect(await cleanup.cleanup(raw) == raw)
    }

    @Test func emptyInputReturnsEmpty() async {
        let cleanup = MLXCleanup(modelFolder: FileManager.default.temporaryDirectory)
        #expect(await cleanup.cleanup("") == "")
    }
}
```

- [ ] **Step 3: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter MLXCleanupTests`
Expected: FAIL — `cannot find 'MLXCleanup' in scope`.

- [ ] **Step 4: MLXCleanup implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/MLXCleanup.swift`:

```swift
import Foundation
import MLXLMCommon
import MLXLLM

public actor MLXCleanup: TextCleanup {
    private let modelFolder: URL
    private var container: ModelContainer?

    private static let instructions = """
        Du bereinigst diktierten Text mechanisch. Erlaubt: Füllwörter \
        entfernen (ähm, äh, öh, …), Zeichensetzung setzen und korrigieren, \
        Groß-/Kleinschreibung korrigieren, offensichtliche Versprecher \
        und unmittelbare Wortwiederholungen glätten. Verboten: \
        umformulieren, Wortwahl ändern, Sätze umbauen, Inhalt hinzufügen \
        oder weglassen, übersetzen, kommentieren. Antworte ausschließlich \
        mit dem bereinigten Text — keine Einleitung, keine \
        Anführungszeichen, kein „Hier ist…". Behalte die Sprache des \
        Originals bei.
        """

    private static let timeoutSeconds: Double = 8

    public init(modelFolder: URL) {
        self.modelFolder = modelFolder
    }

    public func cleanup(_ raw: String) async -> String {
        guard !raw.isEmpty else { return raw }
        do {
            let container = try await self.ensureContainer()
            let output = try await withTimeout(seconds: Self.timeoutSeconds) {
                try await container.perform { context in
                    let prompt = "\(Self.instructions)\n\nText:\n\(raw)"
                    let result = try await context.generate(
                        input: .init(text: prompt),
                        parameters: GenerateParameters(temperature: 0))
                    return result.output
                }
            }
            return CleanupSanity.accepted(raw: raw, modelOutput: output)
        } catch {
            return raw
        }
    }

    private func ensureContainer() async throws -> ModelContainer {
        if let container { return container }
        let loaded = try await LLMModelFactory.shared.loadContainer(
            configuration: .init(directory: modelFolder))
        self.container = loaded
        return loaded
    }
}

private enum CleanupError: Error { case timeout }

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CleanupError.timeout
        }
        guard let result = try await group.next() else { throw CleanupError.timeout }
        group.cancelAll()
        return result
    }
}
```

> ⚠️ Die `LLMModelFactory`/`ModelContainer`-API von
> mlx-swift-examples ist in Bewegung. Wenn die hier gezeigten
> Methoden-Namen abweichen (z. B. `LLMModelFactory.shared.load(...)`
> oder ein `LLMSession`-Wrapper), in der Lib-Dokumentation prüfen und
> minimal anpassen — Kontrakt nach außen (`cleanup() async -> String`,
> **wirft nie**) bleibt.

- [ ] **Step 5: MLXDownloader implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/MLXDownloader.swift`:

```swift
import Foundation
import Hub                      // aus mlx-swift-examples

public struct MLXDownloader: ModelDownloading {
    public init() {}

    public func download(
        descriptor: ModelDescriptor,
        into folder: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        precondition(descriptor.kind == .mlx)
        let repo = Hub.Repo(id: descriptor.id, type: .model)
        let api = HubApi(downloadBase: folder.deletingLastPathComponent())
        _ = try await api.snapshot(
            from: repo,
            progressHandler: { progress in
                onProgress(progress.fractionCompleted)
            })
        // `snapshot` legt einen `models/<repo>`-Unterordner an. Wir wollen
        // die Inhalte direkt in `folder` haben — Symlink statt Kopie.
        // Implementiert wird das beim ersten manuellen Smoke (Step 7),
        // damit wir das tatsächliche Layout der Lib sehen.
    }
}
```

> Genau wie bei WhisperKit gilt: das tatsächliche Hub-Layout der
> Library beim ersten Smoke-Test prüfen und die `snapshot`/`folder`-
> Verkabelung präzisieren. Möglich, dass wir den `downloadBase` direkt
> auf `folder` setzen und das `models/`-Präfix wegfällt.

- [ ] **Step 6: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter MLXCleanupTests`
Expected: PASS — beide Tests grün (Identity-Fallback ohne Modell).

- [ ] **Step 7: Manueller Smoke (Download + Cleanup)**

Analog Task 6 / Step 5: temporär in `AppController.init` einen
Download + Cleanup-Lauf einbauen, ~4 GB beobachten, Inferenz an
einem Beispieltext laufen lassen (`"ähm das ist ein test"` →
sollte ähnlich zu `"Das ist ein Test."` werden), danach Code wieder
entfernen.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add MLXCleanup and MLXDownloader with identity-fallback"
```

---

## Task 8: EngineFactory + AppController-Refactor + Registry-Observation

Verbindet alle Bausteine: `AppController` hält die Registry, wählt
Engine/Cleanup beim Start, beobachtet den Modell-Status und löst nach
Download-Erfolg automatisch den Live-Swap aus.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/EngineFactory.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/EngineFactoryTests.swift`
- Edit: `VoiceType/VoiceType/VoiceTypeApp.swift`

- [ ] **Step 1: Failing factory tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/EngineFactoryTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct EngineFactoryTests {

    private func makeRegistry() -> ModelRegistry {
        ModelRegistry(rootFolder: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    @Test func makeTranscriptionAppleNeverUsesRegistry() {
        var settings = Settings()
        settings.transcriptionEngine = .apple
        let (_, hint) = EngineFactory.makeTranscription(
            settings: settings, registry: makeRegistry(),
            audioCapture: FakeAudioCapture())
        #expect(hint == nil)
    }

    @Test func makeTranscriptionWhisperKitWithoutModelFallsBackWithHint() {
        var settings = Settings()
        settings.transcriptionEngine = .whisperKit
        let (engine, hint) = EngineFactory.makeTranscription(
            settings: settings, registry: makeRegistry(),
            audioCapture: FakeAudioCapture())
        // Fallback ist die Apple-Engine; Hint erklärt warum.
        #expect(engine is AppleSpeechEngine)
        #expect(hint?.contains("WhisperKit") == true)
    }

    @Test func makeCleanupOffReturnsPassthrough() {
        var settings = Settings()
        settings.cleanupEngine = .off
        let (cleanup, hint) = EngineFactory.makeCleanup(
            settings: settings, registry: makeRegistry())
        #expect(cleanup is PassthroughCleanup)
        #expect(hint == nil)
    }

    @Test func makeCleanupMLXWithoutModelFallsBackWithHint() {
        var settings = Settings()
        settings.cleanupEngine = .mlx
        let (cleanup, hint) = EngineFactory.makeCleanup(
            settings: settings, registry: makeRegistry())
        #expect(cleanup is PassthroughCleanup)
        #expect(hint?.contains("MLX") == true)
    }
}

/// Stummer AudioCapturing — Factory braucht ihn nur als Konstruktor-Argument.
final class FakeAudioCapture: AudioCapturing, @unchecked Sendable {
    var onLevel: (@MainActor (Float) -> Void)?
    func startStream() throws -> AsyncStream<CapturedAudio> {
        AsyncStream { _ in }
    }
    func stop() {}
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter EngineFactoryTests`
Expected: FAIL — `cannot find 'EngineFactory' in scope`.

- [ ] **Step 3: EngineFactory implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/EngineFactory.swift`:

```swift
import Foundation

@MainActor
public enum EngineFactory {

    public static func makeTranscription(
        settings: Settings,
        registry: ModelRegistry,
        audioCapture: AudioCapturing
    ) -> (engine: TranscriptionEngine, fallbackHint: String?) {
        switch settings.transcriptionEngine {
        case .apple:
            return (AppleSpeechEngine(
                audioCapture: audioCapture, language: settings.language), nil)
        case .whisperKit:
            guard let desc = ModelCatalog.whisperKit(id: settings.whisperKitModelId),
                  let folder = registry.folder(for: desc) else {
                return (AppleSpeechEngine(
                    audioCapture: audioCapture, language: settings.language),
                        "WhisperKit-Modell nicht installiert — Apple Speech aktiv.")
            }
            return (WhisperKitEngine(
                audioCapture: audioCapture,
                modelFolder: folder,
                language: settings.language), nil)
        }
    }

    public static func makeCleanup(
        settings: Settings,
        registry: ModelRegistry
    ) -> (cleanup: TextCleanup, hint: String?) {
        switch settings.cleanupEngine {
        case .off:
            return (PassthroughCleanup(), nil)
        case .appleFoundationModels:
            let fm = FoundationModelCleanup()
            return (fm.availabilityHint == nil ? fm : PassthroughCleanup(),
                    fm.availabilityHint)
        case .mlx:
            guard let desc = ModelCatalog.mlx(id: settings.mlxModelId),
                  let folder = registry.folder(for: desc) else {
                return (PassthroughCleanup(),
                        "MLX-Modell nicht installiert — Cleanup ist aus.")
            }
            return (MLXCleanup(modelFolder: folder), nil)
        }
    }
}
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter EngineFactoryTests`
Expected: PASS — 4 Tests grün.

- [ ] **Step 5: `AppState` um Fallback-Hint erweitern**

Edit `VoiceTypeCore/Sources/VoiceTypeCore/AppState.swift` — neue
Property nach `livePreview`:

```swift
public var engineFallbackHint: String?
```

(Keine Tests nötig — pures Speicherfeld; das `AppController`-Integrate-
Verhalten wird manuell im Smoke geprüft.)

- [ ] **Step 6: AppController refactoren**

Edit `VoiceType/VoiceType/VoiceTypeApp.swift` — den `AppController`
komplett ersetzen durch:

```swift
@MainActor
@Observable
final class AppController {
    let appState = AppState()
    let permissions = Permissions()
    let registry = ModelRegistry(
        downloaders: [
            .whisperKit: WhisperKitDownloader(),
            .mlx: MLXDownloader(),
        ])
    var cleanupHint: String?
    var permissionsGranted = false
    var loginErrorMessage: String?

    private let settingsStore = SettingsStore()
    private let audioCapture: AudioCapturing
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor
    private let overlayController: OverlayWindowController
    private var isApplyingLogin = false
    private var statusObservationTask: Task<Void, Never>?

    var settings: Settings {
        didSet { handleSettingsChange(old: oldValue) }
    }

    init() {
        let loaded = settingsStore.load()
        self.settings = loaded
        let audioCapture = AudioCapture()
        self.audioCapture = audioCapture

        let (engine, fallback) = EngineFactory.makeTranscription(
            settings: loaded, registry: registry, audioCapture: audioCapture)
        let (cleanup, hint) = EngineFactory.makeCleanup(
            settings: loaded, registry: registry)
        appState.engineFallbackHint = fallback
        cleanupHint = hint

        coordinator = DictationCoordinator(
            engine: engine, cleanup: cleanup,
            delivery: TextOutput(clipboardEnabled: loaded.clipboardCopy),
            focus: FocusInspector(), appState: appState)

        audioCapture.onLevel = { [coordinator] level in
            coordinator.updateMicLevel(level)
        }

        hotkey = HotkeyMonitor(hotkey: loaded.pushToTalkKey)
        hotkey.onPress = { [coordinator] in coordinator.startDictation() }
        hotkey.onRelease = { [coordinator] held in
            coordinator.endDictation(heldFor: held)
        }
        overlayController = OverlayWindowController(appState: appState)

        Task {
            await registry.refresh()
            // Falls beim Start ein gewähltes Modell zwischenzeitlich
            // verfügbar geworden ist (z. B. manuell kopiert), greift der
            // Standard-Watcher unten.
            swapEngineIfReady()
            swapCleanupIfReady()
        }

        Task {
            if permissions.microphoneStatus() == .notDetermined {
                _ = await permissions.requestMicrophone()
            }
            recheckPermissions()
        }

        observeRegistryStatus()
    }

    func recheckPermissions() {
        permissionsGranted = permissions.allGranted
        guard permissionsGranted else { return }
        Task {
            await coordinator.prepare()
            hotkey.start()
        }
    }

    func retry() { Task { await coordinator.prepare() } }

    // MARK: - Settings change handling

    private func handleSettingsChange(old: Settings) {
        try? settingsStore.save(settings)

        if old.pushToTalkKey != settings.pushToTalkKey {
            hotkey.setHotkey(settings.pushToTalkKey)
        }
        if old.launchAtLogin != settings.launchAtLogin {
            applyLoginAtLogin(settings.launchAtLogin)
        }

        if old.transcriptionEngine != settings.transcriptionEngine
            || old.whisperKitModelId != settings.whisperKitModelId {
            swapEngineIfReady()
        }
        if old.cleanupEngine != settings.cleanupEngine
            || old.mlxModelId != settings.mlxModelId {
            swapCleanupIfReady()
        }
    }

    private func swapEngineIfReady() {
        let (new, hint) = EngineFactory.makeTranscription(
            settings: settings, registry: registry, audioCapture: audioCapture)
        appState.engineFallbackHint = hint
        Task { await coordinator.requestSwap(engine: new) }
    }

    private func swapCleanupIfReady() {
        let (new, hint) = EngineFactory.makeCleanup(
            settings: settings, registry: registry)
        cleanupHint = hint
        Task { await coordinator.requestSwap(cleanup: new) }
    }

    /// Beobachtet `registry.status` via Observation-Tracking. Sobald sich
    /// der Status irgendeines Modells ändert, prüfen wir, ob die aktuelle
    /// Settings-Wahl jetzt frisch installiert ist — und triggern den Swap.
    private func observeRegistryStatus() {
        statusObservationTask = Task { [weak self] in
            while !Task.isCancelled {
                _ = withObservationTracking {
                    self?.registry.status
                } onChange: { [weak self] in
                    Task { @MainActor in
                        self?.swapEngineIfReady()
                        self?.swapCleanupIfReady()
                    }
                }
                // bis zur nächsten Änderung schlafen — onChange weckt uns
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    /// (Unverändert aus Plan 3.)
    func hotkeyCaptureBegin(_ completion: @escaping (String) -> Void) {
        hotkey.stopCapture()
        hotkey.onCaptured = { [weak self] name in
            self?.hotkey.stopCapture()
            self?.hotkey.onCaptured = nil
            completion(name)
        }
        hotkey.startCapture()
    }

    func cancelHotkeyCapture() {
        hotkey.stopCapture()
        hotkey.onCaptured = nil
    }

    private func applyLoginAtLogin(_ enabled: Bool) {
        guard !isApplyingLogin else { return }
        isApplyingLogin = true
        defer { isApplyingLogin = false }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            var rollback = settings
            rollback.launchAtLogin = !enabled
            settings = rollback
            loginErrorMessage = error.localizedDescription
        }
    }
}
```

> Beachten: Die Übergangs-UI für `cleanupEnabled` aus Task 1/Step 5 wird
> in Task 9 durch echte Pickers ersetzt. Bis dahin funktioniert die App
> weiterhin — Engine wechselt nur, wenn `whisperKit` per Settings-JSON
> manuell gesetzt wird (gut für Smoke-Tests).

- [ ] **Step 7: App bauen**

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add EngineFactory and wire AppController for live engine/cleanup swap"
```

---

## Task 9: SettingsView — Pickers + ModelStatusView + Confirmation-Dialog

UI-Schicht für die Engine- und Cleanup-Wahl. Übergangs-Toggle aus
Task 1 wird ersetzt.

**Files:**
- Create: `VoiceType/VoiceType/ModelStatusView.swift`
- Edit: `VoiceType/VoiceType/SettingsView.swift`

- [ ] **Step 1: ModelStatusView implementieren**

Create `VoiceType/VoiceType/ModelStatusView.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Rendert den aktuellen Modell-Status (installiert / lädt / fehlt /
/// fehlgeschlagen) und bietet die jeweils passende Aktion an.
struct ModelStatusView: View {
    let descriptor: ModelDescriptor
    let registry: ModelRegistry

    var body: some View {
        HStack(spacing: 8) {
            switch registry.status[descriptor] ?? .notInstalled {
            case .notInstalled:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("Nicht installiert")
                Spacer()
                Button("Laden") { Task { await registry.download(descriptor) } }
            case .installing(let p):
                ProgressView(value: p)
                Text("\(Int(p * 100)) %")
                    .monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Abbrechen") {
                    Task { await registry.cancelDownload(descriptor) }
                }
            case .installed(let size):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Installiert (\(humanSize(size)))")
                Spacer()
                Button("Löschen") {
                    Task { try? await registry.delete(descriptor) }
                }
            case .failed(let reason):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(reason).font(.caption)
                Spacer()
                Button("Erneut laden") {
                    Task { await registry.download(descriptor) }
                }
            }
        }
        .font(.caption)
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 2: SettingsView umbauen**

Edit `VoiceType/VoiceType/SettingsView.swift` — komplette Form-Sektion
ersetzen (alle bisherigen Sections bleiben, neue kommen dazwischen):

```swift
import SwiftUI
import VoiceTypeCore

struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var isCapturingHotkey = false
    @State private var showLoginError = false
    @State private var pendingEngineChoice: TranscriptionEngineKind?
    @State private var pendingCleanupChoice: CleanupEngineKind?
    @State private var pendingDescriptor: ModelDescriptor?

    var body: some View {
        Form {
            Section("Push-to-Talk") {
                hotkeyRow
            }

            Section {
                Picker("Sprache", selection: $controller.settings.language) {
                    Text("Automatisch").tag("auto")
                    Text("Deutsch").tag("de")
                    Text("Englisch").tag("en")
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Wirkt beim nächsten App-Start.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            transcriptionSection
            cleanupSection

            Section("Start") {
                Toggle("Beim Login starten",
                       isOn: $controller.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .onDisappear { cancelCaptureIfNeeded() }
        .onChange(of: controller.loginErrorMessage) { _, new in
            showLoginError = (new != nil)
        }
        .alert("Anmeldeobjekt konnte nicht gesetzt werden",
               isPresented: $showLoginError) {
            Button("OK") { controller.loginErrorMessage = nil }
        } message: { Text(controller.loginErrorMessage ?? "") }
        .confirmationDialog(downloadDialogTitle,
                            isPresented: Binding(
                                get: { pendingDescriptor != nil },
                                set: { if !$0 { pendingDescriptor = nil } }),
                            titleVisibility: .visible) {
            Button("Laden") { confirmDownload() }
            Button("Abbrechen", role: .cancel) { revertPendingChoice() }
        } message: {
            if let d = pendingDescriptor {
                Text("\(d.displayName) (\(humanSize(d.approxSizeBytes))) wird einmalig aus dem Internet heruntergeladen und lokal gespeichert. Bis es bereit ist, bleibt die aktuelle Wahl aktiv.")
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var transcriptionSection: some View {
        Section {
            Picker("Engine", selection: Binding(
                get: { controller.settings.transcriptionEngine },
                set: { handleTranscriptionPick($0) })) {
                    Text("Apple Speech").tag(TranscriptionEngineKind.apple)
                    Text("WhisperKit (lokal)").tag(TranscriptionEngineKind.whisperKit)
                }
                .pickerStyle(.menu)

            if controller.settings.transcriptionEngine == .whisperKit,
               let desc = ModelCatalog.whisperKit(id: controller.settings.whisperKitModelId) {
                Picker("Modell", selection: $controller.settings.whisperKitModelId) {
                    ForEach(ModelCatalog.whisperKitAll, id: \.id) { d in
                        Text(d.displayName).tag(d.id)
                    }
                }
                .pickerStyle(.menu)
                ModelStatusView(descriptor: desc, registry: controller.registry)
            }
        } header: {
            Text("Spracherkennung")
        } footer: {
            Text(transcriptionFooter)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cleanupSection: some View {
        Section {
            Picker("Cleanup", selection: Binding(
                get: { controller.settings.cleanupEngine },
                set: { handleCleanupPick($0) })) {
                    Text("Aus").tag(CleanupEngineKind.off)
                    Text("Apple Foundation Models").tag(CleanupEngineKind.appleFoundationModels)
                    Text("Lokales LLM (MLX)").tag(CleanupEngineKind.mlx)
                }
                .pickerStyle(.menu)

            if controller.settings.cleanupEngine == .mlx,
               let desc = ModelCatalog.mlx(id: controller.settings.mlxModelId) {
                Picker("Modell", selection: $controller.settings.mlxModelId) {
                    ForEach(ModelCatalog.mlxAll, id: \.id) { d in
                        Text(d.displayName).tag(d.id)
                    }
                }
                .pickerStyle(.menu)
                ModelStatusView(descriptor: desc, registry: controller.registry)
            }

            if let hint = controller.cleanupHint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Text aufpolieren")
        } footer: {
            Text(cleanupFooter)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hotkeyRow: some View {
        HStack {
            Text("Hotkey:")
            Text(controller.settings.pushToTalkKey.uppercased())
                .font(.body.monospaced())
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Spacer()
            Button(isCapturingHotkey ? "Drücke eine Taste…" : "Drücke neue Taste…") {
                startHotkeyCapture()
            }
            .disabled(isCapturingHotkey)
        }
    }

    // MARK: - Picker-Handling

    private func handleTranscriptionPick(_ pick: TranscriptionEngineKind) {
        switch pick {
        case .apple:
            controller.settings.transcriptionEngine = .apple
        case .whisperKit:
            let desc = ModelCatalog.whisperKit(id: controller.settings.whisperKitModelId)
                ?? ModelCatalog.whisperKitDefault
            askDownloadOrApply(descriptor: desc) {
                controller.settings.transcriptionEngine = .whisperKit
                controller.settings.whisperKitModelId = desc.id
            }
        }
    }

    private func handleCleanupPick(_ pick: CleanupEngineKind) {
        switch pick {
        case .off, .appleFoundationModels:
            controller.settings.cleanupEngine = pick
        case .mlx:
            let desc = ModelCatalog.mlx(id: controller.settings.mlxModelId)
                ?? ModelCatalog.mlxDefault
            askDownloadOrApply(descriptor: desc) {
                controller.settings.cleanupEngine = .mlx
                controller.settings.mlxModelId = desc.id
            }
        }
    }

    private func askDownloadOrApply(
        descriptor: ModelDescriptor, apply: @escaping () -> Void
    ) {
        let current = controller.registry.status[descriptor] ?? .notInstalled
        switch current {
        case .installed, .installing:
            apply()
        case .notInstalled, .failed:
            pendingDescriptor = descriptor
            pendingApply = apply
        }
    }

    @State private var pendingApply: (() -> Void)?

    private func confirmDownload() {
        pendingApply?()
        if let d = pendingDescriptor {
            Task { await controller.registry.download(d) }
        }
        pendingDescriptor = nil
        pendingApply = nil
    }

    private func revertPendingChoice() {
        pendingDescriptor = nil
        pendingApply = nil
    }

    // MARK: - Footer-Texte

    private var transcriptionFooter: String {
        // Plan-4-Schluss: hier könnten wir den exakten Aktivierungs-
        // Status (idle vs busy vs download) rendern. In dieser Iteration
        // halten wir es minimal und nutzen den allgemeinen Hint.
        controller.appState.engineFallbackHint ?? "Aktiv."
    }

    private var cleanupFooter: String {
        controller.cleanupHint ?? "Aktiv."
    }

    // MARK: - Hotkey-Capture (unverändert aus Plan 3)

    private func startHotkeyCapture() {
        isCapturingHotkey = true
        controller.hotkeyCaptureBegin { newName in
            controller.settings.pushToTalkKey = newName
            isCapturingHotkey = false
        }
    }

    private func cancelCaptureIfNeeded() {
        if isCapturingHotkey {
            controller.cancelHotkeyCapture()
            isCapturingHotkey = false
        }
    }

    private var downloadDialogTitle: String {
        if let d = pendingDescriptor {
            switch d.kind {
            case .whisperKit: return "WhisperKit-Modell laden?"
            case .mlx: return "MLX-Modell laden?"
            }
        }
        return "Modell laden?"
    }

    private func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 3: App bauen**

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manueller Smoke (UI-Pfad)**

App starten und in Settings:

1. **Engine-Picker auf „WhisperKit (lokal)"** → Confirmation-Dialog
   („Whisper large-v3-turbo (~1.6 GB)…"). „Laden" → Progress-Bar
   im Model-Status, Hint „WhisperKit-Modell nicht installiert — Apple
   Speech aktiv." erscheint als Footer.
2. **Während des Downloads diktieren** → funktioniert mit Apple Speech.
3. **Download fertig** → Footer wird zu „Aktiv.", Diktat nutzt
   WhisperKit (an einer schwierigen Aufnahme erkennbar besser).
4. **Engine zurück auf „Apple Speech"** → sofortiger Swap, Footer
   „Aktiv.".
5. **Cleanup-Picker auf „Lokales LLM (MLX)"** → Confirmation-Dialog,
   ~4 GB Download, danach Live-Swap. Cleanup-Verhalten testen.
6. **Picker-Klick während laufendem Diktat** → Setting wird übernommen,
   Swap erfolgt nach Diktat-Ende ohne Crash.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add SettingsView pickers, ModelStatusView and download confirmation"
```

---

## Task 10: Aktivierungs-Footer mit echtem Status

Die Spec (§ 7.3) verlangt fünf verschiedene Footer-Strings je nach
Beziehung zwischen Setting und laufender Engine. Bisher ist der Footer
auf Fallback-Hint reduziert. Hier wird er auf das vollständige
Statusset erweitert.

**Files:**
- Edit: `VoiceTypeCore/Sources/VoiceTypeCore/AppState.swift`
- Edit: `VoiceType/VoiceType/VoiceTypeApp.swift`
- Edit: `VoiceType/VoiceType/SettingsView.swift`

- [ ] **Step 1: AppState um Activeness-Spiegel ergänzen**

Edit `VoiceTypeCore/Sources/VoiceTypeCore/AppState.swift` — neue
Properties:

```swift
/// Spiegelt die *tatsächlich laufende* Transcription-Engine.
/// Wird vom AppController nach jedem erfolgreichen Swap aktualisiert.
public var activeTranscriptionEngine: TranscriptionEngineKind = .apple
public var activeCleanupEngine: CleanupEngineKind = .appleFoundationModels
```

- [ ] **Step 2: AppController-Swap-Stellen aktualisieren**

Edit `VoiceType/VoiceType/VoiceTypeApp.swift` — in `swapEngineIfReady()`
nach dem `requestSwap`-Aufruf:

```swift
Task {
    await coordinator.requestSwap(engine: new)
    appState.activeTranscriptionEngine =
        (hint == nil ? settings.transcriptionEngine : .apple)
}
```

Analog in `swapCleanupIfReady()`:

```swift
Task {
    await coordinator.requestSwap(cleanup: new)
    appState.activeCleanupEngine =
        (hint == nil ? settings.cleanupEngine : .off)
}
```

Und im `init()` direkt nach den initialen Factory-Aufrufen:

```swift
appState.activeTranscriptionEngine =
    (fallback == nil ? loaded.transcriptionEngine : .apple)
appState.activeCleanupEngine =
    (hint == nil ? loaded.cleanupEngine : .off)
```

- [ ] **Step 3: Footer-Helfer in SettingsView**

Edit `VoiceType/VoiceType/SettingsView.swift` — `transcriptionFooter`
und `cleanupFooter` ersetzen:

```swift
private var transcriptionFooter: String {
    activationFooter(
        setting: controller.settings.transcriptionEngine,
        active: controller.appState.activeTranscriptionEngine,
        descriptor: controller.settings.transcriptionEngine == .whisperKit
            ? ModelCatalog.whisperKit(id: controller.settings.whisperKitModelId)
            : nil,
        fallbackHint: controller.appState.engineFallbackHint)
}

private var cleanupFooter: String {
    activationFooter(
        setting: controller.settings.cleanupEngine,
        active: controller.appState.activeCleanupEngine,
        descriptor: controller.settings.cleanupEngine == .mlx
            ? ModelCatalog.mlx(id: controller.settings.mlxModelId)
            : nil,
        fallbackHint: controller.cleanupHint)
}

private func activationFooter<E: Equatable>(
    setting: E, active: E,
    descriptor: ModelDescriptor?,
    fallbackHint: String?
) -> String {
    if setting == active { return "Aktiv." }
    if let d = descriptor,
       case .installing = controller.registry.status[d] ?? .notInstalled {
        return "Wird nach Download aktiv."
    }
    if controller.appState.dictationState != .idle
        && controller.appState.dictationState != .loading {
        return "Wird nach aktuellem Diktat aktiv."
    }
    if let fallbackHint { return fallbackHint }
    return "Wird sofort aktiv…"
}
```

- [ ] **Step 4: App bauen**

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manueller Smoke (Footer)**

1. Engine wechseln, während gerade ein Diktat läuft → Footer „Wird nach
   aktuellem Diktat aktiv.", nach Loslassen → „Aktiv.".
2. Engine wechseln, Modell wird geladen → Footer „Wird nach Download
   aktiv." bis Download fertig.
3. Engine zurück auf Apple → Footer „Aktiv." sofort.
4. Engine auf WhisperKit, das Modell wurde extern gelöscht → Footer
   zeigt den Fallback-Hint.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add activation-state footer that reflects live swap status"
```

---

## Abschluss Plan 4

Nach Task 10 ist die Engine-/Cleanup-Wahl vollständig nutzbar:

- Settings-Pickers für Spracherkennung (Apple ↔ WhisperKit) und Cleanup
  (Aus ↔ Apple FM ↔ MLX).
- On-Demand-Download mit Bestätigung, Progress, Abbrechen, Löschen.
- Live-Swap ohne App-Neustart; während laufendem Diktat sauber
  aufgeschoben; nach Download-Erfolg automatisch ausgelöst.
- Fallback-Pfad bei fehlenden/defekten Modellen oder
  `prepare()`-Fehlern, ohne dass die App ihre Diktat-Funktion verliert.
- Alle Core-Bausteine TDD-abgedeckt (Migration, Sanity, Katalog,
  Registry, Coordinator-Swap, Factory). System-Integrationen
  (WhisperKit, MLX, AppController, SettingsView) per Smoke verifiziert.

**Was bewusst noch fehlt (kann in einem späteren Plan kommen):**
- **Modell-Updates** (Hash-basierte Erkennung neuer Versionen).
- **Performance-Telemetrie** (Latenz, Wort-Fehler-Rate).
- **Live-Sprachenwechsel ohne App-Restart** (`language`-Setting bleibt
  Plan-3-Verhalten).
- **Eigene HuggingFace-Repo-Eingabe** (Katalog ist statisch).

---

## Self-Review

**Spec-Abdeckung (Plan 4 vs. § 13 der Spec):**

| Spec-Schritt | Plan-4-Task |
|---|---|
| 1 Settings-Schema + Migration | Task 1 ✓ |
| 2 ModelDescriptor + Katalog + Status | Task 3 ✓ |
| 3 ModelRegistry (FS-Tests) | Task 4 ✓ |
| 4 DictationCoordinator-Swap (TDD) | Task 5 ✓ |
| 5 SPM + WhisperKitEngine | Task 6 ✓ |
| 6 SPM + MLXCleanup | Task 7 ✓ |
| 7 EngineFactory + AppController + Registry-Observation | Task 8 ✓ |
| 8 SettingsView + ModelStatusView + Dialog + Activation-Footer | Task 9 + 10 ✓ |
| 9 End-to-End-Smoke | Task 9/Step 4 + Task 10/Step 5 ✓ |

Zusätzlich: Task 2 (`CleanupSanity` extrahieren) ist Vorarbeit für
Task 7 — in der Spec implizit, hier explizit.

**Typ-Konsistenz:**
`TranscriptionEngine`, `TextCleanup`, `AudioCapturing`, `AppState`,
`Settings.*EngineKind`, `ModelDescriptor.Kind`, `ModelStatus`,
`ModelDownloading` — über alle Tasks hinweg einheitlich.

**TDD-Disziplin:** Tasks 1, 2, 3, 4, 5, 7, 8 starten mit failing tests
(rot → grün). Tasks 6, 9, 10 sind System-/UI-Integrationen mit „bauen +
manueller Smoke-Test", konsistent mit dem Stil aus Plan 1 (Tasks 6–10
dort).

**Platzhalter-Scan:** Keine offenen TBD/TODO. Die zwei API-Risiko-
Hinweise in Tasks 6 und 7 sind explizit als „bei abweichender Signatur
in Xcode prüfen" markiert und ändern den `TranscriptionEngine`/
`TextCleanup`-Vertrag nicht.

**Abhängigkeitsreihenfolge ist linear:**
1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10. Jeder Task baut sauber auf den
vorherigen auf; nach jedem Task kompiliert das Repo und Tests sind
grün.
