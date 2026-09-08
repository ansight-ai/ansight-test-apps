#!/usr/bin/env python3
"""Synthesize the eight manifest quotes into fixtures/audio/quotes; never play them."""

import array
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import wave


def generate() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    fixture_directory = repo_root / "fixtures" / "audio" / "quotes"
    manifest_path = fixture_directory / "manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    settings = manifest["generation"]
    fixtures = manifest["fixtures"]
    for dependency in ("say", "ffmpeg"):
        if shutil.which(dependency) is None:
            raise RuntimeError(f"Required executable not found: {dependency}")
    if len(fixtures) != 8 or len({item["id"] for item in fixtures}) != 8:
        raise RuntimeError("The quote manifest must contain exactly eight unique fixtures.")

    generated = []
    with tempfile.TemporaryDirectory(prefix="ansight-quote-fixtures-") as temporary:
        temporary_directory = Path(temporary)
        for fixture in fixtures:
            filename = fixture["filename"]
            if Path(filename).name != filename or not filename.endswith(".wav"):
                raise RuntimeError(f"Fixture must use a local WAV filename: {filename}")
            text_path = temporary_directory / "speech.txt"
            speech_path = temporary_directory / "speech.aiff"
            wave_path = temporary_directory / filename
            text_path.write_text(fixture["text"] + "\n", encoding="utf-8")
            subprocess.run([
                "say", "-v", settings["voice"], "-r", str(settings["wordsPerMinute"]),
                "-f", str(text_path), "-o", str(speech_path)
            ], check=True)
            filter_chain = (
                f"aresample={settings['sampleRate']},"
                f"volume={settings['volumeMultiplier']},"
                f"adelay={round(settings['leadingSilenceSeconds'] * 1000)}:all=1,"
                f"apad=pad_dur={settings['trailingSilenceSeconds']}"
            )
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(speech_path),
                "-af", filter_chain, "-ar", str(settings["sampleRate"]),
                "-ac", str(settings["channels"]), "-c:a", settings["encoding"], str(wave_path)
            ], check=True)

            with wave.open(str(wave_path), "rb") as audio:
                frames = audio.getnframes()
                sample_rate = audio.getframerate()
                channels = audio.getnchannels()
                sample_width = audio.getsampwidth()
                pcm = audio.readframes(frames)
            duration = frames / sample_rate
            if (sample_rate, channels, sample_width) != (16000, 1, 2):
                raise RuntimeError(f"Unexpected sample format for {filename}")
            if not 0 < duration < settings["maximumDurationSeconds"]:
                raise RuntimeError(f"{filename} is {duration:.3f}s; choose a shorter quote before regenerating.")
            leading_bytes = round(settings["leadingSilenceSeconds"] * sample_rate) * channels * sample_width
            trailing_bytes = round(settings["trailingSilenceSeconds"] * sample_rate) * channels * sample_width
            if any(pcm[:leading_bytes]) or any(pcm[-trailing_bytes:]):
                raise RuntimeError(f"Expected silent padding is missing in {filename}")
            samples = array.array("h", pcm)
            if sys.byteorder != "little":
                samples.byteswap()
            peak = max(abs(sample) for sample in samples) / 32768
            if peak == 0 or peak > 0.251:
                raise RuntimeError(f"Unexpected peak level {peak:.4f} for {filename}")

            output_path = fixture_directory / filename
            shutil.copyfile(wave_path, output_path)
            data = output_path.read_bytes()
            generated.append({
                "id": fixture["id"], "filename": filename, "durationSeconds": round(duration, 6),
                "frames": frames, "sampleRate": sample_rate, "channels": channels,
                "sampleWidthBits": sample_width * 8, "peakLevel": round(peak, 6),
                "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()
            })
            print(f"{fixture['id']}: {duration:.3f}s, {len(data):,} bytes", flush=True)

    generated_manifest = {
        "schemaVersion": 1,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "sourceManifestSha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "macOSVersion": subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
        "generation": settings,
        "fixtures": generated
    }
    (fixture_directory / "generated-manifest.json").write_text(
        json.dumps(generated_manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"Created all eight WAV files in {fixture_directory}")


if __name__ == "__main__":
    try:
        generate()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
