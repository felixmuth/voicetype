# VoiceType — Plan 1: Fundament & minimales End-to-End-Diktat

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine lauffähige native macOS-Menüleisten-App, mit der man per Push-to-Talk-Hotkey in jedes Textfeld diktiert — der erkannte Rohtext wird eingefügt und in die Zwischenablage kopiert.

**Architecture:** Swift-Package `VoiceTypeCore` enthält die gesamte testbare Logik (Einstellungen, Zustandsmaschine, Protokolle, System-Adapter); eine schlanke SwiftUI-App (`VoiceType.xcodeproj`) verdrahtet sie über `MenuBarExtra`. Spracherkennung (`AppleSpeechEngine`) und Text-Cleanup (`TextCleanup`) liegen hinter Protokollen — die `DictationCoordinator`-Zustandsmaschine wird gegen Mocks per TDD getestet. In Plan 1 ist das Cleanup ein Pass-through (Identität); echtes Cleanup kommt in Plan 2.

**Tech Stack:** Swift 6.3, SwiftUI (`MenuBarExtra`), Swift Testing, `AVAudioEngine` (Audio), `SpeechAnalyzer`/`SpeechTranscriber` (macOS 26 On-Device-Spracherkennung), `NSEvent`-Monitor (globaler Hotkey), Accessibility API (`AXUIElement`, Text einfügen). Ziel: macOS 26+, Apple Silicon.

**Spec:** `docs/superpowers/specs/2026-05-14-voicetype-redesign-design.md`

> ⚠️ **Neue APIs:** `SpeechAnalyzer`/`SpeechTranscriber` (Task 7) sind macOS-26-APIs ohne breite Community-Beispiele. Der Code unten basiert auf Apple-Doku und WWDC25-Material. Tasks 6–9 sind System-Integrationen — sie lassen sich nicht sinnvoll unit-testen, deshalb haben sie „bauen + manueller Smoke-Test"-Schritte statt Unit-Tests. Wenn eine Signatur abweicht: in Xcode Quick Help (⌥-Klick) prüfen und anpassen.

---

## Dateistruktur

```
voicetype/
├── VoiceType.xcodeproj                       # App-Projekt (Task 1)
├── VoiceType/
│   ├── VoiceTypeApp.swift                    # App-Einstieg, MenuBarExtra (Task 10)
│   ├── MenuContentView.swift                 # Popover-Inhalt (Task 10)
│   ├── PermissionsView.swift                 # Berechtigungs-Onboarding (Task 11)
│   ├── Info.plist                            # Usage-Strings (Task 1)
│   └── VoiceType.entitlements                # Entitlements (Task 1)
├── VoiceTypeCore/                            # lokales Swift-Package
│   ├── Package.swift                         # (Task 1)
│   ├── Sources/VoiceTypeCore/
│   │   ├── Settings.swift                    # Settings + SettingsStore (Task 2)
│   │   ├── Models.swift                      # DictationState, TranscriptEntry, TranscriptionUpdate (Task 3)
│   │   ├── AppState.swift                    # @Observable Single Source of Truth (Task 3)
│   │   ├── Protocols.swift                   # TranscriptionEngine, TextCleanup, TextDelivering, FocusInspecting, AudioCapturing (Task 4)
│   │   ├── PassthroughCleanup.swift          # Identitäts-Cleanup für Plan 1 (Task 4)
│   │   ├── DictationCoordinator.swift        # Zustandsmaschine (Task 5)
│   │   ├── AudioCapture.swift                # AVAudioEngine-Adapter (Task 6)
│   │   ├── BufferConverter.swift             # AVAudioConverter-Helfer (Task 6)
│   │   ├── AppleSpeechEngine.swift           # SpeechTranscriber-Adapter (Task 7)
│   │   ├── HotkeyMonitor.swift               # globaler NSEvent-Monitor (Task 8)
│   │   ├── FocusInspector.swift              # AXUIElement-Fokusprüfung (Task 9)
│   │   ├── TextOutput.swift                  # Text einfügen + Clipboard (Task 9)
│   │   └── Permissions.swift                 # Berechtigungs-Status & -Anforderung (Task 11)
│   └── Tests/VoiceTypeCoreTests/
│       ├── SettingsStoreTests.swift          # (Task 2)
│       ├── AppStateTests.swift               # (Task 3)
│       ├── PassthroughCleanupTests.swift     # (Task 4)
│       ├── Mocks.swift                       # Mock-Implementierungen aller Protokolle (Task 4)
│       └── DictationCoordinatorTests.swift   # (Task 5)
```

---

## Task 1: Projekt-Gerüst — Xcode-App + VoiceTypeCore-Paket

**Files:**
- Create: `VoiceTypeCore/Package.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/Placeholder.swift`
- Create: `VoiceTypeCore/Tests/VoiceTypeCoreTests/SmokeTest.swift`
- Create: `VoiceType.xcodeproj` (über Xcode-GUI)
- Create: `VoiceType/Info.plist`, `VoiceType/VoiceType.entitlements`

- [ ] **Step 1: Volles Xcode installieren**

Aktuell sind nur die Command Line Tools vorhanden. Volles Xcode aus dem App Store installieren, dann:

Run: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -version`
Expected: `Xcode 26.x` (nicht „Command Line Tools").

- [ ] **Step 2: VoiceTypeCore-Paket anlegen**

Create `VoiceTypeCore/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceTypeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceTypeCore", targets: ["VoiceTypeCore"]),
    ],
    targets: [
        .target(name: "VoiceTypeCore"),
        .testTarget(
            name: "VoiceTypeCoreTests",
            dependencies: ["VoiceTypeCore"]
        ),
    ]
)
```

Create `VoiceTypeCore/Sources/VoiceTypeCore/Placeholder.swift`:

```swift
// Platzhalter, damit das Target kompiliert. Wird in Task 2 gelöscht.
enum Placeholder {}
```

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/SmokeTest.swift`:

