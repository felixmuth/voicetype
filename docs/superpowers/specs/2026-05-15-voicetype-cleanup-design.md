# VoiceType — Plan 2: Text-Cleanup mit Apple Foundation Models

**Datum:** 2026-05-15
**Status:** Design freigegeben, bereit für Implementierungsplan
**Vorgänger:** Plan 1 (`2026-05-14-voicetype-foundation.md`) — `PassthroughCleanup` als Platzhalter
**Übergeordnetes Spec:** `2026-05-14-voicetype-redesign-design.md`

## Überblick

Plan 2 ersetzt das `PassthroughCleanup` aus Plan 1 durch eine echte
`FoundationModelCleanup`-Implementierung auf Basis von Apples lokalem
`FoundationModels`-Framework (macOS 26). Der diktierte Rohtext wird vor der
Ausgabe **mechanisch** bereinigt — ohne Wortlaut oder Satzbau anzutasten.

Alles andere bleibt: Architektur, Zustandsmaschine, UI-Hülle.

## Entscheidungen

- **Cleanup-Tiefe:** **nur Mechanik** — Füllwörter raus, Zeichensetzung,
  Groß-/Kleinschreibung, offensichtliche Versprecher und unmittelbare
  Wortwiederholungen glätten. Wortwahl und Satzbau bleiben unangetastet
  (maximales Vertrauen: das Diktat klingt nach dem Nutzer).
