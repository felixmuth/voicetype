# VoiceType — Plan 2: Text-Cleanup mit Apple Foundation Models — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Den `PassthroughCleanup` aus Plan 1 durch ein echtes `FoundationModelCleanup` ersetzen, das diktierten Rohtext per Apples lokalem Foundation Model **mechanisch** bereinigt (Füllwörter raus, Zeichensetzung, Groß-/Kleinschreibung) — ohne Wortlaut oder Satzbau anzutasten.

**Architecture:** Eine neue `FoundationModelCleanup`-Struktur im `VoiceTypeCore`-Paket kapselt die `FoundationModels`-API hinter dem bestehenden `TextCleanup`-Protokoll. Verfügbarkeit, Timeout und Sanity-Check sind interne Belange; die reine `acceptedOutput`-Hilfsfunktion ist unit-testbar. `AppController` wählt die Cleanup-Implementierung beim Start anhand von `settings.cleanupEnabled` und reicht den Verfügbarkeits-Hinweis an `MenuContentView` durch (analog zum bestehenden `onRetry`).

**Tech Stack:** Swift 6, Apple `FoundationModels`-Framework (macOS 26), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-05-15-voicetype-cleanup-design.md`

> ⚠️ **Neue API** (Task 2): `FoundationModels` ist eine macOS-26-API ohne breite Community-Beispiele. Der Code unten basiert auf Apple-Doku & WWDC25. Falls eine Signatur abweicht (besonders `SystemLanguageModel.default.availability`-Enum, `LanguageModelSession`-Init, `respond(to:)`-Rückgabe), in Xcode Quick Help (⌥-Klick) prüfen und anpassen. Struktur (Verfügbarkeits-Prüfung → frische Session → respond mit Timeout → `acceptedOutput`-Check → Fallback) bleibt.

---

## Dateistruktur

```
voicetype/.worktrees/plan-2-cleanup/
├── VoiceTypeCore/
│   ├── Sources/VoiceTypeCore/
│   │   └── FoundationModelCleanup.swift     # NEU — Task 1 (acceptedOutput), Task 2 (vollständig)
│   └── Tests/VoiceTypeCoreTests/
│       └── FoundationModelCleanupTests.swift # NEU — Task 1
└── VoiceType/VoiceType/
    ├── MenuContentView.swift                # MODIFIZIERT — Task 3 (cleanupHint-Parameter + Anzeige)
    └── VoiceTypeApp.swift                   # MODIFIZIERT — Task 4 (AppController wählt Cleanup + reicht Hinweis durch)
```

---

## Task 1: `acceptedOutput`-Hilfsfunktion (TDD)

Die reine Akzeptanz-Logik (entscheidet, ob die Modell-Ausgabe übernommen oder auf den Rohtext zurückgefallen wird) ist das einzige unit-testbare Stück von Plan 2. Wir bauen sie isoliert per TDD, bevor in Task 2 der `FoundationModels`-Aufruf dazukommt.

**Files:**
- Create: `VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/FoundationModelCleanupTests.swift`

- [ ] **Step 1: Failing tests schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/FoundationModelCleanupTests.swift`:

