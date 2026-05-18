# VoiceType — Engine- und Cleanup-Wahl: Design

> **Status:** Design — die WhisperKit-Hälfte wird in Plan 4 implementiert; **die MLX-Cleanup-Hälfte ist auf Plan 5 vertagt** wegen eines harten SPM-Dependency-Konflikts (WhisperKit verlangt swift-transformers 1.1.x, mlx-swift-examples verlangt 1.0.x — Xcodes Resolver konsolidiert beide Lokal-Packages und scheitert). Eine separate Reintegration über xcframework oder Subprocess-Isolation kommt in einem Folge-Plan.
> **Vorgänger-Specs:** [`2026-05-14-voicetype-redesign-design.md`](2026-05-14-voicetype-redesign-design.md)
> **Voraussetzungen:** Plan 1–3 sind gemerged oder befinden sich im Stack
> (`plan-3-ui-polish`). Diese Spec setzt die dort etablierte Architektur
> (`TranscriptionEngine`, `TextCleanup`, `AppController`, `SettingsStore`)
> als Grundlage voraus.

## 1. Motivation

Die in der ursprünglichen Spec als „dokumentierte Optionen" parkierten
Alternativen (`WhisperKit` als zweite Engine, MLX-LLMs als zweites Cleanup)
werden jetzt zu **echten, vom Nutzer wählbaren Backends**. Drei Gründe:

1. **Robustheit.** Apple `SpeechTranscriber` deckt Locales und Geräte nicht
   vollständig ab; bei jedem Defekt steht der Nutzer ohne Engine da. Ein
   austauschbares zweites Backend ist die einzige Versicherung.
2. **Qualitätsdifferenzierung.** WhisperKit (`large-v3-turbo`) erreicht in
   schwierigen Aufnahmen messbar bessere Wort-Fehler-Raten als die
   Apple-Engine — wer will, soll wechseln können.
3. **Apple Intelligence ist nicht universell.** `FoundationModelCleanup`
   ist nur verfügbar, wenn Apple Intelligence aktiviert _und_ der Mac
   geeignet _und_ das Modell geladen ist. Auf allen anderen Macs steht
   das Cleanup auf „aus" — ein lokales MLX-LLM (Default
   `mlx-community/Qwen2.5-7B-Instruct-4bit`) füllt diese Lücke.

## 2. Ziele und Nicht-Ziele

### Ziele

- Eine **`Transkription`-** und eine **`Cleanup`-Engine** sind über
  Settings auswählbar; pro Engine ein Default-Modell, das beim ersten
  Wechsel on-demand geladen wird.
- Modelle werden **lokal verwaltet** (Download, Cache, Status, Löschen).
- **Download läuft im Hintergrund**, die App bleibt diktierfähig — mit
  dem alten (bzw. einem Fallback-) Backend.
- **Default-Belegung bleibt rückwärtskompatibel**: bestehende Settings,
  die keine Engine-Auswahl kennen, mappen auf `apple` /
  `apple-foundation-models` und verhalten sich identisch zu Plan 2/3.
- **Switching wirkt live** — ohne App-Neustart. Während eines laufenden
  Diktats wird der Wechsel verzögert bis `.idle`; bei nicht installiertem
  Modell wird er verzögert bis der Download abgeschlossen ist.

### Nicht-Ziele

- Kein **mehrsprachiges Cleanup-Tuning** oder Prompt-Editor — die
  Cleanup-Instruktionen bleiben mechanisch und vor dem Nutzer verborgen.
- Keine **Modell-Custom-URLs**: Der Nutzer wählt aus einer kuratierten
  Liste, statt freien HuggingFace-Repo-Eingaben.
- **Kein Hot-Swap _während_ eines Diktats.** Picker-Änderungen werden
  sofort gespeichert, aber erst angewendet, wenn der Coordinator wieder
  `.idle` ist (siehe § 8).
- **GPU-/Quantisierungs-Optionen** sind in dieser Iteration nicht
  konfigurierbar — die kuratierten Defaults reichen.
- Keine **Telemetrie** zu Modell-Performance.

## 3. Architektur-Überblick

