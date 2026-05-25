#!/bin/bash
# Dual Opinion benchmark: two whisper models → LLM merge
set -e

WHISPER="/opt/homebrew/bin/whisper-cli"
MODEL_DIR="$HOME/.local/share/whisper"
TMPDIR=$(mktemp -d)
OLLAMA_MODEL="qwen2.5:3b-instruct"

SENTENCES=(
    "Hello, my name is John. How are you doing today? I am doing great, thanks!"
    "Please send the report to sales at company dot com by Friday. It is urgent!"
    "The meeting is at 3 30 PM. Do not forget to bring the Q3 numbers, the budget spreadsheet, and your laptop."
    "Wait, what? You did not finish the project? That is unacceptable. We need it done by tomorrow."
)

EXPECTED=(
    "Hello, my name is John. How are you doing today? I am doing great, thanks!"
    "Please send the report to sales@company.com by Friday. It's urgent!"
    "The meeting is at 3:30 PM. Don't forget to bring the Q3 numbers, the budget spreadsheet, and your laptop."
    "Wait, what? You didn't finish the project? That's unacceptable. We need it done by tomorrow."
)

echo "============================================"
echo "  Dual Opinion Benchmark"
echo "  Models: base + small → $OLLAMA_MODEL"
echo "============================================"
echo ""

# Generate test audio
echo "Generating test audio..."
for i in "${!SENTENCES[@]}"; do
    say -o "$TMPDIR/test_$i.aiff" "${SENTENCES[$i]}"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$TMPDIR/test_$i.aiff" "$TMPDIR/test_$i.wav"
done
echo ""

SINGLE_PROMPT="Fix the punctuation, capitalization, and any obvious misheard words. Add correct punctuation: periods, commas, question marks, exclamation marks. Preserve tone - questions stay questions, exclamations stay exclamations. Do NOT add or remove content. Return ONLY the corrected text."

MERGE_PROMPT="You are a transcription editor. You receive multiple versions of the same spoken text from different speech recognition models. Produce a single final version that:
1. Picks the most accurate wording from whichever version got it right
2. Has correct punctuation: periods, commas, question marks, exclamation marks, colons, semicolons, apostrophes
3. Has proper capitalization
4. Preserves the speakers intended tone - questions stay questions, exclamations stay exclamations
5. Does NOT add, remove, or rephrase content
Return ONLY the final corrected text. No explanations, no labels, no quotes."

for i in "${!SENTENCES[@]}"; do
    WAV="$TMPDIR/test_$i.wav"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "TEST $((i+1))"
    echo "Expected: ${EXPECTED[$i]}"
    echo ""

    # Run both models in parallel
    START=$(python3 -c "import time; print(time.time())")
    "$WHISPER" -m "$MODEL_DIR/ggml-base.bin" -f "$WAV" -l en -np > "$TMPDIR/base_$i.txt" 2>/dev/null &
    PID1=$!
    "$WHISPER" -m "$MODEL_DIR/ggml-small.bin" -f "$WAV" -l en -np > "$TMPDIR/small_$i.txt" 2>/dev/null &
    PID2=$!
    wait $PID1 $PID2
    WHISPER_END=$(python3 -c "import time; print(time.time())")

    BASE_TEXT=$(sed -n 's/.*\] *//p' "$TMPDIR/base_$i.txt" | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    SMALL_TEXT=$(sed -n 's/.*\] *//p' "$TMPDIR/small_$i.txt" | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')

    # Save to files for python to read safely
    echo "$BASE_TEXT" > "$TMPDIR/base_clean_$i.txt"
    echo "$SMALL_TEXT" > "$TMPDIR/small_clean_$i.txt"

    WHISPER_TIME=$(python3 -c "print(f'{$WHISPER_END - $START:.3f}')")
    echo "  Base:  $BASE_TEXT"
    echo "  Small: $SMALL_TEXT"
    echo "  Whisper time (parallel): ${WHISPER_TIME}s"
    echo ""

    # --- Single model + AI polish ---
    POLISH_START=$(python3 -c "import time; print(time.time())")
    SINGLE_POLISHED=$(python3 << PYEOF
import json, urllib.request
with open("$TMPDIR/base_clean_$i.txt") as f:
    base_text = f.read().strip()
prompt = """$SINGLE_PROMPT

""" + base_text
data = json.dumps({"model": "$OLLAMA_MODEL", "prompt": prompt, "stream": False}).encode()
req = urllib.request.Request("http://localhost:11434/api/generate", data=data, headers={"Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req).read())
print(resp.get("response", "").strip())
PYEOF
    )
    POLISH_END=$(python3 -c "import time; print(time.time())")
    POLISH_TIME=$(python3 -c "print(f'{$POLISH_END - $POLISH_START:.3f}')")

    echo "  [Single + Polish] (${POLISH_TIME}s):"
    echo "    $SINGLE_POLISHED"

    # --- Dual opinion merge ---
    MERGE_START=$(python3 -c "import time; print(time.time())")
    MERGED=$(python3 << PYEOF
import json, urllib.request
with open("$TMPDIR/base_clean_$i.txt") as f:
    base_text = f.read().strip()
with open("$TMPDIR/small_clean_$i.txt") as f:
    small_text = f.read().strip()
merge_prompt = """$MERGE_PROMPT"""
user_input = f"VERSION 1:\n{base_text}\n\nVERSION 2:\n{small_text}"
full_prompt = merge_prompt + "\n\n" + user_input
data = json.dumps({"model": "$OLLAMA_MODEL", "prompt": full_prompt, "stream": False}).encode()
req = urllib.request.Request("http://localhost:11434/api/generate", data=data, headers={"Content-Type": "application/json"})
resp = json.loads(urllib.request.urlopen(req).read())
print(resp.get("response", "").strip())
PYEOF
    )
    MERGE_END=$(python3 -c "import time; print(time.time())")
    MERGE_TIME=$(python3 -c "print(f'{$MERGE_END - $MERGE_START:.3f}')")

    echo ""
    echo "  [Dual Opinion Merge] (${MERGE_TIME}s):"
    echo "    $MERGED"

    # Punctuation comparison
    EXP_PUNCT=$(echo "${EXPECTED[$i]}" | grep -o '[.,!?;:'"'"']' | wc -l | tr -d ' ')
    BASE_PUNCT=$(echo "$BASE_TEXT" | grep -o '[.,!?;:'"'"']' | wc -l | tr -d ' ')
    SINGLE_PUNCT=$(echo "$SINGLE_POLISHED" | grep -o '[.,!?;:'"'"']' | wc -l | tr -d ' ')
    MERGED_PUNCT=$(echo "$MERGED" | grep -o '[.,!?;:'"'"']' | wc -l | tr -d ' ')

    echo ""
    echo "  Punctuation — expected:$EXP_PUNCT  raw-base:$BASE_PUNCT  single+polish:$SINGLE_PUNCT  dual-merged:$MERGED_PUNCT"
    echo ""
done

rm -rf "$TMPDIR"
echo "============================================"
echo "  Benchmark complete"
echo "============================================"