- **Modell nicht verfügbar:** Rohtext wird normal ausgeliefert, plus dezente
  Hinweiszeile im Menüleisten-Popover („Cleanup nicht verfügbar — Apple
  Intelligence aktivieren").
- **Verdrahtung:** `FoundationModelCleanup` ist selbst-enthalten;
  `AppController` wählt die Implementierung anhand von
  `settings.cleanupEnabled`, liest einmalig den Verfügbarkeits-Hinweis aus
  und reicht ihn an `MenuContentView` durch — wie schon `onRetry`.

## Architektur & Verdrahtung

### Neu: `FoundationModelCleanup`

Eine neue Datei im `VoiceTypeCore`-Paket:

`VoiceTypeCore/Sources/VoiceTypeCore/FoundationModelCleanup.swift`

```swift
public struct FoundationModelCleanup: TextCleanup {
    public init() {}

    /// `nil` = Modell verfügbar. Sonst ein deutscher Hinweistext, den die
    /// UI dem Nutzer anzeigen kann (Ursache: Apple Intelligence aus oder
    /// Gerät nicht unterstützt).
    public var availabilityHint: String? { ... }

    /// Bereinigt den Rohtext mechanisch. Fällt bei jedem Problem auf den
    /// Rohtext zurück — wirft nie.
    public func cleanup(_ raw: String) async -> String { ... }

    /// Pure Hilfsfunktion: entscheidet, ob eine Modell-Ausgabe akzeptiert
    /// wird (oder ob auf raw zurückgefallen wird). Bewusst frei isoliert
    /// für Unit-Tests.
    static func acceptedOutput(raw: String, modelOutput: String) -> String { ... }
}
```

### Geändert: `AppController` (App-Target)

- Wählt die Cleanup-Implementierung beim Start:
  `settings.cleanupEnabled` → `FoundationModelCleanup()`,
  sonst → `PassthroughCleanup()`.
- Wenn `FoundationModelCleanup` benutzt wird: liest einmalig
  `availabilityHint` aus und hält ihn als Property
  (`let cleanupHint: String?`).
- Gibt den Hinweis als zusätzlichen Parameter an `MenuContentView` weiter.

### Geändert: `MenuContentView` (App-Target)

- Neuer Parameter `cleanupHint: String?` (analog zu `onRetry`).
- Zeigt eine dezente Hinweiszeile, wenn der Hinweis nicht `nil` ist.

### Unverändert

- `TextCleanup`-Protokoll.
- `DictationCoordinator` — ruft weiterhin `await cleanup.cleanup(raw)` im
  `.cleaning`-Zustand auf, kennt nur das Protokoll.
- `AppState` — der Hinweis ist beim Start statisch bestimmt und wird direkt
  via Property an die View durchgereicht, kein zusätzliches Feld nötig.
- Restlicher Datenfluss aus Plan 1.

## Cleanup-Verhalten

### Anweisungen ans Foundation Model

In jede frisch erzeugte `LanguageModelSession` gehen Anweisungen, die
„Mechanik-only" durchsetzen:

> Du bereinigst diktierten Text. Erlaubt: Füllwörter entfernen (ähm, äh,
> öh, …), Zeichensetzung setzen und korrigieren, Groß-/Kleinschreibung
> korrigieren, offensichtliche Versprecher und unmittelbare
> Wortwiederholungen glätten. Verboten: umformulieren, Wortwahl ändern,
> Sätze umbauen, Inhalt hinzufügen oder weglassen, übersetzen,
> kommentieren. Antworte ausschließlich mit dem bereinigten Text — keine
> Einleitung, keine Anführungszeichen, kein „Hier ist…". Behalte die
> Sprache des Originals bei.

Der Rohtext geht anschließend als Prompt an `session.respond(to: raw)`.

### Sicherheits-Check (`acceptedOutput`)

Nach der Modell-Antwort entscheidet eine **reine Funktion** über
Akzeptanz vs. Verwurf:

- Modell-Ausgabe leer oder nur Whitespace → **Rohtext**
- Längenverhältnis aus dem Rahmen (< 50 % oder > 200 % der Rohlänge —
  ein Zeichen, dass das Modell „abgedriftet" ist) → **Rohtext**
- Sonst → getrimmte Modell-Ausgabe

Diese Funktion ist die unit-testbare Insel der Logik.

### Timeout

Der `respond(to:)`-Aufruf wird mit einem Timeout als Sicherheitsnetz
umschlossen (5 s). Mechanik-Cleanup ist schnell — der Timeout greift im
Normalfall nie, verhindert aber einen hängenden Aufruf. Timeout → Rohtext.

### Verfügbarkeit

- `cleanup(_:)` prüft zuerst `SystemLanguageModel.default.availability`.
  Nicht verfügbar (`appleIntelligenceNotEnabled`, `deviceNotEligible`,
  `modelNotReady`) → **sofort Rohtext** ohne `respond`-Versuch.
- `availabilityHint` mappt diese Fälle auf deutschen Hinweistext:
  - „aus" → „Cleanup nicht verfügbar — Apple Intelligence aktivieren."
  - „Gerät" → „Cleanup nicht verfügbar — auf diesem Gerät nicht unterstützt."
  - „lädt noch" → „Cleanup nicht verfügbar — Modell lädt noch."
  - verfügbar → `nil`
- Verfügbar-aber-`respond`-wirft (`LanguageModelSession.GenerationError`,
  IO-Fehler …) → try/catch → **Rohtext**. Gürtel und Hosenträger.

### Session-Lebenszyklus

**Frische `LanguageModelSession` pro Cleanup-Aufruf.** Die Session ist
stateful (sammelt den Aufruf-Transcript) — für unabhängige
Einzeltransformationen ist „frisch pro Aufruf" die korrekte Wahl und
vermeidet, dass spätere Cleanups frühere als Kontext sehen.

## Fehlerbehandlung

Leitprinzip: **Cleanup ist Veredelung, nie ein Single Point of Failure.**
Der diktierte Rohtext ist bereits korrekt; jeder Cleanup-Fehler degradiert
sanft zu dem, was der Nutzer eh schon gesprochen hat.

| Szenario | Ergebnis |
|---|---|
| Apple Intelligence aus / Gerät nicht unterstützt / Modell lädt noch | Rohtext + Hinweis im Popover |
| `respond(to:)` wirft (`GenerationError`, Systemfehler) | Rohtext |
| Timeout (5 s) | Rohtext |
| Modell-Ausgabe leer | Rohtext |
| Modell-Ausgabe stark abweichend (Längenverhältnis < 50 % oder > 200 %) | Rohtext |
| `settings.cleanupEnabled == false` | `PassthroughCleanup` aktiv — Rohtext, kein Hinweis |

## Tests

- **`FoundationModelCleanupTests.swift`** (Swift Testing) prüft die reine
  `acceptedOutput`-Hilfsfunktion:
  - leere Ausgabe → Rohtext
  - reine Whitespace-Ausgabe → Rohtext
  - zu kurze Ausgabe (< 50 %) → Rohtext
  - zu lange Ausgabe (> 200 %) → Rohtext
  - normale Ausgabe → akzeptiert und getrimmt
- Der echte Modell-Aufruf (`LanguageModelSession`, `respond`,
  `SystemLanguageModel.default.availability`) ist System-Integration —
  kein Unit-Test, verifiziert per Build + manuellem Test (wie
  `AppleSpeechEngine` in Plan 1).

## Nicht im Scope (YAGNI)

Bewusst weggelassen, wird in späteren Plänen oder gar nicht adressiert:

- **Settings-UI** für `cleanupEnabled` — Plan 3 (Seitenleisten-Fenster
  bringt die Einstellungs-Oberfläche).
- **Live-Aktualisierung** der Verfügbarkeit — der Hinweis wird einmal
  beim App-Start ermittelt. Toggelt der Nutzer Apple Intelligence
  währenddessen, wirkt es erst nach App-Neustart. Eine spätere Politur
  könnte `availabilityHint` reaktiv beobachten, ist hier aber unnötig.
- **Strukturierte/`@Generable`-Ausgaben** — eine reine `String`-Antwort
  ist für Mechanik-Cleanup ausreichend.
- **Streaming-Cleanup** (`streamResponse`) — Cleanup arbeitet auf dem
  finalen, abgeschlossenen Diktat; One-shot ist passend.
- **Konfigurierbare Aggressivität** — die Tiefe ist fest auf „nur
  Mechanik" festgelegt; eine Aggressivitäts-Einstellung wäre ein
  separates Feature.
- **Sprach-spezifische Prompts** — der Anweisungstext fordert
  Sprach-Erhalt; das Modell wählt entsprechend, kein Spezial-Prompt pro
  Sprache nötig.
- **Plan-1-Lücken** (paralleles Diktat, cursor-genaues Einfügen) — sind
  in Plan 1 dokumentiert, bleiben separat zu adressieren.
