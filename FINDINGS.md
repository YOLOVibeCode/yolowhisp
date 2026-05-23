# YOLOWhisp - Fully Local Speech-to-Text for macOS

## Concept
Native macOS speech-to-text app using whisper-cpp with Metal GPU acceleration.
100% local — no data leaves the machine. Movable floating pill UI.

## Benchmark Results (50 LibriSpeech samples, 238s audio)

### whisper-cpp on Metal (Apple Silicon)
| Model | WER    | Avg/sample | Real-time factor |
|-------|--------|-----------|-----------------|
| tiny  | 12.32% | 0.565s    | 0.118x          |
| base  | 8.43%  | 0.560s    | 0.117x          |
| small | 5.76%  | 0.561s    | 0.118x          |

All three models run at the same speed on Metal. **Use small — best accuracy, no speed penalty.**

### vs CPU (openai-whisper Python)
| Model | CPU time | Metal time | Speedup |
|-------|----------|-----------|---------|
| base  | 18.6s    | 0.6s      | 31x     |
| small | 58.8s    | 0.57s     | 103x    |

### Post-processing models (TESTED AND REJECTED)
| Pipeline                          | WER    | Verdict |
|-----------------------------------|--------|---------|
| Whisper-cpp small alone           | 5.76%  | BEST    |
| + fullstop-punctuation-multilang  | 45.52% | Destroys words via tokenizer mismatch |
| + Qwen 2.5 3B (Ollama)           | 17.69% | Hallucinate/paraphrases, worse |
| + Cadence-Fast                    | —      | Incompatible with transformers 5.9 |

**Key finding: Whisper small already outputs good punctuation. No post-processing needed.**

## Text Output Modes (CRITICAL)
Must support multiple ways to deliver text to the active application:

1. **Clipboard Paste** (default) — `pbcopy` + simulated Cmd+V. Fastest, but fails across
   Parallels, Remote Desktop, and some sandboxed apps.

2. **Simulated Keystrokes** — CGEvent key-by-key typing. Works everywhere including
   Parallels/RDP/VMs. Visually types words rapidly. Slightly slower but universal.

3. **Accessibility Insertion** — AXUIElement text insertion via Accessibility API.
   Most reliable for native macOS apps, doesn't touch clipboard.

User should be able to pick the mode in settings. Default to keystrokes for maximum
compatibility, with paste as the fast option.

## Hotkey System
Multiple configurable hotkeys, each can trigger different actions:

**Hotkey recorder UI** — click a field, press any key combo, it captures it (like macOS 
Keyboard Shortcuts preferences). No typing — just press what you want.

**First-run experience:**
On first launch, a simple prompt: "Pick your dictation shortcut" with common presets:
- Globe key (replaces macOS dictation)
- Ctrl+Shift (sflow-style)
- Double-tap Fn
- F5
- Custom (opens recorder)
One click to select, one click to confirm. Done — you're dictating.

