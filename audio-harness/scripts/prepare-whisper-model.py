#!/usr/bin/env python3
"""Prepare the pinned offline model for MAUI packaging; never called by the app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.request


def identity(path):
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
            size += len(block)
    return size, digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Verify the prepared file without downloading.")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parents[1] / "apps/Ansight.AudioHarness/Resources/Raw/models"
    manifest = json.loads((directory / "whisper-model.json").read_text())
    if manifest["schema"] != "ansight.whisper-model/v1" or manifest["fileName"] != "ggml-base.en.bin":
        raise ValueError("Unrecognized pinned Whisper model manifest.")
    destination = directory / manifest["fileName"]
    expected = manifest["sizeBytes"], manifest["sha256"]
    downloaded = False
    if not destination.exists() or identity(destination) != expected:
        if args.verify_only:
            raise ValueError("Prepared model is missing or does not match the pinned hash; run without --verify-only.")
        temporary = destination.with_name(destination.name + f".{os.getpid()}.partial")
        try:
            request = urllib.request.Request(manifest["sourceUrl"] + "?download=true", headers={"User-Agent": "Ansight-AudioHarness-ModelPrep/1"})
            print(f"Downloading {manifest['model']} ({manifest['sizeBytes']:,} bytes) from the pinned public revision...", file=sys.stderr)
            with urllib.request.urlopen(request, timeout=60) as source, temporary.open("xb") as output:
                size = 0
                while block := source.read(1024 * 1024):
                    size += len(block)
                    if size > manifest["sizeBytes"]:
                        raise ValueError("Downloaded model exceeds the pinned size.")
                    output.write(block)
            if identity(temporary) != expected:
                raise ValueError("Downloaded model failed pinned size/SHA-256 verification.")
            temporary.replace(destination)
            downloaded = True
        finally:
            temporary.unlink(missing_ok=True)
    print(json.dumps({"schema": "ansight.whisper-model-preparation/v1", "model": manifest["model"],
                      "modelPath": str(destination), "sha256": manifest["sha256"],
                      "sizeBytes": manifest["sizeBytes"], "downloaded": downloaded}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as error:
        print(f"Model preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
