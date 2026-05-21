# VoiceType — Plan 3: UI-Politur — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drei sichtbare UI-Bausteine bauen — animiertes grünes Wellenform-Icon in der Menüleiste, klick-durchlässiges Aufnahme-Overlay unten zentriert mit Live-Text, und ein Hauptfenster mit Seitenleiste (Verlauf + Einstellungen inkl. Hotkey-Capture und SMAppService-Login). Das Menüleisten-Popover wird zur schlanken Quick-Glance-View zurückgestutzt.

**Architecture:** SwiftUI durchgehend, mit kleinem AppKit-Touch nur fürs klick-durchlässige Overlay-Fenster (`NSPanel` mit `ignoresMouseEvents = true`, hosted via `NSHostingView`). Pegel-Plumbing über einen neuen `AudioCapturing.onLevel`-Callback → `DictationCoordinator.updateMicLevel(_:)` → `appState.micLevel`. Architektur-Invariante „nur der Coordinator mutiert AppState" bleibt gewahrt.

**Tech Stack:** Swift 6, SwiftUI (`MenuBarExtra`, `Window`, `NavigationSplitView`, `TimelineView`, `@Environment(\.openWindow)`), AppKit (`NSPanel`, `NSHostingView`, `withObservationTracking`), `SMAppService` (Login-at-Login, macOS 13+).

**Spec:** `docs/superpowers/specs/2026-05-15-voicetype-ui-polish-design.md`

---

## Dateistruktur

```
voicetype/.worktrees/plan-3-ui-polish/
├── VoiceTypeCore/
│   ├── Sources/VoiceTypeCore/
│   │   ├── Protocols.swift              # MOD — AudioCapturing.onLevel-Property (Task 1)
│   │   ├── AudioCapture.swift           # MOD — onLevel im Tap-Callback aufrufen (Task 1)
│   │   ├── DictationCoordinator.swift   # MOD — updateMicLevel(_:) (Task 1)
│   │   └── HotkeyMonitor.swift          # MOD — startCapture/stopCapture/onCaptured (Task 2)
│   └── Tests/VoiceTypeCoreTests/
│       ├── DictationCoordinatorTests.swift  # MOD — 1 Test für updateMicLevel (Task 1)
│       └── HotkeyMonitorTests.swift     # NEU — Tests für hotkeyName(forEvent:) (Task 2)
└── VoiceType/VoiceType/
    ├── WaveformIcon.swift               # NEU — Task 3
    ├── OverlayContent.swift             # NEU — Task 5
    ├── OverlayWindowController.swift    # NEU — Task 5
    ├── MainView.swift                   # NEU — Task 6
    ├── HistoryView.swift                # NEU — Task 6
    ├── SettingsView.swift               # NEU — Task 7
    ├── MenuContentView.swift            # MOD — schlanker Refactor (Task 8)
    └── VoiceTypeApp.swift               # MOD — schrittweise in Tasks 4, 5, 6, 7, 9
```

Optional kleine Helfer-Datei in `VoiceTypeCore` für die Bar-Höhen-Formel — wird in Task 3 entschieden (extraherter pure-func oder inline).

---

## Task 1: Mic-Level-Plumbing

`AudioCapturing` bekommt eine `onLevel`-Callback-Property; `AudioCapture` ruft sie im Tap-Callback auf; `DictationCoordinator.updateMicLevel(_:)` schreibt den Wert in `appState.micLevel`. Reiner-Logik-Teil per TDD.

**Files:**
- Modify: `VoiceTypeCore/Sources/VoiceTypeCore/Protocols.swift`
- Modify: `VoiceTypeCore/Sources/VoiceTypeCore/AudioCapture.swift`
- Modify: `VoiceTypeCore/Sources/VoiceTypeCore/DictationCoordinator.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/DictationCoordinatorTests.swift`

- [ ] **Step 1: Failing test schreiben**

Am Ende von `DictationCoordinatorTests.swift` (innerhalb des `@Suite struct DictationCoordinatorTests`-Bodys, vor der schließenden Klammer), diesen Test ergänzen:

```swift
    @Test func updateMicLevelWritesToAppState() {
        let (coordinator, appState, _, _, _, _) = makeCoordinator()
        coordinator.updateMicLevel(0.42)
        #expect(appState.micLevel == 0.42)
        coordinator.updateMicLevel(0)
        #expect(appState.micLevel == 0)
    }
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter DictationCoordinatorTests.updateMicLevelWritesToAppState`
Expected: FAIL — `value of type 'DictationCoordinator' has no member 'updateMicLevel'`.

- [ ] **Step 3: `updateMicLevel` zum Coordinator hinzufügen**

In `VoiceTypeCore/Sources/VoiceTypeCore/DictationCoordinator.swift`, direkt vor dem Ende der `DictationCoordinator`-Klasse (nach `finishAfterStream`-Implementation, vor der schließenden Klasse-Klammer), diese Methode einfügen:

```swift
    /// Mikrofonpegel-Update. Wird vom `onLevel`-Callback der
    /// `AudioCapturing`-Implementierung über den `AppController`
    /// hier durchgereicht — so bleibt die Invariante „nur der
    /// Coordinator mutiert AppState" gewahrt.
    public func updateMicLevel(_ level: Float) {
        appState.micLevel = level
    }
```

