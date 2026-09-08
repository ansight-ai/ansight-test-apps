#!/usr/bin/env python3
"""Compare an actual microphone recording with the complete spoken fixture.

Requires ffmpeg, ffprobe and numpy. Resamples both files to mono PCM16/16 kHz,
then finds the whole nonzero fixture span in the recording. Only zero padding
is excluded; words cannot be trimmed or reordered. Allows capture-start delay
and microphone gain, with a fixed minimum whole-span correlation of 0.90.
This verifies audio reception, independently of any speech recognizer.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np


RATE = 16000
MINIMUM_CORRELATION = 0.90


def inspect_audio(path):
    if not path.is_file() or path.stat().st_size > 128 * 1024 * 1024:
        raise ValueError(f"Missing or oversized audio file: {path}")
    result = subprocess.run([
        "ffprobe", "-v", "error", "-show_entries",
        "stream=codec_name,sample_rate,channels:format=duration", "-of", "json", str(path)
    ], capture_output=True, check=True, timeout=20)
    details = json.loads(result.stdout)
    duration = float(details["format"]["duration"])
    if not 0 < duration <= 120:
        raise ValueError("Use a nonempty microphone recording shorter than two minutes.")
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "durationSeconds": duration, "streams": details["streams"]}


def decode(path):
    result = subprocess.run([
        "ffmpeg", "-v", "error", "-nostdin", "-i", str(path), "-map", "0:a:0",
        "-ac", "1", "-ar", str(RATE), "-f", "s16le", "pipe:1"
    ], capture_output=True, check=True, timeout=30)
    return np.frombuffer(result.stdout, dtype="<i2").astype(np.float64)


def compare(expected, actual):
    nonzero = np.flatnonzero(expected)
    if not len(nonzero):
        raise ValueError("This comparison requires a speech fixture, not silence.")
    first = int(nonzero[0])
    end = int(nonzero[-1]) + 1
    speech = expected[first:end].copy()
    if len(speech) < RATE // 4:
        raise ValueError("The spoken fixture must last at least a quarter of a second.")
    if len(actual) < len(speech):
        return {"passed": False, "reason": "Recording is shorter than the full spoken fixture."}
    speech -= speech.mean()
    energy = float(np.dot(speech, speech))
    if energy == 0:
        raise ValueError("Constant audio cannot identify a spoken fixture.")
    size = 1 << (len(actual) + len(speech) - 2).bit_length()
    dots = np.fft.irfft(np.fft.rfft(actual, size) * np.conj(np.fft.rfft(speech, size)), size)
    count = len(actual) - len(speech) + 1
    sums = np.concatenate(([0.0], np.cumsum(actual)))
    squares = np.concatenate(([0.0], np.cumsum(actual * actual)))
    window_sums = sums[len(speech):] - sums[:-len(speech)]
    window_energy = squares[len(speech):] - squares[:-len(speech)] - window_sums ** 2 / len(speech)
    denominator = np.sqrt(np.maximum(window_energy, 0) * energy)
    correlations = np.divide(dots[:count], denominator, out=np.zeros(count), where=denominator > 0)
    offset = int(np.argmax(correlations))
    correlation = float(correlations[offset])
    return {
        "passed": correlation >= MINIMUM_CORRELATION,
        "waveformCorrelation": correlation,
        "minimumCorrelation": MINIMUM_CORRELATION,
        "comparedSpeechSamples": len(speech),
        "comparedSpeechSeconds": len(speech) / RATE,
        "fixtureLeadingPaddingSeconds": first / RATE,
        "recordingSpeechOffsetSeconds": offset / RATE,
        "estimatedGain": float(dots[offset] / energy),
        "recordingPeakPcm16": float(np.max(np.abs(actual))),
        "wholeSpeechSpanCompared": True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("recording", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = {"schema": "ansight.microphone-waveform-verification/v1", "passed": False,
              "transcriptionVerified": False, "comparisonSampleRate": RATE}
    try:
        if args.fixture.resolve() == args.recording.resolve():
            raise ValueError("Supply the separately captured microphone recording.")
        report["fixture"] = inspect_audio(args.fixture)
        report["recording"] = inspect_audio(args.recording)
        report["comparison"] = compare(decode(args.fixture), decode(args.recording))
        report["passed"] = report["comparison"]["passed"]
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
