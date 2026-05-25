# Developing YOLOWhisp

## Prerequisites

YOLOWhisp shells out to `whisper-cli` and needs at least one GGML model:

```bash
brew install whisper-cpp
mkdir -p ~/.local/share/whisper
curl -L -o ~/.local/share/whisper/ggml-base.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin
```

Optional AI Polish uses Ollama: `brew install ollama && ollama pull qwen2.5:3b-instruct`.

## Build, test, run

```bash
make build      # swift build (debug)
make test       # swift test
make app        # assemble build/YOLOWhisp.app (Info.plist + ad-hoc sign)
make run        # build the bundle and launch it (menu-bar app)
make clean
```

`CONFIG=release make app` produces an optimized bundle.

### Why the .app bundle matters

YOLOWhisp is a menu-bar (`LSUIElement`) app that needs **Microphone** and
**Accessibility** permissions. macOS only grants those to a real `.app` with an
`Info.plist` — `swift run` will silently fail to capture audio or post
keystrokes. Always test through `make run`.

First launch will prompt for Microphone, and you'll need to add the app under
**System Settings → Privacy & Security → Accessibility** for keystroke output
and global hotkeys. After a rebuild macOS may re-prompt; the bundle lives at a
fixed path (`build/YOLOWhisp.app`) to minimise that.

## Architecture

See [FINDINGS.md](FINDINGS.md) for the design rationale and benchmarks, and
[PUNCTUATION_RECIPE.md](PUNCTUATION_RECIPE.md) for the punctuation pipeline.
Code is protocol-oriented (`Sources/YOLOWhisp/Protocols/`) with dependency
injection throughout, so most logic is unit-tested without hardware.