- [ ] **Step 4: Test ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter DictationCoordinatorTests.updateMicLevelWritesToAppState`
Expected: PASS.

- [ ] **Step 5: `AudioCapturing`-Protokoll um `onLevel` erweitern**

In `VoiceTypeCore/Sources/VoiceTypeCore/Protocols.swift`, finde:

```swift
public protocol AudioCapturing: Sendable {
    func startStream() throws -> AsyncStream<CapturedAudio>
    func stop()
}
```

Ersetze durch:

```swift
public protocol AudioCapturing: AnyObject, Sendable {
    func startStream() throws -> AsyncStream<CapturedAudio>
    func stop()
    /// Optionaler Callback, der bei jedem Audio-Buffer mit dem aktuellen
    /// RMS-Pegel (0…1) aufgerufen wird. Erwartet auf MainActor.
    var onLevel: ((Float) -> Void)? { get set }
}
```

(`AnyObject` ist nötig, weil ein mutables `var`-Property in einem Protokoll eine Klassen-Anforderung impliziert; `AudioCapture` ist schon `final class`.)

- [ ] **Step 6: `AudioCapture` um die `onLevel`-Property erweitern**

In `VoiceTypeCore/Sources/VoiceTypeCore/AudioCapture.swift`, in der `AudioCapture`-Klasse, direkt nach `private var continuation: AsyncStream<CapturedAudio>.Continuation?`, diese Zeile ergänzen:

```swift
    public var onLevel: ((Float) -> Void)?
```

Dann den `installTap`-Callback-Body um den `onLevel`-Aufruf erweitern. Finde:

```swift
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = Self.rms(of: buffer)
            self?.continuation?.yield(CapturedAudio(pcmBuffer: buffer, level: level))
        }
```

Ersetze durch:

```swift
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = Self.rms(of: buffer)
            self?.continuation?.yield(CapturedAudio(pcmBuffer: buffer, level: level))
            // onLevel auf MainActor liefern — die Verbraucher sind UI-Bindings.
            DispatchQueue.main.async { self?.onLevel?(level) }
        }
```

- [ ] **Step 7: Paket bauen, alle Tests laufen lassen**

Run: `cd VoiceTypeCore && swift build && swift test`
Expected: `Build complete!` und alle Tests grün (21 bisherige + 1 neuer = 22). Falls Compiler-Fehler in anderen Dateien wegen der `AnyObject`-Ergänzung am Protokoll auftauchen: vermutlich nirgends, weil `AudioCapture` schon `final class` ist und das einzige `AudioCapturing` ist.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add mic-level plumbing (AudioCapturing.onLevel + DictationCoordinator.updateMicLevel)"
```

---

## Task 2: HotkeyMonitor-Capture-Erweiterung

Neue API für die spätere Settings-UI, um den Hotkey live umzustellen. Die reine Auflösung „NSEvent → Hotkey-Name" als pure static func extrahieren und unit-testen.

**Files:**
- Modify: `VoiceTypeCore/Sources/VoiceTypeCore/HotkeyMonitor.swift`
- Create: `VoiceTypeCore/Tests/VoiceTypeCoreTests/HotkeyMonitorTests.swift`

- [ ] **Step 1: Failing test schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/HotkeyMonitorTests.swift`:

```swift
import Testing
import AppKit
@testable import VoiceTypeCore

@MainActor
@Suite struct HotkeyMonitorTests {

