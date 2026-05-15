# VoiceType — Plan 3: UI-Politur

**Datum:** 2026-05-15
**Status:** Design freigegeben, bereit für Implementierungsplan
**Vorgänger:** Plan 2 (`2026-05-15-voicetype-cleanup-design.md`) — und durch Plan 2 mittelbar auf Plan 1 (`2026-05-14-voicetype-foundation.md`)
**Übergeordnetes Spec:** `2026-05-14-voicetype-redesign-design.md`

## Überblick

Plan 3 hebt die App von „funktioniert" auf „fühlt sich poliert an". Drei
neue/erweiterte UI-Bausteine — alle in SwiftUI, mit kleinem AppKit-Touch
nur dort, wo SwiftUI auf macOS 26 nicht direkt reicht (Klick-Durchlässigkeit
beim Overlay):

1. **Animiertes Wellenform-Icon** in der Menüleiste — fünf grüne Balken
   mit Hybrid-Animation (Grundrhythmus × Mikrofonpegel) bei Aufnahme.
2. **Aufnahme-Overlay** — dunkle Pille unten zentriert mit Live-Text.
3. **Hauptfenster mit Seitenleiste** — Verlauf-Liste + Einstellungen-Form
   (Hotkey-Capture, Sprache, Cleanup-Toggle, Login-at-Login).

Das bestehende Menüleisten-Popover wird zur **schlanken Quick-Glance-View**
zurückgestutzt; der volle Verlauf wandert ins Hauptfenster.

Funktional ändert Plan 3 nichts an Engine, Cleanup, Diktat-Zustandsmaschine
oder Berechtigungen.

## Entscheidungen

- **Icon-Animation:** **Hybrid** — Grundrhythmus läuft immer beim Aufnehmen,
  der `appState.micLevel` skaliert die Amplitude. Während der
  Verarbeitungsphasen (`.finalizing`/`.cleaning`/`.delivering`) läuft nur
  der Rhythmus (kein Pegel mehr).
- **Popover-Zukunft:** **schlankes Popover** — Status + Cleanup-Hinweis +
  „Fenster öffnen…" + „Beenden". Verlauf-Block raus, lebt nur noch im
  Hauptfenster.
- **Architektur:** SwiftUI throughout, AppKit nur fürs klick-durchlässige
  Overlay-Fenster (`NSPanel` mit `ignoresMouseEvents = true`).

## Architektur & Module

### Neu im App-Target (`VoiceType/VoiceType/`)
- **`WaveformIcon.swift`** — `View`, das fünf grüne Balken animiert.
- **`OverlayWindowController.swift`** — NSObject, besitzt einen `NSPanel`
  mit `NSHostingView` als Inhalt; steuert Sichtbarkeit anhand
  `appState.dictationState`.
- **`OverlayContent.swift`** — die SwiftUI-View für den Pillen-Inhalt
  (Wellenform-Icon + Live-Text).
- **`MainView.swift`** — Wurzelview des Hauptfensters mit
  `NavigationSplitView`.
- **`HistoryView.swift`** — Verlaufs-Liste.
- **`SettingsView.swift`** — Einstellungs-Form mit den vier Sektionen.

### Geändert im App-Target
- **`MenuContentView.swift`** — schlanker Refactor: kein Verlauf-Block,
  neuer „Fenster öffnen…"-Button, „Erneut versuchen"-Recovery bleibt.
- **`VoiceTypeApp.swift` / `AppController`**:
  - neue `Window`-Scene neben dem `MenuBarExtra`,
  - `settings` wird mutierbar gemacht und mit `SettingsStore.save(_:)`
    auf jede Änderung gespiegelt,
  - `audioCapture.onLevel`-Callback wird gesetzt → ruft
    `coordinator.updateMicLevel(_:)`,
  - hält `OverlayWindowController` am Leben.

### Geändert im Paket (`VoiceTypeCore`)
- **`Protocols.swift`** — `AudioCapturing` bekommt
  `var onLevel: ((Float) -> Void)? { get set }` (analog zu
  `HotkeyMonitor.onPress`).
