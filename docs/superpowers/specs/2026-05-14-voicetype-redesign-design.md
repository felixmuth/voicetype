# VoiceType — Neuaufbau als native macOS-App

**Datum:** 2026-05-14
**Status:** Design freigegeben, bereit für Implementierungsplan

## Überblick

VoiceType ist eine lokale Speech-to-Text-App für macOS — eine kostenlose
Alternative zu Wispr Flow. Per Push-to-Talk-Hotkey diktiert man in jedes
Textfeld, der erkannte Text wird automatisch aufpoliert und eingefügt.

Dieses Dokument beschreibt den **kompletten Neuaufbau** als native
SwiftUI-App. Das bestehende Python/PyQt6-Projekt wird abgelöst, nicht
weiterentwickelt.

## Warum Neuaufbau

Drei konkrete Probleme der Python-Version:

1. **Hohe Latenz** — `whisper-large-v3` wird erst nach dem Loslassen der
   Taste komplett am Stück transkribiert. Die Wartezeit ist die volle
   Transkriptionsdauer.
2. **Schlechte Genauigkeit** — falsche Wörter, Probleme mit Zeichensetzung
   und Groß-/Kleinschreibung.
3. **Abstürze / Instabilität** — die MLX/Metal-Aufrufe aus Python heraus
   sind fragil (EXC_BAD_ACCESS bei Thread-Wechseln).

Dazu kam eine **pixelige UI** — das Menüleisten-Icon wurde als 22×22-px-
`QPixmap` ohne `devicePixelRatio` gezeichnet und auf Retina hochskaliert.

Der Neuaufbau adressiert alle vier Punkte an der Wurzel statt sie zu
flicken.

## Stack-Entscheidung

| Bereich | Wahl | Begründung |
|---|---|---|
| Sprache / UI | Swift 6.3, SwiftUI, `MenuBarExtra` | Gestochen scharfes Retina-Rendering, flüssige Core-Animationen, native Menüleiste & Berechtigungen |
| Spracherkennung | Apple `SpeechTranscriber` (macOS 26) | Null Drittanbieter-Abhängigkeiten → die Crash-Klasse fällt weg. Streaming eingebaut → minimale Latenz. Gratis, kein Modell-Download |
| Text-Cleanup | Apple `FoundationModels` (lokales LLM) | Gratis, lokal, keine Extra-Downloads. Poliert Füllwörter, Zeichensetzung, Groß-/Kleinschreibung |
| Audio | `AVAudioEngine` | Native Mikrofon-Aufnahme als Stream |
| Hotkey | Globaler Event-Tap | Push-to-Talk systemweit |
| Tests | Swift Testing | In Swift 6 eingebaut |

**Zielplattform:** macOS 26+, Apple Silicon. Voraussetzung für die
Entwicklung: volles Xcode (Command Line Tools allein reichen für
App-Bundling, Signing und Entitlements nicht).

### Engine und Cleanup sind austauschbar

`SpeechTranscriber` und `FoundationModels` sind Apple-exklusiv. Damit das
nicht die ganze App vergiftet, liegen beide hinter Swift-Protokollen
(`TranscriptionEngine`, `TextCleanup`). Vorteile:

- **Testbarkeit** — die Kern-Logik wird gegen Mock-Implementierungen
  getestet.
- **Sicherheitsnetz Genauigkeit** — falls Apples Engine irgendwo nicht
  reicht, kann WhisperKit als alternative `TranscriptionEngine` eingesetzt
  werden, ohne den Rest der App anzufassen.
- **Windows-Zukunft** — siehe unten.

## Architektur

Vier Schichten, jedes Modul mit genau einer Aufgabe.

### SwiftUI-Oberfläche
- `VoiceTypeApp` — App-Einstieg, `MenuBarExtra`
- `MenuBarController` — Icon-Zustand & Pulsieren
- `OverlayWindow` — klick-durchlässiges Fenster mit Live-Vorschau
- `MainWindow` — Fenster mit Seitenleiste: Verlauf + Einstellungen

