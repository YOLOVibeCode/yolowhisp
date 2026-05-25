#!/bin/bash
# Test the --prompt flag's effect on punctuation
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
echo "============================================"
echo "  --prompt flag test (base model)"
echo "============================================"

for i in "${!SENTENCES[@]}"; do
    WAV="$TMPDIR/test_$i.wav"
    echo ""
    echo "TEST $((i+1)): ${SENTENCES[$i]}"

    # Without prompt
    START=$(python3 -c "import time; print(time.time())")
    NO_PROMPT=$("$WHISPER" -m "$MODEL_DIR/ggml-base.bin" -f "$WAV" -l en -np 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    NO_PROMPT_TEXT=$(echo "$NO_PROMPT" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    T1=$(python3 -c "print(f'{$END-$START:.3f}')")

    # With prompt
    START=$(python3 -c "import time; print(time.time())")
    WITH_PROMPT=$("$WHISPER" -m "$MODEL_DIR/ggml-base.bin" -f "$WAV" -l en -np --prompt "$PROMPT" 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    WITH_PROMPT_TEXT=$(echo "$WITH_PROMPT" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    T2=$(python3 -c "print(f'{$END-$START:.3f}')")

    echo "  No prompt (${T1}s):   $NO_PROMPT_TEXT"
    echo "  With prompt (${T2}s): $WITH_PROMPT_TEXT"
done

echo ""
echo "============================================"
echo "  --prompt flag test (small model)"
echo "============================================"

for i in "${!SENTENCES[@]}"; do
    WAV="$TMPDIR/test_$i.wav"
    echo ""
    echo "TEST $((i+1)): ${SENTENCES[$i]}"

    START=$(python3 -c "import time; print(time.time())")
    NO_PROMPT=$("$WHISPER" -m "$MODEL_DIR/ggml-small.bin" -f "$WAV" -l en -np 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    NO_PROMPT_TEXT=$(echo "$NO_PROMPT" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    T1=$(python3 -c "print(f'{$END-$START:.3f}')")

    START=$(python3 -c "import time; print(time.time())")
    WITH_PROMPT=$("$WHISPER" -m "$MODEL_DIR/ggml-small.bin" -f "$WAV" -l en -np --prompt "$PROMPT" 2>/dev/null)
    END=$(python3 -c "import time; print(time.time())")
    WITH_PROMPT_TEXT=$(echo "$WITH_PROMPT" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g;s/^ *//;s/ *$//')
    T2=$(python3 -c "print(f'{$END-$START:.3f}')")

    echo "  No prompt (${T1}s):   $NO_PROMPT_TEXT"
    echo "  With prompt (${T2}s): $WITH_PROMPT_TEXT"
done

rm -rf "$TMPDIR"
echo ""
echo "Done."