    @Test func resolveModifierFn() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 0, modifierFlags: [.function], isKeyDown: false)
        #expect(result == "fn")
    }

    @Test func resolveModifierCmd() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 0, modifierFlags: [.command], isKeyDown: false)
        #expect(result == "cmd")
    }

    @Test func resolveFunctionKeyF13() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 105, modifierFlags: [], isKeyDown: true)
        #expect(result == "f13")
    }

    @Test func resolveFunctionKeyF1() {
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 122, modifierFlags: [], isKeyDown: true)
        #expect(result == "f1")
    }

    @Test func resolveUnknownReturnsNil() {
        // KeyCode 50 (`§`) ist nicht in den Function-Keys; ohne Modifier
        // gibt's nichts Passendes.
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 50, modifierFlags: [], isKeyDown: true)
        #expect(result == nil)
    }

    @Test func functionKeyOnKeyUpReturnsNil() {
        // Capture darf nur auf keyDown auslösen — nicht auf keyUp.
        let result = HotkeyMonitor.hotkeyName(
            keyCode: 105, modifierFlags: [], isKeyDown: false)
        #expect(result == nil)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter HotkeyMonitorTests`
Expected: FAIL — `type 'HotkeyMonitor' has no member 'hotkeyName'`.

- [ ] **Step 3: Pure-Helper-Funktion ergänzen**

In `VoiceTypeCore/Sources/VoiceTypeCore/HotkeyMonitor.swift`, direkt nach den beiden static-Dictionaries `modifierFlags` und `functionKeys` (vor `public init(hotkey:)`), diese pure helper ergänzen:

```swift
    /// Auflösung „NSEvent-Eigenschaften → Hotkey-Name". Pure, testbar.
    /// - `keyCode`: nur relevant für Funktionstasten (F1–F20), nutzt
    ///   `isKeyDown == true` als Filter (Capture nimmt nur keyDown an).
    /// - `modifierFlags`: relevant für Modifier-Tasten (fn, cmd, shift, …).
    /// - Rückgabe: passender Hotkey-Name oder `nil`, falls nichts matcht.
    public static func hotkeyName(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isKeyDown: Bool
    ) -> String? {
        // Modifier hat Vorrang — Funktionstasten kommen nur in Betracht,
        // wenn KEIN reiner Modifier vorliegt.
        for (name, bit) in Self.modifierFlags where modifierFlags.contains(bit) {
            return name
        }
        guard isKeyDown else { return nil }
        for (name, code) in Self.functionKeys where code == keyCode {
            return name
        }
        return nil
    }
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter HotkeyMonitorTests`
Expected: PASS — 6 tests passed.

- [ ] **Step 5: Capture-API auf der Instanz ergänzen**

In `VoiceTypeCore/Sources/VoiceTypeCore/HotkeyMonitor.swift`, in der `HotkeyMonitor`-Klasse, finde die Property-Deklarationen:

```swift
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isStarted = false
    private var pressedAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var hotkey: String

    public var onPress: (() -> Void)?
    public var onRelease: ((Duration) -> Void)?
```

Ersetze durch (vier neue Zeilen):

```swift
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var captureGlobalMonitor: Any?
    private var captureLocalMonitor: Any?
    private var isStarted = false
    private var pressedAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private var hotkey: String

    public var onPress: (() -> Void)?
    public var onRelease: ((Duration) -> Void)?
    public var onCaptured: ((String) -> Void)?
```

Dann am Ende der Klasse (vor der schließenden Klammer der Klasse), diese zwei Methoden ergänzen:

```swift
    /// Beginnt einen Capture-Modus: globale Tastendrücke werden
    /// abgefangen, der erste passende Modifier oder F-Key wird per
    /// `onCaptured` zurückgegeben. Stoppt sich danach selbst.
    public func startCapture() {
        guard captureGlobalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        captureGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleCapture(event)
        }
        captureLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleCapture(event)
            return event
        }
    }

    public func stopCapture() {
        if let captureGlobalMonitor { NSEvent.removeMonitor(captureGlobalMonitor) }
        if let captureLocalMonitor { NSEvent.removeMonitor(captureLocalMonitor) }
        captureGlobalMonitor = nil
        captureLocalMonitor = nil
    }

    private func handleCapture(_ event: NSEvent) {
        let name = Self.hotkeyName(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isKeyDown: event.type == .keyDown)
        if let name {
            onCaptured?(name)
            stopCapture()
        }
    }
```

- [ ] **Step 6: Paket bauen, alle Tests laufen lassen**

Run: `cd VoiceTypeCore && swift build && swift test`
Expected: `Build complete!` und alle 28 Tests grün (22 bisherige + 6 neue HotkeyMonitor-Tests).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add HotkeyMonitor capture API (startCapture/stopCapture/onCaptured)"
```

---

## Task 3: `WaveformIcon`-View

Reine SwiftUI-View für die fünf Balken. Die Bar-Höhen-Formel als pure-static-func extrahieren und unit-testen.

**Files:**
- Create: `VoiceType/VoiceType/WaveformIcon.swift`
- Test: `VoiceTypeCore/Tests/VoiceTypeCoreTests/WaveformIconMathTests.swift`
- Modify: `VoiceTypeCore/Sources/VoiceTypeCore/AppState.swift` (kein Touch — es wird über `DictationState`/`Float` als Eingaben verwendet)

Hinweis: die pure-helper liegt in einer **Core-Test-Datei**, weil sie nur Float-Arithmetik testet — keine SwiftUI-Abhängigkeit. Sie wird im View aber als `BarHeight.heights(...)` aufgerufen — siehe Step 3.

- [ ] **Step 1: Failing test schreiben**

Create `VoiceTypeCore/Tests/VoiceTypeCoreTests/WaveformIconMathTests.swift`:

```swift
import Testing
@testable import VoiceTypeCore

@Suite struct WaveformIconMathTests {

    @Test func inactiveProducesThreeFlatBars() {
        let h = BarHeight.heights(active: false, recording: false, level: 0.5, phase: 1.23)
        #expect(h.count == 3)
        #expect(h.allSatisfy { $0 == BarHeight.baseline })
    }

    @Test func activeProducesFiveBars() {
        let h = BarHeight.heights(active: true, recording: true, level: 0.5, phase: 0)
        #expect(h.count == 5)
    }

    @Test func activeRecordingAtZeroLevelStillWiggles() {
        // Selbst bei level=0 sorgt die Mindest-Amplitude dafür, dass
        // mindestens ein Balken sichtbar höher ist als baseline.
        let h = BarHeight.heights(active: true, recording: true, level: 0, phase: 0)
        #expect(h.max()! > BarHeight.baseline)
    }

    @Test func higherLevelProducesHigherBars() {
        // Bei recording-Mode skaliert level die Amplitude → max(level=1)
        // muss höher sein als max(level=0).
        let low  = BarHeight.heights(active: true, recording: true, level: 0,   phase: 0).max()!
        let high = BarHeight.heights(active: true, recording: true, level: 1.0, phase: 0).max()!
        #expect(high > low)
    }

    @Test func processingModeUsesConstantAmplitude() {
        // Im Verarbeitungs-Modus (active=true, recording=false) wird level
        // ignoriert — Werte für level=0 und level=1 sind identisch.
        let a = BarHeight.heights(active: true, recording: false, level: 0,   phase: 0.5)
        let b = BarHeight.heights(active: true, recording: false, level: 1.0, phase: 0.5)
        #expect(a == b)
    }
}
```

- [ ] **Step 2: Test ausführen, Fehlschlag bestätigen**

Run: `cd VoiceTypeCore && swift test --filter WaveformIconMathTests`
Expected: FAIL — `cannot find 'BarHeight' in scope`.

- [ ] **Step 3: Pure helper in `VoiceTypeCore` anlegen**

Create `VoiceTypeCore/Sources/VoiceTypeCore/BarHeight.swift`:

```swift
import Foundation

/// Reine, testbare Berechnung der Balken-Höhen für das animierte
/// Wellenform-Icon. Wird sowohl vom Menüleisten-Icon als auch vom
/// Overlay-Inhalt verwendet.
public enum BarHeight {
    public static let baseline: Double = 4    // pt — Höhe inaktiver Balken
    public static let maxRange: Double = 14   // pt — Spannweite über baseline
    public static let processingAmplitude: Double = 0.6
    public static let recordingMinAmplitude: Double = 0.5
    public static let levelGain: Double = 1.6
    public static let omega: Double = 2 * .pi * 2.0  // 2 Hz Grundfrequenz
    public static let phaseStride: Double = .pi / 3   // 60° Versatz pro Balken

    /// Liefert ein Array von Balken-Höhen (in pt) für den gegebenen
    /// Animations-Zustand.
    /// - `active`: einer von { recording, finalizing, cleaning, delivering }.
    /// - `recording`: nur `recording` aktiv (Pegel-Skalierung erlaubt).
    /// - `level`: aktueller `appState.micLevel`, 0…1.
    /// - `phase`: aktuelle Zeit in Sekunden (für die Animation).
    public static func heights(active: Bool, recording: Bool, level: Float, phase: TimeInterval) -> [Double] {
        let count = active ? 5 : 3
        guard active else {
            return Array(repeating: baseline, count: count)
        }
        return (0..<count).map { index in
            let rhythm = 0.5 * (1 + sin(phase * omega + Double(index) * phaseStride))
            let amplitude: Double
            if recording {
                let levelScaled = Double(level) * levelGain
                amplitude = rhythm * max(recordingMinAmplitude, levelScaled)
            } else {
                amplitude = rhythm * processingAmplitude
            }
            return baseline + amplitude * maxRange
        }
    }
}
```

- [ ] **Step 4: Tests ausführen, Erfolg bestätigen**

Run: `cd VoiceTypeCore && swift test --filter WaveformIconMathTests`
Expected: PASS — 5 tests passed.

- [ ] **Step 5: SwiftUI-View anlegen**

Create `VoiceType/VoiceType/WaveformIcon.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Animiertes Wellenform-Icon: drei graue statische Balken im Inaktiv-
/// Modus, fünf grüne animierte Balken im Aktiv-Modus (Hybrid bei
/// Aufnahme, reiner Rhythmus beim Verarbeiten).
struct WaveformIcon: View {
    let state: DictationState
    let level: Float

    private var isActive: Bool {
        switch state {
        case .recording, .finalizing, .cleaning, .delivering: return true
        case .idle, .loading, .error:                          return false
        }
    }
    private var isRecording: Bool { state == .recording }
    private var color: Color { isActive ? .green : .secondary }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let heights = BarHeight.heights(
                active: isActive,
                recording: isRecording,
                level: level,
                phase: phase)
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2, height: h)
                }
            }
            .frame(width: 18, height: 18)
        }
    }
}
```

- [ ] **Step 6: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün (28 bisherige + 5 neue Bar-Tests).

- [ ] **Step 7: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`. (Der View wird noch nirgends instanziiert — Task 4 wird ihn ins MenuBarExtra-Label setzen.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add WaveformIcon view and BarHeight pure helper with full TDD coverage"
```

---

## Task 4: `WaveformIcon` ins `MenuBarExtra`-Label einbauen

Ersetzt das statische SF-Symbol durch das animierte Icon. Erste sichtbare Plan-3-Wirkung beim App-Start.

**Files:**
- Modify: `VoiceType/VoiceType/VoiceTypeApp.swift`

- [ ] **Step 1: Label im MenuBarExtra umstellen**

In `VoiceType/VoiceType/VoiceTypeApp.swift`, finde:

```swift
        } label: {
            Image(systemName: controller.menuBarSymbol)
        }