### Kern-Logik
- `DictationCoordinator` — zentrale Zustandsmaschine, verbindet alle Teile
- `HotkeyMonitor` — globaler Event-Tap für Push-to-Talk
- `AudioCapture` — `AVAudioEngine`, streamt Mikrofon-Buffer
- `AppState` — beobachtbarer Zustand (`@Observable`), Single Source of
  Truth für die Views

### Austauschbare Dienste (hinter Protokollen)
- `TranscriptionEngine` → `AppleSpeechEngine` (mit `SpeechTranscriber`)
- `TextCleanup` → `FoundationModelCleanup` (mit `FoundationModels`)

### Plattform-Adapter
- `TextOutput` — fügt Text ins fokussierte Feld ein (Accessibility API) +
  Zwischenablage
- `FocusInspector` — prüft, ob ein Textfeld fokussiert ist
- `SettingsStore` — lädt/speichert Hotkey, Sprache, Cleanup-Schalter

## Datenfluss bei einem Diktat

1. `HotkeyMonitor` erkennt Taste gedrückt → `DictationCoordinator` startet
2. `FocusInspector` macht einen Snapshot: ist gerade ein Textfeld
   fokussiert?
3. `AudioCapture` startet und streamt Buffer **laufend** an die
   `TranscriptionEngine`
4. Die Engine liefert **fortlaufend** Teilergebnisse → `AppState` →
   Overlay zeigt Live-Text, Icon pulsiert
5. Taste losgelassen → Audio stoppt, Engine liefert das finale Transkript
   (schon fast fertig, weil gestreamt → kaum Latenz)
6. `TextCleanup` poliert den Text auf
7. `TextOutput` fügt ein + kopiert in die Zwischenablage, Eintrag landet im
   Verlauf, Zustand zurück auf `idle`

Der Kern: Weil während des Sprechens schon gestreamt wird, ist nach dem
Loslassen fast nichts mehr zu tun — das ist die Antwort auf die Latenz.

## Zustandsmaschine

`DictationCoordinator` kennt sechs Zustände:

```
loading → idle → recording → finalizing → cleaning → delivering → idle
          ↑________________________________________________________|
```

- `loading` — Engine wärmt beim App-Start auf
- `idle` — bereit, wartet auf Hotkey
- `recording` — Taste gehalten, Audio streamt, Teilergebnisse laufen ein
- `finalizing` — Taste los, finales Transkript wird abgeholt
- `cleaning` — Cleanup-Pass durch das Foundation Model
- `delivering` — Text wird ins Zielfeld eingefügt

## Edge Cases & Fehlerbehandlung

Leitgedanke: **jeder Fehler degradiert sanft.** Schlimmstenfalls landet der
Rohtext in der Zwischenablage — aber nichts crasht, nichts geht verloren.

| Szenario | Verhalten |
|---|---|
| Tastendruck < ~300 ms | Verwerfen, gar nicht transkribieren |
| Keine Sprache erkannt / leeres Transkript | Nichts einfügen, kurzer Hinweis im Overlay, zurück zu `idle` |
| Cleanup schlägt fehl / Timeout | Fallback auf Rohtext — Cleanup ist Veredelung, kein Single Point of Failure |
| `FoundationModels` gar nicht verfügbar (Apple Intelligence aus/nicht unterstützt) | Beim Start erkennen, Cleanup dauerhaft überspringen, Rohtext ausliefern, dezenter Hinweis in den Einstellungen |
| Engine nicht bereit / Fehler | Fehler im Overlay & Popover anzeigen, App läuft weiter, kein Absturz |
| Neuer Tastendruck während vorheriges Diktat noch in `cleaning`/`delivering` | Neue Aufnahme startet sofort; vorige Auslieferung läuft im Hintergrund zu Ende. Jedes Diktat ist unabhängig |
| Fokus wechselt zwischen Drücken und Loslassen | Snapshot beim Drücken — das beim Start fokussierte Feld ist das Ziel |
| Keine Mikrofon-Berechtigung | Klare Aufforderung mit Anleitung statt stillem Versagen |
| Keine Bedienungshilfen-Berechtigung | Fallback auf „nur Zwischenablage" + Hinweis zur Freischaltung |
| Sehr langes Diktat | `SpeechTranscriber` ist für Langform gebaut — weiter streamen |

