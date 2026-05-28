# YOLOWhisp

Fully local, fast speech-to-text for macOS — a native menu-bar dictation app powered by
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal GPU acceleration. Nothing
leaves your machine. Hold a hotkey, talk, and the text is typed into whatever app you're in.

## Features

- **100% local transcription** via `whisper-cli` (Metal-accelerated). No cloud, no account.
- **Global hotkeys** — hold-to-talk or toggle; Globe / Ctrl+Shift / F5 / custom.
- **Three output modes** — simulated keystrokes (works everywhere, incl. Parallels/RDP),
  clipboard paste, or Accessibility insertion. Configurable **typing speed**.
- **Dual-model mode** — run two Whisper models and merge by AI or an offline majority vote.
- **Optional AI polish** — clean up punctuation/casing via Ollama, OpenAI, Anthropic, or a
  custom endpoint. A failure here never drops your dictation (you still get the raw text).
- **Searchable history** (local SQLite) and a movable floating pill.
- **Guided first-run Setup + Diagnostics** — a one-click health check that verifies mic /
  accessibility permissions, whisper-cli, model, device, and end-to-end transcription, with
  fix buttons (grant permission, download a model, install whisper-cli) and "Set up everything".

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

Requires macOS 14+.
