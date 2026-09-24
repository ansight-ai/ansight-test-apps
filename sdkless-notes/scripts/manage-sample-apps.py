#!/usr/bin/env python3
"""Register or deregister the SDK-free iOS/Android Notes samples in Ansight."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

APP_ID = "ai.ansight.testapps.sdklessnotes"
APP_NAME = "SDK-less Notes"
DATABASES = {"ios": "Documents/notes.sqlite", "android": "files/notes.sqlite"}


class Ansight:
    def __init__(self, executable, data_directory):
        self.executable = shutil.which(os.path.expanduser(executable))
        if not self.executable:
            raise RuntimeError(f"Ansight executable not found: {executable}. Install Ansight or set ANSIGHT_CLI.")
        self.options = ["--json"]
        if data_directory:
            self.options += ["--data-dir", str(Path(data_directory).expanduser().resolve())]

    def run(self, *arguments, allow_unregistered=False):
        command = [self.executable, *arguments, *self.options]
        print("+ " + shlex.join(command), flush=True)
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError as error:
            raise RuntimeError(f"Ansight returned invalid JSON:\n{result.stderr or result.stdout}") from error
        if not isinstance(payload, dict):
            raise RuntimeError("Ansight returned an unexpected response; update the CLI and resident host.")
        if result.returncode:
            # Only the exact 'already removed' result is idempotent; never hide auth/host errors.
            already_removed = (
                allow_unregistered
                and payload.get("schema") == "ansight.app-operation/v1"
                and payload.get("operation") == "remove"
                and payload.get("result", {}).get("message") == f"App '{APP_ID}' is not registered."
            )
            if not already_removed:
                raise RuntimeError(f"Ansight command failed ({result.returncode}):\n{result.stderr or result.stdout}")
        return payload

    def watches(self):
        result = self.run("app", "watch", "list")
        if result.get("schema") != "ansight.app-watches/v1" or not isinstance(result.get("watches"), list):
            raise RuntimeError("This harness requires Ansight app-watch support. Update the CLI and resident host.")
        return result


def sample_watches(response):
    return [entry["watch"] for entry in response["watches"] if entry["watch"]["appId"] == APP_ID]


def register(client):
    client.watches()  # Prove host access before changing configuration.
    client.run("app", "register", APP_ID, "--name", APP_NAME)
    desired_ids = set()
    for platform, database in DATABASES.items():
        response = client.run("app", "watch", "add", APP_ID, "--platform", platform, "--capture-file", database)
        if not response.get("watchId"):
            raise RuntimeError("Ansight did not return the new watch ID.")
        desired_ids.add(response["watchId"])

    # The dedicated sample ID belongs to this harness. Replace legacy or overlapping
    # watches so they cannot take capture ownership without the database snapshots.
    for watch in sample_watches(client.watches()):
        if watch["id"] not in desired_ids:
            client.run("app", "watch", "remove", watch["id"])

    result = client.watches()
    watches = sample_watches(result)
    if len(watches) != len(DATABASES) or any(
        not watch["enabled"] or watch.get("deviceId") is not None
        or watch.get("platform") not in DATABASES
        or watch["captureFiles"] != [DATABASES[watch["platform"]]]
        for watch in watches
    ):
        raise RuntimeError("The sample watch configuration did not match the requested setup.")
    print(f"\nRegistered {APP_NAME} ({APP_ID}) on all iOS simulators and Android emulators.")
    for watch in watches:
        print(f"  {watch['platform']}: {watch['id']} — capture {DATABASES[watch['platform']]} on exit")
    if not result.get("hostRunning"):
        options = ["--data-dir", client.options[-1]] if "--data-dir" in client.options else []
        print("Configuration saved. Start the resident host: " + shlex.join([client.executable, "host", "run", *options]))
    else:
        print("The resident host is running. Launch either sample app to record automatically.")


def deregister(client):
    for watch in sample_watches(client.watches()):
        client.run("app", "watch", "remove", watch["id"])
    if sample_watches(client.watches()):
        raise RuntimeError("Some sample watches remain; rerun deregistration before removing app metadata.")
    client.run("app", "remove", APP_ID, allow_unregistered=True)
    print(f"\nDeregistered {APP_NAME} ({APP_ID}).")
    print("Recordings and installed apps are preserved. Historical sessions may still show the app in Ansight.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["register", "deregister"])
    parser.add_argument("--ansight", default=os.environ.get("ANSIGHT_CLI", "ansight"),
                        help="Ansight executable (default: ANSIGHT_CLI or ansight on PATH)")
    parser.add_argument("--data-dir", help="Use a specific Ansight data directory; defaults to the installed host")
    args = parser.parse_args()
    try:
        client = Ansight(args.ansight, args.data_dir)
        (register if args.action == "register" else deregister)(client)
        return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
