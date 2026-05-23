#!/usr/bin/env python3
"""
YOLOWhisp Pipeline Benchmark
=============================
Fully reproducible benchmark: whisper-cpp (Metal) → Cadence punctuation restoration.

Requirements:
    brew install whisper-cpp ffmpeg
    # Download whisper models:
    curl -L -o models/ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin

    # Python deps (in venv):
    pip install transformers torch

    # LibriSpeech test data:
    curl -L -o benchmark/test-clean.tar.gz https://www.openslr.org/resources/12/test-clean.tar.gz
    tar xzf benchmark/test-clean.tar.gz -C benchmark/

Usage:
    python pipeline/benchmark_pipeline.py
"""

import subprocess
import os
import re
import time
import json
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────
ROOT = Path(__file__).parent.parent
BENCH_DIR = ROOT / "benchmark"
MODELS_DIR = BENCH_DIR / "models"
WAV_DIR = BENCH_DIR / "wav_samples"
DATA_DIR = BENCH_DIR / "LibriSpeech" / "test-clean"
RESULTS_FILE = ROOT / "pipeline" / "benchmark_results.json"

WHISPER_MODEL = MODELS_DIR / "ggml-small.bin"


# ── Helpers ────────────────────────────────────────────────────────────

def load_references():
    """Load ground truth transcriptions from LibriSpeech."""
    refs = {}
    for trans_file in DATA_DIR.rglob("*.trans.txt"):
        for line in trans_file.read_text().strip().split("\n"):
            parts = line.split(" ", 1)
            if len(parts) == 2:
                refs[parts[0]] = parts[1].strip()
    return refs


def normalize(text):
    """Strip punctuation and normalize for WER comparison."""
    text = text.upper()
    text = re.sub(r"[^A-Z ]", "", text)
    return " ".join(text.split())


def word_error_rate(ref, hyp):
    """Compute WER using Levenshtein edit distance on words."""
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


def get_duration(wav_path):
    """Get audio duration in seconds via ffprobe."""
    result = subprocess.run(
        ["ffprobe", "-i", str(wav_path), "-show_entries", "format=duration",
         "-v", "quiet", "-of", "csv=p=0"],
        capture_output=True, text=True
    )
    return float(result.stdout.strip())


def whisper_transcribe(wav_path):
    """Run whisper-cli (Metal-accelerated) and return raw text with punctuation."""
    result = subprocess.run(
        ["whisper-cli", "-m", str(WHISPER_MODEL), "-f", str(wav_path), "-l", "en", "-np"],
        capture_output=True, text=True, timeout=60
    )
    text = ""
    for line in result.stdout.split("\n"):
        match = re.search(r"\]\s+(.*)", line)
        if match:
            text += " " + match.group(1)
    return text.strip()


# ── Cadence Punctuation Model ─────────────────────────────────────────

