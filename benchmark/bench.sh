#!/bin/bash
# Benchmark whisper-cpp across models on 50 LibriSpeech test-clean samples
# Measures Word Error Rate (WER) and speed

MODELS_DIR="models"
DATA_DIR="LibriSpeech/test-clean"
RESULTS_DIR="results"
mkdir -p "$RESULTS_DIR" wav_samples

# Collect 50 samples from different speakers
SAMPLES=()
for trans_file in $(find "$DATA_DIR" -name "*.trans.txt" | head -10); do
    dir=$(dirname "$trans_file")
    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        ref=$(echo "$line" | cut -d' ' -f2-)
        flac="$dir/$id.flac"
        if [ -f "$flac" ]; then
            wav="wav_samples/$id.wav"
            if [ ! -f "$wav" ]; then
                ffmpeg -i "$flac" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" -y 2>/dev/null
            fi
            SAMPLES+=("$id|$wav|$ref")
        fi
        [ ${#SAMPLES[@]} -ge 50 ] && break
    done < "$trans_file"
    [ ${#SAMPLES[@]} -ge 50 ] && break
done

echo "Collected ${#SAMPLES[@]} samples"
echo ""

for model_file in "$MODELS_DIR"/ggml-*.bin; do
    model_name=$(basename "$model_file" .bin | sed 's/ggml-//')
    echo "=== Model: $model_name ==="
    
    total_words=0
    total_errors=0
    total_time=0
    total_audio_dur=0
    
    for entry in "${SAMPLES[@]}"; do
        IFS='|' read -r id wav ref <<< "$entry"
        
        # Get audio duration
        dur=$(ffprobe -i "$wav" -show_entries format=duration -v quiet -of csv="p=0" 2>/dev/null)
        total_audio_dur=$(echo "$total_audio_dur + $dur" | bc)
        
        # Run whisper-cpp and time it
        start=$(python3 -c "import time; print(time.time())")
        hyp=$(whisper-cli -m "$model_file" -f "$wav" -l en -np 2>/dev/null | grep -oP '(?<=\]  ).*')
        end=$(python3 -c "import time; print(time.time())")
        elapsed=$(echo "$end - $start" | bc)
        total_time=$(echo "$total_time + $elapsed" | bc)
        
        # Normalize both to uppercase, remove punctuation
        ref_clean=$(echo "$ref" | tr '[:lower:]' '[:upper:]' | sed "s/[^A-Z ]//g" | xargs)
        hyp_clean=$(echo "$hyp" | tr '[:lower:]' '[:upper:]' | sed "s/[^A-Z ]//g" | xargs)
        
        # Simple word-level error count
        ref_words=($ref_clean)
        hyp_words=($hyp_clean)
        total_words=$((total_words + ${#ref_words[@]}))
        
        # Count mismatches (simple diff-based)
        errors=$(diff <(printf '%s\n' "${ref_words[@]}") <(printf '%s\n' "${hyp_words[@]}") | grep -c "^[<>]")
        errors=$((errors / 2))  # rough approximation
        total_errors=$((total_errors + errors))
    done
    
    wer=$(echo "scale=2; $total_errors * 100 / $total_words" | bc)
    rtf=$(echo "scale=3; $total_time / $total_audio_dur" | bc)
    avg_time=$(echo "scale=3; $total_time / ${#SAMPLES[@]}" | bc)
    
    echo "  Samples: ${#SAMPLES[@]}"
    echo "  Total audio: ${total_audio_dur}s"
    echo "  Total processing: ${total_time}s"  
    echo "  Avg per sample: ${avg_time}s"
    echo "  Real-time factor: ${rtf}x (lower = faster)"
    echo "  Word Error Rate: ${wer}%"
    echo ""
done