**Power users — multiple shortcuts with different behaviors:**
- Hotkey 1: Hold-to-record (release to transcribe) — e.g., Ctrl+Shift
- Hotkey 2: Toggle recording on/off — e.g., F5
- Hotkey 3: Record + AI Polish — e.g., Cmd+Shift+D
- Hotkey 4: Record to clipboard only (don't paste) — e.g., custom
- User can add/remove as many as they want

**Each hotkey is independently configurable:**
- Trigger mode: hold-to-record, toggle, double-tap
- Output mode: paste, keystrokes, clipboard-only
- Post-processing: on/off, which model
- Whisper model: tiny (fastest) vs small (most accurate)

Stored in UserDefaults. Conflict detection warns if a shortcut overlaps 
with system or other app shortcuts.

## Pill Drag Behavior
The pill must NOT be accidentally movable. Drag requires a deliberate long-press unlock:

1. **Normal state** — pill is locked in place. Single clicks and short presses trigger recording.
2. **Long-press (~500ms)** — pill enters "drag mode": visual feedback (subtle jiggle/glow,
   like iOS icon rearrange). Haptic feedback if available.
3. **Drag mode** — pill follows cursor freely, can be placed anywhere on screen. No edge
   snapping unless user wants it (configurable). Semi-transparent during drag.
4. **Release** — pill locks into new position. Position persists across app restarts
   (saved to UserDefaults).
5. **Click away or Escape** — exits drag mode without moving.

## Optional Post-Processing (AI Polish Mode)
Off by default. When enabled, pipes Whisper output through an LLM for formatting/cleanup.

**Built-in provider support:**
- Ollama (local) — any model: qwen2.5, llama3.3, mistral, etc.
- OpenAI API (cloud) — GPT-4o, etc.
- Anthropic API (cloud) — Claude
- Custom/BYO model — user provides endpoint URL + API key

**Settings:**
- Toggle: "AI Polish" on/off
- Model selector dropdown (auto-discovers Ollama models)
- Custom prompt field (user can tune the correction prompt)
- API key fields for cloud providers
- Note: Post-processing adds latency. For vibe-coding, punctuation matters less — 
  keep it off. For emails/docs, turn it on.

## Transcription History
Searchable history of all transcriptions, like superwhisper/Wispr Flow:

- **History panel** accessible from menu bar icon or hotkey
- Each entry shows: timestamp, raw transcription, post-processed version (if used),
  duration, model used, which app it was pasted into
- **Search** across all history
- **Copy** any past transcription
- **Re-paste** into current app
- **Delete** individual entries or clear all
- Stored locally in SQLite — never leaves the machine
- Configurable retention (7 days, 30 days, forever)

## Why Not macOS Dictation?
- Already local on Apple Silicon since Ventura
- But accuracy is noticeably worse than Whisper
- No customization

## Why Not sflow / superwhisper / Wispr Flow?
- sflow: Cloud API (Groq), Python, not native
- superwhisper: Good but not open source, can't customize
- Wispr Flow: $15/mo subscription, cloud, pill locked to bottom-center

## Architecture (Native Swift)
```
YOLOWhisp/
├── App/
│   ├── YOLOWhispApp.swift          # Menu bar app entry
│   └── AppDelegate.swift           # Lifecycle, permissions
├── UI/
│   ├── PillView.swift              # Floating pill (NSPanel), long-press to drag
│   ├── PillDragController.swift    # Long-press unlock → free drag → snap to position
│   ├── PillVisualizer.swift        # Audio waveform bars
│   └── SettingsView.swift          # Preferences window
├── Audio/
│   ├── AudioCapture.swift          # AVAudioEngine, mic selection
│   └── AudioBuffer.swift           # Ring buffer for recording
├── Whisper/
│   ├── WhisperBridge.h             # C bridging header for whisper.cpp
│   ├── WhisperEngine.swift         # Transcription engine
│   └── ModelManager.swift          # Model loading/selection
├── Output/
│   ├── TextOutputManager.swift     # Routes to correct output mode
│   ├── ClipboardPaster.swift       # pbcopy + Cmd+V
│   ├── KeystrokeTyper.swift        # CGEvent simulated typing
│   └── AccessibilityInserter.swift # AXUIElement text insertion
├── PostProcess/
│   ├── PostProcessor.swift         # Protocol for all post-processing providers
│   ├── OllamaProvider.swift        # Local Ollama (auto-discovers models)
│   ├── OpenAIProvider.swift        # OpenAI API
│   ├── AnthropicProvider.swift     # Claude API
│   └── CustomProvider.swift        # BYO endpoint URL + API key
├── History/
│   ├── HistoryStore.swift          # SQLite storage
│   ├── HistoryEntry.swift          # Model: timestamp, text, app, model, duration
│   ├── HistoryView.swift           # Searchable history panel
│   └── HistoryManager.swift        # Retention policy, search, export
├── Hotkey/
│   ├── HotkeyManager.swift         # Global shortcut registration, multiple hotkeys
│   ├── HotkeyRecorder.swift        # "Press any key" capture UI (like macOS Shortcuts)
│   └── DoubleTapDetector.swift     # Double-tap trigger detection
├── Models/                         # GGML model files
│   ├── ggml-tiny.bin
│   ├── ggml-base.bin
│   └── ggml-small.bin
└── Resources/
    └── Info.plist
```

## Tools & Models
- `whisper-cli` / whisper.cpp (Homebrew, Metal-accelerated)
- Models: ggml-tiny.bin (75MB), ggml-base.bin (141MB), ggml-small.bin (465MB)
- LibriSpeech test-clean: 2,620 samples for benchmarking

## Reproducible Benchmark
```bash
cd /path/to/yolowhisp
bash setup.sh
source venv/bin/activate
python pipeline/benchmark_pipeline.py
```