class PunctuationRestorer:
    """
    Punctuation restoration using oliverguhr/fullstop-punctuation-multilang-large.
    No gated access, no custom code, proven model.
    Falls back to Cadence-Fast if available.
    """

    MODELS = [
        ("oliverguhr/fullstop-punctuation-multilang-large", False),
        ("ai4bharat/Cadence-Fast", True),
    ]

    def __init__(self):
        from transformers import AutoTokenizer, AutoModelForTokenClassification
        import torch

        self.torch = torch
        loaded = False

        for model_name, trust_remote in self.MODELS:
            try:
                print(f"Loading {model_name}...")
                t0 = time.time()
                self.tokenizer = AutoTokenizer.from_pretrained(
                    model_name, trust_remote_code=trust_remote
                )
                self.model = AutoModelForTokenClassification.from_pretrained(
                    model_name, trust_remote_code=trust_remote
                )
                self.model.eval()
                self.model_name = model_name

                if torch.backends.mps.is_available():
                    self.device = torch.device("mps")
                    self.model.to(self.device)
                    print(f"  Using Apple Metal GPU")
                else:
                    self.device = torch.device("cpu")

                self.id2label = self.model.config.id2label
                self.load_time = time.time() - t0
                print(f"  Loaded in {self.load_time:.2f}s")
                loaded = True
                break
            except Exception as e:
                print(f"  Failed: {e}")

        if not loaded:
            raise RuntimeError("No punctuation model could be loaded")

    def punctuate(self, text):
        """Add punctuation to raw text."""
        # Tokenize
        inputs = self.tokenizer(
            text, return_tensors="pt", truncation=True, max_length=512
        ).to(self.device)

        with self.torch.no_grad():
            outputs = self.model(**inputs)

        predictions = self.torch.argmax(outputs.logits, dim=-1)[0]
        tokens = self.tokenizer.convert_ids_to_tokens(inputs["input_ids"][0])

        # Map labels to punctuation
        label_punct = {
            "0": "", "LABEL_0": "",  # no punctuation
            "1": ",", "LABEL_1": ",",  # comma
            "2": ".", "LABEL_2": ".",  # period
            "3": "?", "LABEL_3": "?",  # question
            "4": "-", "LABEL_4": "-",  # dash
            "5": ":", "LABEL_5": ":",  # colon
            "PERIOD": ".", "COMMA": ",", "QUESTION": "?",
            "EXCLAMATION": "!", "COLON": ":", "SEMICOLON": ";",
            ".": ".", ",": ",", "?": "?", "!": "!", ":": ":", ";": ";",
        }

        words = []
        current_word = []

        for token, pred_id in zip(tokens, predictions):
            if token in ("[CLS]", "[SEP]", "<s>", "</s>", "<pad>"):
                continue

            label = self.id2label.get(pred_id.item(), "0")

            # Handle subword tokens
            if token.startswith("▁"):
                if current_word:
                    words.append("".join(current_word))
                current_word = [token[1:]]
            elif token.startswith("##"):
                current_word.append(token[2:])
            else:
                if current_word:
                    words.append("".join(current_word))
                current_word = [token]

            # Append punctuation
            punct = label_punct.get(label, "")
            if punct:
                current_word.append(punct)

        if current_word:
            words.append("".join(current_word))

        result = " ".join(words)
        # Capitalize after sentence-ending punctuation
        result = re.sub(r'([.!?])\s+(\w)', lambda m: m.group(1) + " " + m.group(2).upper(), result)
        # Capitalize first letter
        if result:
            result = result[0].upper() + result[1:]

        return result


# ── Ollama (Qwen 2.5 3B) Post-Processing ──────────────────────────────

def ollama_correct(text):
    """Use local Qwen 2.5 3B via Ollama for full correction."""
    prompt = (
        "Fix the punctuation, capitalization, and any misheard words in this "
        "speech transcription. Return ONLY the corrected text, nothing else.\n\n"
        f"Transcription: {text}"
    )
    result = subprocess.run(
        ["ollama", "run", "qwen2.5:3b-instruct", prompt],
        capture_output=True, text=True, timeout=30
    )
    return result.stdout.strip()


# ── Main Benchmark ────────────────────────────────────────────────────