## UI-Design

Durchgängige Akzentfarbe: **Grün** (signalisiert „aktiv, hört zu").

### Menüleisten-Icon — Wellenform-Balken
- **In Ruhe:** drei kurze, statische Balken
- **Bei Aufnahme:** fünf grüne Balken, animiert; können später auf den
  echten Mikrofonpegel reagieren
- Gezeichnet als natives Vektor-/SF-Symbol → automatisch Retina-scharf
  (behebt den Pixelbug der alten App)

### Aufnahme-Overlay — unten zentriert
- Feste Position am unteren Bildschirmrand, mittig (Wispr-Flow-Stil) —
  ruhig, vorhersehbar, lenkt nicht vom Tippcursor ab
- Dunkle Pille mit grüner Wellenform links
- **Live mitlaufender Text** rechts: das Teilergebnis der Engine wird
  fortlaufend angezeigt
- Klick-durchlässiges, randloses Fenster

### Hauptfenster — ein Fenster mit Seitenleiste
- Seitenleiste mit zwei Bereichen: **Verlauf** und **Einstellungen**
- **Verlauf:** Liste der Transkriptionen (Zeitstempel, Text, Kopieren-Knopf)
- **Einstellungen:** Push-to-Talk-Taste, Sprache (Auto/DE/EN),
  „Text aufpolieren"-Schalter, „Beim Login starten"-Schalter

## Windows-Zukunft

Mac-first. Eine spätere Windows-Version ist ein **bewusster Rewrite**, kein
Port — SwiftUI gibt es auf Windows nicht, und `SpeechTranscriber` /
`FoundationModels` sind Apple-exklusiv. Was sich überträgt, ist nicht der
Code, sondern die **Architektur-Form**: die Zustandsmaschine, die
Modul-Grenzen, die Protokoll-Schnitte. Deshalb die saubere Kapselung von
Engine und Cleanup.

## Tests

- **Test-Framework:** Swift Testing
- `DictationCoordinator` — Zustandsmaschine gegen Mock-`TranscriptionEngine`
  und Mock-`TextCleanup`: kurzer Tastendruck, leeres Transkript,
  Cleanup-Fehler → Rohtext-Fallback, paralleles Diktat
- `SettingsStore` — Laden/Speichern, Defaults, kaputte Datei
- Cleanup-Prompt-Aufbau — korrekter Prompt ans Foundation Model
- Audio-Aufnahme und Apple-APIs (`SpeechTranscriber`, `FoundationModels`,
  Accessibility) — manuelle Integrationstests, nicht sinnvoll mockbar

## Verteilung

- **`.app`-Bundle mit lokaler Signatur** (Ad-hoc bzw. kostenlose Apple-ID)
  — reicht für die eigene Nutzung, kein bezahlter Developer-Account nötig
- Berechtigungen sauber in `Info.plist` / Entitlements: **Mikrofon**,
  **Bedienungshilfen** (globaler Hotkey + Text einfügen), ggf.
  **Eingabeüberwachung**
- **Erster praktischer Schritt vor dem Coden: volles Xcode installieren**
- Notarisierung (bezahlter Account, 99 $/Jahr) erst relevant, falls die App
  später weitergegeben werden soll — für jetzt außerhalb des Scopes

## Nicht im Scope (YAGNI)

Bewusst weggelassen, um den ersten Wurf fokussiert zu halten:

- **Toggle-Modus** (an/aus statt halten) — nur Push-to-Talk
- **WhisperKit als Engine** — bleibt als dokumentierte Option hinter dem
  `TranscriptionEngine`-Protokoll, wird aber jetzt nicht implementiert
- **Windows-Version** — siehe oben
- **Notarisierung & Weitergabe**
- **Eigenes Vokabular / Diktat-Befehle** („neue Zeile", „Komma" usw.)
- **Reaktive Pegel-Balken im Menüleisten-Icon** — erst statische/animierte
  Balken; echte Pegel-Reaktion ist eine spätere Politur
- **Mehr Sprachen als Auto/DE/EN**