```swift
import Testing
@testable import VoiceTypeCore

@Test func packageCompiles() {
    #expect(true)
}
```

- [ ] **Step 3: Paket bauen und Test ausführen**

Run: `cd VoiceTypeCore && swift test`
Expected: `Test run with 1 test passed`.

- [ ] **Step 4: Xcode-App-Projekt anlegen**

In Xcode: `File → New → Project → macOS → App`.
- Product Name: `VoiceType`
- Organization Identifier: `com.felixmuth`
- Interface: SwiftUI, Language: Swift
- Speicherort: Repo-Wurzel `<repo>` (sodass `VoiceType.xcodeproj` neben `VoiceTypeCore/` liegt). Häkchen „Create Git repository" **deaktivieren** (Repo existiert schon).

Dann das lokale Paket einbinden: `File → Add Package Dependencies → Add Local…` → Ordner `VoiceTypeCore` wählen → zum Target `VoiceType` hinzufügen.

- [ ] **Step 5: App als Menüleisten-Agent konfigurieren**

In den Target-Einstellungen von `VoiceType`:
- `General → Minimum Deployments → macOS 26.0`
- `Info` → neue Zeile: `Application is agent (UIElement)` = `YES` (kein Dock-Icon)
- `Info` → neue Zeile: `Privacy - Microphone Usage Description` = `VoiceType nimmt dein Mikrofon auf, um deine Sprache in Text umzuwandeln.`

`VoiceType/VoiceType.entitlements` — App Sandbox **deaktivieren** (globaler Hotkey & Accessibility-Einfügen funktionieren nicht in der Sandbox). In `Signing & Capabilities` die Capability „App Sandbox" entfernen, falls vorhanden.

- [ ] **Step 6: App bauen und starten**

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

In Xcode mit ⌘R starten: ein leeres Fenster bzw. (je nach Default) kein Fenster — kein Crash. Beenden.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold VoiceTypeCore package and VoiceType app project"
```

---

## Task 2: Settings & SettingsStore

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/Settings.swift`
- Delete: `VoiceTypeCore/Sources/VoiceTypeCore/Placeholder.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/SettingsStoreTests.swift`:

```swift
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
        settings.cleanupEnabled = false
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
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter SettingsStoreTests`
Expected: FAIL — `cannot find 'SettingsStore' in scope`.

- [ ] **Step 3: Settings & SettingsStore implementieren**

Delete `VoiceTypeCore/Sources/VoiceTypeCore/Placeholder.swift`.

Create `VoiceTypeCore/Sources/VoiceTypeCore/Settings.swift`:

```swift
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
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter SettingsStoreTests`
Expected: PASS — 3 tests passed.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Settings and SettingsStore with JSON persistence"
```

---

## Task 3: Modelltypen & AppState

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/Models.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/AppState.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/AppStateTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/AppStateTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct AppStateTests {
    @Test func startsInLoadingStateWithEmptyLog() {
        let state = AppState()
        #expect(state.dictationState == .loading)
        #expect(state.log.isEmpty)
        #expect(state.livePreview == "")
    }

    @Test func addEntryPrependsNewestFirst() {
        let state = AppState()
        state.addEntry("erster")
        state.addEntry("zweiter")
        #expect(state.log.count == 2)
        #expect(state.log.first?.text == "zweiter")
    }

    @Test func addEntryIgnoresEmptyText() {
        let state = AppState()
        state.addEntry("   ")
        #expect(state.log.isEmpty)
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter AppStateTests`
Expected: FAIL — `cannot find 'AppState' in scope`.

- [ ] **Step 3: Modelltypen implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/Models.swift`:

```swift
import Foundation

public enum DictationState: Equatable, Sendable {
    case loading      // Engine wärmt beim Start auf
    case idle         // bereit
    case recording    // Taste gehalten, Audio streamt
    case finalizing   // Taste los, finales Transkript wird abgeholt
    case cleaning     // Cleanup-Pass
    case delivering   // Text wird eingefügt
    case error(String)
}

/// Ein Teil- oder Endergebnis der Spracherkennung.
public struct TranscriptionUpdate: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Ein abgeschlossenes Diktat im Verlauf.
public struct TranscriptEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}
```

- [ ] **Step 4: AppState implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/AppState.swift`:

```swift
import Foundation
import Observation

/// Single Source of Truth für alle Views. Wird ausschließlich vom
/// DictationCoordinator (Controller) mutiert; Views lesen nur.
@MainActor
@Observable
public final class AppState {
    public var dictationState: DictationState = .loading
    public var livePreview: String = ""
    public var micLevel: Float = 0
    public private(set) var log: [TranscriptEntry] = []

    public init() {}

    /// Hängt ein abgeschlossenes Diktat vorne an (neueste zuerst).
    /// Leerer/nur-Whitespace-Text wird ignoriert.
    public func addEntry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.insert(TranscriptEntry(text: trimmed), at: 0)
    }
}
```

- [ ] **Step 5: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter AppStateTests`
Expected: PASS — 3 tests passed.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add DictationState, TranscriptionUpdate, TranscriptEntry and AppState"
```

---

## Task 4: Kern-Protokolle, PassthroughCleanup & Mocks

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/Protocols.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/PassthroughCleanup.swift`
- Create: `VoiceTypeCore/Tests/VoiceTypeCoreTests/Mocks.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/PassthroughCleanupTests.swift`

- [ ] **Step 1: Failing test schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/PassthroughCleanupTests.swift`:

