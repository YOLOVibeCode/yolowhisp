#!/usr/bin/env bash
#
# gen-benchmark-samples.sh
#
# Builds the audio corpus for the YOLOWhisp transcription accuracy benchmark
# and writes Benchmark/manifest.tsv (one "<relative-audio-path>\t<reference>"
# row per sample). Two sources are combined:
#
#   1. TTS samples  - macOS `say` reads each line of Benchmark/references.txt,
#                     giving perfect ground-truth text for every clip.
#   2. Your recordings - drop an audio file (wav/aiff/m4a/mp3/caf) in
#                     Benchmark/recordings/ alongside a same-named .txt file
#                     containing exactly what you said. Both get added.
#
# The benchmark harness loads any audio format via AVFoundation, so no
# ffmpeg/sox conversion is required here.
#
# Usage:
#   scripts/gen-benchmark-samples.sh            # default system voice
#   VOICE="Samantha" scripts/gen-benchmark-samples.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH="$ROOT/Benchmark"
SAMPLES="$BENCH/samples"
REFERENCES="$BENCH/references.txt"
RECORDINGS="$BENCH/recordings"
MANIFEST="$BENCH/manifest.tsv"
VOICE="${VOICE:-}"

mkdir -p "$SAMPLES" "$RECORDINGS"
: > "$MANIFEST"

count=0

# --- 1. TTS samples from references.txt ---
if [[ -f "$REFERENCES" ]]; then
  index=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments.
    [[ -z "${line//[[:space:]]/}" ]] && continue
    [[ "${line#\#}" != "$line" ]] && continue
    index=$((index + 1))
    out="$SAMPLES/ref_$(printf '%02d' "$index").aiff"
    if [[ -n "$VOICE" ]]; then
      say -v "$VOICE" -o "$out" "$line"
    else
      say -o "$out" "$line"
    fi
    printf 'samples/%s\t%s\n' "$(basename "$out")" "$line" >> "$MANIFEST"
    count=$((count + 1))
    echo "TTS  [$index] $(basename "$out")"
  done < "$REFERENCES"
fi

# --- 2. User recordings with sibling .txt references ---
if [[ -d "$RECORDINGS" ]]; then
  shopt -s nullglob
  for f in "$RECORDINGS"/*.wav "$RECORDINGS"/*.aiff "$RECORDINGS"/*.aif "$RECORDINGS"/*.m4a "$RECORDINGS"/*.mp3 "$RECORDINGS"/*.caf; do
    base="$(basename "$f")"
    name="${base%.*}"
    reftxt="$RECORDINGS/$name.txt"
    if [[ -f "$reftxt" ]]; then
      # Flatten the reference to a single whitespace-collapsed line.
      ref="$(tr '\n' ' ' < "$reftxt" | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')"
      printf 'recordings/%s\t%s\n' "$base" "$ref" >> "$MANIFEST"
      count=$((count + 1))
      echo "REC  $base"
    else
      echo "SKIP $base (no $name.txt reference)"
    fi
  done
fi

echo ""
echo "Wrote $MANIFEST with $count sample(s)."
echo "Run the benchmark with:"
echo "  RUN_WHISPER_BENCHMARK=1 swift test --filter ModelAccuracyBenchmarkTests"
