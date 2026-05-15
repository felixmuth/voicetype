# VoiceType

Lokale Speech-to-Text-App für macOS — eine kostenlose Alternative zu Wispr Flow.

Per Push-to-Talk-Hotkey in jedes Textfeld diktieren. Der erkannte Text wird
lokal aufpoliert und automatisch eingefügt. Alles on-device, keine Cloud,
keine Kosten.

## Status

🎨 **In Design** — kompletter Neuaufbau als native SwiftUI-App.

Das Designdokument liegt unter
[`docs/superpowers/specs/2026-05-14-voicetype-redesign-design.md`](docs/superpowers/specs/2026-05-14-voicetype-redesign-design.md).

## Stack (geplant)

- **Swift 6 / SwiftUI** — native Menüleisten-App
- **Apple `SpeechTranscriber`** (macOS 26) — On-Device-Spracherkennung mit Streaming
- **Apple `FoundationModels`** — lokales LLM zum Aufpolieren des Texts

Zielplattform: macOS 26+, Apple Silicon.
