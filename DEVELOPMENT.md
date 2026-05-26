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

## Signing & notarized distribution

Local builds (`make app` / `make run`) are **ad-hoc signed** — fine on your own
machine. For a build you can hand to other people you need a Developer ID
signature + Apple notarization, otherwise Gatekeeper blocks it ("app is
damaged / can't be opened").

**Signed local build** (Developer ID cert must be in your keychain):

```bash
make app-signed                       # uses the NoctuSoft Developer ID
SIGN_ID="Developer ID Application: …" make app-signed   # or override
```

This applies the hardened runtime + the microphone entitlement
([scripts/YOLOWhisp.entitlements](scripts/YOLOWhisp.entitlements)). It is signed
but **not notarized** — notarization happens in CI on tagged releases.

**Release CI** ([.github/workflows/release.yml](.github/workflows/release.yml))
signs, notarizes (`notarytool --wait`), and staples on every `v*` tag — but
only if these repo secrets are set (Settings → Secrets and variables → Actions).
Without them the release still builds, just unsigned.

| Secret | What it is |
|---|---|
| `MACOS_CERT_P12` | base64 of your exported Developer ID Application `.p12` |
| `MACOS_CERT_PASSWORD` | the password you set when exporting the `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_PASSWORD` | app-specific password (appleid.apple.com → Sign-In & Security) |
| `APPLE_TEAM_ID` | `N42FM5L5KD` |
| `MACOS_SIGN_IDENTITY` | *(optional)* override the signing identity string |

Export the certificate once:

```bash
# Keychain Access → "Developer ID Application: NoctuSoft, Inc." → Export → .p12
base64 -i DeveloperID.p12 | pbcopy      # paste into the MACOS_CERT_P12 secret
```

## Architecture

See [FINDINGS.md](FINDINGS.md) for the design rationale and benchmarks, and
[PUNCTUATION_RECIPE.md](PUNCTUATION_RECIPE.md) for the punctuation pipeline.
Code is protocol-oriented (`Sources/YOLOWhisp/Protocols/`) with dependency
injection throughout, so most logic is unit-tested without hardware.
