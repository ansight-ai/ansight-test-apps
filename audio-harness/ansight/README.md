# Audio harness Ansight workspace

App ID: `ai.ansight.audioharness`. The dedicated `audio-harness/` folder is the registered Ansight workspace root, within the `ansight-test-apps` Git repository. All fixtures, scripts, dependencies, and task evidence resolve relative to that folder. The workspace uses generated version 1 schemas and task declarations from the audio-enabled host build. It contains no MAUI unit tests.

| Kind | ID | Behavior |
| --- | --- | --- |
| Agentic test | `audio.synthetic-microphone` | Runs the single-fixture capture task and assesses its actual recording evidence. |
| Deterministic task | `audio.inject-and-verify` | Starts ordinary recording, injects one WAV into the selected virtual microphone, downloads exact-run SDK artifacts, verifies the whole waveform and a wrong-fixture control, and resets after success. |
| Deterministic task | `audio.quote-corpus` | Composes the single-fixture task for all eight quotes serially; stops at the first failed child. |
| Trigger | `audio.capture-terminal-result` | Requests immutable result JSON after the app persists a terminal run. |
| Trigger | `audio.capture-terminal-recording` | Requests that run's microphone WAV when its terminal event reports a recording. |

## Prepare the worker

Use an Ansight CLI and resident host exposing `ansight audio` and `ansight.device.audioCapabilities()` / `injectAudio()`. Copying declarations does not add capabilities to an older running host.

From the dedicated app folder:

```sh
cd /Users/matthewrobbins/Development/git/ansight-test-apps/audio-harness
npm ci --prefix ansight
python3 -m venv .venv-audio
.venv-audio/bin/python -m pip install -r scripts/requirements-audio.txt
ffmpeg -version
ffprobe -version
ansight workspace init "$PWD" --app-id ai.ansight.audioharness --json
```

The tasks are trusted local Node code. They read repository fixtures, accept host-returned SDK artifact paths, write under `artifacts/audio-harness/ansight/`, and invoke the existing Python waveform verifier with bounded subprocess timeouts. The repository, Python environment, ffmpeg, and ffprobe must exist on the worker running the resident host. Task calls do not upload them automatically.

Install and open the current Debug harness with its SDK and `audio-harness.runs` provider; see the [app instructions](../apps/Ansight.AudioHarness/README.md). Grant microphone permission before a deterministic run. Transcript mode also requires speech permissions and a working native recognizer.

- **Android:** use an authenticated emulator audio gRPC endpoint with the host microphone disabled. An idle app may report `microphone-not-ready`; the task starts ordinary `AudioRecord` capture before injection. Emulator 37.1.11 has an upstream native injection race that can crash it. Guards reduce risk but cannot guarantee stability; tasks do not restart or retry after failure.
- **iOS:** use exactly one booted simulator and the running Xcode Simulator UI with Audio Input already set to the separately installed BlackHole device. Ansight needs Accessibility access to verify the route. The task changes no host defaults, permissions, or routes. After installing the driver or restarting CoreAudio, restart any simulator that was already booted before selecting its input again. Capture mode works independently of Apple Speech availability. Serialize audio runs because the loopback route is shared on the host.

The single-fixture task checks files and dependencies before Start, then immediately awaits `injectAudio({file, timeoutMs:30000, waitForMicrophoneMs:5000})`, with no intervening UI calls. The iOS readiness wait observes a host loopback input client; proof of app capture comes from the downloaded WAV.

## Validate and discover

```sh
npm run --prefix ansight check
ansight test validate "$PWD" --json
ansight task list --app-id ai.ansight.audioharness --repository "$PWD" --json
ansight repo automation inspect ai.ansight.audioharness "$PWD" --json
```

Use absolute repository paths for forwarded host commands. Initialization preserves customized files. Review generated support-file changes before using `--force`.

