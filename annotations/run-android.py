#!/usr/bin/env python3
"""Drive the Android harness editor and verify its session annotation."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import time


APP_ID = "ai.ansight.harness"
MARKER = "annotation e2e android roundtrip"


def command(*args):
    completed = subprocess.run(args, capture_output=True, text=True)
    if completed.returncode:
        raise RuntimeError(f"{args}: {completed.stderr or completed.stdout}")
    return completed.stdout


def ansight(*args):
    return json.loads(command("ansight", *args, "--json"))


def connected_ids():
    response = ansight("session", "list", "--connected", "--app-id", APP_ID)
    return {session["sessionId"] for session in response["sessions"]}


def find_text(node, text):
    if text in node.get("text", ""):
        return True
    return any(find_text(child, text) for child in node.get("children", []))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device_id", help="Booted Android emulator, such as emulator-5554")
    parser.add_argument("--apk", type=Path, help="Install this Debug harness APK first")
    args = parser.parse_args()

    if args.apk:
        ansight("device", "install", "android", args.device_id, str(args.apk.resolve()))
    previous_ids = connected_ids()
    ansight("device", "terminate", "android", args.device_id, APP_ID)
    ansight("device", "launch", "android", args.device_id, APP_ID)

    session_id = None
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        current = connected_ids() - previous_ids
        if len(current) == 1:
            session_id = current.pop()
            break
        time.sleep(1)
    assert session_id, "Android harness did not establish a new Ansight session"
    before = ansight("session", "annotations", session_id, "--limit", "100")
    assert before["totalCount"] == 0, "Expected a fresh session without annotations"

    size = command("adb", "-s", args.device_id, "shell", "wm", "size")
    width, height = map(int, re.search(r"(\d+)x(\d+)", size).groups())
    command(
        "ansight", "input", "swipe", "android", args.device_id,
        "--start-x", str(round(width * 0.5)), "--start-y", str(round(height * 0.85)),
        "--end-x", str(round(width * 0.5)), "--end-y", str(round(height * 0.66)),
        "--duration-ms", "450",
    )
    ansight("ui", "tap", "--session", session_id, "--text", "Annotate", "--role", "button")
    editor = ansight("ui", "snapshot", "--session", session_id)
    assert find_text(editor["result"]["root"], "Describe the issue"), "Annotation editor did not open"

    command(
        "ansight", "input", "swipe", "android", args.device_id,
        "--start-x", str(round(width * 0.25)), "--start-y", str(round(height * 0.35)),
        "--end-x", str(round(width * 0.65)), "--end-y", str(round(height * 0.45)),
        "--duration-ms", "500",
    )
    ansight("ui", "type", "--session", session_id, "--text", "Describe the issue", "--role", "textbox", "--value", MARKER)
    typed = ansight("ui", "snapshot", "--session", session_id)
    assert find_text(typed["result"]["root"], MARKER), "Feedback text did not reach the editor"
    ansight("ui", "tap", "--session", session_id, "--text", "SAVE", "--role", "button")

    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        dashboard = ansight("ui", "snapshot", "--session", session_id)
        if find_text(dashboard["result"]["root"], "annotation=Completed id="):
            break
        time.sleep(1)
    else:
        raise AssertionError("Harness did not report a completed annotation result")

    verifier = Path(__file__).with_name("verify-session.py")
    print(command(sys.executable, str(verifier), session_id, MARKER))


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, AttributeError, RuntimeError) as exc:
        print(f"Android annotation test failed: {exc}", file=sys.stderr)
        sys.exit(1)