```

Ersetze durch:

```swift
        } label: {
            WaveformIcon(
                state: controller.appState.dictationState,
                level: controller.appState.micLevel)
        }
```

(Die alte `menuBarSymbol`-Computed-Property auf `AppController` darf erst mal stehen bleiben — sie wird in Task 9 entfernt, wenn klar ist, dass nichts mehr darauf zugreift.)

- [ ] **Step 2: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: replace static SF symbol with animated WaveformIcon in menu bar"
```

---

## Task 5: `OverlayContent`-View + `OverlayWindowController`

Klick-durchlässige NSPanel-basierte Overlay-Pille, gehostet via `NSHostingView`, sichtbar während `.recording → .delivering`.

**Files:**
- Create: `VoiceType/VoiceType/OverlayContent.swift`
- Create: `VoiceType/VoiceType/OverlayWindowController.swift`
- Modify: `VoiceType/VoiceType/VoiceTypeApp.swift` (Controller im AppController-Init erzeugen)

- [ ] **Step 1: `OverlayContent`-View anlegen**

Create `VoiceType/VoiceType/OverlayContent.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Pillen-Inhalt für das klick-durchlässige Aufnahme-Overlay: links das
/// animierte Wellenform-Icon (größer als in der Menüleiste), rechts der
/// Live-Vorschau-Text aus `appState.livePreview`.
struct OverlayContent: View {
    let appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            WaveformIcon(
                state: appState.dictationState,
                level: appState.micLevel)
                .frame(width: 36, height: 24)

            Text(appState.livePreview)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .animation(.default, value: appState.livePreview)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .fixedSize()
        .frame(maxWidth: 440)
    }
}
```

- [ ] **Step 2: `OverlayWindowController` anlegen**

Create `VoiceType/VoiceType/OverlayWindowController.swift`:

