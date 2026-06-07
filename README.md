# VoiceType

Local speech-to-text for macOS — a free, on-device alternative to Wispr Flow.

Hold a push-to-talk hotkey, speak, and the transcribed text is polished by a
local LLM and inserted straight into whatever text field you are focused on.
Everything runs on-device: no cloud, no account, no cost.

[![CI](https://github.com/felixmuth/voicetype/actions/workflows/ci.yml/badge.svg)](https://github.com/felixmuth/voicetype/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Demo

https://github.com/user-attachments/assets/5330b631-3fec-4163-bbd4-629579dfea76

## Features

- **Push-to-talk dictation** — hold a hotkey (default: `fn`), speak, release. The
  text appears where your cursor is.
- **Fully on-device** — audio never leaves the machine. No network calls, no
  telemetry.
- **Live preview** — a floating overlay shows the transcription as you speak,
  word by word.
- **Pluggable transcription** — choose the speech engine that fits your machine
  and language.
- **Optional LLM cleanup** — a local model fixes punctuation, casing and filler
  words before the text is inserted. Can be turned off.
- **Menu-bar app** — stays out of the way; no Dock icon.

## How it works

```
hotkey down ─▶ capture audio ─▶ transcribe (live) ─▶ LLM cleanup ─▶ insert text
```

`DictationCoordinator` orchestrates the flow; each stage is a protocol so engines
can be swapped at runtime from Settings.

### Transcription engines

| Engine | Backend | Notes |
|--------|---------|-------|
| Apple Speech | `SpeechTranscriber` (macOS 26) | Built in, no download, streaming. |
| WhisperKit | [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit) | Whisper large-v3 via Core ML. |
| Parakeet | [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio) | NVIDIA Parakeet TDT, runs on the ANE. |

### Cleanup engines

| Engine | Backend | Notes |
|--------|---------|-------|
| Apple FoundationModels | System LLM (macOS 26) | No download. |
| MLX | Qwen 2.5 3B Instruct (4-bit) via [mlx-swift](https://github.com/ml-explore/mlx-swift-examples) | Downloaded on first use. |
| Off | — | Insert the raw transcription unchanged. |

## Requirements

- macOS 26.4 or later
- Apple Silicon
- Xcode 26 or later (to build)

macOS 26 is required because the Apple Speech and Apple FoundationModels engines
build against system frameworks introduced in that release. The WhisperKit and
Parakeet engines do not depend on macOS 26 themselves — running on older macOS
by hiding the Apple engines behind availability checks is on the roadmap.

VoiceType needs **Microphone** and **Accessibility** permissions — the first for
recording, the second to insert text into other apps. macOS prompts for both on
first use.

## Build & run

```sh
git clone https://github.com/felixmuth/voicetype.git
cd voicetype
open VoiceType/VoiceType.xcodeproj
```

Build and run the `VoiceType` scheme in Xcode. The transcription and cleanup
engine packages resolve automatically via Swift Package Manager.

## Project layout

```
VoiceType/            SwiftUI menu-bar app (UI, windows, overlay)
VoiceTypeCore/        Engine-agnostic logic: coordination, audio, settings,
                      model registry — no third-party engine dependencies
VoiceTypeWhisperKit/  WhisperKit engine adapter
VoiceTypeParakeet/    Parakeet / FluidAudio engine adapter
VoiceTypeMLX/         MLX cleanup-engine adapter
```

`VoiceTypeCore` deliberately has no dependency on any speech or LLM library.
Each engine lives in its own package and is wired in through a protocol, so the
core stays small, fast to compile, and easy to test.

## Development

Run the core test suite:

```sh
cd VoiceTypeCore
swift test
```

64 tests cover settings migration, the model registry, the dictation
coordinator, hotkey parsing and the cleanup sanity filter.

The design specs and implementation plans this app was built from live in
[`docs/superpowers/`](docs/superpowers/) — they document the decisions behind
the architecture, engine choices and UI.

## Roadmap

- Support for older macOS by gating the Apple engines behind availability checks
- Notarized release build for download

## License

[MIT](LICENSE) © Felix Muth
