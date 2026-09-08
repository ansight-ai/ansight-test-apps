#!/usr/bin/env python3
"""Run real microphone transcription with a fixture and retain Android evidence.

Emulator 37.1.11 crashes if injectAudio starts without an open guest microphone.
This runner checks AudioFlinger's live record thread and injects immediately in
the same process. It never enables the host microphone. Requires the sibling
Ansight repository's audio injector and its Python requirements.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

import grpc
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory


PACKAGE = "ai.ansight.audioharness"
SERVICE = "/android.emulation.control.EmulatorController/"


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def clipboard_type():
    definition = descriptor_pb2.FileDescriptorProto(
        name="harness_clipboard.proto", package="android.emulation.control", syntax="proto3")
    definition.message_type.add(name="ClipData").field.add(name="text", number=1, type=9, label=1)
    pool = descriptor_pool.DescriptorPool()
    pool.Add(definition)
    return message_factory.GetMessageClass(pool.FindMessageTypeByName("android.emulation.control.ClipData"))


def active_record_threads(dump):
    blocks = re.split(r"(?m)^(?=(?:Input|Record|Output) thread )", dump)
    active = []
    for block in blocks:
        block = block.split("\nHistorical Thread Log", 1)[0]
        if not re.match(r"(?:Input|Record) thread ", block):
            continue
        read_age = re.search(r"Last read occurred \(msecs\):\s*(\d+)", block)
        if (re.search(r"(?m)^\s*Standby:\s*no\s*$", block)
                and re.search(r"\b\d+ Tracks? of which [1-9]\d* are active", block)
                and re.search(r"Frames read:\s*[1-9]\d*", block)
                and read_age and int(read_age.group(1)) < 250):
            active.append(block)
    return active


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--injector", type=Path, default=root.parent.parent / "ansight/scripts/audio-input/inject_audio.py")
    parser.add_argument("--expected", help="Set the harness expectation through its visible editor before capture.")
    parser.add_argument("--prepare-only", action="store_true", help="Set the expectation and reset to Ready without starting capture.")
    parser.add_argument("--outcome", choices=("pass", "mismatch", "no-speech"), default="pass")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"emulator-\d+", args.serial):
        parser.error("Specify one Android emulator serial.")
    spec = importlib.util.spec_from_file_location("harness_audio_injector", args.injector.resolve())
    if spec is None or spec.loader is None:
        parser.error("Cannot load the audio injector.")
    injector = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = injector
    spec.loader.exec_module(injector)
    fixture = injector.read_fixture(args.fixture)
    if fixture.duration_seconds > 15:
        parser.error("Use a short fixture (at most fifteen seconds) for native speech recognition.")
    output = args.output or root / "artifacts/audio-harness" / datetime.now(timezone.utc).strftime("android-%Y%m%dT%H%M%S%fZ")
    output.mkdir(parents=True, exist_ok=False)
    shutil.copy2(fixture.path, output / "fixture.wav")
    report = {"schema": "ansight.audio-harness-test/v1", "serial": args.serial,
              "fixtureSha256": fixture.sha256, "requestedOutcome": args.outcome,
              "startedUtc": utc_now(), "passed": False, "events": []}

    def event(name, **values):
        record = {"event": name, "atUtc": utc_now(), **values}
        report["events"].append(record)
        print(json.dumps(record), flush=True)

    def adb(*arguments, timeout=15):
        return subprocess.run(["adb", "-s", args.serial, *arguments],
                              check=True, capture_output=True, timeout=timeout).stdout

    def ui_snapshot(name):
        device_path = "/data/local/tmp/ansight-audio-harness-ui.xml"
        adb("shell", "uiautomator", "dump", device_path)
        data = adb("exec-out", "cat", device_path)
        (output / f"{name}.xml").write_bytes(data)
        return ET.fromstring(data)

    def node(tree, automation_id):
        matches = [n for n in tree.iter("node")
                   if n.get("resource-id") == f"{PACKAGE}:id/{automation_id}"]
        if len(matches) != 1:
            raise RuntimeError(f"Expected one visible {automation_id}; found {len(matches)}.")
        return matches[0]

    def tap(tree, automation_id):
        target = node(tree, automation_id)
        if target.get("enabled") != "true":
            raise RuntimeError(f"{automation_id} is disabled.")
        left, top, right, bottom = map(int, re.findall(r"\d+", target.get("bounds", "")))
        adb("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))

    try:
        target = injector.resolve_endpoint(serial=args.serial)
        messages = injector.audio_message_types()
        metadata = (("authorization", f"Bearer {target.token}"),) if target.token else ()
        clip_type = clipboard_type()
        with grpc.insecure_channel(target.address) as channel:
            grpc.channel_ready_future(channel).result(timeout=5)
            get_mic = channel.unary_unary(SERVICE + "getMicrophoneState", response_deserializer=messages["MicrophoneState"].FromString)
            get_clip = channel.unary_unary(SERVICE + "getClipboard", response_deserializer=clip_type.FromString)
            set_clip = channel.unary_unary(SERVICE + "setClipboard", request_serializer=lambda message: message.SerializeToString())
            mic = get_mic(b"", metadata=metadata, timeout=5)
            report["hostMicrophoneEnabledBefore"] = mic.realAudioEnabled
            if mic.realAudioEnabled:
                raise RuntimeError("Host microphone must already be disabled. This runner will not enable or capture it.")
            initial = ui_snapshot("before")
            phase = node(initial, "capture-phase").get("text")
            if phase not in ("Ready", "Completed", "Error", "Cancelled"):
                raise RuntimeError(f"The harness already has an active run ({phase}).")
            if args.expected is not None:
                set_clip(clip_type(text=args.expected), metadata=metadata, timeout=5)
                tap(initial, "expected-phrase")
                adb("shell", "input", "keycombination", "113", "29")
                adb("shell", "input", "keyevent", "KEYCODE_PASTE")
                adb("shell", "input", "keyevent", "KEYCODE_BACK")
                initial = ui_snapshot("expectation")
                if node(initial, "expected-phrase").get("text") != args.expected:
                    raise RuntimeError("Visible expected phrase did not update.")
            report["expected"] = node(initial, "expected-phrase").get("text")
            if args.prepare_only:
                tap(initial, "reset-test")
                prepared = ui_snapshot("prepared")
                if node(prepared, "capture-phase").get("text") != "Ready":
                    raise RuntimeError("The harness did not reset to Ready.")
                (output / "prepared.png").write_bytes(adb("exec-out", "screencap", "-p"))
                report["schema"] = "ansight.audio-harness-preparation/v1"
                report["passed"] = True
                event("prepared", expected=report["expected"], phase="Ready", microphoneStarted=False)
                return 0
            baseline = adb("shell", "dumpsys", "media.audio_flinger").decode()
            if active_record_threads(baseline):
                raise RuntimeError("Another recording is already active; cannot attribute the new microphone stream.")
            (output / "audio-before.txt").write_text(baseline)
            event("start-tapped")
            tap(initial, "start-listening")
            # No UI-tree capture, screenshot or model round-trip in this critical window.
            deadline = time.monotonic() + 8
            active = None
            while time.monotonic() < deadline:
                current = adb("shell", "dumpsys", "media.audio_flinger", timeout=3).decode()
                if active_record_threads(current):
                    active = current
                    break
                time.sleep(0.05)
            if active is None:
                (output / "audio-not-ready.txt").write_text(current)
                raise RuntimeError("No active non-standby AudioFlinger input thread; injection was not started.")
            # Warm up this already-open input briefly so native initialization finishes.
            time.sleep(0.10)
            current = adb("shell", "dumpsys", "media.audio_flinger", timeout=3).decode()
            active_threads = active_record_threads(current)
            if not active_threads:
                raise RuntimeError("The microphone closed before injection; refusing the crash-prone RPC.")
            (output / "audio-active.txt").write_text(current)
            # The observed repeated-run emulator fault produced ~-3 dB input
            # before any fixture, despite its host microphone being disabled.
            # Healthy runs here had a noise floor near -78 dB. Refuse that
            # concrete broken-input state rather than risk another native crash.
            power_samples = []
            for block in active_threads:
                for line in block.splitlines():
                    if re.match(r"\s+\d{2}-\d{2} \d{2}:\d{2}:\d{2}.*?:\s*\[", line):
                        values = line.partition("[")[2].partition("]")[0]
                        power_samples.extend(float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", values))
            if power_samples:
                report["maximumPreInjectionPowerDb"] = max(power_samples)
                if max(power_samples) > -40:
                    raise RuntimeError("Unexpected input energy with host microphone disabled; no fixture was injected. Cold-boot the emulator before retrying.")
            event("microphone-active")
            report["injection"] = injector.inject_audio(fixture.path, serial=args.serial, timeout_seconds=fixture.duration_seconds + 8)
            event("injection-complete", elapsedSeconds=report["injection"]["elapsed_seconds"])
            deadline = time.monotonic() + 20
            final = None
            while time.monotonic() < deadline:
                observed = ui_snapshot("latest")
                phase = node(observed, "capture-phase").get("text")
                if phase in ("Completed", "Error", "Cancelled"):
                    final = observed
                    break
                time.sleep(0.15)
            if final is None:
                raise RuntimeError("The harness did not reach a final state.")
            (output / "final.png").write_bytes(adb("exec-out", "screencap", "-p"))
            tap(final, "copy-result")
            result = None
            for attempt in range(20):
                try:
                    candidate = json.loads(get_clip(b"", metadata=metadata, timeout=3).text)
                    if (candidate.get("schema") == "ansight.audio-harness-result/v1"
                            and candidate.get("expected") == report["expected"]
                            and datetime.fromisoformat(candidate["startedUtc"]) >= datetime.fromisoformat(report["startedUtc"])):
                        result = candidate
                        break
                except (json.JSONDecodeError, AttributeError, KeyError, ValueError, TypeError):
                    pass
                time.sleep(0.10)
            if result is None:
                raise RuntimeError("Could not retrieve the harness's result JSON from Copy result.")
            (output / "app-result.json").write_text(json.dumps(result, indent=2) + "\n")
            report["appResult"] = result
            report["hostMicrophoneEnabledAfter"] = get_mic(b"", metadata=metadata, timeout=3).realAudioEnabled
            if report["hostMicrophoneEnabledAfter"]:
                raise RuntimeError("Host microphone state was unexpectedly enabled after injection.")
            if args.outcome == "pass":
                report["passed"] = result["isFinal"] and result["passed"] and bool(result["transcript"].strip())
            elif args.outcome == "mismatch":
                report["passed"] = result["isFinal"] and not result["passed"] and bool(result["transcript"].strip())
            else:
                report["passed"] = (not result["isFinal"] and not result["passed"]
                                    and not result["transcript"].strip() and result["phase"] == "Error"
                                    and any(code in result["message"] for code in ("(NoMatch, code 7)", "(SpeechTimeout, code 6)")))
            event("asserted", passed=report["passed"], transcript=result["transcript"], phase=result["phase"])
    except Exception as error:
        code = getattr(error, "code", None)
        report["error"] = f"gRPC {code().name}" if callable(code) else str(error)
        try:
            ui_snapshot("failure")
            (output / "failure.png").write_bytes(adb("exec-out", "screencap", "-p"))
        except Exception:
            pass
        event("failed", error=report["error"])
    finally:
        report["completedUtc"] = utc_now()
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Evidence: {output}", flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