```swift
import AppKit
import SwiftUI
import VoiceTypeCore

/// Besitzt einen klick-durchlässigen `NSPanel` und steuert dessen
/// Sichtbarkeit anhand von `appState.dictationState`. Re-positioniert
/// das Panel bei Screen-Konfigurations-Änderungen.
@MainActor
final class OverlayWindowController: NSObject {
    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayContent>
    private let appState: AppState
    private var isCurrentlyVisible = false

    init(appState: AppState) {
        self.appState = appState
        self.hostingView = NSHostingView(rootView: OverlayContent(appState: appState))
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: style,
            backing: .buffered,
            defer: true)
        super.init()

        panel.contentView = hostingView
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.alphaValue = 0   // unsichtbar starten

        observeState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleScreenChange() {
        if isCurrentlyVisible { reposition() }
    }

    private func observeState() {
        let active = Self.isActiveState(appState.dictationState)
        if active != isCurrentlyVisible {
            active ? fadeIn() : fadeOut()
        }
        withObservationTracking {
            _ = appState.dictationState
        } onChange: {
            Task { @MainActor in self.observeState() }
        }
    }

    private static func isActiveState(_ state: DictationState) -> Bool {
        switch state {
        case .recording, .finalizing, .cleaning, .delivering: return true
        case .idle, .loading, .error:                          return false
        }
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let frame = screen.visibleFrame
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
    }

    private func fadeIn() {
        isCurrentlyVisible = true
        reposition()
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    private func fadeOut() {
        isCurrentlyVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}
```

- [ ] **Step 3: Controller im `AppController` instanziieren**

In `VoiceType/VoiceType/VoiceTypeApp.swift`, in der `AppController`-Klasse, direkt nach den bisherigen Properties (nach `private let hotkey: HotkeyMonitor`) diese Property ergänzen:

```swift
    private let overlayController: OverlayWindowController
```

Dann in `init()`, **direkt vor** dem `Task { ... }`-Block am Ende von `init`, diese Zeile einfügen:

```swift
        self.overlayController = OverlayWindowController(appState: appState)
```

- [ ] **Step 4: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add OverlayWindowController with click-through NSPanel showing OverlayContent"
```

---

## Task 6: `MainView` + `HistoryView`-Scaffold + Window-Scene

Hauptfenster mit `NavigationSplitView`, Verlauf-View, Settings-Placeholder (echte Settings kommen in Task 7). Die `Window`-Scene ist neben dem bestehenden `MenuBarExtra`.

**Files:**
- Create: `VoiceType/VoiceType/MainView.swift`
- Create: `VoiceType/VoiceType/HistoryView.swift`
- Modify: `VoiceType/VoiceType/VoiceTypeApp.swift`

- [ ] **Step 1: `HistoryView` anlegen**

Create `VoiceType/VoiceType/HistoryView.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Volle Verlaufs-Liste — eine Row pro `TranscriptEntry` (neueste oben),
/// mit Zeitstempel, Text und „Kopieren"-Knopf.
struct HistoryView: View {
    let appState: AppState

