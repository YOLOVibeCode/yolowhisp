# Changelog

All notable changes to YOLOWhisp. Format based on [Keep a Changelog](https://keepachangelog.com/).

## [0.2.2] - 2026-05-28

### Added
- **Guided first-run Setup** — a friendly window that checks every requirement (mic +
  accessibility permissions, whisper-cli, a model) and offers one-click fixes plus a
  "Set up everything" button. Replaces the old onboarding window that was never opened.
- **Redesigned Diagnostics** that exercises the *real* app components (not clones), with a
  one-click **Health Check** (per-stage ok/warn/fail + remediation), live mic meter, a
  record→transcribe test, a hotkey live-test, and a Logs viewer.
- **Self-contained "complete" build** (`YOLOWhisp-<v>-complete-macOS.zip`, Apple Silicon):
  whisper-cli built from source with static backends + embedded Metal, plus a bundled model —
  no Homebrew or model download needed. `make complete` builds it locally.
- **Configurable typing speed** (fast / medium / slow) for simulated keystrokes.
- App logging (`AppLog`) to Console + a rolling file, surfaced in Diagnostics → Logs.

### Fixed
- **Silent capture**: multichannel input devices (e.g. some built-in mics reporting 4ch) were
  downmixed to silence — the converter now maps to channel 0. Device-selection failures fall
  back to the system default instead of capturing nothing.
- **Dictation crash**: keyboard-layout lookup ran off the main thread (HIToolbox SIGTRAP) —
  now runs on the main actor.
- **Window crash**: Diagnostics/Settings/History windows over-released on close
  (EXC_BAD_ACCESS) — now retained/reused via a window store.
- **Pipeline resilience**: an AI-polish or dual-merge failure (e.g. an Ollama 404) no longer
  aborts the whole dictation; it falls back to the raw transcription and still types + saves.
- AI Polish single-pass was a no-op (no provider injected); now wired. Onboarding hotkey
  presets now actually register.

### Changed
- Microphone selection routes the app's own engine (no longer changes the system default) and
  the engine is recreated per capture so it follows the current default device.
- Bundle identifier is `com.noctusoft.yolowhisp`.

## [0.2.1] - 2026-05-28

### Added
- Developer ID signing + notarized release pipeline; the downloaded app opens cleanly.

### Fixed
- Crash & data-loss hardening (Accessibility insert cast, clipboard restore, SQLite text
  binding, whisper-cli process timeout). First end-to-end fix of the dictation crash and
  initial diagnostics logging.

## [0.2.0] - 2026-05-26

### Added
- Phase 3 features: diagnostics view, sound feedback, custom menu-bar icons, hotkey recorder,
  dual-opinion polisher, `--prompt` punctuation conditioning, expanded settings.

## [0.1.0] - 2026-05-23

- Initial release: local whisper-cpp dictation, floating pill, hotkeys, history.

[0.2.2]: https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.2.2
[0.2.1]: https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.2.1
[0.2.0]: https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.2.0
[0.1.0]: https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.1.0