```swift
import Testing
@testable import VoiceTypeCore

@Suite struct PassthroughCleanupTests {
    @Test func returnsInputUnchanged() async {
        let cleanup = PassthroughCleanup()
        let result = await cleanup.cleanup("ähm das ist ein test")
        #expect(result == "ähm das ist ein test")
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter PassthroughCleanupTests`
Expected: FAIL — `cannot find 'PassthroughCleanup' in scope`.

- [ ] **Step 3: Protokolle definieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/Protocols.swift`:

```swift
import Foundation

/// Spracherkennungs-Engine. Streamt Teilergebnisse während der Aufnahme
/// und liefert genau ein `isFinal`-Ergebnis, bevor der Stream endet.
public protocol TranscriptionEngine: Sendable {
    /// Lädt/prüft Modelle. Wirft, wenn die Engine nicht nutzbar ist.
    func prepare() async throws
    /// Startet Aufnahme + Transkription. Der zurückgegebene Stream
    /// emittiert Teilergebnisse und zum Schluss ein `isFinal`-Ergebnis.
    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error>
    /// Stoppt die Aufnahme; der Stream finalisiert und endet danach.
    func stop() async
}

/// Poliert Rohtext auf. Wirft nie — bei Problemen wird der Rohtext
/// zurückgegeben (sanfte Degradierung, siehe Spec).
public protocol TextCleanup: Sendable {
    func cleanup(_ raw: String) async -> String
}

/// Liefert fertigen Text aus: fügt ihn ggf. ins fokussierte Feld ein
/// und/oder kopiert ihn in die Zwischenablage.
public protocol TextDelivering: Sendable {
    func deliver(_ text: String, pasteIntoFocusedField: Bool)
}

/// Prüft on-demand, ob gerade ein Textfeld den Fokus hat.
public protocol FocusInspecting: Sendable {
    func isTextFieldFocused() -> Bool
}

/// Mikrofon-Aufnahme als Puffer-Stream.
public protocol AudioCapturing: Sendable {
    func startStream() throws -> AsyncStream<CapturedAudio>
    func stop()
}

/// Roh-Audiopuffer plus aktueller Pegel (RMS, 0…1) für den Visualizer.
public struct CapturedAudio: @unchecked Sendable {
    public let pcmBuffer: AnyObject   // AVAudioPCMBuffer; AnyObject hält den Core testbar
    public let level: Float
    public init(pcmBuffer: AnyObject, level: Float) {
        self.pcmBuffer = pcmBuffer
        self.level = level
    }
}

public enum TranscriptionError: Error, Equatable {
    case notPrepared
    case localeNotSupported
    case modelUnavailable
}
```

- [ ] **Step 4: PassthroughCleanup implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/PassthroughCleanup.swift`:

```swift
/// Cleanup-Implementierung für Plan 1: gibt den Text unverändert zurück.
/// Wird in Plan 2 durch FoundationModelCleanup ersetzt.
public struct PassthroughCleanup: TextCleanup {
    public init() {}
    public func cleanup(_ raw: String) async -> String { raw }
}
```

- [ ] **Step 5: Mocks für die Coordinator-Tests anlegen**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/Mocks.swift`:

```swift
import Foundation
@testable import VoiceTypeCore

/// Steuerbare TranscriptionEngine: der Test schiebt Updates rein und
/// entscheidet, ob/wann der Stream endet bzw. mit Fehler abbricht.
final class MockTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    var prepareError: Error?
    var startError: Error?
    private(set) var prepareCallCount = 0
    private(set) var stopCallCount = 0
    private var continuation: AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?

    func prepare() async throws {
        prepareCallCount += 1
        if let prepareError { throw prepareError }
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        if let startError { throw startError }
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    func stop() async { stopCallCount += 1 }

    // Test-Steuerung:
    func emit(_ text: String, isFinal: Bool) {
        continuation?.yield(TranscriptionUpdate(text: text, isFinal: isFinal))
    }
    func finishStream() { continuation?.finish() }
    func failStream(_ error: Error) { continuation?.finish(throwing: error) }
}

/// Cleanup-Mock: ersetzt den Text durch ein konfigurierbares Ergebnis.
final class MockCleanup: TextCleanup, @unchecked Sendable {
    var transform: @Sendable (String) -> String = { $0 }
    private(set) var receivedInput: String?
    func cleanup(_ raw: String) async -> String {
        receivedInput = raw
        return transform(raw)
    }
}

/// Output-Mock: merkt sich, was ausgeliefert wurde.
final class MockTextDelivery: TextDelivering, @unchecked Sendable {
    private(set) var deliveredText: String?
    private(set) var deliveredPaste: Bool?
    private(set) var deliverCallCount = 0
    func deliver(_ text: String, pasteIntoFocusedField: Bool) {
        deliveredText = text
        deliveredPaste = pasteIntoFocusedField
        deliverCallCount += 1
    }
}

/// Fokus-Mock: liefert einen festen Wert.
final class MockFocusInspector: FocusInspecting, @unchecked Sendable {
    var focused: Bool = false
    func isTextFieldFocused() -> Bool { focused }
}
```

- [ ] **Step 6: Test ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter PassthroughCleanupTests`
Expected: PASS — 1 test passed. (Der Rest des Pakets kompiliert dabei mit, inkl. Mocks.)

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add core protocols, PassthroughCleanup and test mocks"
```

---

## Task 5: DictationCoordinator — Zustandsmaschine

Das Herzstück. Reine Logik, vollständig per TDD gegen die Mocks aus Task 4.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/DictationCoordinator.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/DictationCoordinatorTests.swift`

- [ ] **Step 1: Failing tests schreiben (Happy Path + Edge Cases)**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/DictationCoordinatorTests.swift`:

```swift
import Testing
import Foundation
@testable import VoiceTypeCore

@MainActor
@Suite struct DictationCoordinatorTests {

