#!/usr/bin/env python3
"""Run every quote in a fixture manifest and preserve each exact assertion."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--ids", nargs="+", help="Run only these manifest fixture IDs, preserving manifest order.")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"emulator-\d+", args.serial):
        parser.error("Specify one Android emulator serial.")
    manifest_path = args.manifest.resolve()
    manifest = json.loads(manifest_path.read_text())
    fixtures = manifest["fixtures"]
    if not fixtures or len({item["id"] for item in fixtures}) != len(fixtures):
        parser.error("Manifest needs distinct fixture IDs.")
    if args.ids:
        missing = set(args.ids) - {item["id"] for item in fixtures}
        if missing:
            parser.error(f"Unknown fixture IDs: {', '.join(sorted(missing))}")
        fixtures = [item for item in fixtures if item["id"] in args.ids]
    for item in fixtures:
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", item["id"]):
            parser.error("Fixture IDs must be safe directory names.")
        path = (manifest_path.parent / item["filename"]).resolve()
        if not path.is_relative_to(manifest_path.parent) or not path.is_file() or not item["text"].strip():
            parser.error(f"Missing or invalid fixture {item['id']}.")
    output = args.output or root / "artifacts/audio-harness" / datetime.now(timezone.utc).strftime("android-quotes-%Y%m%dT%H%M%S%fZ")
    output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(manifest_path, output / "manifest.json")
    aggregate = {"schema": "ansight.audio-harness-corpus/v1", "serial": args.serial,
                 "startedUtc": datetime.now(timezone.utc).isoformat(),
                 "fixtureIds": [item["id"] for item in fixtures], "cases": [], "skipped": []}
    runner = root / "scripts/run-android-audio-test.py"

    def connected():
        result = subprocess.run(["adb", "-s", args.serial, "get-state"], capture_output=True, timeout=5)
        return result.returncode == 0 and result.stdout.strip() == b"device"

    for index, item in enumerate(fixtures):
        if not connected():
            aggregate["skipped"] = [entry["id"] for entry in fixtures[index:]]
            aggregate["error"] = "The selected emulator disconnected; no subsequent injections were attempted."
            break
        case_output = output / item["id"]
        fixture_path = manifest_path.parent / item["filename"]
        print(json.dumps({"event": "case-start", "id": item["id"], "expected": item["text"]}), flush=True)
        command = [sys.executable, str(runner), str(fixture_path), "--serial", args.serial,
                   "--expected", item["text"], "--output", str(case_output)]
        try:
            completed = subprocess.run(command, capture_output=True, text=True, timeout=90)
            (output / f"{item['id']}-runner.log").write_text(completed.stdout + completed.stderr)
            result_path = case_output / "result.json"
            result = json.loads(result_path.read_text()) if result_path.exists() else {"passed": False, "error": completed.stderr}
        except subprocess.TimeoutExpired as error:
            result = {"passed": False, "error": "The fixture runner exceeded 90 seconds; remaining cases were not started."}
            aggregate["skipped"] = [entry["id"] for entry in fixtures[index + 1:]]
        app = result.get("appResult", {})
        case = {"id": item["id"], "expected": item["text"], "author": item.get("author"),
                "testPassed": result["passed"], "phase": app.get("phase"), "transcript": app.get("transcript"),
                "isFinal": app.get("isFinal"), "appPassed": app.get("passed"),
                "fixtureSha256": result.get("fixtureSha256"), "evidencePath": str(case_output)}
        if "error" in result:
            case["error"] = result["error"]
            aggregate["error"] = "A fixture encountered an infrastructure failure; remaining cases were not started."
            aggregate["skipped"] = [entry["id"] for entry in fixtures[index + 1:]]
        aggregate["cases"].append(case)
        print(json.dumps({"event": "case-complete", **case}), flush=True)
        (output / "result.json").write_text(json.dumps(aggregate, indent=2) + "\n")
        if "error" in result or aggregate["skipped"]:
            break

    if connected():
        default_phrase = (root / "fixtures/audio/expected.txt").read_text().strip()
        command = [sys.executable, str(runner), str(manifest_path.parent / fixtures[0]["filename"]),
                   "--serial", args.serial, "--expected", default_phrase, "--prepare-only",
                   "--output", str(output / "restored")]
        try:
            restored = subprocess.run(command, capture_output=True, text=True, timeout=30)
            (output / "restore-runner.log").write_text(restored.stdout + restored.stderr)
            aggregate["restoredToReady"] = restored.returncode == 0
        except subprocess.TimeoutExpired:
            aggregate["restoredToReady"] = False
    else:
        aggregate["restoredToReady"] = False
    aggregate["passedCount"] = sum(case["testPassed"] for case in aggregate["cases"])
    aggregate["failedCount"] = len(aggregate["cases"]) - aggregate["passedCount"]
    aggregate["skippedCount"] = len(aggregate["skipped"])
    aggregate["passed"] = aggregate["passedCount"] == len(fixtures)
    aggregate["completedUtc"] = datetime.now(timezone.utc).isoformat()
    (output / "result.json").write_text(json.dumps(aggregate, indent=2) + "\n")
    print(json.dumps({"event": "corpus-complete", "passed": aggregate["passed"],
                      "passedCount": aggregate["passedCount"], "failedCount": aggregate["failedCount"],
                      "skippedCount": aggregate["skippedCount"], "restoredToReady": aggregate["restoredToReady"],
                      "evidencePath": str(output)}), flush=True)
    return 0 if aggregate["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