    var body: some View {
        Group {
            if appState.log.isEmpty {
                ContentUnavailableView(
                    "Noch keine Transkriptionen",
                    systemImage: "waveform",
                    description: Text("Halte den Hotkey, um zu diktieren."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.log) { entry in
                            row(for: entry)
                            Divider()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Verlauf")
    }

    @ViewBuilder
    private func row(for entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("Kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: `MainView` mit NavigationSplitView anlegen**

Create `VoiceType/VoiceType/MainView.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Wurzelview des Hauptfensters: NavigationSplitView mit Sidebar
/// (Verlauf / Einstellungen) und Detail-Bereich.
struct MainView: View {
    let controller: AppController
    @State private var selection: Section = .history

    enum Section: String, CaseIterable, Identifiable {
        case history, settings
        var id: String { rawValue }
        var label: String {
            switch self {
            case .history:  return "Verlauf"
            case .settings: return "Einstellungen"
            }
        }
        var systemImage: String {
            switch self {
            case .history:  return "clock"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection {
            case .history:
                HistoryView(appState: controller.appState)
            case .settings:
                // Platzhalter — echte SettingsView kommt in Task 7.
                ContentUnavailableView(
                    "Einstellungen",
                    systemImage: "gearshape",
                    description: Text("Folgt in Task 7."))
                    .navigationTitle("Einstellungen")
            }
        }
    }
}
```

- [ ] **Step 3: Window-Scene zur App ergänzen**

In `VoiceType/VoiceType/VoiceTypeApp.swift`, in `VoiceTypeApp.body`, **nach** dem `MenuBarExtra { ... }`-Block (also als zweite Scene innerhalb des `var body: some Scene { ... }`), diese Scene ergänzen:

```swift
        Window("VoiceType", id: "main") {
            MainView(controller: controller)
        }
        .defaultSize(width: 720, height: 480)
```

- [ ] **Step 4: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`. Das Fenster kann momentan über `⌘N` (oder die Window-Menü-Einträge) oder über `openWindow(id: "main")` aus anderem Code geöffnet werden — die Popover-Anbindung folgt in Task 8.

- [ ] **Step 5: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add MainView (NavigationSplitView), HistoryView, and Window scene"
```

---

## Task 7: `SettingsView` mit Hotkey-Capture und Login-Toggle

Größter SwiftUI-Block: vier Form-Sektionen, Hotkey-Capture-Flow, SMAppService-Login. `AppController` bekommt eine mutable `settings`-Property mit didSet, das die richtigen Side Effects propagiert.

**Files:**
- Create: `VoiceType/VoiceType/SettingsView.swift`
- Modify: `VoiceType/VoiceType/MainView.swift` (Settings-Placeholder durch echte View ersetzen)
- Modify: `VoiceType/VoiceType/VoiceTypeApp.swift` (settings mutable + didSet, applyLoginAtLogin-Helfer)

- [ ] **Step 1: `AppController.settings` mutable machen + didSet**

In `VoiceType/VoiceType/VoiceTypeApp.swift`, im `AppController`, finde die Property-Deklaration `private let settingsStore = SettingsStore()` und die Init-Zeile `let settings = settingsStore.load()`.

Ändere die Property-Liste so, dass `settings` zur Klasse gehört (statt nur lokal in `init`). Ersetze:

```swift
    private let settingsStore = SettingsStore()
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor
```

durch:

```swift
    private let settingsStore = SettingsStore()
    var settings: Settings {
        didSet {
            try? settingsStore.save(settings)
            if oldValue.pushToTalkKey != settings.pushToTalkKey {
                hotkey.setHotkey(settings.pushToTalkKey)
            }
            if oldValue.launchAtLogin != settings.launchAtLogin {
                applyLoginAtLogin(settings.launchAtLogin)
            }
        }
    }
    private let coordinator: DictationCoordinator
    private let hotkey: HotkeyMonitor
```

In `init()`, ersetze die erste Zeile `let settings = settingsStore.load()` durch:

```swift
        let settings = settingsStore.load()
        self.settings = settings
```

(Der lokale `let` bleibt, damit der weitere init-Body nichts ändern muss — er nutzt `settings.language`, `settings.cleanupEnabled` usw. unverändert. Die self-Property hält denselben Wert.)

Direkt am Ende der Klasse (vor der schließenden Klammer der Klasse), diese Hilfsmethode ergänzen:

```swift
    /// Wendet die „Beim Login starten"-Einstellung via SMAppService an.
    /// Bei Fehler wird der Toggle in der UI zurückgesetzt und ein Alert
    /// (durch die View) gezeigt.
    private func applyLoginAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Rollback: Toggle in den Settings zurücksetzen (löst kein
            // weiteres didSet aus, weil oldValue == newValue).
            var rollback = settings
            rollback.launchAtLogin = !enabled
            settings = rollback
            loginErrorMessage = error.localizedDescription
        }
    }

    /// Fehlertext, den die SettingsView bei SMAppService-Fehlern anzeigt.
    var loginErrorMessage: String?
```

Am Anfang der Datei, neben den bestehenden Imports, ergänzen:

```swift
import ServiceManagement
```

- [ ] **Step 2: `SettingsView` anlegen**

Create `VoiceType/VoiceType/SettingsView.swift`:

```swift
import SwiftUI
import VoiceTypeCore

/// Einstellungen — vier Sektionen: Push-to-Talk-Hotkey-Capture, Sprache,
/// Text-Cleanup-Schalter (mit Verfügbarkeits-Hinweis), Login-at-Login.
struct SettingsView: View {
    @Bindable var controller: AppController
    @State private var isCapturingHotkey = false
    @State private var showLoginError = false

    var body: some View {
        Form {
            Section("Push-to-Talk") {
                HStack {
                    Text("Hotkey:")
                    Text(controller.settings.pushToTalkKey.uppercased())
                        .font(.body.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Button(isCapturingHotkey ? "Drücke eine Taste…" : "Drücke neue Taste…") {
                        startHotkeyCapture()
                    }
                    .disabled(isCapturingHotkey)
                }
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

            Section {
                Toggle("Text aufpolieren (Apple Foundation Models)",
                       isOn: $controller.settings.cleanupEnabled)
                if let hint = controller.cleanupHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("Wirkt beim nächsten App-Start.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Start") {
                Toggle("Beim Login starten",
                       isOn: $controller.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Einstellungen")
        .onChange(of: controller.loginErrorMessage) { _, new in
            showLoginError = (new != nil)
        }
        .alert("Anmeldeobjekt konnte nicht gesetzt werden",
               isPresented: $showLoginError) {
            Button("OK") { controller.loginErrorMessage = nil }
        } message: {
            Text(controller.loginErrorMessage ?? "")
        }
    }

    private func startHotkeyCapture() {
        isCapturingHotkey = true
        // HotkeyMonitor während Capture nicht doppelt feuern lassen —
        // er bleibt aktiv, aber sein onCaptured wird vorrangig behandelt.
        controller.hotkeyCaptureBegin { newName in
            controller.settings.pushToTalkKey = newName
            isCapturingHotkey = false
        }
    }
}
```

- [ ] **Step 3: `AppController` um eine Capture-Brücke ergänzen**

`AppController` muss `hotkey.startCapture()` aufrufen, den `onCaptured`-Callback verkabeln und nach Abschluss aufräumen. In `VoiceType/VoiceType/VoiceTypeApp.swift`, am Ende der `AppController`-Klasse (vor `private func applyLoginAtLogin` aus Step 1), diese Methode ergänzen:

```swift
    /// Startet den Hotkey-Capture-Modus. Der übergebene Closure wird mit
    /// dem neu erkannten Hotkey-Namen aufgerufen, wenn der Nutzer eine
    /// passende Taste drückt.
    func hotkeyCaptureBegin(_ completion: @escaping (String) -> Void) {
        hotkey.onCaptured = { [weak self] name in
            self?.hotkey.onCaptured = nil   // einmalig
            completion(name)
        }
        hotkey.startCapture()
    }
```

`hotkey` ist `private let`, müsste also für diese Methode lesbar bleiben (was bei `private` innerhalb der Klasse ohnehin der Fall ist). Die Methode selbst muss **nicht** `private` sein, weil `SettingsView` sie aufruft.

- [ ] **Step 4: `MainView` an die echte `SettingsView` anschließen**

In `VoiceType/VoiceType/MainView.swift`, im `body`, ersetze den Settings-Platzhalter-Block:

```swift
            case .settings:
                // Platzhalter — echte SettingsView kommt in Task 7.
                ContentUnavailableView(
                    "Einstellungen",
                    systemImage: "gearshape",
                    description: Text("Folgt in Task 7."))
                    .navigationTitle("Einstellungen")
```

durch:

```swift
            case .settings:
                SettingsView(controller: controller)
```

- [ ] **Step 5: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

Falls Compiler-Fehler zu `@Bindable` auf einem `@Observable`-Typ: korrekt — `AppController` ist bereits `@Observable`, `@Bindable var controller: AppController` braucht keinen zusätzlichen Property-Wrapper.

- [ ] **Step 6: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add SettingsView with hotkey capture and SMAppService login toggle"
```

---

## Task 8: Schlankes `MenuContentView`-Refactor + „Fenster öffnen…"-Verkabelung

Verlauf-Block raus, „Fenster öffnen…"-Button rein, nutzt `@Environment(\.openWindow)` + `NSApp.activate`.

**Files:**
- Modify: `VoiceType/VoiceType/MenuContentView.swift`

- [ ] **Step 1: Datei vollständig überschreiben**

Overwrite `VoiceType/VoiceType/MenuContentView.swift` with EXACTLY:

```swift
import SwiftUI
import VoiceTypeCore

/// Inhalt des Menüleisten-Popovers (schlank): aktueller Status, optional
/// der Cleanup-Hinweis, „Erneut versuchen" im Fehlerfall, „Fenster
/// öffnen…" und „Beenden". Verlauf-Liste lebt jetzt im Hauptfenster.
struct MenuContentView: View {
    let appState: AppState
    let onRetry: () -> Void
    // `var` mit Default ist hier nötig, damit der Parameter im
    // synthetisierten memberwise init landet — `let cleanupHint = nil`
    // würde ihn rausnehmen. Wird de-facto nie mutiert.
    var cleanupHint: String? = nil

    @Environment(\.openWindow) private var openWindow

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

            if let cleanupHint {
                Text(cleanupHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if isError {
                Button("Erneut versuchen", action: onRetry)
            }

            Divider()

            Button("Fenster öffnen…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Beenden") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 260)
    }
}
```

- [ ] **Step 2: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: slim MenuContentView refactor — open-window button, history moved to main window"
```

---

## Task 9: End-to-End-Verdrahtung — Pegel + alte SF-Symbol-Property entfernen + manueller Smoke-Test

Verkabelt das Pegel-Plumbing von Task 1 (`audioCapture.onLevel` → `coordinator.updateMicLevel`), entfernt die nicht mehr genutzte `menuBarSymbol`-Property aus dem `AppController` und schließt mit einem manuellen End-to-End-Smoke-Test ab.

**Files:**
- Modify: `VoiceType/VoiceType/VoiceTypeApp.swift`

- [ ] **Step 1: Pegel-Callback im `AppController.init` verdrahten**

In `VoiceType/VoiceType/VoiceTypeApp.swift`, in `AppController.init`, finde die Zeile:

```swift
        let audioCapture = AudioCapture()
```

Direkt **danach** diese Zeile ergänzen:

```swift
        audioCapture.onLevel = { [weak coordinator] level in
            coordinator?.updateMicLevel(level)
        }
```

Hmm — `coordinator` wird *unten* erst gleich definiert, also gibt es zum Zeitpunkt dieser Zeile noch keinen `coordinator` in Reichweite. Verschiebe daher die Pegel-Verdrahtung an eine Stelle **nach** der `coordinator`-Zuweisung. Suche die Stelle, an der `self.coordinator = DictationCoordinator(...)` zugewiesen wird (es ist die `coordinator = DictationCoordinator(...)`-Zeile innerhalb der `if settings.cleanupEnabled / else`-Blöcke schon abgeschlossen — sucht den Punkt, wo `self.coordinator` final gesetzt ist; das ist nach dem `coordinator = DictationCoordinator(...)`-Ausdruck im Init-Body).

Direkt **nach** der Zeile `coordinator = DictationCoordinator(...)` (vor `hotkey = HotkeyMonitor(...)`), füge ein:

```swift
        // Mikrofon-Pegel → Coordinator → AppState (Plan 3).
        audioCapture.onLevel = { [coordinator] level in
            Task { @MainActor in coordinator.updateMicLevel(level) }
        }
```

(`coordinator` ist hier ein lokaler `let` aus dem Init und referenziert die soeben erzeugte Instanz; `Task { @MainActor }` ist nötig, weil `audioCapture.onLevel` zwar bereits auf MainActor dispatched aufgerufen wird (siehe Task 1, Step 6), `coordinator.updateMicLevel` aber `@MainActor` ist.)

- [ ] **Step 2: Alte `menuBarSymbol`-Property entfernen**

In `VoiceType/VoiceType/VoiceTypeApp.swift`, finde:

```swift
    /// Statisches SF-Symbol je Zustand (Animation kommt in einem späteren Plan).
    var menuBarSymbol: String {
        switch appState.dictationState {
        case .recording:            return "waveform.circle.fill"
        case .loading, .error:      return "waveform.circle"
        default:                    return "waveform"
        }
    }
```

Lösche diese Computed-Property komplett. Sie wurde in Task 4 durch das `WaveformIcon` ersetzt; keine andere Code-Stelle referenziert sie mehr.

- [ ] **Step 3: App bauen**

Run: `xcodebuild -project <repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj -scheme VoiceType -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`. Bei Compiler-Fehler „Cannot find 'menuBarSymbol'": das ist genau das, was Step 2 entfernen sollte — referenziert wird sie nirgends mehr, daher sollte der Build sauber durchgehen.

- [ ] **Step 4: Paket-Tests laufen lassen (Regression)**

Run: `cd VoiceTypeCore && swift test`
Expected: PASS — alle 33 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: wire mic-level callback in AppController, remove obsolete menuBarSymbol"
```

- [ ] **Step 6: Manueller End-to-End-Smoke-Test**

(Vom Subagent NICHT auszuführen — braucht eine GUI-Sitzung.)

1. In Xcode den Plan-3-Worktree öffnen
   (`<repo>/.worktrees/plan-3-ui-polish/VoiceType/VoiceType.xcodeproj`), ⌘R.
2. **Menüleisten-Icon:**
   - Beim Start (`.loading`): 3 graue statische Balken.
   - Nach Berechtigungs-Freischaltung (`.idle`): immer noch 3 graue statische Balken.
   - Hotkey halten (`.recording`): 5 grüne Balken, animiert, **reagieren** auf Stimme (lauter sprechen → höhere Ausschläge).
   - Loslassen (`.finalizing → .cleaning → .delivering`): 5 grüne Balken animiert, aber **ohne** Pegel-Reaktion (reiner Rhythmus).
   - Zurück zu `.idle`: wieder 3 graue Balken.
3. **Overlay:**
   - Während `.recording`: unten zentriert die dunkle Pille mit grüner Wellenform + Live-Text. Fade-In sichtbar.
   - Klick auf den Bildschirm-Bereich **unter** der Pille sollte die App **unter** ihr fokussieren — also klick-durchlässig.
   - Nach `.delivering` → Fade-Out.
4. **Hauptfenster:**
   - Aus dem Popover „Fenster öffnen…" klicken → Fenster erscheint, springt in den Vordergrund.
   - Seitenleiste: „Verlauf" und „Einstellungen".
   - Verlauf: zeigt zuvor erstellte Diktate; „Kopieren"-Knopf funktioniert.
   - Einstellungen → „Push-to-Talk": „Drücke neue Taste…" klicken, dann eine andere Modifier-Taste drücken (z. B. `Ctrl`) → Anzeige aktualisiert, Diktat reagiert ab sofort auf die neue Taste.
   - Einstellungen → „Sprache": Picker-Auswahl ändern, Caption „Wirkt beim nächsten App-Start." sichtbar.
   - Einstellungen → „Text aufpolieren": Toggle umschalten, Caption-Hinweis sichtbar.
   - Einstellungen → „Beim Login starten": Toggle umschalten; sollte ohne Fehler greifen (System-Einstellungen → Allgemein → Anmeldeobjekte verifizierbar).
5. **Schlankes Popover:**
   - Nur Statustext, optional Cleanup-Hinweis (falls Apple Intelligence aus), „Erneut versuchen" nur bei Fehler, „Fenster öffnen…", „Beenden".
6. **Window-Schließen:** Hauptfenster mit `⌘W` schließen — App läuft weiter im Agent-Modus, Menüleisten-Icon bleibt.

Falls bei einem Schritt etwas hakt, beschreibe es zurück — wir justieren nach.

---

## Abschluss Plan 3

Damit ist die App **funktional vollständig nach Spec**: native Menüleisten-App, animiertes Icon, klick-durchlässiges Overlay mit Live-Text, Hauptfenster mit Verlauf und Einstellungen, lokales Cleanup, Berechtigungs-Onboarding. Plan-1-Lücken (paralleles Diktat, cursor-genaues Einfügen) bleiben separat zu adressieren.

---

## Self-Review

**Spec-Abdeckung (Plan 3):**
- Animiertes Wellenform-Icon mit zwei Modi und Hybrid-Animation → Task 3, 4 ✓
- Pegel-Plumbing (`AudioCapturing.onLevel` → Coordinator → AppState) → Task 1, 9 ✓
- Klick-durchlässiges Overlay unten zentriert, Sichtbarkeit `recording → delivering` → Task 5 ✓
- Hauptfenster mit `NavigationSplitView`, Verlauf-View → Task 6 ✓
- Einstellungs-View mit vier Sektionen, Hotkey-Capture, SMAppService-Login → Task 7 ✓
- `HotkeyMonitor`-Capture-API + pure Resolver-Funktion → Task 2 ✓
- Schlankes `MenuContentView`-Refactor + „Fenster öffnen…" → Task 8 ✓
- Edge Cases (Screen-Wechsel, SMAppService-Fehler, Hotkey mitten im Diktat) → in Tasks 5, 7 jeweils adressiert ✓
- Architektur-Invariante „nur Coordinator mutiert AppState" → durch `updateMicLevel`-Wrapper gewahrt (Task 1, 9) ✓

**Platzhalter-Scan:** keine TBD/TODO. Numerische Animations-Konstanten sind in `BarHeight` konkret hinterlegt (`baseline=4`, `maxRange=14`, `omega=2π·2`, `phaseStride=π/3`, `recordingMinAmplitude=0.5`, `processingAmplitude=0.6`, `levelGain=1.6`). Der Task-7-Settings-View-Code ist vollständig.

**Typ-Konsistenz:** `BarHeight.heights(active:recording:level:phase:)` — selbe Signatur in Task 3 Tests, Implementierung und Verwendung in `WaveformIcon.swift`. `HotkeyMonitor.hotkeyName(keyCode:modifierFlags:isKeyDown:)` — selbe Signatur in Test, Helper und `handleCapture`-Aufruf. `AppController.settings: Settings` (mutable, didSet), `controller.cleanupHint`, `controller.loginErrorMessage`, `controller.hotkeyCaptureBegin(_:)` — alle in Task 7 deklariert und in der gleichen Datei verwendet. `OverlayWindowController.isActiveState` — privat im Controller, konsistent mit dem `isActive`-Computed in `WaveformIcon` (beide cover dieselben vier Recording-Phasen).