- **`AudioCapture.swift`** — implementiert `onLevel`, ruft es im
  AVAudioEngine-Tap-Callback mit dem RMS-Pegel auf, auf MainActor
  dispatched.
- **`DictationCoordinator.swift`** — neue `@MainActor func updateMicLevel(_ level: Float)`,
  setzt `appState.micLevel = level`. So bleibt die Invariante „nur der
  Coordinator mutiert `AppState`" gewahrt.
- **`HotkeyMonitor.swift`** — neue Capture-API:
  `func startCapture()`, `func stopCapture()`,
  `var onCaptured: ((String) -> Void)? { get set }`. Während Capture
  werden globale Tastendrücke abgefangen und der erste passende Modifier
  oder F-Key als Hotkey-Name (z. B. `"fn"`, `"f13"`) per `onCaptured`
  zurückgegeben.

### Unverändert
`AppleSpeechEngine`, `FoundationModelCleanup`, `PassthroughCleanup`,
`TextCleanup`/`TranscriptionEngine`/`TextDelivering`/`FocusInspecting`-
Protokolle, `Permissions`, `BufferConverter`, `TextOutput`, `FocusInspector`,
`Settings`-Struct, `AppState`-API.

## Animiertes Wellenform-Icon

**Zwei visuelle Modi:**

- **Inaktiv** (`.idle`, `.loading`, `.error`): drei kurze graue Balken,
  statisch.
- **Aktiv** (`.recording`, `.finalizing`, `.cleaning`, `.delivering`):
  fünf grüne Balken, animiert. Während `.recording` Hybrid
  (Rhythmus × `appState.micLevel`); sonst reiner Rhythmus.

**Implementierung — Skizze:**

```swift
struct WaveformIcon: View {
    let state: DictationState
    let level: Float
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    bar(at: i, phase: phase)
                }
            }
        }
    }
    private var barCount: Int { isActive ? 5 : 3 }
    private var isActive: Bool { /* recording | finalizing | cleaning | delivering */ }
    private var isRecording: Bool { state == .recording }
    private func bar(at index: Int, phase: TimeInterval) -> some View {
        let amplitude: Double = isActive
            ? rhythmAmplitude(phase: phase, index: index)
              * (isRecording ? max(0.5, Double(level) * 1.6) : 0.6)
            : 0
        let height: Double = barBaseHeight + amplitude * barMaxRange
        return RoundedRectangle(cornerRadius: 1)
            .fill(isActive ? Color.green : Color.secondary)
            .frame(width: 2, height: height)
    }
    private func rhythmAmplitude(phase: TimeInterval, index: Int) -> Double {
        let omega = 2 * Double.pi * 2.0   // 2 Hz Grundfrequenz
        let stride = Double.pi / 3.0      // Phasenversatz pro Balken
        return 0.5 * (1 + sin(phase * omega + Double(index) * stride))
    }
}
```

(Genaue Konstanten — `barBaseHeight`, `barMaxRange`, Grundfrequenz,
Pegel-Gain — feinjustiert beim Implementieren mit visuellem Test.)

**Einbindung:**
```swift
MenuBarExtra { /* MenuContentView */ } label: {
    WaveformIcon(state: controller.appState.dictationState,
                 level: controller.appState.micLevel)
}
```

`@Observable`-Beobachtung auf `appState.dictationState` und `.micLevel`
sorgt für automatisches Re-Rendering.

## Aufnahme-Overlay

**Sichtbarkeitsregel:** während `.recording`, `.finalizing`, `.cleaning`,
`.delivering` sichtbar; bei `.idle`, `.loading`, `.error` versteckt.
Übergang per Fade (~150 ms) über `NSAnimationContext`.

**Inhalt:** `HStack { WaveformIcon (5 Balken, ~24 pt), Text(livePreview) }`
in einer Capsule, dunkles Material-Hintergrund.

```swift
struct OverlayContent: View {
    let appState: AppState
    var body: some View {
        HStack(spacing: 10) {
            WaveformIcon(state: appState.dictationState, level: appState.micLevel)
                .frame(width: 36, height: 24)
            Text(appState.livePreview)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .animation(.default, value: appState.livePreview)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
        .frame(maxWidth: 440)
    }
}
```