Task selectors use `harness-scroll`, `start-listening`, `run-id`, `capture-only-state`, `capture-only`, `stop-listening`, `result-saved`, `reset-test`, and `capture-phase`. Transcript mode also uses `expected-phrase`. Verify these IDs and displayed states in a fresh live visual tree before the first run on a new build; source inspection and compilation alone do not establish visible selectors.

The task seeks offscreen controls with at most three semantic swipes per search in `harness-scroll`, using fresh UI evidence after each gesture. It stops recording before seeking the footer, then brings Reset into view and returns to the top after success. The 80-action limit covers these bounded searches and cleanup on small screens. It never substitutes coordinates for missing selectors.

## Run deterministic verification

Discover the harness session and use its exact ID:

```sh
ansight session list --app-id ai.ansight.audioharness --json
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"capture"}' --json
```

Defaults are fixture `shakespeare-hamlet` and mode `capture`. All eight fixture IDs are declared in the task schema and [manifest](../fixtures/audio/quotes/manifest.json). The expected phrase is only a validation input in transcript mode; it is never sent to the recorder as audio or substituted for a recognized result.

```sh
ansight task run audio.quote-corpus \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"mode":"capture"}' --json
```

The corpus has the maximum 300-second task deadline; each child is capped by the parent's remaining time. Slow workers may need separate single-fixture runs. Each child retains its own assertions and result; a failure preserves completed corpus results and does not count as a pass.

To exercise native recognition explicitly:

```sh
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"transcript"}' --json
```

Transcript mode requires the app's final `Completed` result, `isFinal` and `passed`, and an independent normalized match between the actual transcript and fixture text. Missing recognition or permission remains a failure; the task does not silently change modes.

## Evidence and success

Each run saves `artifacts/audio-harness/ansight/<task-run-id>/`:

- `fixture.wav`, `fixture.json`, `capabilities.json`, and `injection.json` identify the exact fixture and provider delivery.
- `run-result-transfer.json` and `app-result.json` bind the fresh app run to provider/artifact IDs, transfer ID, complete byte count, and result metadata.
- Capture mode adds `microphone-wav-transfer.json`, the full `microphone.wav`, `waveform-verification.json`, `wrong-fixture.wav`, and `wrong-fixture-verification.json`.
- `verification.json` records the outcome and injection evidence ID; `failure.json` preserves errors. Unconfirmed recorder cleanup is reported separately when task execution remains available.

Capture mode requires `recording-sha256-matches-app`, `whole-spoken-fixture-received`, and `different-spoken-fixture-rejected`. The verifier compares the entire nonzero fixture span, permits capture delay and gain, and requires waveform correlation of at least **0.90**. It does not trim or reorder words. A different quote must fail the same comparator; an error running the comparator cannot count as the negative control.

The task's `captureVerified:true` is based on separately recorded WAV evidence. Injection itself correctly returns `captureVerified:false` and `transcriptionVerified:false`: delivery alone does not prove app capture. Capture mode makes no transcription claim. Failed tasks preserve their state and never silently reinject; successful tasks reset the harness to Ready.

## Terminal artifacts in the timeline

After persisting immutable files, the app emits `audio-harness.run.finished` with versioned run and artifact IDs. Each trigger returns one supported `app.artifacts.request` action. Explicitly connect when the host should collect these artifacts automatically:

```sh
ansight repo automation connect ai.ansight.audioharness "$PWD" --json
ansight repo automation runs ai.ansight.audioharness --json
```

Verify retained artifacts and successful trigger attempts after an actual run; registration alone is not upload evidence. Tasks independently request their exact run artifacts, so a connected trigger can create a second snapshot of the same immutable content. `Ready for snapshot` means files are available to request, not that an upload has finished.

## Agentic test

The agentic test is authored for optional execution. Creating this workspace does not run the model-backed test. When that run is wanted:

```sh
ansight test run "$PWD" audio.synthetic-microphone --trace --json
```

The test delegates the known workflow to the exact task and requires its recorded-audio and negative-control evidence. Missing prerequisites must be reported rather than silently bypassed.
