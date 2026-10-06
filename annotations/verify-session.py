#!/usr/bin/env python3
"""Verify that an app annotation reached its capturing Ansight session."""

import argparse
import json
import subprocess
import sys
import time


def annotations(session_id):
    completed = subprocess.run(
        ["ansight", "session", "annotations", session_id, "--limit", "100", "--json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(completed.stdout)["items"]


def verify(item, marker):
    assert item["source"] == "sdk.annotatedFeedback", item
    assert item["notes"] == marker, item
    assert item["annotationId"], item
    evidence = item.get("evidence", [])
    assert any(
        entry.get("kind") == "screenshot"
        and entry.get("status") == "captured"
        and entry.get("sizeBytes", 0) > 0
        for entry in evidence
    ), evidence
    assert any(
        entry.get("kind") == "visualtree" and entry.get("status") == "captured"
        for entry in evidence
    ), evidence
    geometry = item.get("geometry", [])
    assert any(
        shape.get("kind") == 3
        and shape.get("frameId")
        and len(shape.get("points", [])) >= 2
        for shape in geometry
    ), geometry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session_id")
    parser.add_argument("marker", help="Exact feedback text entered in the app")
    parser.add_argument("--timeout", type=int, default=20)
    args = parser.parse_args()

    deadline = time.monotonic() + args.timeout
    while True:
        matches = [item for item in annotations(args.session_id) if item.get("notes") == args.marker]
        if matches or time.monotonic() >= deadline:
            break
        time.sleep(1)
    assert len(matches) == 1, f"Expected one annotation for {args.marker!r}; found {len(matches)}"
    verify(matches[0], args.marker)
    print(json.dumps({
        "sessionId": args.session_id,
        "annotationId": matches[0]["annotationId"],
        "source": matches[0]["source"],
        "notes": matches[0]["notes"],
        "geometryCount": len(matches[0]["geometry"]),
        "evidence": [entry["kind"] for entry in matches[0]["evidence"] if entry["status"] == "captured"],
        "passed": True,
    }, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, KeyError, subprocess.CalledProcessError) as exc:
        print(f"Annotation roundtrip failed: {exc}", file=sys.stderr)
        sys.exit(1)