```text
                ┌────────────────────────────────────┐
                │            Settings                │
                │  transcriptionEngine: .apple|.wk   │
                │  whisperKitModelId: String         │
                │  cleanupEngine: .off|.fm|.mlx      │
                │  mlxModelId: String                │
                └─────────────┬──────────────────────┘
                              │
              read at start   │            mutated by SettingsView
                              ▼
                ┌────────────────────────────────────┐
                │           AppController            │
                │  resolves settings → engines       │
                │  owns ModelRegistry                │
                │  applies live swaps                │
                └─────┬──────────────┬───────────────┘
                      │              │
              swap()  │              │ observes status
                      ▼              ▼
   ┌─────────────────────────┐  ┌────────────────────────┐
   │ DictationCoordinator    │  │      ModelRegistry     │
   │  var engine   (swap)    │  │  - status per model    │
   │  var cleanup  (swap)    │  │  - download / cancel   │
   │  pendingSwap (if busy)  │  │  - storage layout      │
   └───────┬─────────┬───────┘  │  - integrity check     │
           │         │          └────────────────────────┘
           ▼         ▼
   ┌──────────────┐ ┌──────────────┐         ▲
   │ Transcription│ │  TextCleanup │         │ binds to
   │ Engine       │ │              │ ┌────────────────────────┐
   │ ├ Apple      │ │ ├ Passthrough│ │   SettingsView (UI)    │
   │ └ WhisperKit │ │ ├ Apple FM   │ │  pickers + download    │
   └──────────────┘ │ └ MLX        │ │  confirmation + bar    │
                    └──────────────┘ │  live activation hint  │
                                     └────────────────────────┘
```

Drei Bausteine sind neu, drei werden erweitert:

| Baustein | Status |
|---|---|
| `ModelRegistry` (`actor`) | **neu** |
| `WhisperKitEngine` (`TranscriptionEngine`) | **neu** |
| `MLXCleanup` (`TextCleanup`) | **neu** |
| `Settings` | **erweitert** |
| `AppController` | **erweitert** (Auswahl, Fallback, Registry) |
| `SettingsView` | **erweitert** (Pickers, Status, Download) |

## 4. Datenmodell

### 4.1 `Settings` (additiv, defaults wahren altes Verhalten)

```swift
public enum TranscriptionEngineKind: String, Codable, Sendable {
    case apple        // SpeechTranscriber (Plan 1)
    case whisperKit   // WhisperKit (neu)
}

public enum CleanupEngineKind: String, Codable, Sendable {
    case off                    // PassthroughCleanup
    case appleFoundationModels  // FoundationModelCleanup (Plan 2)
    case mlx                    // MLXCleanup (neu)
}

public struct Settings: Codable, Equatable, Sendable {
    // bestehend
    public var pushToTalkKey: String = "fn"
    public var language: String = "auto"
    public var clipboardCopy: Bool = true
    public var launchAtLogin: Bool = false

    // neu — ersetzt `cleanupEnabled: Bool` über Migration (s. § 9)
    public var transcriptionEngine: TranscriptionEngineKind = .apple
    public var whisperKitModelId: String =
        "openai_whisper-large-v3-turbo"     // Argmax-Naming, s. § 5.2
    public var cleanupEngine: CleanupEngineKind = .appleFoundationModels
    public var mlxModelId: String =
        "mlx-community/Qwen2.5-7B-Instruct-4bit"   // HF-Repo-ID
}
```

`cleanupEnabled: Bool` wird **entfernt**. Die Migration liest den alten
Wert noch aus dem JSON, mappt `true → .appleFoundationModels` und
`false → .off`, schreibt anschließend das neue Schema zurück (siehe § 9).

### 4.2 Modell-Identität

Ein Modell ist ein Wertobjekt mit stabiler ID:

```swift
public struct ModelDescriptor: Hashable, Sendable {
    public enum Kind: Sendable { case whisperKit, mlx }
    public let kind: Kind
    public let id: String              // z. B. "openai_whisper-large-v3-turbo"
    public let displayName: String     // "Whisper large-v3-turbo"
    public let approxSizeBytes: Int64  // für die UI ("≈1.6 GB")
    public let isDefault: Bool         // bestimmt die Erstauswahl
}
```

Die Liste der bekannten Modelle ist **statisch im Code hinterlegt** —
keine Server-Discovery, kein Update-Pull. Erweiterungen erfolgen durch
App-Updates.