**Fenster-Konfiguration (`OverlayWindowController`):**

```swift
@MainActor
final class OverlayWindowController: NSObject {
    private let panel: NSPanel
    private let hostingView: NSHostingView<OverlayContent>
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let content = OverlayContent(appState: appState)
        self.hostingView = NSHostingView(rootView: content)
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        self.panel = NSPanel(
            contentRect: .zero, styleMask: style,
            backing: .buffered, defer: true)
        super.init()
        panel.contentView = hostingView
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true   // ← klick-durchlässig
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        observeState()
        observeScreenChanges()
    }

    private func observeState() {
        // withObservationTracking-Schleife auf appState.dictationState
        // → fadeIn() / fadeOut() bei Übergängen
    }
    private func observeScreenChanges() {
        // NSApplication.didChangeScreenParametersNotification → repositioning
    }
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let x = frame.midX - size.width / 2
        let y = frame.minY + 80
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: size), display: true)
    }
    private func fadeIn() { /* alpha 0 → 1 in 150 ms, orderFront */ }
    private func fadeOut() { /* alpha 1 → 0 in 150 ms, orderOut */ }
}
```

`AppController` erzeugt und hält den Controller in `init` (nachdem
`appState` existiert). Der Controller lebt für die Lifetime der App.

## Hauptfenster: Verlauf & Einstellungen

**Window-Scene** (im `VoiceTypeApp.body`, neben dem bestehenden
`MenuBarExtra`):

```swift
Window("VoiceType", id: "main") {
    MainView(controller: controller)
}
.defaultSize(width: 720, height: 480)
```

**`MainView`** — `NavigationSplitView` mit Sidebar (Auswahl: Verlauf
oder Einstellungen) und Detail-Bereich.

### Verlaufs-View

`ScrollView` + `LazyVStack` über `appState.log`. Jede Row:

```swift
HStack(alignment: .top, spacing: 12) {
    Text(entry.timestamp, format: .dateTime.hour().minute().second())
        .font(.caption.monospaced()).foregroundStyle(.secondary)
        .frame(width: 70, alignment: .leading)
    Text(entry.text).font(.body).lineLimit(3)
    Spacer()
    Button("Kopieren") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
    .buttonStyle(.borderless)
}
```

Empty-State: zentrierter Text
*„Noch keine Transkriptionen. Halte den Hotkey, um zu diktieren."*

### Einstellungs-View

`Form` mit vier `Section`s:

1. **Push-to-Talk** — Anzeige der aktuellen Hotkey-ID; Button
   „Drücke neue Taste…". Während Capture: Button-Text wechselt auf
   „Drücke eine Taste…", `HotkeyMonitor.startCapture()` läuft, beim
   `onCaptured`-Callback wird `settings.pushToTalkKey` gesetzt,
   `hotkey.setHotkey(_:)` live aktualisiert. *Wirkung: sofort.*
2. **Sprache** — `Picker` mit Auto/Deutsch/Englisch, gebunden an
   `settings.language`. Caption-Hinweis: *„Wirkt beim nächsten App-Start."*
3. **Text aufpolieren** — `Toggle` gebunden an `settings.cleanupEnabled`.
   Direkt darunter, falls `controller.cleanupHint != nil`, die orange
   Hinweiszeile aus Plan 2. Caption-Hinweis: *„Wirkt beim nächsten
   App-Start."*
4. **Start** — `Toggle` „Beim Login starten", gebunden an
   `settings.launchAtLogin`. Beim Umschalten wird
   `SMAppService.mainApp.register()` bzw. `.unregister()` aufgerufen
   (macOS-13+-API). Bei Wurf: Toggle springt zurück, kleines `Alert`.
   *Wirkung: sofort.*

**Settings-Persistierung:** der `AppController` exponiert `settings` als
mutierbares `@Observable`-Property. Bindings an einzelne Properties
spiegeln Änderungen sofort auf die Platte via
`SettingsStore.save(_:)`.

## Verdrahtung & Edge Cases

**Schlankes `MenuContentView`:**

