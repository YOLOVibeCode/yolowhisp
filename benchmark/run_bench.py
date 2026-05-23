#!/usr/bin/env python3
"""WER benchmark for whisper-cpp models on LibriSpeech test-clean."""

import subprocess
import os
import time
import re
from pathlib import Path

BENCH_DIR = Path(__file__).parent
MODELS_DIR = BENCH_DIR / "models"
WAV_DIR = BENCH_DIR / "wav_samples"
DATA_DIR = BENCH_DIR / "LibriSpeech" / "test-clean"


def load_references():
    """Load ground truth transcriptions."""
    refs = {}
    for trans_file in DATA_DIR.rglob("*.trans.txt"):
        for line in trans_file.read_text().strip().split("\n"):
            parts = line.split(" ", 1)
            if len(parts) == 2:
                refs[parts[0]] = parts[1].strip()
    return refs


def normalize(text):
    """Normalize text for WER comparison."""
    text = text.upper()
    text = re.sub(r"[^A-Z ]", "", text)
    return " ".join(text.split())


def word_error_rate(ref, hyp):
    """Compute WER using edit distance."""
    r = ref.split()
    h = hyp.split()
    d = [[0] * (len(h) + 1) for _ in range(len(r) + 1)]
    for i in range(len(r) + 1):
        d[i][0] = i
    for j in range(len(h) + 1):
        d[0][j] = j
    for i in range(1, len(r) + 1):
        for j in range(1, len(h) + 1):
            if r[i - 1] == h[j - 1]:
                d[i][j] = d[i - 1][j - 1]
            else:
                d[i][j] = 1 + min(d[i - 1][j], d[i][j - 1], d[i - 1][j - 1])
    return d[len(r)][len(h)], len(r)


def transcribe(model_path, wav_path):
    """Run whisper-cli and return transcription text."""
    result = subprocess.run(
        ["whisper-cli", "-m", str(model_path), "-f", str(wav_path), "-l", "en", "-np"],
        capture_output=True, text=True, timeout=60
    )
    # Extract text after timestamps
    text = ""
    for line in result.stdout.split("\n"):
        match = re.search(r"\]\s+(.*)", line)
        if match:
            text += " " + match.group(1)
    return text.strip()


def get_duration(wav_path):
    """Get audio duration in seconds."""
    result = subprocess.run(
        ["ffprobe", "-i", str(wav_path), "-show_entries", "format=duration",
         "-v", "quiet", "-of", "csv=p=0"],
        capture_output=True, text=True
    )
    return float(result.stdout.strip())


def main():
    refs = load_references()
    wav_files = sorted(WAV_DIR.glob("*.wav"))[:50]

    print(f"Benchmarking {len(wav_files)} samples\n")

    models = sorted(MODELS_DIR.glob("ggml-*.bin"))

    for model_path in models:
        model_name = model_path.stem.replace("ggml-", "")
        print(f"=== {model_name} ===")

        total_errors = 0
        total_words = 0
        total_time = 0.0
        total_audio = 0.0

        for wav in wav_files:
            sample_id = wav.stem
            if sample_id not in refs:
                continue

            ref = normalize(refs[sample_id])
            dur = get_duration(wav)
            total_audio += dur

            start = time.time()
            hyp = normalize(transcribe(model_path, wav))
            elapsed = time.time() - start
            total_time += elapsed

            errors, words = word_error_rate(ref, hyp)
            total_errors += errors
            total_words += words

        wer = (total_errors / total_words * 100) if total_words else 0
        rtf = total_time / total_audio if total_audio else 0
        avg = total_time / len(wav_files)

        print(f"  WER:              {wer:.2f}%")
        print(f"  Avg per sample:   {avg:.3f}s")
        print(f"  Real-time factor: {rtf:.3f}x")
        print(f"  Total audio:      {total_audio:.1f}s")
        print(f"  Total processing: {total_time:.1f}s")
        print()


if __name__ == "__main__":
    main()
