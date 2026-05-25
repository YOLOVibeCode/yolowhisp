# YOLOWhisp Punctuation Recipe

## Recommended Pipeline

**`base model` + `--prompt` flag → `qwen2.5:3b-instruct` AI polish**

Total latency: ~1.1s for typical dictation clips (4-6s audio).

## Setup

### 1. Whisper Model

```bash
# Download base model (141MB) — best speed/quality ratio
curl -L -o ~/.local/share/whisper/ggml-base.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
```

### 2. The `--prompt` Flag (Free Win)

Conditioning Whisper's decoder with a well-punctuated example dramatically improves punctuation output at zero speed cost.

```bash
whisper-cli -m ggml-base.bin -f audio.wav -l en -np \
  --prompt "Hello, how are you? I'm doing great! That's wonderful. Let's meet at 3:30 PM. Don't forget — it's urgent!"
```

**What it fixes:**
- Restores exclamation marks (`Thanks.` → `Thanks!`)
- Capitalizes PM (`pm` → `PM`)
- Adds Oxford commas
- Produces em dashes where appropriate

This is built into `WhisperEngine.swift` via the `initialPrompt` property.

### 3. AI Polish via Ollama (Optional, +0.5s)

```bash
# Install qwen2.5:3b-instruct
ollama pull qwen2.5:3b-instruct
```

Enable "AI Polish" in Settings with:
- Provider: Ollama
- Model: `qwen2.5:3b-instruct`

**What it fixes (on top of --prompt):**
- `3.30` → `3:30` (time formatting)
- Adds `!` where tone is emphatic
- Fixes remaining capitalization issues

### 4. Dual Opinion Mode (Optional)

Runs two Whisper models (e.g., base + small) in parallel, then merges via AI. Both models run in ~0.6s in parallel, so no speed penalty for transcription — only the merge step adds latency.

Enable in Settings → "Dual Opinion" → pick second model.

## Benchmark Results (Apple Silicon)

| Approach | Speed | Punctuation Quality |
|---|---|---|
| base (no prompt) | 0.58s | Misses `!`, lowercase `pm` |
| **base + prompt** | **0.58s** | **Adds `!`, `PM`, Oxford comma** |
| small + prompt | 0.58s | Similar, adds em dashes |
| large-v3-turbo + prompt | 1.09s | Best raw quality but occasional hallucination |
| base+prompt → qwen2.5:3b | **~1.1s total** | **Fixes 3.30→3:30, adds tone-appropriate `!`** |
| base+prompt → qwen3:0.6b | ~2.0s total | Unreliable (sometimes eats prompt) |

## Models Tested But Not Recommended

- **large-v3-turbo**: Hallucinated on one test ("advertisers" instead of actual speech). Not reliable enough for a dictation tool.
- **qwen3:0.6b**: Too small — sometimes includes its own system prompt in output.
- **deepmultilingualpunctuation** (Python/XLM-RoBERTa): Tokenizer splits words badly with newer transformers library. Not suitable as post-processor.

## Available Whisper Models

```bash
ls ~/.local/share/whisper/
# ggml-base.bin       (141MB) — recommended default
# ggml-small.bin      (465MB) — good for dual opinion second model
# ggml-large-v3-turbo.bin (1.5GB) — not recommended (hallucination risk)
```

## Ollama Models for Polish

```
qwen2.5:3b-instruct  — recommended (fast, reliable, ~0.5s)
qwen2.5-coder:7b     — overkill for punctuation
llama3.3:70b         — way too slow for real-time dictation
```
