#!/usr/bin/env python3
"""Play the quote corpus into an iOS Simulator microphone and verify its captures.

Requires a booted Simulator running the Ansight-enabled harness, capture-only mode,
Simulator audio input already routed to the selected virtual audio device, and
Python with numpy plus ffmpeg/ffprobe. This script never changes host audio defaults.
It verifies waveform reception, not speech-to-text. Each attempt retains evidence.
"""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time


REPOSITORY = Path(__file__).resolve().parents[1]
APP_ID = "ai.ansight.audioharness"


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def command_json(arguments):
    completed = subprocess.run(arguments, capture_output=True, text=True, check=True, timeout=45)
    return json.loads(completed.stdout)


def select_session(simulator):
    listing = command_json(["ansight", "session", "list", "--connected", "--app-id", APP_ID,
                            "--limit", "20", "--json"])
    matches = []
    for item in listing.get("sessions", []):
        if item.get("platform") != "ios" or not item.get("isConnected"):
            continue
        details = command_json(["ansight", "session", "show", item["sessionId"], "--json"])
        device = details.get("session", {}).get("deviceProfile", {}).get("device", {})
        if details.get("isConnected") and device.get("nativeDeviceId") == simulator:
            matches.append({"sessionId": item["sessionId"], "appId": APP_ID, "device": device})
    if len(matches) != 1:
        raise RuntimeError(f"Expected one connected harness session on {simulator}; found {len(matches)}.")
    return matches[0]


class Interaction:
    def __init__(self, session, output):
        self.sequence = 0
        self.responses = queue.Queue()
        self.events = (output / "interaction.jsonl").open("w")
        self.errors = (output / "interaction.stderr.log").open("w")
        self.process = subprocess.Popen(
            ["ansight", "app", "interact", "--session", session, "--jsonl"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors, text=True, bufsize=1)
        threading.Thread(target=self.read_output, daemon=True).start()
        self.latest = self.receive("ready", None)

    def read_output(self):
        for line in self.process.stdout:
            self.responses.put(line)
        self.responses.put(None)

    def receive(self, command, identifier):
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            line = self.responses.get(timeout=max(0.1, deadline - time.monotonic()))
            if line is None:
                raise RuntimeError("Ansight interaction bridge disconnected.")
            self.events.write(line)
            self.events.flush()
            response = json.loads(line)
            if response.get("command") == command and response.get("id") == identifier:
                self.latest = response
                if not response.get("succeeded"):
                    raise RuntimeError(f"Ansight {command} failed: {response.get('message', response)}")
                return response
        raise TimeoutError(f"No response to Ansight {command}; the input outcome is uncertain.")

    def send(self, command, **arguments):
        self.sequence += 1
        identifier = f"corpus-{self.sequence}"
        payload = {"id": identifier, "command": command, **arguments}
        self.events.write(json.dumps({"sentUtc": utc_now(), "input": payload}) + "\n")
        self.events.flush()
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()
        return self.receive(command, identifier)

    def node(self, identifier):
        matches = [node for node in self.latest.get("ui", {}).get("nodes", [])
                   if node.get("automationId") == identifier]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one visible automation ID {identifier}; found {len(matches)}.")
        return matches[0]

    def tap(self, identifier):
        if not self.node(identifier).get("enabled"):
            raise RuntimeError(f"Control {identifier} is disabled.")
        return self.send("tap", target={"automationId": identifier})

    def wait_phase(self, phase, timeout=20):
        deadline = time.monotonic() + timeout
        while self.node("capture-phase").get("text") != phase:
            actual = self.node("capture-phase").get("text")
            if actual == "Error" or time.monotonic() >= deadline:
                raise RuntimeError(f"Expected phase {phase}; observed {actual}.")
            time.sleep(0.15)
            self.send("snapshot")
        return self.latest

    def ready(self):
        self.send("snapshot")
        phase = self.node("capture-phase").get("text")
        if phase == "Listening":
            self.tap("stop-listening")
        if self.node("capture-phase").get("text") != "Ready":
            self.tap("reset-test")
        self.wait_phase("Ready")
        if self.node("capture-only").get("value") == "0":
            self.tap("capture-only")
        if self.node("capture-only").get("value") != "1":
            raise RuntimeError("Capture-only mode is not checked.")

    def close(self):
        try:
            if self.process.poll() is None:
                self.send("exit")
                self.process.stdin.close()
                self.process.wait(timeout=5)
        finally:
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=5)
            self.events.close()
            self.errors.close()


def save_observation(path, observation):
    write_json(path, observation)
    screenshot = observation.get("screenshot", {}).get("artifactPath")
    if screenshot and Path(screenshot).is_file():
        shutil.copy2(screenshot, path.with_suffix(".png"))


def read_fresh_result(path, previous_run, started_utc):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if path.is_file():
            result = json.loads(path.read_text())
            if result.get("runId") != previous_run:
                if not re.fullmatch(r"[0-9a-f]{32}", result.get("runId", "")):
                    raise RuntimeError("Unexpected capture run ID.")
                if datetime.fromisoformat(result["startedUtc"]) < started_utc:
                    raise RuntimeError("Result predates this case.")
                return result
        time.sleep(0.1)
    raise TimeoutError("No fresh app result was saved.")


