# YOLOWhisp

Fully local, fast speech-to-text for macOS — a native menu-bar dictation app powered by
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal GPU acceleration. Nothing
leaves your machine. Hold a hotkey, talk, and the text is typed into whatever app you're in.

## Features

- **100% local transcription** via `whisper-cli` (Metal-accelerated). No cloud, no account.
- **Global hotkeys** — hold-to-talk or toggle; Globe / Ctrl+Shift / F5 / custom.
- **Three output modes** — simulated keystrokes, clipboard paste, or Accessibility insertion,
  with configurable **typing speed**.
- **Automatic remote-session typing** — detects RDP/VM clients (Microsoft Remote Desktop /
  Windows App, Parallels, VMware, Citrix, Jump) and switches to hardware-faithful key-code
  output so dictation lands correctly inside the remote desktop (with a Ctrl+V fallback).
- **Dual-model mode** — run two Whisper models and merge by AI or an offline majority vote.
- **Optional AI polish** — clean up punctuation/casing via Ollama, OpenAI, Anthropic, or a
  custom endpoint. A failure here never drops your dictation (you still get the raw text).
- **Searchable history** (local SQLite) and a movable floating pill.
- **Guided first-run Setup + Diagnostics** — a one-click health check that verifies mic /
  accessibility permissions, whisper-cli, model, device, and end-to-end transcription, with
  fix buttons (grant permission, download a model, install whisper-cli) and "Set up everything".

## Requirements

- **macOS 14 (Sonoma) or later.**
- **Apple Silicon (M1 or newer)** for GPU (Metal) acceleration. The self-contained
  **complete** build is Apple-Silicon only; the lean build also runs on Intel but
  transcribes on the CPU (much slower).
- **Microphone** and **Accessibility** permissions — Accessibility is required to type
  text into other apps and to use global hotkeys.
- **Disk + memory for the Whisper model** you choose (see the table below).
- *(Optional)* **AI polish** needs its own provider: a local [Ollama](https://ollama.com)
  install + a pulled model, or an OpenAI / Anthropic API key. It's off by default and a
  failure here never drops your dictation.

### Whisper models — running the full model

YOLOWhisp defaults to **`large-v3-turbo`**, the most accurate model and the one bundled in the
complete build. Bigger models are more accurate but need more disk, memory, and time per
dictation; switch in **Settings → Whisper Model** if you're tight on resources. Models live in
`~/.local/share/whisper/` and the in-app **Setup** can download them for you.

| Model | Download size | Suggested free RAM | Notes |
|---|---|---|---|
| `tiny` | ~75 MB | 2 GB | Fastest, least accurate |
| `base` | ~140 MB | 2 GB | Lightweight |
| `small` | ~470 MB | 4 GB | Balanced |
| `medium` | ~1.5 GB | 8 GB | High accuracy |
| **`large-v3-turbo`** | **~1.5 GB** | **8 GB+ unified memory** | **Default — best accuracy, fast on Apple Silicon** |
| `large` | ~2.9 GB | 16 GB | Highest accuracy, slowest |

To run the full **`large-v3-turbo`** model comfortably, use an **Apple Silicon Mac with at least
8 GB of unified memory** and keep **~1.5 GB of free disk** for the model file. It works on 8 GB
machines; **16 GB+** is recommended if you also enable **dual-model** mode (loads two models at
once) or run heavy AI polish alongside it.

## Install

Two downloads on the [latest release](https://github.com/YOLOVibeCode/yolowhisp/releases/latest):

| Download | Who it's for |
|---|---|
| **`YOLOWhisp-<v>-complete-macOS.zip`** | **Apple Silicon, zero setup** — whisper + a model are bundled. Just unzip, move to /Applications, and grant permissions. |
| **`YOLOWhisp-<v>-macOS.zip`** | Lean universal build. Needs `whisper-cpp` + a model — the in-app **Setup** can install/download them for you. |

Both are signed with a Developer ID and notarized, so they open without Gatekeeper warnings.

### First run

Launch it and the **Setup** window walks you through everything:
1. **Microphone** and **Accessibility** permissions (Accessibility is required for typing/hotkeys).
2. **whisper-cli** + a **Whisper model** (the lean build offers one-click install/download).
3. Pick a **dictation shortcut**.

Click **Set up everything** to do all the fixes at once, then **Get Started**.

## Usage

- Focus any text field, **hold your hotkey and speak**, release — the text is typed in.
- Menu-bar icon → **Microphone**, **Recent Captures**, **Diagnostics**, **History**, **Settings**.
- **Settings** → output mode, typing speed, Whisper model, dual-opinion, AI polish, retention.
- **Diagnostics → Health** re-runs the full pipeline check anytime; **Logs** shows recent activity.

## Build from source

```bash
make build      # swift build
make test       # swift test (run the suite)
make run        # build a signed .app and launch it
make complete   # self-contained build (static whisper-cli + bundled model; needs cmake)
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for prerequisites, signing/notarization, and the build flavors,
[FINDINGS.md](FINDINGS.md) for the design rationale + benchmarks, and
[PUNCTUATION_RECIPE.md](PUNCTUATION_RECIPE.md) for the punctuation pipeline.