def main():
    refs = load_references()
    wav_files = sorted(WAV_DIR.glob("*.wav"))[:50]
    print(f"{'='*70}")
    print(f"YOLOWhisp Pipeline Benchmark")
    print(f"{'='*70}")
    print(f"Samples: {len(wav_files)}")
    print(f"Whisper model: {WHISPER_MODEL.name}")
    print()

    # Load Cadence
    try:
        punctuator = PunctuationRestorer()
        has_punctuator = True
    except Exception as e:
        print(f"  Punctuation model failed: {e}")
        has_punctuator = False

    # Check Ollama
    try:
        subprocess.run(["ollama", "list"], capture_output=True, timeout=5)
        has_ollama = True
        print("Ollama: available (qwen2.5:3b-instruct)")
    except Exception:
        has_ollama = False
        print("Ollama: not available")

    print(f"\n{'='*70}")
    print("Running benchmark...")
    print(f"{'='*70}\n")

    results = {
        "whisper_only": {"wer_errors": 0, "wer_words": 0, "time": 0.0, "audio": 0.0},
    }
    if has_punctuator:
        results["whisper_punctuator"] = {"wer_errors": 0, "wer_words": 0, "time": 0.0, "audio": 0.0}
    if has_ollama:
        results["whisper_ollama"] = {"wer_errors": 0, "wer_words": 0, "time": 0.0, "audio": 0.0}

    samples_detail = []

    for i, wav in enumerate(wav_files):
        sample_id = wav.stem
        if sample_id not in refs:
            continue

        ref_raw = refs[sample_id]
        ref_norm = normalize(ref_raw)
        dur = get_duration(wav)

        # ── Stage 1: Whisper-cpp ──
        t0 = time.time()
        whisper_out = whisper_transcribe(wav)
        whisper_time = time.time() - t0

        whisper_norm = normalize(whisper_out)
        w_err, w_words = word_error_rate(ref_norm, whisper_norm)

        results["whisper_only"]["wer_errors"] += w_err
        results["whisper_only"]["wer_words"] += w_words
        results["whisper_only"]["time"] += whisper_time
        results["whisper_only"]["audio"] += dur

        detail = {
            "id": sample_id,
            "reference": ref_raw,
            "whisper_raw": whisper_out,
            "whisper_time": round(whisper_time, 3),
            "duration": round(dur, 2),
        }

        # ── Stage 2a: Punctuation restoration ──
        if has_punctuator:
            t0 = time.time()
            punct_out = punctuator.punctuate(whisper_out)
            punct_time = time.time() - t0

            punct_norm = normalize(punct_out)
            p_err, p_words = word_error_rate(ref_norm, punct_norm)

            total_time = whisper_time + punct_time
            results["whisper_punctuator"]["wer_errors"] += p_err
            results["whisper_punctuator"]["wer_words"] += p_words
            results["whisper_punctuator"]["time"] += total_time
            results["whisper_punctuator"]["audio"] += dur

            detail["punctuator_out"] = punct_out
            detail["punctuator_time"] = round(punct_time, 3)

        # ── Stage 2b: Ollama correction ──
        if has_ollama and i < 10:  # Only first 10 for Ollama (slower)
            t0 = time.time()
            ollama_out = ollama_correct(whisper_out)
            ollama_time = time.time() - t0

            ollama_norm = normalize(ollama_out)
            o_err, o_words = word_error_rate(ref_norm, ollama_norm)

            total_time = whisper_time + ollama_time
            results["whisper_ollama"]["wer_errors"] += o_err
            results["whisper_ollama"]["wer_words"] += o_words
            results["whisper_ollama"]["time"] += total_time
            results["whisper_ollama"]["audio"] += dur

            detail["ollama_out"] = ollama_out
            detail["ollama_time"] = round(ollama_time, 3)

        samples_detail.append(detail)

        # Progress
        if (i + 1) % 10 == 0:
            print(f"  Processed {i+1}/{len(wav_files)} samples...")

    # ── Print Results ──────────────────────────────────────────────────
    print(f"\n{'='*70}")
    print("RESULTS")
    print(f"{'='*70}\n")

    for pipeline_name, data in results.items():
        if data["wer_words"] == 0:
            continue
        wer = data["wer_errors"] / data["wer_words"] * 100
        rtf = data["time"] / data["audio"] if data["audio"] else 0
        avg = data["time"] / len(wav_files)

        label = {
            "whisper_only": "Whisper-cpp (small, Metal)",
            "whisper_punctuator": "Whisper-cpp → Punctuation Model",
            "whisper_ollama": "Whisper-cpp → Qwen 2.5 3B (first 10 only)",
        }.get(pipeline_name, pipeline_name)

        print(f"  {label}")
        print(f"    WER:              {wer:.2f}%")
        print(f"    Avg per sample:   {avg:.3f}s")
        print(f"    Real-time factor: {rtf:.3f}x")
        print()

    # ── Show Example Outputs ───────────────────────────────────────────
    print(f"{'='*70}")
    print("EXAMPLE OUTPUTS (first 5 samples)")
    print(f"{'='*70}\n")

    for detail in samples_detail[:5]:
        print(f"  REF:     {detail['reference']}")
        print(f"  WHISPER: {detail['whisper_raw']}")
        if "punctuator_out" in detail:
            print(f"  PUNCT:   {detail['punctuator_out']}")
        if "ollama_out" in detail:
            print(f"  OLLAMA:  {detail['ollama_out']}")
        print()

    # ── Save Full Results ──────────────────────────────────────────────
    output = {"summary": {}, "samples": samples_detail}
    for pipeline_name, data in results.items():
        if data["wer_words"] == 0:
            continue
        output["summary"][pipeline_name] = {
            "wer": round(data["wer_errors"] / data["wer_words"] * 100, 2),
            "avg_time_per_sample": round(data["time"] / len(wav_files), 3),
            "real_time_factor": round(data["time"] / data["audio"], 3) if data["audio"] else 0,
        }

    RESULTS_FILE.write_text(json.dumps(output, indent=2))
    print(f"Full results saved to {RESULTS_FILE}")


if __name__ == "__main__":
    main()
