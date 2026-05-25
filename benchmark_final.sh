#!/bin/bash
# Final showdown: all punctuation approaches compared
set -e

WHISPER="/opt/homebrew/bin/whisper-cli"
MODEL_DIR="$HOME/.local/share/whisper"
TMPDIR=$(mktemp -d)

PROMPT="Hello, how are you? I'm doing great! That's wonderful. Let's meet at 3:30 PM. Don't forget — it's urgent!"

SENTENCES=(
    "Hello, my name is John. How are you doing today? I am doing great, thanks!"
    "Please send the report to sales at company dot com by Friday. It is urgent!"
    "The meeting is at 3 30 PM. Do not forget to bring the Q3 numbers, the budget spreadsheet, and your laptop."
    "Wait, what? You did not finish the project? That is unacceptable. We need it done by tomorrow."
)

echo "Generating audio..."
for i in "${!SENTENCES[@]}"; do
    say -o "$TMPDIR/test_$i.aiff" "${SENTENCES[$i]}"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$TMPDIR/test_$i.aiff" "$TMPDIR/test_$i.wav"
done

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        PUNCTUATION APPROACH SHOWDOWN                ║"
echo "╚══════════════════════════════════════════════════════╝"

for i in "${!SENTENCES[@]}"; do
    WAV="$TMPDIR/test_$i.wav"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TEST $((i+1)): ${SENTENCES[$i]}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 1. Base, no prompt
    START=$(python3 -c "import time; print(time.time())")
    R=$("$WHISPER" -m "$MODEL_DIR/ggml-base.bin" -f "$WAV" -l en -np 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(f'{$END-$START:.3f}')")
    TEXT=$(echo "$R" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    echo "  1) base (${T}s):                $TEXT"

    # 2. Base + prompt
    START=$(python3 -c "import time; print(time.time())")
    R=$("$WHISPER" -m "$MODEL_DIR/ggml-base.bin" -f "$WAV" -l en -np --prompt "$PROMPT" 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(f'{$END-$START:.3f}')")
    TEXT=$(echo "$R" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    echo "  2) base+prompt (${T}s):         $TEXT"
    echo "$TEXT" > "$TMPDIR/base_prompt_$i.txt"

    # 3. Small + prompt
    START=$(python3 -c "import time; print(time.time())")
    R=$("$WHISPER" -m "$MODEL_DIR/ggml-small.bin" -f "$WAV" -l en -np --prompt "$PROMPT" 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(f'{$END-$START:.3f}')")
    TEXT=$(echo "$R" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    echo "  3) small+prompt (${T}s):        $TEXT"

    # 4. large-v3-turbo + prompt
    START=$(python3 -c "import time; print(time.time())")
    R=$("$WHISPER" -m "$MODEL_DIR/ggml-large-v3-turbo.bin" -f "$WAV" -l en -np --prompt "$PROMPT" 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(f'{$END-$START:.3f}')")
    TEXT=$(echo "$R" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    echo "  4) turbo+prompt (${T}s):        $TEXT"

    # 5. Base+prompt → qwen3:0.6b polish
    BASE_TEXT=$(cat "$TMPDIR/base_prompt_$i.txt")
    START=$(python3 -c "import time; print(time.time())")
    POLISHED=$(python3 << PYEOF
import json, urllib.request
with open("$TMPDIR/base_prompt_$i.txt") as f:
    text = f.read().strip()
prompt = "Fix punctuation and capitalization. Keep exclamation marks where the tone is emphatic. Return ONLY the corrected text, nothing else.\n\n" + text
data = json.dumps({"model": "qwen3:0.6b", "prompt": prompt, "stream": False}).encode()
req = urllib.request.Request("http://localhost:11434/api/generate", data=data, headers={"Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req).read())
r = resp.get("response", "").strip()
# Strip thinking tags if present
import re
r = re.sub(r'<think>.*?</think>', '', r, flags=re.DOTALL).strip()
print(r)
PYEOF
    )
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(f'{$END-$START:.3f}')")
    echo "  5) base+prompt→qwen3:0.6b (${T}s): $POLISHED"

    # 6. Base+prompt → qwen2.5:3b polish
    START=$(python3 -c "import time; print(time.time())")
    POLISHED2=$(python3 << PYEOF
import json, urllib.request
with open("$TMPDIR/base_prompt_$i.txt") as f:
    text = f.read().strip()
prompt = "Fix punctuation and capitalization. Keep exclamation marks where the tone is emphatic. Return ONLY the corrected text, nothing else.\n\n" + text
data = json.dumps({"model": "qwen2.5:3b-instruct", "prompt": prompt, "stream": False}).encode()
req = urllib.request.Request("http://localhost:11434/api/generate", data=data, headers={"Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req).read())
print(resp.get("response", "").strip())
PYEOF
    )
    END=$(python3 -c "import time; print(time.time())")
    T=$(python3 -c "print(f'{$END-$START:.3f}')")
    echo "  6) base+prompt→qwen2.5:3b (${T}s): $POLISHED2"
done

rm -rf "$TMPDIR"
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        BENCHMARK COMPLETE                           ║"
echo "╚══════════════════════════════════════════════════════╝"
