#!/bin/bash
# YOLOWhisp transcription benchmark
# Tests speed + punctuation accuracy across whisper models

set -e

WHISPER="/opt/homebrew/bin/whisper-cli"
MODEL_DIR="$HOME/.local/share/whisper"
TMPDIR=$(mktemp -d)

# Test sentences with punctuation that matters
SENTENCES=(
    "Hello, my name is John. How are you doing today? I'm doing great, thanks!"
    "Please send the report to sales@company.com by Friday. It's urgent!"
    "The meeting is at 3:30 PM. Don't forget to bring the Q3 numbers, the budget spreadsheet, and your laptop."
    "Wait, what? You didn't finish the project? That's unacceptable. We need it done by tomorrow."
)

echo "============================================"
echo "  YOLOWhisp Transcription Benchmark"
echo "============================================"
echo ""

# Generate test audio files using macOS TTS
echo "Generating test audio files..."
for i in "${!SENTENCES[@]}"; do
    WAV="$TMPDIR/test_$i.wav"
    say -o "$TMPDIR/test_$i.aiff" "${SENTENCES[$i]}"
    # Convert AIFF to WAV 16kHz mono
    afconvert -f WAVE -d LEI16@16000 -c 1 "$TMPDIR/test_$i.aiff" "$WAV"
    DURATION=$(afinfo "$WAV" 2>/dev/null | grep "estimated duration" | awk '{print $3}')
    echo "  Test $((i+1)): ${DURATION}s audio"
done
echo ""

# Run benchmarks for each available model
for MODEL_FILE in "$MODEL_DIR"/ggml-*.bin; do
    [ -f "$MODEL_FILE" ] || continue
    MODEL_NAME=$(basename "$MODEL_FILE" .bin | sed 's/ggml-//')

    echo "--------------------------------------------"
    echo "  Model: $MODEL_NAME"
    echo "--------------------------------------------"

    TOTAL_TIME=0

    for i in "${!SENTENCES[@]}"; do
        WAV="$TMPDIR/test_$i.wav"
        EXPECTED="${SENTENCES[$i]}"

        # Time the transcription
        START=$(python3 -c "import time; print(time.time())")
        OUTPUT=$("$WHISPER" -m "$MODEL_FILE" -f "$WAV" -l en -np 2>/dev/null)
        END=$(python3 -c "import time; print(time.time())")

        ELAPSED=$(python3 -c "print(f'{$END - $START:.3f}')")
        TOTAL_TIME=$(python3 -c "print(f'{$TOTAL_TIME + $END - $START:.3f}')")

        # Parse output (strip timestamps)
        TRANSCRIBED=$(echo "$OUTPUT" | sed -n 's/.*\] *//p' | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

        echo ""
        echo "  Test $((i+1)) (${ELAPSED}s):"
        echo "    Expected:     $EXPECTED"
        echo "    Transcribed:  $TRANSCRIBED"

        # Check punctuation
        EXPECTED_PUNCT=$(echo "$EXPECTED" | grep -o '[.,!?;:'"'"']' | wc -l | tr -d ' ')
        GOT_PUNCT=$(echo "$TRANSCRIBED" | grep -o '[.,!?;:'"'"']' | wc -l | tr -d ' ')
        echo "    Punctuation:  expected=$EXPECTED_PUNCT got=$GOT_PUNCT"
    done

    echo ""
    echo "  Total transcription time: ${TOTAL_TIME}s"
    echo ""
done

# Cleanup
rm -rf "$TMPDIR"

echo "============================================"
echo "  Benchmark complete"
echo "============================================"
