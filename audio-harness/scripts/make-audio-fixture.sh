#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$repo_root/fixtures/audio"
temporary_directory="$(mktemp -d -t ansight-audio-fixture)"
temporary_audio="$temporary_directory/speech.aiff"
trap 'rm -f "$temporary_audio"; rmdir "$temporary_directory"' EXIT
say -v Samantha -r 140 -f "$fixture_dir/expected.txt" -o "$temporary_audio"
ffmpeg -hide_banner -loglevel error -y -i "$temporary_audio" \
  -af 'volume=0.25,adelay=1000:all=1,apad=pad_dur=1' \
  -ar 16000 -ac 1 -c:a pcm_s16le "$fixture_dir/expected.wav"
printf 'Created %s\n' "$fixture_dir/expected.wav"
