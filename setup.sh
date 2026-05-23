#!/bin/bash
# ============================================================================
# YOLOWhisp - Setup & Benchmark
# Fully local speech-to-text pipeline on Apple Silicon
# ============================================================================
set -e

echo "=========================================="
echo "YOLOWhisp Setup"
echo "=========================================="

# ── 1. System Dependencies ────────────────────────────────────────────
echo ""
echo "[1/5] Installing system dependencies..."
brew install whisper-cpp ffmpeg 2>/dev/null || echo "  Already installed"

# ── 2. Python Environment ────────────────────────────────────────────
echo ""
echo "[2/5] Setting up Python environment..."
python3 -m venv venv
source venv/bin/activate
pip install --quiet transformers torch

# ── 3. Whisper GGML Models ────────────────────────────────────────────
echo ""
echo "[3/5] Downloading Whisper models (Metal-accelerated)..."
mkdir -p benchmark/models

for model in tiny base small; do
    dest="benchmark/models/ggml-${model}.bin"
    if [ ! -f "$dest" ]; then
        echo "  Downloading ggml-${model}.bin..."
        curl -L -o "$dest" \
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${model}.bin"
    else
        echo "  ggml-${model}.bin already exists"
    fi
done

# ── 4. LibriSpeech Test Data ─────────────────────────────────────────
echo ""
echo "[4/5] Downloading LibriSpeech test-clean (346MB)..."
mkdir -p benchmark
if [ ! -d "benchmark/LibriSpeech/test-clean" ]; then
    curl -L -o benchmark/test-clean.tar.gz \
        "https://www.openslr.org/resources/12/test-clean.tar.gz"
    tar xzf benchmark/test-clean.tar.gz -C benchmark/
    rm benchmark/test-clean.tar.gz
else
    echo "  Already downloaded"
fi

# Convert 50 samples to 16kHz WAV
echo "  Converting samples to WAV..."
mkdir -p benchmark/wav_samples
count=0
for trans_file in $(find benchmark/LibriSpeech/test-clean -name "*.trans.txt" | head -10); do
    dir=$(dirname "$trans_file")
    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        flac="$dir/$id.flac"
        wav="benchmark/wav_samples/$id.wav"
        if [ -f "$flac" ] && [ ! -f "$wav" ]; then
            ffmpeg -i "$flac" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" -y 2>/dev/null
        fi
        count=$((count + 1))
        [ $count -ge 50 ] && break
    done < "$trans_file"
    [ $count -ge 50 ] && break
done
echo "  $count samples ready"

# ── 5. Optional: Ollama for LLM post-processing ─────────────────────
echo ""
echo "[5/5] Checking Ollama (optional)..."
if command -v ollama &>/dev/null; then
    echo "  Ollama found. Pulling qwen2.5:3b-instruct..."
    ollama pull qwen2.5:3b-instruct 2>/dev/null || true
else
    echo "  Ollama not installed (optional - for LLM post-processing)"
    echo "  Install: brew install ollama"
fi

# ── Done ─────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "Setup complete!"
echo ""
echo "Run the benchmark:"
echo "  source venv/bin/activate"
echo "  python pipeline/benchmark_pipeline.py"
echo "=========================================="