```swift
import Testing
@testable import VoiceTypeCore

@Suite struct FoundationModelCleanupTests {

    @Test func acceptsNormalOutputTrimmed() {
        let raw = "das ist ein Test"
        let modelOutput = "  Das ist ein Test.  "
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: raw, modelOutput: modelOutput) == "Das ist ein Test.")
    }

    @Test func emptyOutputFallsBackToRaw() {
        let raw = "das ist ein Test"
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: raw, modelOutput: "") == raw)
    }

    @Test func whitespaceOnlyOutputFallsBackToRaw() {
        let raw = "das ist ein Test"
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: raw, modelOutput: "   \n  ") == raw)
    }

    @Test func tooShortOutputFallsBackToRaw() {
        // raw 40 Zeichen, Modell-Ausgabe 10 Zeichen → cleanedLen*2 (20) < rawLen (40) → Fallback
        let raw = String(repeating: "a", count: 40)
        let modelOutput = String(repeating: "b", count: 10)
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: raw, modelOutput: modelOutput) == raw)
    }

    @Test func tooLongOutputFallsBackToRaw() {
        // raw 10 Zeichen, Modell-Ausgabe 30 Zeichen → 30 > rawLen*2 (20) → Fallback
        let raw = String(repeating: "a", count: 10)
        let modelOutput = String(repeating: "b", count: 30)
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: raw, modelOutput: modelOutput) == raw)
    }

    @Test func boundaryRatioIsAccepted() {
        // raw 10 Zeichen, Modell-Ausgabe 5 Zeichen → 5*2 == 10 (nicht < 10) → akzeptiert
        let raw = String(repeating: "a", count: 10)
        let modelOutput = String(repeating: "b", count: 5)
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: raw, modelOutput: modelOutput) == modelOutput)
    }

    @Test func emptyRawReturnsEmptyRaw() {
        // Edge Case: leerer Rohtext → Rohtext zurück, Modell-Ausgabe ignoriert.
        #expect(FoundationModelCleanup.acceptedOutput(
            raw: "", modelOutput: "anything") == "")
    }
}
```

- [ ] **Step 2: Tests ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter FoundationModelCleanupTests`
Expected: FAIL — `cannot find 'FoundationModelCleanup' in scope`.

- [ ] **Step 3: Minimal-Implementierung schreiben**

Create `VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift`:

```swift
import Foundation

/// Bereinigt diktierten Rohtext mechanisch über Apples Foundation Models
/// (macOS 26, on-device). Die volle TextCleanup-Konformität (cleanup,
/// availabilityHint) wird in Task 2 ergänzt; hier zunächst nur die reine
/// Akzeptanz-Hilfsfunktion, damit sie isoliert getestet werden kann.
public struct FoundationModelCleanup {

    public init() {}