def run_case(fixture, manifest_directory, bridge, container, output, audio_device):
    case_id = fixture["id"]
    if not re.fullmatch(r"[a-z0-9-]+", case_id):
        raise ValueError("Fixture IDs must contain lowercase letters, numbers, and hyphens.")
    directory = output / case_id
    directory.mkdir()
    result = {"fixtureId": case_id, "startedUtc": utc_now(), "passed": False,
              "transcriptionVerified": False, "evidenceDirectory": str(directory)}
    try:
        source = (manifest_directory / fixture["filename"]).resolve()
        if not source.is_relative_to(manifest_directory) or not source.is_file():
            raise ValueError("Fixture must be an existing file inside the manifest directory.")
        retained_fixture = directory / "fixture.wav"
        shutil.copy2(source, retained_fixture)
        write_json(directory / "fixture.json", fixture)
        bridge.ready()
        save_observation(directory / "before.json", bridge.latest)
        latest = container / "Library/audio-results/latest.json"
        previous_run = json.loads(latest.read_text()).get("runId") if latest.is_file() else None
        started_utc = datetime.now(timezone.utc)
        bridge.tap("start-listening")
        bridge.wait_phase("Listening")
        save_observation(directory / "listening.json", bridge.latest)
        playback = subprocess.run(
            [str(REPOSITORY / "scripts/play-to-audio-device.sh"), "--device", audio_device, str(retained_fixture)],
            capture_output=True, text=True, timeout=45)
        (directory / "playback.stdout.log").write_text(playback.stdout)
        (directory / "playback.stderr.log").write_text(playback.stderr)
        if playback.returncode:
            raise RuntimeError(f"Explicit-device playback exited {playback.returncode}.")
        bridge.tap("stop-listening")
        bridge.wait_phase("Captured")
        save_observation(directory / "captured.json", bridge.latest)
        app_result = read_fresh_result(latest, previous_run, started_utc)
        write_json(directory / "app-result.json", app_result)
        if app_result.get("phase") != "Captured" or app_result.get("captureOnly") is not True:
            raise RuntimeError("The app did not finish a capture-only recording.")
        if app_result.get("isFinal") or app_result.get("passed") or app_result.get("transcript"):
            raise RuntimeError("Capture-only result unexpectedly claims a transcript result.")
        recording = Path(app_result["captureFilePath"]).resolve()
        capture_directory = (container / "Library/audio-captures").resolve()
        if not recording.is_relative_to(capture_directory) or recording.name != app_result["runId"] + ".wav":
            raise RuntimeError("Capture file is outside this app container or does not match the fresh run.")
        retained_recording = directory / "microphone.wav"
        shutil.copy2(recording, retained_recording)
        verification = subprocess.run(
            [sys.executable, str(REPOSITORY / "scripts/verify-microphone-capture.py"), str(retained_fixture),
             str(retained_recording), "--output", str(directory / "verification.json")],
            capture_output=True, text=True, timeout=60)
        (directory / "verification.stderr.log").write_text(verification.stderr)
        report = json.loads((directory / "verification.json").read_text())
        result.update(runId=app_result["runId"], passed=verification.returncode == 0 and report.get("passed") is True,
                      comparison=report.get("comparison"), captureDurationSeconds=app_result.get("durationSeconds"))
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError, queue.Empty) as error:
        result["error"] = str(error)
        result["infrastructureFailure"] = isinstance(error, queue.Empty) or any(
            marker in str(error) for marker in ("Mach port invalid", "bridge disconnected", "input outcome is uncertain"))
    result["completedUtc"] = utc_now()
    write_json(directory / "result.json", result)
    print(json.dumps(result), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True, help="Exact booted Simulator UDID.")
    parser.add_argument("--audio-device", default="BlackHole2ch_UID", help="Exact virtual audio output device UID.")
    parser.add_argument("--manifest", type=Path, default=REPOSITORY / "fixtures/audio/quotes/manifest.json")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    output = (args.output or REPOSITORY / "artifacts/audio-harness" /
              datetime.now(timezone.utc).strftime("ios-corpus-%Y%m%dT%H%M%SZ")).resolve()
    output.mkdir(parents=True, exist_ok=False)
    session = select_session(args.simulator)
    write_json(output / "session.json", session)
    container = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", args.simulator, APP_ID, "data"], text=True).strip()).resolve()
    if args.simulator not in container.parts or not container.is_dir():
        raise RuntimeError("Simulator returned an unexpected app data container.")
    fixtures = json.loads(manifest.read_text())["fixtures"]
    shutil.copy2(manifest, output / "manifest.json")
    summary = {"schema": "ansight.ios-microphone-corpus/v1", "simulator": args.simulator,
               "sessionId": session["sessionId"], "audioDevice": args.audio_device, "startedUtc": utc_now(),
               "transcriptionVerified": False, "passed": False, "cases": []}
    bridge = Interaction(session["sessionId"], output)
    try:
        for index, fixture in enumerate(fixtures):
            result = run_case(fixture, manifest.parent, bridge, container, output, args.audio_device)
            summary["cases"].append(result)
            write_json(output / "summary.json", summary)
            if result.get("infrastructureFailure"):
                summary["infrastructureFailure"] = result["error"]
                summary["cases"].extend({"fixtureId": pending["id"], "passed": False, "status": "NotRun",
                                         "reason": "Stopped after UI infrastructure failure."}
                                        for pending in fixtures[index + 1:])
                break
        if summary.get("infrastructureFailure"):
            return 1
        bridge.ready()
        save_observation(output / "final-ready.json", bridge.latest)
        summary["finalPhase"] = bridge.node("capture-phase")["text"]
        summary["captureOnly"] = bridge.node("capture-only")["value"] == "1"
        summary["passed"] = bool(fixtures) and all(case["passed"] for case in summary["cases"])
    finally:
        summary["completedUtc"] = utc_now()
        write_json(output / "summary.json", summary)
        bridge.close()
    print(json.dumps({"summary": str(output / "summary.json"), "passed": summary["passed"],
                      "passedCases": sum(case["passed"] for case in summary["cases"]), "totalCases": len(fixtures)}), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