| Engine | ID | Display | Größe | Default |
|---|---|---|---|---|
| WhisperKit | `openai_whisper-large-v3-turbo` | Whisper large-v3-turbo | ≈1.6 GB | ✅ |
| WhisperKit | `openai_whisper-large-v3` | Whisper large-v3 | ≈3 GB | |
| WhisperKit | `distil-whisper_distil-large-v3` | Distil-Whisper large-v3 | ≈1.4 GB | |
| MLX | `mlx-community/Qwen2.5-7B-Instruct-4bit` | Qwen 2.5 7B Instruct (4-bit) | ≈4 GB | ✅ |
| MLX | `mlx-community/Qwen2.5-3B-Instruct-4bit` | Qwen 2.5 3B Instruct (4-bit) | ≈1.8 GB | |
| MLX | `mlx-community/Llama-3.2-3B-Instruct-4bit` | Llama 3.2 3B Instruct (4-bit) | ≈1.8 GB | |

### 4.3 Modell-Status

```swift
public enum ModelStatus: Sendable, Equatable {
    case notInstalled
    case installing(progress: Double)   // 0…1
    case installed(sizeOnDisk: Int64)
    case failed(reason: String)
}
```

Die Registry hält eine `[ModelDescriptor: ModelStatus]`-Map als
`@Observable`-Eigenschaft des `AppController` (Single Source of Truth
für die UI).

## 5. Engines

### 5.1 Apple Speech (unverändert)

Bleibt wie in Plan 1: `AppleSpeechEngine` lädt sein Sprach-Asset über
`AssetInventory.assetInstallationRequest` selbst. Aus Sicht des
`ModelRegistry` ist Apples Asset **kein verwaltetes Modell** — die
Apple-Engine taucht in der Modell-Übersicht nicht auf.

### 5.2 WhisperKit (neu)