```
[Statustext]
[orange Cleanup-Hinweis, falls vorhanden]
[Erneut versuchen]   (nur bei .error)
─────────
[Fenster öffnen…]
[Beenden]
```

Implementiert mit `@Environment(\.openWindow) var openWindow`:

```swift
Button("Fenster öffnen…") {
    openWindow(id: "main")
    NSApp.activate(ignoringOtherApps: true)
}
```

**Pegel-Plumbing-Fluss:**

`AudioCapture.installTap`-Callback → `onLevel(rms)` → `AppController` (im
Init gesetzter Closure) → `coordinator.updateMicLevel(rms)` →
`appState.micLevel = rms`. Sowohl `WaveformIcon` im Menüleisten-Label als
auch `OverlayContent` im Overlay lesen `appState.micLevel` und animieren
entsprechend.

**Edge Cases:**

| Szenario | Verhalten |
|---|---|
| App-Start ohne Berechtigungen | Popover zeigt weiterhin `PermissionsView`. Hauptfenster ist manuell aufrufbar, Hotkey-Capture im Settings funktioniert aber erst, sobald Bedienungshilfen freigeschaltet sind. |
| Hotkey-Änderung mitten im Diktat | `HotkeyMonitor.setHotkey(_:)` setzt `pressedAt = nil`. Eine laufende Aufnahme wird damit „verwaist" — der neue Hotkey gilt ab dem nächsten Press. |
| Multi-Monitor / Screen-Wechsel | `OverlayWindowController` beobachtet `NSApplication.didChangeScreenParametersNotification` und recalculiert Position. |
| `SMAppService.register()` schlägt fehl | Login-Toggle springt zurück auf `false`, `Alert` mit `error.localizedDescription`. |
| Cleanup-Hinweis-Redundanz | Wird sowohl im schlanken Popover **als auch** in der Cleanup-Sektion der Einstellungen gezeigt. Bewusst doppelt — Popover ist Quick-Glance, Settings ist der Wirkungsort. |
| Fenster schließen vs. App beenden | Hauptfenster-Schließen lässt die App im Agent-Modus weiterlaufen. „Beenden" im Popover ist der einzige Quit-Pfad. |
| Sprache/Cleanup-Toggle geändert | Setting wird gespeichert, kein Forced-Restart-Dialog — nur die Caption „Wirkt beim nächsten App-Start." informiert. |

## Tests

- **Unit-Tests** für die wenigen reinen Logik-Stücke:
  - Hotkey-Capture-Auflösung: Mapping „NSEvent-KeyCode/Flags → Hotkey-ID-String"
    als pure Funktion extrahieren und mit erwarteten Mappings testen.
  - Bar-Höhen-Formel im `WaveformIcon` falls als reine Funktion extrahiert.
- **System-Integration** (kein Unit-Test, verifiziert per Build + manuellem
  Smoke-Test, wie in Plan 1/2):
  - `WaveformIcon`-Anzeige im `MenuBarExtra`-Label,
  - `OverlayWindowController`-Sichtbarkeit + Klick-Durchlässigkeit,
  - `MainView` / `NavigationSplitView` / `HistoryView` / `SettingsView`,
  - `HotkeyMonitor`-Capture-Modus,
  - `SMAppService`-Login-Toggle.

## Nicht im Scope (YAGNI)

Bewusst weggelassen:

- **Live-Hotswap von Cleanup-Engine oder Sprache** ohne App-Neustart.
- **Reaktive Verfügbarkeits-Updates** für das Foundation Model (Plan 2
  hatte das bereits als YAGNI vermerkt — bleibt es).
- **Drag-and-Drop / Tastatur-Shortcuts** im Verlauf (Auswahl, Multi-
  Kopieren, Löschen einzelner Einträge).
- **Such-/Filter-Funktion** im Verlauf.
- **Export** des Verlaufs.
- **Theme-Anpassungen** (folgt System-Light/Dark automatisch).
- **Sounds** für Aufnahme-Start/Stop.
- **Plan-1-Lücken** (paralleles Diktat, cursor-genaues Einfügen) — bleiben
  separat zu adressieren.