    /// Pure: entscheidet, ob die Modell-Ausgabe akzeptiert wird.
    /// - Leere oder reine Whitespace-Ausgabe → Rohtext
    /// - Längenverhältnis < 50 % oder > 200 % der Rohlänge → Rohtext
    /// - Sonst → getrimmte Modell-Ausgabe
    static func acceptedOutput(raw: String, modelOutput: String) -> String {
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

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter FoundationModelCleanupTests`
Expected: PASS — 7 tests passed.

- [ ] **Step 5: Gesamtes Paket testen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle bisherigen Tests plus die 7 neuen FoundationModelCleanup-Tests (insgesamt 20 Tests aus 5 Suites) sind grün.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add FoundationModelCleanup acceptedOutput helper with full TDD coverage"
```

---

## Task 2: `FoundationModelCleanup` — `TextCleanup`-Konformität mit Apple Foundation Models

System-Integration: füllt `availabilityHint` und `cleanup(_:)` mit der echten `FoundationModels`-API. Ein lokaler `withTimeout`-Helfer setzt die 5-Sekunden-Sicherheitsgrenze.

> ⚠️ **Neue macOS-26-API.** Falls Signaturen abweichen, verifizieren und anpassen — Struktur (prepare/check availability → frische Session pro Aufruf → respond mit Timeout → `acceptedOutput` → Fallback auf jeder Stufe) muss bleiben.

**Files:**
- Modify: `VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift`

- [ ] **Step 1: Datei vollständig überschreiben**

Overwrite `VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift` with EXACTLY:

```swift
import Foundation
import FoundationModels

/// Bereinigt diktierten Rohtext mechanisch über Apples Foundation Models
/// (macOS 26, on-device). Fällt bei jedem Problem auf den Rohtext zurück —
/// `cleanup(_:)` wirft nie.
public struct FoundationModelCleanup: TextCleanup {

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

    private static let timeoutSeconds: Double = 5

    public init() {}

    /// `nil` = Modell verfügbar. Sonst deutscher Hinweistext für die UI.
    public var availabilityHint: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .appleIntelligenceNotEnabled:
                return "Cleanup nicht verfügbar — Apple Intelligence aktivieren."
            case .deviceNotEligible:
                return "Cleanup nicht verfügbar — auf diesem Gerät nicht unterstützt."
            case .modelNotReady:
                return "Cleanup nicht verfügbar — Modell lädt noch."
            @unknown default:
                return "Cleanup nicht verfügbar."
            }
        }
    }

    public func cleanup(_ raw: String) async -> String {
        // Modell-Verfügbarkeit vor jedem Aufruf prüfen — bei „nicht verfügbar"
        // sofort Rohtext zurück, ohne respond zu versuchen.
        guard case .available = SystemLanguageModel.default.availability else {
            return raw
        }
        do {
            let modelOutput = try await withTimeout(seconds: Self.timeoutSeconds) {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(to: raw)
                return response.content
            }
            return Self.acceptedOutput(raw: raw, modelOutput: modelOutput)
        } catch {
            // Timeout, GenerationError, oder beliebiger Systemfehler →
            // sanfte Degradierung auf den unveränderten Rohtext.
            return raw
        }
    }

    /// Pure: entscheidet, ob die Modell-Ausgabe akzeptiert wird.
    /// - Leere oder reine Whitespace-Ausgabe → Rohtext
    /// - Längenverhältnis < 50 % oder > 200 % der Rohlänge → Rohtext
    /// - Sonst → getrimmte Modell-Ausgabe
    static func acceptedOutput(raw: String, modelOutput: String) -> String {
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

private enum CleanupError: Error { case timeout }

/// Führt eine async-Operation mit Timeout aus. Wer zuerst fertig wird,
/// gewinnt; der jeweils andere Task wird gecancelt. Bei Überschreitung
/// wirft die Funktion `CleanupError.timeout`.
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
        guard let result = try await group.next() else {
            throw CleanupError.timeout
        }
        group.cancelAll()
        return result
    }
}
```

- [ ] **Step 2: Paket bauen**

Run: `cd VoiceTypeCore && swift build`
Expected: `Build complete!`

Falls Compiler-Fehler zu `SystemLanguageModel`, `LanguageModelSession` oder Verfügbarkeits-Enum-Cases auftauchen: Signaturen im Xcode SDK-Interface verifizieren (z. B. `find /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/FoundationModels.framework -name "*.swiftinterface"`) und anpassen — die Struktur des `cleanup(_:)`-Flows muss erhalten bleiben. Falls eine `@available(macOS 26.0, *)`-Annotation gefordert wird, an die `FoundationModelCleanup`-Struktur kleben.

- [ ] **Step 3: Tests ausführen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 20 Tests grün (die `acceptedOutput`-Tests aus Task 1 plus alle Plan-1-Tests).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: implement FoundationModelCleanup with FoundationModels and timeout"
```

---

## Task 3: `MenuContentView` zeigt den Cleanup-Hinweis

`MenuContentView` bekommt einen neuen Parameter `cleanupHint: String?` mit Default `nil` (so dass der bestehende Aufrufer in Task 10 von Plan 1 weiterhin baut). Der Hinweis erscheint als dezente orange Caption-Zeile direkt unter der Statuszeile.

**Files:**
- Modify: `VoiceType/VoiceType/MenuContentView.swift`

- [ ] **Step 1: Datei vollständig überschreiben**

Overwrite `VoiceType/VoiceType/MenuContentView.swift` with EXACTLY:

```swift
import SwiftUI
import VoiceTypeCore

/// Inhalt des Menüleisten-Popovers: aktueller Status, letzte
/// Transkriptionen, Beenden — plus optional ein dezenter Hinweis, wenn
/// das Cleanup-Modell nicht verfügbar ist.
struct MenuContentView: View {
    let appState: AppState
    let onRetry: () -> Void
    let cleanupHint: String? = nil

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

    private var isError: Bool {
        if case .error = appState.dictationState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)

            if isError {
                Button("Erneut versuchen", action: onRetry)
            }

            if let cleanupHint {
                Text(cleanupHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

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

Hinweis: `cleanupHint` hat Default `nil`, damit der bestehende Aufruf in `VoiceTypeApp.swift` (`MenuContentView(appState:onRetry:)` aus Plan 1) ohne Änderung weiter baut. Task 4 ergänzt dort den expliziten Aufruf mit Hinweis.

- [ ] **Step 2: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-2-cleanup/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 20 Tests grün.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: MenuContentView accepts and displays optional cleanup hint"
```

---

## Task 4: `AppController` wählt das Cleanup und reicht den Hinweis durch

Hier wird Plan 2 lebendig: `AppController` wählt anhand von `settings.cleanupEnabled` zwischen `FoundationModelCleanup` und `PassthroughCleanup`, fragt einmal den Verfügbarkeits-Hinweis ab und gibt ihn an `MenuContentView` weiter.

**Files:**
- Modify: `VoiceType/VoiceType/VoiceTypeApp.swift`

- [ ] **Step 1: Datei vollständig überschreiben**

Overwrite `VoiceType/VoiceType/VoiceTypeApp.swift` with EXACTLY:

```swift
import SwiftUI
import VoiceTypeCore

@main
struct VoiceTypeApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            if controller.permissionsGranted {
                MenuContentView(
                    appState: controller.appState,
                    onRetry: { controller.retry() },
                    cleanupHint: controller.cleanupHint)
            } else {
                PermissionsView(
                    permissions: controller.permissions,
                    onRecheck: { controller.recheckPermissions() })
            }
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
    let permissions = Permissions()
    let cleanupHint: String?
    var permissionsGranted = false
    private let settingsStore = SettingsStore()
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor

    init() {
        let settings = settingsStore.load()
        let audioCapture = AudioCapture()
        let engine = AppleSpeechEngine(
            audioCapture: audioCapture, language: settings.language)

        // Cleanup-Implementierung wählen und Verfügbarkeits-Hinweis erfassen.
        // Plan 2: Bei aktiviertem Cleanup nutzen wir FoundationModelCleanup,
        // das intern auf Rohtext zurückfällt, wenn das Modell nicht verfügbar
        // ist — und parallel den Hinweis liefert, den die UI anzeigt.
        let cleanup: TextCleanup
        let hint: String?
        if settings.cleanupEnabled {
            let fmCleanup = FoundationModelCleanup()
            hint = fmCleanup.availabilityHint
            cleanup = fmCleanup
        } else {
            hint = nil
            cleanup = PassthroughCleanup()
        }
        cleanupHint = hint

        coordinator = DictationCoordinator(
            engine: engine,
            cleanup: cleanup,
            delivery: TextOutput(clipboardEnabled: settings.clipboardCopy),
            focus: FocusInspector(),
            appState: appState)
        hotkey = HotkeyMonitor(hotkey: settings.pushToTalkKey)

        hotkey.onPress = { [coordinator] in coordinator.startDictation() }
        hotkey.onRelease = { [coordinator] held in
            coordinator.endDictation(heldFor: held)
        }

        Task {
            if permissions.microphoneStatus() == .notDetermined {
                _ = await permissions.requestMicrophone()
            }
            recheckPermissions()
        }
    }

    /// Prüft die Berechtigungen neu; bei vollständiger Freigabe wird die
    /// Engine vorbereitet und der Hotkey-Monitor gestartet.
    func recheckPermissions() {
        permissionsGranted = permissions.allGranted
        guard permissionsGranted else { return }
        Task {
            await coordinator.prepare()
            hotkey.start()
        }
    }

    /// Erholung aus dem .error-Zustand: Engine erneut vorbereiten.
    func retry() {
        Task { await coordinator.prepare() }
    }

    /// Statisches SF-Symbol je Zustand (Animation kommt in einem späteren Plan).
    var menuBarSymbol: String {
        switch appState.dictationState {
        case .recording:            return "waveform.circle.fill"
        case .loading, .error:      return "waveform.circle"
        default:                    return "waveform"
        }
    }
}
```

- [ ] **Step 2: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-2-cleanup/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 20 Tests grün.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire FoundationModelCleanup in AppController, pass hint to MenuContentView"
```

- [ ] **Step 5: Manueller Smoke-Test**

(Vom Subagent NICHT auszuführen — braucht eine GUI-Sitzung und einen Menschen.)

1. App in Xcode mit ⌘R starten (oder aus Build-Folder).
2. **Mit Apple Intelligence aktiv:** Diktat in TextEdit ausführen — der ausgegebene Text sollte gegenüber Plan 1 sichtbar bereinigt sein (Füllwörter weg, Zeichensetzung, Groß-/Kleinschreibung), Wortlaut bleibt erkennbar. Im Popover steht **kein** Cleanup-Hinweis.
3. **Mit Apple Intelligence aus** (System-Einstellungen → Apple Intelligence & Siri → ausschalten, dann App neu starten): Diktat sollte den Rohtext liefern; das Popover zeigt eine orange Caption-Zeile „Cleanup nicht verfügbar — Apple Intelligence aktivieren."

---

## Abschluss Plan 2

Nach Task 4 läuft das Diktat-Erlebnis nahe am Wispr-Flow-Standard: gesprochener Text → bereinigt → eingefügt. Die Architektur ist wieder so isoliert wie in Plan 1 (das `TextCleanup`-Protokoll, der Coordinator und `AppState` blieben unangetastet).

**Was bewusst noch fehlt (folgt in Plan 3):**
- **Plan 3 — UI-Politur:** animiertes grünes Wellenform-Icon, Overlay unten zentriert mit Live-Text, Seitenleisten-Fenster mit Verlauf & Einstellungen (inkl. UI-Toggle für `cleanupEnabled`).

**Plan-1-Lücken, die separat zu adressieren sind** (im Plan 1 Code dokumentiert):
- Paralleles Diktat während Cleanup/Delivery — wird im Plan-2-Kontext spürbarer (echtes Cleanup dauert länger als `PassthroughCleanup`); separater Fix nötig.
- Cursor-genaues Einfügen statt Anhängen.

---

## Self-Review

**Spec-Abdeckung (Plan 2):**
- Cleanup-Tiefe „nur Mechanik" → Anweisungstext in Task 2 ✓
- `FoundationModelCleanup` mit Sanity-Check + Timeout + Fallback → Task 2 ✓
- `acceptedOutput`-Hilfsfunktion testbar → Task 1 ✓
- Verfügbarkeits-Hinweis → Task 2 (`availabilityHint`), Task 3 (Anzeige), Task 4 (Verdrahtung) ✓
- `MenuContentView` zeigt den Hinweis dezent → Task 3 ✓
- `AppController` wählt Cleanup anhand von `settings.cleanupEnabled` → Task 4 ✓
- `TextCleanup`-Protokoll und `DictationCoordinator` unangetastet → keine Modifikation in irgendeinem Task ✓
- Frische `LanguageModelSession` pro Aufruf → in `cleanup(_:)` (Task 2) ✓

**Platzhalter-Scan:** Keine TBD/TODO. Jeder Code-Block ist vollständig. Task 1 ist voll TDD; Task 2 ist System-Integration (kein Unit-Test) mit klarem API-Verifikations-Hinweis; Tasks 3 & 4 sind UI-Verdrahtung mit Build + Regression.

**Typ-Konsistenz:** `FoundationModelCleanup` ist überall derselbe `public struct`; `acceptedOutput(raw:modelOutput:)` hat dieselbe Signatur in Task 1 und Task 2; `MenuContentView`s `cleanupHint: String?` ist konsistent zwischen Task 3 (Deklaration) und Task 4 (Aufruf); `AppController.cleanupHint: String?` ebenso.