`WhisperKitEngine: TranscriptionEngine` ist ein dünner Adapter um
`WhisperKit` aus dem [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
Swift-Package. Streaming-Verhalten wird über die `AudioStreamTranscriber`-
API realisiert (entscheidung aus dem Brainstorming).

```swift
public actor WhisperKitEngine: TranscriptionEngine {
    private let audioCapture: AudioCapturing
    private let modelFolder: URL          // von ModelRegistry geliefert
    private let language: String          // "auto" | "de" | "en"

    private var whisperKit: WhisperKit?
    private var transcribeTask: Task<Void, Error>?
    private var updateContinuation:
        AsyncThrowingStream<TranscriptionUpdate, Error>.Continuation?

    public init(audioCapture: AudioCapturing, modelFolder: URL, language: String)

    public func prepare() async throws {
        // 1. WhisperKit aus modelFolder laden — kein automatischer Download.
        //    Wenn modelFolder fehlt/inkonsistent ist:
        //    throw TranscriptionError.modelUnavailable
        // 2. Audio-Sample-Rate gegen 16 kHz prüfen; BufferConverter wiederverwenden.
    }

    public func start() async throws -> AsyncThrowingStream<TranscriptionUpdate, Error> {
        // - Audio-Stream → WhisperKit AudioStreamTranscriber
        // - Partial-Hypothesen → TranscriptionUpdate(text:, isFinal: false)
        // - Bei stop() → einmaliges TranscriptionUpdate(isFinal: true)
    }

    public func stop() async {
        // - Audio stoppen, Transcriber finalisieren, Continuation finishen
    }
}
```

**Wichtig:** `prepare()` **lädt kein Modell aus dem Netz**. Das ist
ausschließlich Sache der `ModelRegistry` und wird vom `SettingsView`
(über `AppController`) angestoßen — Engine und Download sind sauber
entkoppelt.

### 5.3 MLX-Cleanup (neu)

`MLXCleanup: TextCleanup` ist ein Adapter um die LLM-Loader-Pipeline aus
[ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) +
[ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples).

Die `TextCleanup`-API (`func cleanup(_ raw: String) async -> String`,
**wirft nie**) bleibt erhalten — sanfte Degradierung wie bei
`FoundationModelCleanup`:

- Modell nicht geladen → Rohtext.
- Inferenz überschreitet 8 s (statt 5 s — größere Modelle, höhere Latenz)
  → Rohtext.
- Ausgabe verletzt Längen-Sanity (`acceptedOutput`-Helfer wird mit
  `FoundationModelCleanup` geteilt — in `CleanupSanity.swift` extrahiert)
  → Rohtext.

Die Instruktionen sind **dieselben Strings** wie in
`FoundationModelCleanup` (Plan 2) — der Cleanup-Vertrag ist von der
Engine unabhängig.

```swift
public actor MLXCleanup: TextCleanup {
    private let modelFolder: URL
    private var container: ModelContainer?      // mlx-swift-examples Typ

    public init(modelFolder: URL)

    public func cleanup(_ raw: String) async -> String {
        guard !raw.isEmpty else { return raw }
        do {
            if container == nil { container = try await ModelFactory.load(from: modelFolder) }
            let out = try await withTimeout(seconds: 8) {
                try await container!.generate(
                    prompt: Self.prompt(for: raw),
                    parameters: .deterministic)
            }
            return CleanupSanity.accepted(raw: raw, modelOutput: out)
        } catch {
            return raw   // jede Art von Fehler → Rohtext
        }
    }
}
```

## 6. ModelRegistry — Download, Speicher, Status

### 6.1 Speicherlayout

```text
~/Library/Application Support/VoiceType/
├── settings.json
└── Models/
    ├── whisperkit/
    │   └── openai_whisper-large-v3-turbo/
    │       ├── AudioEncoder.mlmodelc/...
    │       ├── TextDecoder.mlmodelc/...
    │       ├── MelSpectrogram.mlmodelc/...
    │       └── tokenizer.json
    └── mlx/
        └── mlx-community__Qwen2.5-7B-Instruct-4bit/
            ├── config.json
            ├── tokenizer.json
            ├── model-00001-of-XXXXX.safetensors
            └── ...
```

Pro Engine ein Unterordner, pro Modell ein eindeutiger Ordnername.
HF-Repo-Slash (`mlx-community/…`) wird in `__` umgesetzt, damit der Pfad
gültig bleibt und im Finder identifizierbar bleibt.

### 6.2 `ModelRegistry`-API

```swift
@MainActor
@Observable
public final class ModelRegistry {
    public private(set) var status: [ModelDescriptor: ModelStatus] = [:]

    public init(rootFolder: URL = ModelRegistry.defaultRoot)

    /// Scannt das Dateisystem und aktualisiert `status` einmalig.
    public func refresh() async

    /// Liefert den lokalen Modellordner, falls vollständig installiert.
    public func folder(for descriptor: ModelDescriptor) -> URL?

    /// Beginnt einen Download. Idempotent: zweiter Aufruf für denselben
    /// Descriptor liefert den laufenden Download zurück, ohne neu zu starten.
    public func download(_ descriptor: ModelDescriptor) async

    /// Bricht einen laufenden Download ab und räumt Teildaten auf.
    public func cancelDownload(_ descriptor: ModelDescriptor) async

    /// Löscht ein installiertes Modell vom Datenträger.
    public func delete(_ descriptor: ModelDescriptor) async throws
}
```

### 6.3 Download-Quellen

| Engine | Quelle | Bibliothek |
|---|---|---|
| WhisperKit | `argmaxinc/whisperkit-coreml` auf HuggingFace | `WhisperKit.download(variant:from:)` (im Lib enthalten) |
| MLX | jeweiliger HF-Repo (z. B. `mlx-community/...`) | `Hub.snapshot(from:to:progress:)` aus `mlx-swift-examples` |

Beide Bibliotheken bieten Progress-Callbacks. Die Registry kapselt das
und schreibt `installing(progress:)` mit gedrosselter Frequenz (jede
~0.5 s oder bei 5-%-Sprüngen) in den State — sonst überschwemmt das die
UI-Updates.

### 6.4 Integritäts-Check

Beim `refresh()` und nach jedem Download wird geprüft, ob die für die
Engine **minimal erforderlichen Dateien** existieren. Für WhisperKit:
die drei `.mlmodelc`-Bundles + `tokenizer.json`. Für MLX: `config.json`,
`tokenizer.json`, mindestens eine `.safetensors`-Datei. Fehlt etwas
nach Download → `failed(reason:)`; fehlt etwas davor → `notInstalled`.

Kein Hash-Vergleich (würde Re-Download bei Library-Updates auslösen).

### 6.5 Concurrency

`ModelRegistry` ist `@MainActor`, weil ihr `@Observable`-State von der
UI gelesen wird. Tatsächliche Downloads laufen in unstrukturierten
`Task`s mit detacheter Hub-/WhisperKit-API; Progress wird über
`MainActor.run` zurückgehoppt.

Maximal **ein Download pro Engine-Typ gleichzeitig**: ein zweiter
`download(...)` für eine andere ID derselben Engine wird **abgelehnt**
(Status bleibt `notInstalled`, ein Hinweis erscheint im UI). Über
Engines hinweg darf parallel geladen werden.

## 7. Settings-UI

Aufbau der `SettingsView` ergänzt die bestehenden Sections um zwei neue:

```text
┌──────────────────────────────────────────────────────────────┐
│ Push-to-Talk         [ fn ]  [ Drücke neue Taste… ]          │
│                                                              │
│ Sprache              [ Automatisch ▾ ]                       │
│                                                              │
│ ── Spracherkennung ──────────────────────────────────────────│
│ Engine               [ Apple Speech ▾ ]                      │
│                        ├ Apple Speech                        │
│                        └ WhisperKit (lokal)                  │
│                                                              │
│ ⤷ wenn WhisperKit gewählt:                                   │
│   Modell             [ Whisper large-v3-turbo ▾ ]            │
│   Status             ● Installiert (1,6 GB)   [ Löschen ]    │
│                        oder                                   │
│                      ▒▒▒▒▒▒░░░░░░ 53 %  ≈12 MB/s             │
│                                  [ Abbrechen ]               │
│                        oder                                   │
│                      ⚠ Nicht installiert     [ Laden ]       │
│                                                              │
│ ── Text aufpolieren ─────────────────────────────────────────│
│ Cleanup              [ Apple Foundation Models ▾ ]           │
│                        ├ Aus                                 │
│                        ├ Apple Foundation Models             │
│                        └ Lokales LLM (MLX)                   │
│                                                              │
│ ⤷ wenn MLX gewählt: identische Modell-Sektion wie oben       │
│ ⤷ wenn FM und nicht verfügbar:                               │
│   ⚠ Cleanup nicht verfügbar — Apple Intelligence aktivieren. │
│                                                              │
│ ── Start ────────────────────────────────────────────────────│
│ ◯ Beim Login starten                                         │
└──────────────────────────────────────────────────────────────┘
```

### 7.1 Bestätigungsdialog beim Engine-/Modell-Wechsel

Auswahl eines Engine- oder Modell-Werts, dessen Asset **nicht
installiert** ist, öffnet einen Confirmation-Dialog:

> **WhisperKit-Modell laden?**
> _Whisper large-v3-turbo (~1,6 GB) wird einmalig aus dem Internet
> heruntergeladen und lokal gespeichert. Bis es bereit ist, transkribiert
> VoiceType weiter mit Apple Speech._
> [ Abbrechen ] [ Laden ]

Bei „Laden": Setting wird gespeichert, Download startet, der Footer
wechselt auf _„Wird nach Download aktiv."_. Sobald das Modell auf der
Platte liegt, beobachtet `AppController` die Registry und löst den
Live-Swap aus (§ 8.4). Bei „Abbrechen": Setting bleibt auf dem
vorherigen Wert, Picker springt zurück.

### 7.2 Status-Komponente

Eine wiederverwendbare `ModelStatusView(descriptor:registry:)` rendert
je nach `ModelStatus`:

- `notInstalled` → ⚠-Icon + „Nicht installiert" + `[ Laden ]`-Button
- `installing(p)` → `ProgressView(value: p)` + Prozent + `[ Abbrechen ]`
- `installed(size)` → ●-Icon (grün) + „Installiert (1,6 GB)" + `[ Löschen ]`
- `failed(reason)` → ✕-Icon (rot) + Grund + `[ Erneut laden ]`

### 7.3 Live-Aktivierungs-Hinweis

Picker-Sections für Engine und Cleanup zeigen statt eines statischen
Footers einen **Status auf die laufende Instanz**:

| `AppController`-Zustand | Footer |
|---|---|
| Setting == laufende Engine | _„Aktiv."_ |
| Setting != laufende Engine, gewähltes Modell installiert, App `.idle` | _„Wird sofort aktiv…"_ — verschwindet, sobald Swap durch ist |
| Setting != laufende Engine, App `.recording` / `.cleaning` / `.delivering` | _„Wird nach aktuellem Diktat aktiv."_ |
| Setting != laufende Engine, Modell wird geladen | _„Wird nach Download aktiv."_ |
| Setting != laufende Engine, neue Engine schlug fehl | _„Wechsel fehlgeschlagen — Apple Speech bleibt aktiv."_ |

Die `language`-Section behält ihren bisherigen
„Wirkt beim nächsten App-Start"-Hinweis — Locale-Switching ist nicht
Teil dieser Spec.

## 8. AppController + DictationCoordinator — Live-Switching

Engine und Cleanup werden zur Laufzeit ausgetauscht. Drei Bausteine
machen das sauber: eine **Factory**, ein **Pending-Swap-Puffer** im
Coordinator und ein **Wait-for-Idle**-Trigger.

### 8.1 Engine-/Cleanup-Factory

```swift
@MainActor
enum EngineFactory {
    static func makeTranscription(
        settings: Settings,
        registry: ModelRegistry,
        audioCapture: AudioCapturing
    ) -> (engine: TranscriptionEngine, fallbackHint: String?) {
        switch settings.transcriptionEngine {
        case .apple:
            return (AppleSpeechEngine(audioCapture: audioCapture,
                                      language: settings.language), nil)
        case .whisperKit:
            let desc = ModelCatalog.whisperKit(settings.whisperKitModelId)
            guard let folder = registry.folder(for: desc) else {
                return (AppleSpeechEngine(audioCapture: audioCapture,
                                          language: settings.language),
                        "WhisperKit-Modell nicht installiert — Apple Speech aktiv.")
            }
            return (WhisperKitEngine(audioCapture: audioCapture,
                                     modelFolder: folder,
                                     language: settings.language), nil)
        }
    }

    static func makeCleanup(
        settings: Settings,
        registry: ModelRegistry
    ) -> (cleanup: TextCleanup, hint: String?) { /* analog */ }
}
```

### 8.2 `DictationCoordinator`-API für Hot-Swap

```swift
@MainActor
public final class DictationCoordinator {
    private var engine: TranscriptionEngine
    private var cleanup: TextCleanup
    private struct PendingSwap {
        var engine: TranscriptionEngine?
        var cleanup: TextCleanup?
    }
    private var pendingSwap: PendingSwap?
    …

    /// Ersetzt Engine und/oder Cleanup. Anwendung erfolgt sofort,
    /// wenn der Coordinator `.idle` oder `.loading` ist; sonst wird
    /// der Swap gepuffert und nach Abschluss des laufenden Diktats
    /// in `finishAfterStream()` angewendet.
    public func requestSwap(
        engine: TranscriptionEngine? = nil,
        cleanup: TextCleanup? = nil
    ) async {
        let pending = PendingSwap(engine: engine, cleanup: cleanup)
        if canSwapNow { await applySwap(pending) } else { pendingSwap = pending }
    }

    private var canSwapNow: Bool {
        switch appState.dictationState {
        case .idle, .loading, .error: return true
        case .recording, .finalizing, .cleaning, .delivering: return false
        }
    }

    private func applySwap(_ p: PendingSwap) async {
        if let new = p.engine {
            await engine.stop()                  // ggf. no-op
            appState.dictationState = .loading
            do {
                try await new.prepare()
                engine = new
                appState.dictationState = .idle
            } catch {
                appState.dictationState = .error("Engine-Wechsel fehlgeschlagen")
                // alte Engine bleibt aktiv; AppController setzt Hint im AppState
            }
        }
        if let new = p.cleanup {
            cleanup = new                        // Cleanup hat keinen Stream
        }
    }
}
```

`finishAfterStream()` (Plan 1) wird am Ende um einen Block ergänzt:

```swift
if let pending = pendingSwap {
    pendingSwap = nil
    await applySwap(pending)
}
```

Damit gilt die Invariante: **der Coordinator wechselt Engine/Cleanup
nie mitten in einem Diktat**. Picker-Klicks während `.recording`
schreiben die Settings sofort, ein Hinweis _„Wird nach aktuellem Diktat
aktiv."_ erscheint, der Swap erfolgt unmittelbar nach Übergabe des
Cleanup-Ergebnisses.

### 8.3 `AppController` — Glue

```swift
@MainActor @Observable
final class AppController {
    let appState = AppState()
    let permissions = Permissions()
    let registry = ModelRegistry()
    private let audioCapture: AudioCapturing
    private let coordinator: DictationCoordinator
    var settings: Settings { didSet { handleSettingsChange(old: oldValue) } }
    var cleanupHint: String?    // jetzt var, wird auf Swap aktualisiert

    init() {
        let loaded = settingsStore.load()
        self.settings = loaded
        audioCapture = AudioCapture()
        let (engine, fallback) = EngineFactory.makeTranscription(
            settings: loaded, registry: registry, audioCapture: audioCapture)
        let (cleanup, hint) = EngineFactory.makeCleanup(
            settings: loaded, registry: registry)
        cleanupHint = hint
        appState.engineFallbackHint = fallback
        coordinator = DictationCoordinator(engine: engine, cleanup: cleanup, …)
        …
    }

    private func handleSettingsChange(old: Settings) {
        try? settingsStore.save(settings)

        // bestehend: Hotkey, Login (Plan 3)
        if old.pushToTalkKey != settings.pushToTalkKey { hotkey.setHotkey(…) }
        if old.launchAtLogin != settings.launchAtLogin { applyLoginAtLogin(…) }

        // neu: Engine-/Cleanup-Wechsel
        if old.transcriptionEngine != settings.transcriptionEngine
            || old.whisperKitModelId != settings.whisperKitModelId {
            swapEngineIfReady()
        }
        if old.cleanupEngine != settings.cleanupEngine
            || old.mlxModelId != settings.mlxModelId {
            swapCleanupIfReady()
        }
    }

    /// Wird sowohl von `handleSettingsChange` als auch nach erfolgreichem
    /// Download (Registry-Observation) aufgerufen — idempotent.
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
}
```

### 8.4 Verkettung mit Download-Erfolg

Wenn der Nutzer eine Engine wählt, deren Modell fehlt:

1. Confirmation-Dialog → Setting wird gespeichert, Download startet.
2. `EngineFactory.makeTranscription` liefert vorerst die Fallback-Engine
   (Apple Speech) zurück; `engineFallbackHint` wird gesetzt.
3. `AppController` beobachtet `registry.status[descriptor]`. Sobald
   dieses auf `.installed(...)` umschlägt **und** das aktuelle Setting
   noch zum Descriptor passt, ruft er `swapEngineIfReady()` auf. Der
   Coordinator wendet den Swap an, sobald er `.idle` ist.
4. UI-Footer wechselt automatisch (_„Wird nach Download aktiv."_ →
   _„Wird sofort aktiv…"_ → _„Aktiv."_).

Die Observation läuft über das `@Observable`-Property `status` der
Registry — kein zusätzliches Notification-Center nötig.

### 8.5 Was passiert mit einem laufenden Stream beim Swap?

`applySwap` wird nur in den Zuständen `.idle`, `.loading`, `.error`
aufgerufen. In `.recording` etc. ist `pendingSwap` der einzige Puffer.
Damit kann es nie passieren, dass der Coordinator mitten in der
Verarbeitung die Engine wechselt — der bestehende
`prepare()`/`start()`/`stop()`-Vertrag bleibt unangetastet.

Bei `prepare()`-Fehler der neuen Engine: alte Engine bleibt aktiv
(wurde vor dem Tausch zwar `stop()`pt, aber `AppleSpeechEngine`/
`WhisperKitEngine` müssen `prepare()` idempotent unterstützen — das
ist in Plan 1 für Apple bereits der Fall, für WhisperKit Teil des
Adapter-Vertrags).

## 9. Migration

Beim ersten Start nach dem Update wird `settings.json` möglicherweise
noch im alten Schema (`cleanupEnabled: Bool`, keine Engine-Felder)
gefunden. Migrationspfad in `SettingsStore.load()`:

1. Versuche, das **neue** Schema zu decodieren. Erfolg → fertig.
2. Sonst: dekodiere `LegacySettings` (`cleanupEnabled: Bool` +
   gemeinsame Felder).
3. Mappe:
   - `cleanupEnabled == true`  → `cleanupEngine = .appleFoundationModels`
   - `cleanupEnabled == false` → `cleanupEngine = .off`
   - alle Engine-/Modell-Felder bleiben auf ihrem Default.
4. Schreibe das migrierte `Settings`-Objekt sofort zurück (atomar) und
   gib es an die App weiter.

Auf einem frischen System (keine `settings.json`) entfällt die
Migration — Defaults greifen direkt.

## 10. Fallback-Verhalten zur Laufzeit

| Situation | Reaktion |
|---|---|
| Gewählte WhisperKit-Engine, Modell fehlt beim Start | Fallback-Engine Apple Speech läuft; sobald Download fertig **und** Coordinator `.idle`, erfolgt Live-Swap |
| Engine-Swap zur Laufzeit, `prepare()` der neuen Engine wirft | Alte Engine bleibt aktiv; `engineFallbackHint` füllt sich mit Grund; `dictationState = .error(…)` mit Retry |
| Picker-Wechsel während aktivem Diktat (`.recording` etc.) | Setting wird gespeichert, Swap gepuffert; Footer: _„Wird nach aktuellem Diktat aktiv."_ |
| MLX-Cleanup gewählt, Modell fehlt | Cleanup-Hint in Popover + Settings: _„MLX-Modell nicht installiert."_; Passthrough aktiv; Live-Swap nach Download-Erfolg |
| MLX-Cleanup wirft / Timeout während `cleanup()` | Rohtext (bestehender `cleanup()`-Vertrag, § 5.3) |
| Apple FM gewählt, Apple Intelligence nicht verfügbar | Hint aus `FoundationModelCleanup.availabilityHint`; Passthrough aktiv |
| Download bricht ab (Netz weg) | `status = .failed(reason:)`, App-Funktion unbeeinträchtigt; User kann „Erneut laden" |
| Download abgebrochen vom User | Teilordner wird gelöscht, `status = .notInstalled` |

Die Engine-/Cleanup-Wahl wirkt **nie blockierend**. Solange Apple Speech
und Passthrough verfügbar sind, kann diktiert werden — der Nutzer
verliert nur Qualität, nicht Funktion.

## 11. Tests

Wie bisher TDD-gewichtet im Core, Smoke-Tests in der App.

| Datei | Inhalt |
|---|---|
| `SettingsMigrationTests.swift` | Alt-Schema → Neu-Schema, idempotent |
| `ModelRegistryTests.swift` | Scan + Status-Übergänge + Concurrent-Download-Ablehnung + Folder-Layout (gegen Fake-FS) |
| `CleanupSanityTests.swift` | Längen-Sanity (existierende Tests aus Plan 2 umgezogen) |
| `WhisperKitEngineTests.swift` | nur Pfad-Validierung + Stream-Lifecycle gegen Mock-AudioCapturing; **nicht** echte Inferenz (langsam, modellabhängig) |
| `MLXCleanupTests.swift` | Identity-Fallback bei fehlendem Modell + Timeout-Pfad (analog `FoundationModelCleanupTests`) |
| `DictationCoordinatorSwapTests.swift` | `requestSwap` während `.idle` → sofort; während `.recording` → gepuffert + nach `finishAfterStream` angewendet; `prepare()`-Fehler → alte Engine bleibt aktiv; Cleanup-Swap berührt Engine nicht |
| Manuell | Download-UX in Settings, Live-Swap Apple↔WhisperKit, Picker-Klick während Aufnahme, FS-Layout im Finder |

## 12. Abhängigkeiten

Im `VoiceTypeCore/Package.swift` werden zwei Swift-Packages ergänzt:

```swift
.package(url: "https://github.com/argmaxinc/WhisperKit",  from: "0.9.0"),
.package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "1.16.0"),
```

> Versionen sind als Richtwerte gemeint; konkrete Pin-Wahl erfolgt im
> Implementierungs-Plan und wird gegen die zur Build-Zeit aktuellsten
> stabilen Releases verifiziert.

Beides sind macOS-26-kompatible, ausschließlich on-device arbeitende
Bibliotheken. Lizenz: MIT (WhisperKit) bzw. MIT (mlx-swift-examples) —
kompatibel mit der App-Distribution.

## 13. Implementierungs-Reihenfolge (Vorschau für Plan 4)

1. Settings-Schema + Migration (TDD, Core).
2. `ModelDescriptor` + statische Modell-Liste + `ModelStatus` (Core).
3. `ModelRegistry` mit Fake-Filesystem-Tests (Core).
4. `DictationCoordinator.requestSwap` + Pending-Buffer (TDD gegen Mock-Engine, Core).
5. SPM-Dependencies + `WhisperKitEngine`-Adapter (Core, Smoke).
6. SPM-Dependency + `MLXCleanup`-Adapter (Core, Smoke).
7. `EngineFactory` + `AppController`-Refactor: Wahl, Fallback, Live-Swap, Registry-Observation.
8. `SettingsView`-Erweiterung: Pickers + `ModelStatusView` + Confirmation-Dialog + Activation-Footer.
9. End-to-End-Smoke: Apple → WhisperKit-Download → Live-Swap → Diktat;
   FM → MLX-Download → Live-Swap → Cleanup; Picker-Wechsel _während_ Aufnahme.

## 14. Bewusst offen gelassen

- **Auto-Sprachenwahl in WhisperKit**: Plan 4 nutzt zunächst nur die
  Sprache aus `Settings.language` (oder `auto` → von WhisperKit
  bestimmt). Eine Feinjustage erfolgt erst, wenn die Engine im Alltag
  läuft.
- **Modell-Updates**: Wir cachen Modelle ewig; ein „Update verfügbar"-
  Flow kommt später. Manuelles Löschen + Neuladen genügt für Plan 4.
- **Background-Download während Mac schläft**: nicht garantiert; das
  System darf den Task pausieren. Wenn der Download nicht abgeschlossen
  ist, bleibt `installing` stehen und der User kann fortsetzen oder
  abbrechen.