    private func makeCoordinator() -> (
        DictationCoordinator, AppState, MockTranscriptionEngine,
        MockCleanup, MockTextDelivery, MockFocusInspector
    ) {
        let appState = AppState()
        let engine = MockTranscriptionEngine()
        let cleanup = MockCleanup()
        let delivery = MockTextDelivery()
        let focus = MockFocusInspector()
        let coordinator = DictationCoordinator(
            engine: engine, cleanup: cleanup, delivery: delivery,
            focus: focus, appState: appState)
        return (coordinator, appState, engine, cleanup, delivery, focus)
    }

    /// Wartet, bis sich der Zustand vom übergebenen Wert wegbewegt hat
    /// (max. 2 s), damit Tests nicht auf interne Tasks pollen müssen.
    private func waitUntilState(
        _ appState: AppState, leaves state: DictationState
    ) async {
        for _ in 0..<200 where appState.dictationState == state {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startMovesToRecordingAndStreamsLivePreview() async {
        let (coordinator, appState, engine, _, _, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        #expect(appState.dictationState == .recording)

        engine.emit("das ist", isFinal: false)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(appState.livePreview == "das ist")
    }

    @Test func happyPathDeliversCleanedTextAndLogsEntry() async {
        let (coordinator, appState, engine, cleanup, delivery, _) = makeCoordinator()
        appState.dictationState = .idle
        cleanup.transform = { $0.uppercased() }

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        engine.emit("hallo welt", isFinal: false)

        coordinator.endDictation(heldFor: .seconds(2))
        engine.emit("hallo welt", isFinal: true)
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)
        await waitUntilState(appState, leaves: .finalizing)
        await waitUntilState(appState, leaves: .cleaning)
        await waitUntilState(appState, leaves: .delivering)

        #expect(appState.dictationState == .idle)
        #expect(delivery.deliveredText == "HALLO WELT")
        #expect(appState.log.first?.text == "HALLO WELT")
        #expect(engine.stopCallCount == 1)
    }

    @Test func shortPressIsDiscarded() async {
        let (coordinator, appState, engine, _, delivery, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        coordinator.endDictation(heldFor: .milliseconds(100))
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)

        #expect(appState.dictationState == .idle)
        #expect(delivery.deliverCallCount == 0)
        #expect(appState.log.isEmpty)
        #expect(engine.stopCallCount == 1)
    }

    @Test func emptyFinalTranscriptIsNotDelivered() async {
        let (coordinator, appState, engine, _, delivery, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        coordinator.endDictation(heldFor: .seconds(2))
        engine.emit("   ", isFinal: true)
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)
        await waitUntilState(appState, leaves: .finalizing)

        #expect(appState.dictationState == .idle)
        #expect(delivery.deliverCallCount == 0)
        #expect(appState.log.isEmpty)
    }

    @Test func focusSnapshotControlsPasteFlag() async {
        let (coordinator, appState, engine, _, delivery, focus) = makeCoordinator()
        appState.dictationState = .idle
        focus.focused = true

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        focus.focused = false   // Fokuswechsel nach dem Start darf nichts ändern
        coordinator.endDictation(heldFor: .seconds(2))
        engine.emit("text", isFinal: true)
        engine.finishStream()
        await waitUntilState(appState, leaves: .recording)
        await waitUntilState(appState, leaves: .finalizing)
        await waitUntilState(appState, leaves: .cleaning)
        await waitUntilState(appState, leaves: .delivering)

        #expect(delivery.deliveredPaste == true)
    }

    @Test func streamErrorSurfacesAndReturnsToIdle() async {
        let (coordinator, appState, engine, _, delivery, _) = makeCoordinator()
        appState.dictationState = .idle

        coordinator.startDictation()
        await waitUntilState(appState, leaves: .idle)
        engine.failStream(TranscriptionError.modelUnavailable)
        await waitUntilState(appState, leaves: .recording)

        if case .error = appState.dictationState {} else {
            Issue.record("expected error state, got \(appState.dictationState)")
        }
        #expect(delivery.deliverCallCount == 0)
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter DictationCoordinatorTests`
Expected: FAIL — `cannot find 'DictationCoordinator' in scope`.

- [ ] **Step 3: DictationCoordinator implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/DictationCoordinator.swift`:

```swift
import Foundation

/// Zentrale Zustandsmaschine. Verbindet Engine, Cleanup, Output und Fokus
/// und mutiert ausschließlich den AppState.
@MainActor
public final class DictationCoordinator {
    private let engine: TranscriptionEngine
    private let cleanup: TextCleanup
    private let delivery: TextDelivering
    private let focus: FocusInspecting
    private let appState: AppState

    private static let minHold: Duration = .milliseconds(300)

    private var streamTask: Task<Void, Never>?
    private var latestFinalText: String = ""
    private var pasteTargetFocused = false
    private var discardCurrent = false

    public init(
        engine: TranscriptionEngine,
        cleanup: TextCleanup,
        delivery: TextDelivering,
        focus: FocusInspecting,
        appState: AppState
    ) {
        self.engine = engine
        self.cleanup = cleanup
        self.delivery = delivery
        self.focus = focus
        self.appState = appState
    }

    /// Engine vorbereiten; bei Erfolg geht der Zustand auf `.idle`.
    public func prepare() async {
        do {
            try await engine.prepare()
            appState.dictationState = .idle
        } catch {
            appState.dictationState = .error("Engine nicht verfügbar")
        }
    }

    /// Hotkey gedrückt.
    public func startDictation() {
        guard appState.dictationState == .idle else { return }
        latestFinalText = ""
        discardCurrent = false
        pasteTargetFocused = focus.isTextFieldFocused()   // Snapshot beim Drücken
        appState.livePreview = ""
        appState.dictationState = .recording

        streamTask = Task { [engine, appState] in
            do {
                let stream = try await engine.start()
                for try await update in stream {
                    if update.isFinal {
                        self.latestFinalText = update.text
                    } else {
                        appState.livePreview = update.text
                    }
                }
                await self.finishAfterStream()
            } catch {
                appState.dictationState = .error("Transkription fehlgeschlagen")
            }
        }
    }

    /// Hotkey losgelassen. `heldFor` ist die gemessene Haltedauer.
    public func endDictation(heldFor: Duration) {
        guard appState.dictationState == .recording else { return }
        discardCurrent = heldFor < Self.minHold
        appState.dictationState = .finalizing
        Task { await engine.stop() }   // Engine finalisiert; Stream endet danach
    }

    /// Wird aufgerufen, wenn der Engine-Stream regulär geendet hat.
    private func finishAfterStream() async {
        // Bei zu kurzem Tastendruck: alles verwerfen.
        if discardCurrent {
            appState.livePreview = ""
            appState.dictationState = .idle
            return
        }

        let raw = latestFinalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            appState.livePreview = ""
            appState.dictationState = .idle
            return
        }

        appState.dictationState = .cleaning
        let cleaned = await cleanup.cleanup(raw)

        appState.dictationState = .delivering
        delivery.deliver(cleaned, pasteIntoFocusedField: pasteTargetFocused)
        appState.addEntry(cleaned)

        appState.livePreview = ""
        appState.dictationState = .idle
    }
}
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter DictationCoordinatorTests`
Expected: PASS — 6 tests passed.

- [ ] **Step 5: Gesamtes Paket testen**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle Tests (Smoke, Settings, AppState, PassthroughCleanup, Coordinator) grün.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add DictationCoordinator state machine with full edge-case coverage"
```

---

## Task 6: AudioCapture (AVAudioEngine)

System-Integration — kein Unit-Test, sondern bauen + manueller Smoke-Test.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/BufferConverter.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/AudioCapture.swift`

- [ ] **Step 1: BufferConverter implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/BufferConverter.swift`:

```swift
import AVFoundation

/// Wandelt AVAudioPCMBuffer in ein Zielformat um (z. B. das von
/// SpeechAnalyzer geforderte). Hält einen AVAudioConverter pro Formatpaar.
final class BufferConverter {
    private var converter: AVAudioConverter?
    private var lastInputFormat: AVAudioFormat?
    private var lastOutputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        if inputFormat == outputFormat { return buffer }

        if converter == nil || lastInputFormat != inputFormat || lastOutputFormat != outputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            lastInputFormat = inputFormat
            lastOutputFormat = outputFormat
        }
        guard let converter else { throw TranscriptionError.modelUnavailable }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw TranscriptionError.modelUnavailable
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, statusPtr in
            if consumed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            consumed = true
            statusPtr.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        return output
    }
}
```

- [ ] **Step 2: AudioCapture implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/AudioCapture.swift`:

```swift
import AVFoundation

/// Nimmt das Mikrofon über AVAudioEngine auf und liefert die Puffer als
/// AsyncStream. Pro Puffer wird der RMS-Pegel (0…1) mitgegeben.
public final class AudioCapture: AudioCapturing, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<CapturedAudio>.Continuation?

    public init() {}

    public func startStream() throws -> AsyncStream<CapturedAudio> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let (stream, continuation) = AsyncStream<CapturedAudio>.makeStream()
        self.continuation = continuation

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = Self.rms(of: buffer)
            self?.continuation?.yield(CapturedAudio(pcmBuffer: buffer, level: level))
        }

        engine.prepare()
        try engine.start()
        return stream
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        let samples = channelData[0]
        for i in 0..<frames { sum += samples[i] * samples[i] }
        return min(1, (sum / Float(frames)).squareRoot() * 6)
    }
}
```

- [ ] **Step 3: Paket bauen**

Run: `cd VoiceTypeCore && swift build`
Expected: `Build complete!` (Warnungen zu `@unchecked Sendable` sind ok.)

- [ ] **Step 4: Tests ausführen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle bisherigen Tests weiterhin grün.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AudioCapture (AVAudioEngine) and BufferConverter"
```

---

## Task 7: AppleSpeechEngine (SpeechTranscriber / SpeechAnalyzer)

> ⚠️ **Neue macOS-26-API.** Code basiert auf Apple-Doku & WWDC25. Falls eine
> Signatur abweicht (besonders `analyzer.start(inputSequence:)` und
> `finalizeAndFinishThroughEndOfInput()`): in Xcode mit ⌥-Klick die
> Quick-Help-Signatur prüfen und anpassen. Verhalten bleibt gleich.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/AppleSpeechEngine.swift`

- [ ] **Step 1: AppleSpeechEngine implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/AppleSpeechEngine.swift`:

```swift
import Foundation
import Speech
import AVFoundation

/// TranscriptionEngine auf Basis von SpeechAnalyzer/SpeechTranscriber
/// (macOS 26, on-device, streaming). Konsumiert ein AudioCapturing.
public actor AppleSpeechEngine: TranscriptionEngine {
    private let audioCapture: AudioCapturing
    private let language: String          // "auto" | "de" | "en"

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private let converter = BufferConverter()

    public init(audioCapture: AudioCapturing, language: String) {
        self.audioCapture = audioCapture
        self.language = language
    }

    private func resolveLocale() -> Locale {
        switch language {
        case "de": return Locale(identifier: "de-DE")
        case "en": return Locale(identifier: "en-US")
        default:   return Locale.current
        }
    }

    public func prepare() async throws {
        let locale = resolveLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )

        let supported = await SpeechTranscriber.supportedLocales
            .map { $0.identifier(.bcp47) }
        guard supported.contains(locale.identifier(.bcp47)) else {
            throw TranscriptionError.localeNotSupported
        }

        let installed = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }
        if !installed.contains(locale.identifier(.bcp47)) {
            if let request = try await AssetInventory
                .assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        self.transcriber = transcriber
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        guard let transcriber else { throw TranscriptionError.notPrepared }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let analyzerFormat = await SpeechAnalyzer
            .bestAvailableAudioFormat(compatibleWith: [transcriber])
        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        self.analyzer = analyzer
        self.inputBuilder = inputBuilder

        try await analyzer.start(inputSequence: inputSequence)

        // Audio → Analyzer
        let audioStream = try audioCapture.startStream()
        Task { [converter] in
            for await captured in audioStream {
                guard let pcm = captured.pcmBuffer as? AVAudioPCMBuffer else { continue }
                if let format = analyzerFormat,
                   let converted = try? converter.convert(pcm, to: format) {
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                }
            }
        }

        // Analyzer-Ergebnisse → TranscriptionUpdate
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(TranscriptionUpdate(
                            text: String(result.text.characters),
                            isFinal: result.isFinal))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func stop() async {
        audioCapture.stop()
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
    }
}
```

- [ ] **Step 2: Paket bauen**

Run: `cd VoiceTypeCore && swift build`
Expected: `Build complete!`
Falls Compiler-Fehler zu Speech-Typen: Signaturen in Xcode Quick Help prüfen (⌥-Klick auf den Typ) und anpassen — die Struktur (prepare → start → results-Schleife → stop) bleibt unverändert.

- [ ] **Step 3: Tests ausführen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle Logik-Tests weiterhin grün (AppleSpeechEngine wird hier nur mitkompiliert).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add AppleSpeechEngine using SpeechTranscriber/SpeechAnalyzer"
```

---

## Task 8: HotkeyMonitor (globaler NSEvent-Monitor)

System-Integration — bauen + manueller Smoke-Test in Task 10.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/HotkeyMonitor.swift`

- [ ] **Step 1: HotkeyMonitor implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/HotkeyMonitor.swift`:

```swift
import AppKit

/// Globaler Push-to-Talk-Monitor. Unterstützt Modifier-Tasten (fn, cmd,
/// shift, ctrl, opt) sowie Funktionstasten (f1–f20). Ruft beim Drücken
/// `onPress` und beim Loslassen `onRelease(heldFor:)` auf dem MainActor auf.
///
/// Benötigt die Berechtigung „Bedienungshilfen" (Accessibility).
@MainActor
public final class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressedAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var hotkey: String

    public var onPress: (() -> Void)?
    public var onRelease: ((Duration) -> Void)?

    private static let modifierFlags: [String: NSEvent.ModifierFlags] = [
        "fn": .function, "cmd": .command, "shift": .shift,
        "ctrl": .control, "opt": .option, "alt": .option,
    ]
    private static let functionKeys: [String: UInt16] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64,
        "f18": 79, "f19": 80, "f20": 90,
    ]

    public init(hotkey: String) {
        self.hotkey = hotkey
    }

    public func setHotkey(_ hotkey: String) {
        self.hotkey = hotkey.lowercased()
        pressedAt = nil
    }

    public func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pressedAt = nil
    }

    private func handle(_ event: NSEvent) {
        if let targetMod = Self.modifierFlags[hotkey], event.type == .flagsChanged {
            updateState(isDown: event.modifierFlags.contains(targetMod))
        } else if let targetKey = Self.functionKeys[hotkey] {
            if event.type == .keyDown, event.keyCode == targetKey, !event.isARepeat {
                updateState(isDown: true)
            } else if event.type == .keyUp, event.keyCode == targetKey {
                updateState(isDown: false)
            }
        }
    }

    private func updateState(isDown: Bool) {
        if isDown, pressedAt == nil {
            pressedAt = clock.now
            onPress?()
        } else if !isDown, let start = pressedAt {
            let held = clock.now - start
            pressedAt = nil
            onRelease?(held)
        }
    }
}
```

- [ ] **Step 2: Paket bauen**

Run: `cd VoiceTypeCore && swift build`
Expected: `Build complete!`

- [ ] **Step 3: Tests ausführen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle Tests grün.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add HotkeyMonitor for global push-to-talk"
```

---

## Task 9: FocusInspector & TextOutput (Accessibility API)

System-Integration — bauen + manueller Smoke-Test in Task 10.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/FocusInspector.swift`
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/TextOutput.swift`

- [ ] **Step 1: FocusInspector implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/FocusInspector.swift`:

```swift
import AppKit
import ApplicationServices

/// Prüft on-demand, ob in der Vordergrund-App ein Textfeld den Fokus hat.
public struct FocusInspector: FocusInspecting {
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox",
    ]

    public init() {}

    public func isTextFieldFocused() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let element = focused else { return false }

        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element as! AXUIElement, kAXRoleAttribute as CFString, &role) == .success,
            let roleString = role as? String else { return false }

        return Self.editableRoles.contains(roleString)
    }
}
```

- [ ] **Step 2: TextOutput implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/TextOutput.swift`:

```swift
import AppKit
import ApplicationServices

/// Liefert Text aus: fügt ihn (falls gewünscht) ins fokussierte Feld der
/// Vordergrund-App ein und kopiert ihn in die Zwischenablage.
public struct TextOutput: TextDelivering {
    private let clipboardEnabled: Bool

    public init(clipboardEnabled: Bool = true) {
        self.clipboardEnabled = clipboardEnabled
    }

    public func deliver(_ text: String, pasteIntoFocusedField: Bool) {
        if pasteIntoFocusedField {
            insertIntoFocusedField(text)
        }
        if clipboardEnabled {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func insertIntoFocusedField(_ text: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let element = focused else { return }
        let axElement = element as! AXUIElement

        var current: CFTypeRef?
        let existing = (AXUIElementCopyAttributeValue(
            axElement, kAXValueAttribute as CFString, &current) == .success)
            ? (current as? String ?? "") : ""

        let newValue = existing.isEmpty ? text : existing + text
        AXUIElementSetAttributeValue(
            axElement, kAXValueAttribute as CFString, newValue as CFString)
    }
}
```

- [ ] **Step 3: Paket bauen und testen**

Run: `cd VoiceTypeCore && swift build && swift test`
Expected: `Build complete!` und alle Tests grün.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add FocusInspector and TextOutput via Accessibility API"
```

---

## Task 10: App-Shell — MenuBarExtra & Verdrahtung

Hier wird alles zusammengesteckt. Ergebnis: lauffähiges End-to-End-Diktat.
Das Menüleisten-Icon ist hier noch ein schlichtes statisches SF-Symbol
(animiertes grünes Wellenform-Icon kommt in Plan 3).

**Files:**
- Modify: `VoiceType/VoiceTypeApp.swift`
- Create: `VoiceType/MenuContentView.swift`

- [ ] **Step 1: MenuContentView erstellen**

Create `VoiceType/MenuContentView.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Inhalt des Menüleisten-Popovers: aktueller Status, letzte
/// Transkriptionen, Beenden.
struct MenuContentView: View {
    let appState: AppState

    private var statusText: String {
        switch appState.dictationState {
        case .loading:     return "Modell lädt…"
        case .idle:        return "Bereit — Hotkey halten zum Diktieren"
        case .recording:   return "Aufnahme läuft…"
        case .finalizing:  return "Verarbeite…"
        case .cleaning:    return "Verarbeite…"
        case .delivering:  return "Füge ein…"
        case .error(let m): return m
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !appState.log.isEmpty {
                Divider()
                Text("Zuletzt").font(.caption).foregroundStyle(.tertiary)
                ForEach(appState.log.prefix(3)) { entry in
                    Text(entry.text)
                        .font(.callout)
                        .lineLimit(2)
                }
            }

            Divider()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}
```

- [ ] **Step 2: VoiceTypeApp verdrahten**

Replace the contents of `VoiceType/VoiceTypeApp.swift`:

```swift
import SwiftUI
import VoiceTypeCore

@main
struct VoiceTypeApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: controller.appState)
        } label: {
            Image(systemName: controller.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Verdrahtet alle Kern-Bausteine und hält sie am Leben.
@MainActor
@Observable
final class AppController {
    let appState = AppState()
    private let settingsStore = SettingsStore()
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor

    init() {
        let settings = settingsStore.load()
        let audioCapture = AudioCapture()
        let engine = AppleSpeechEngine(
            audioCapture: audioCapture, language: settings.language)
        coordinator = DictationCoordinator(
            engine: engine,
            cleanup: PassthroughCleanup(),          // Plan 1: kein Cleanup
            delivery: TextOutput(clipboardEnabled: settings.clipboardCopy),
            focus: FocusInspector(),
            appState: appState)
        hotkey = HotkeyMonitor(hotkey: settings.pushToTalkKey)

        hotkey.onPress = { [coordinator] in coordinator.startDictation() }
        hotkey.onRelease = { [coordinator] held in
            coordinator.endDictation(heldFor: held)
        }

        Task {
            await coordinator.prepare()
            hotkey.start()
        }
    }

    /// Statisches SF-Symbol je Zustand (Animation kommt in Plan 3).
    var menuBarSymbol: String {
        switch appState.dictationState {
        case .recording:            return "waveform.circle.fill"
        case .loading, .error:      return "waveform.circle"
        default:                    return "waveform"
        }
    }
}
```

- [ ] **Step 3: App bauen**

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Manueller Smoke-Test — Berechtigungen erteilen**

App in Xcode mit ⌘R starten. Beim ersten Diktatversuch fragt macOS nach
**Mikrofon**-Zugriff → erlauben. Für den globalen Hotkey:
`Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen` → die
laufende `VoiceType.app` hinzufügen und aktivieren. App neu starten.

- [ ] **Step 5: Manueller Smoke-Test — End-to-End-Diktat**

1. TextEdit öffnen, ins Dokument klicken.
2. Push-to-Talk-Taste (`fn`) gedrückt halten, einen Satz sprechen, loslassen.
3. Erwartung: nach kurzer Zeit erscheint der erkannte Text in TextEdit und
   liegt zusätzlich in der Zwischenablage. Das Menüleisten-Symbol wechselt
   während der Aufnahme zu `waveform.circle.fill`.
4. Kurzes Antippen der Taste (<0,3 s) → es passiert nichts (verworfen).

Falls Text nicht eingefügt wird, aber in der Zwischenablage liegt:
Bedienungshilfen-Berechtigung prüfen (Step 4).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: wire MenuBarExtra app shell — end-to-end dictation works"
```

---

## Task 11: Berechtigungs-Onboarding

Sanfter Umgang mit fehlenden Berechtigungen statt stillem Versagen (Spec).

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/Permissions.swift`
- Create: `VoiceType/PermissionsView.swift`
- Modify: `VoiceType/VoiceTypeApp.swift`

- [ ] **Step 1: Permissions-Helfer implementieren**

Create `VoiceTypeCore/Sources/VoiceTypeCore/Permissions.swift`:

```swift
import AVFoundation
import ApplicationServices

public enum PermissionStatus: Equatable, Sendable {
    case granted, denied, notDetermined
}

/// Liest und (für Mikrofon) erfragt die nötigen Berechtigungen.
public struct Permissions: Sendable {
    public init() {}

    public func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default:    return .denied
        }
    }

    public func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
    }

    /// Accessibility kann nicht programmatisch erfragt werden — nur geprüft.
    public func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .denied
    }

    public var allGranted: Bool {
        microphoneStatus() == .granted && accessibilityStatus() == .granted
    }
}
```

- [ ] **Step 2: PermissionsView erstellen**

Create `VoiceType/PermissionsView.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Wird im Popover gezeigt, solange Berechtigungen fehlen.
struct PermissionsView: View {
    let permissions: Permissions
    let onRecheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Berechtigungen nötig")
                .font(.headline)

            row("Mikrofon", permissions.microphoneStatus(),
                hint: "Für die Sprachaufnahme.")
            row("Bedienungshilfen", permissions.accessibilityStatus(),
                hint: "Für den globalen Hotkey und das Einfügen von Text. "
                    + "In Systemeinstellungen → Datenschutz & Sicherheit → "
                    + "Bedienungshilfen aktivieren.")

            Button("Systemeinstellungen öffnen") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            Button("Erneut prüfen", action: onRecheck)
        }
        .padding(12)
        .frame(width: 300)
    }

    @ViewBuilder
    private func row(_ name: String, _ status: PermissionStatus, hint: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: status == .granted
                ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(status == .granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.callout).bold()
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 3: AppController & App um Berechtigungs-Gate erweitern**

In `VoiceType/VoiceTypeApp.swift` — im `AppController` ein `Permissions`-Feld
und ein beobachtbares Flag ergänzen, und `init` so anpassen, dass Mikrofon
angefragt und der Hotkey nur bei erteilten Rechten gestartet wird:

```swift
// in AppController, neue Properties:
let permissions = Permissions()
var permissionsGranted = false

// init: den Task-Block ersetzen durch:
Task {
    if permissions.microphoneStatus() == .notDetermined {
        _ = await permissions.requestMicrophone()
    }
    recheckPermissions()
}

// neue Methode:
func recheckPermissions() {
    permissionsGranted = permissions.allGranted
    guard permissionsGranted else { return }
    Task {
        await coordinator.prepare()
        hotkey.start()
    }
}
```

Und in `VoiceTypeApp.body` den Popover-Inhalt umschalten:

```swift
MenuBarExtra {
    if controller.permissionsGranted {
        MenuContentView(appState: controller.appState)
    } else {
        PermissionsView(
            permissions: controller.permissions,
            onRecheck: { controller.recheckPermissions() })
    }
} label: {
    Image(systemName: controller.menuBarSymbol)
}
.menuBarExtraStyle(.window)
```

- [ ] **Step 4: App bauen**

Run: `xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Manueller Smoke-Test**

1. Bedienungshilfen-Recht für `VoiceType.app` testweise entziehen, App starten.
   → Popover zeigt `PermissionsView` mit oranger Markierung bei
   „Bedienungshilfen".
2. Recht wieder erteilen, „Erneut prüfen" klicken → Popover wechselt zu
   `MenuContentView`, Diktat funktioniert wieder.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add permissions onboarding for microphone and accessibility"
```

---

## Abschluss Plan 1

Nach Task 11 ist eine vollständig nutzbare App vorhanden: Push-to-Talk →
Sprache → Rohtext wird eingefügt und kopiert; Berechtigungen werden sauber
behandelt; die gesamte Kern-Logik ist per Swift Testing abgedeckt.

**Was bewusst noch fehlt (folgt in eigenen Plänen):**
- **Plan 2 — Text-Cleanup:** `FoundationModelCleanup` (Apple `FoundationModels`)
  ersetzt `PassthroughCleanup`; Edge Case „Foundation Model nicht verfügbar".
- **Plan 3 — UI-Politur:** animiertes grünes Wellenform-Icon in der
  Menüleiste, Overlay unten zentriert mit Live-Text, Seitenleisten-Fenster
  mit Verlauf & Einstellungen.

---

## Self-Review

**Spec-Abdeckung (Plan 1):**
- Stack (Swift/SwiftUI/MenuBarExtra) → Task 1, 10 ✓
- `SpeechTranscriber`-Engine hinter Protokoll → Task 4 (Protokoll), 7 (Impl) ✓
- Engine austauschbar → `TranscriptionEngine`-Protokoll, Task 4 ✓
- `AVAudioEngine`-Audio → Task 6 ✓
- Globaler Hotkey / Push-to-Talk → Task 8, 10 ✓
- `AppState` als Single Source of Truth → Task 3 ✓
- `DictationCoordinator`-Zustandsmaschine → Task 5 ✓
- Edge Cases (kurzer Druck, leeres Transkript, Fokus-Snapshot, Engine-Fehler)
  → Task 5 Tests ✓
- `TextOutput` (Accessibility + Clipboard), `FocusInspector` → Task 9 ✓
- `SettingsStore` → Task 2 ✓
- Berechtigungen sanft behandeln → Task 11 ✓
- Verteilung als `.app` mit Entitlements → Task 1 ✓
- Tests mit Swift Testing + Mocks → Task 2–5 ✓
- *Cleanup* und *feine UI* → bewusst Plan 2/3, oben dokumentiert ✓

**Platzhalter-Scan:** Keine TBD/TODO. Jeder Code-Schritt enthält vollständigen
Code; Task 6–9 sind als System-Integration ohne Unit-Test gekennzeichnet
(konsistent mit dem Spec), mit „bauen + Regression + manueller Smoke-Test".

**Typ-Konsistenz:** `TranscriptionEngine` (prepare/start/stop),
`TranscriptionUpdate` (text/isFinal), `DictationState`, `AppState.addEntry`,
`CapturedAudio` (pcmBuffer/level), `TextDelivering.deliver(_:pasteIntoFocusedField:)`,
`FocusInspecting.isTextFieldFocused()` — über alle Tasks hinweg einheitlich
verwendet. `Settings.clipboardCopy` ist in Task 2 definiert und wird in Task 10
gelesen.
