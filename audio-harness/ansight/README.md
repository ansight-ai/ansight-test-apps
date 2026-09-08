# Audio harness Ansight workspace

App ID: `ai.ansight.audioharness`. The dedicated `audio-harness/` folder is the registered Ansight workspace root, within the `ansight-test-apps` Git repository. All fixtures, scripts, dependencies, and task evidence resolve relative to that folder. The workspace uses generated version 1 schemas and task declarations from the audio-enabled host build. It contains no MAUI unit tests.

| Kind | ID | Behavior |
| --- | --- | --- |
| Agentic test | `audio.synthetic-microphone` | Runs the single-fixture capture task and assesses its actual recording evidence. |
| Agentic test | `audio.whisper-transcription` | Runs Whisper mode and requires both the final offline transcript and proof of the microphone recording it transcribed. |
| Deterministic task | `audio.inject-and-verify` | Starts ordinary recording and injects one WAV. Capture verifies the waveform and wrong-fixture control; Whisper adds the final offline transcript and model/audio provenance. Native recognition remains available as explicit transcript mode. |
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

Install and open the current Debug harness with its SDK and `audio-harness.runs` provider; see the [app instructions](../apps/Ansight.AudioHarness/README.md). Grant microphone permission before a deterministic run. Native `transcript` mode also requires speech permissions and a working native recognizer. `whisper` mode uses only microphone permission and the bundled offline model; it does not depend on Apple Speech or Android's speech service.

Before building a Whisper-enabled app, run `python3 scripts/prepare-whisper-model.py`. It verifies the pinned source, size and SHA-256 from `apps/Ansight.AudioHarness/Resources/Raw/models/whisper-model.json` and writes the ignored model binary beside that manifest. `--verify-only` checks an existing download. The task reads the versioned manifest on the host and requires the app's reported model hash to match; the app itself checks its bundled model before recording.

- **Android:** use an authenticated emulator audio gRPC endpoint with the host microphone disabled. An idle app may report `microphone-not-ready`; the task starts ordinary `AudioRecord` capture before injection. Emulator 37.1.11 has an upstream native injection race that can crash it. Guards reduce risk but cannot guarantee stability; tasks do not restart or retry after failure.
- **iOS:** use exactly one booted simulator and the running Xcode Simulator UI with Audio Input already set to the separately installed BlackHole device. Keep Simulator's Audio Output selection stable as well; the local repair selected MacBook Pro Speakers after an EarPods configuration change interrupted playback, without changing Mac audio defaults. Ansight needs Accessibility access to verify the input route. The task changes no host defaults, permissions, or routes. After installing the driver or restarting CoreAudio, restart any simulator that was already booted before selecting its input again. Capture mode works independently of Apple Speech availability. Serialize audio runs because the loopback route is shared on the host.

The single-fixture task checks files and dependencies before Start. Capture and native transcript modes immediately call `injectAudio({file, timeoutMs:30000, waitForMicrophoneMs:5000})`, with no intervening UI calls. Android Whisper also injects immediately after Start, with a 10000 ms readiness wait that checks the active guest microphone and quiet-input guard inside the provider. It leaves the recording controls in view for Stop; navigating to a status label can consume the app's 30-second recording window. iOS Whisper first waits up to 35 seconds for visible `Listening`, allowing bounded first-use model preparation, then injects with a 10000 ms readiness wait and brings Stop back into view. iOS readiness observes a host loopback input client, not the guest app. Both platforms transcribe the continuous PCM recording after Stop, and proof of app capture comes from the downloaded WAV. A missed preparation or recording deadline remains a failure.

## Validate and discover

```sh
npm run --prefix ansight check
ansight test validate "$PWD" --json
ansight task list --app-id ai.ansight.audioharness --repository "$PWD" --json
ansight repo automation inspect ai.ansight.audioharness "$PWD" --json
```

Use absolute repository paths for forwarded host commands. Initialization preserves customized files. Review generated support-file changes before using `--force`.

Task selectors use `harness-scroll`, `start-listening`, `run-id`, `capture-only-state`, `capture-only`, `stop-listening`, `result-saved`, `reset-test`, and `capture-phase`. Both transcription modes also use `expected-phrase`, `use-whisper`, and `transcription-provider-state`. The latter reads exactly `Whisper (offline)` or `Native speech`. Verify these IDs and displayed states in a fresh live visual tree before the first run on a new build; source inspection and compilation alone do not establish visible selectors. The new Whisper controls were observed on 9 September 2026 in iOS session `ai-ansight-audioharness-1538` and Android session `ai-ansight-audioharness-1539`. Local receipts are `artifacts/audio-harness/whisper-20260909/workspace/selector-grounding-ios.json` and `selector-grounding-android.json`. The native-provider transition still requires observation on the updated app.

The task seeks offscreen controls with at most three semantic swipes per search in `harness-scroll`, using fresh UI evidence after each gesture. It stops recording before seeking the footer, then brings Reset into view and returns to the top after success. Its 96-action limit covers mode selection, bounded searches and cleanup on small screens. The single-task deadline is 180 seconds; Whisper allows up to 60 seconds for the terminal result after Stop. Missing controls or timeouts remain failures.

## Run deterministic verification

Discover the harness session and use its exact ID:

```sh
ansight session list --app-id ai.ansight.audioharness --json
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"capture"}' --json
```

Defaults are fixture `shakespeare-hamlet` and mode `capture`. All eight fixture IDs are declared in the task schema and [manifest](../fixtures/audio/quotes/manifest.json). The expected phrase is only a final validation input in either transcription mode; it is never sent to a recognizer as a prompt or substituted for a recognized result. The app's default Whisper switch does not change the task's default capture mode.

Simulator HID cannot type the corpus's typographic punctuation. The task enters an equivalent ASCII expectation: typographic dashes become spaces and curly apostrophes become straight apostrophes, preserving the app's whole-word normalization. It explicitly focuses the field before typing, dismisses the keyboard, and requires the fresh observed field value to match before Start. A completed typing action alone is insufficient. The fixture bytes and original text used by the independent transcript comparator remain unchanged. `expected-input.json` retains the original and intended expectation, and `expected-input-observation.json` records what the app actually displays. Unsupported characters or unapplied edits fail before recording.

```sh
ansight task run audio.quote-corpus \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"mode":"capture"}' --json
```

The corpus has the maximum 300-second task deadline; each child is capped by the parent's remaining time. Slow workers, particularly during offline inference, may need separate single-fixture runs. Each child retains its own assertions and result; a failure preserves completed corpus results and does not count as a pass.

To require offline transcription of the actual microphone recording:

```sh
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"whisper"}' --json
```

Whisper mode disables capture-only, enables `use-whisper`, and checks the provider label before Start. It requires every capture assertion plus a final matching transcript and recorded provenance: `provider:"whisper.net"`, `model:"base.en"`, the pinned `modelSha256`, `sourceAudioSha256` equal to the transferred microphone WAV hash, 16000 Hz mono transcription input, its hash, and processing time. The normalized input hash is app-reported metadata; the task does not independently download a second normalized WAV. A missing model or unsuccessful transcription cannot fall back to native recognition. Use `{"mode":"whisper"}` with `audio.quote-corpus` only after the single case passes on that platform.

To exercise native recognition explicitly:

```sh
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id <session-id> \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"transcript"}' --json
```

Native transcript mode explicitly disables `use-whisper`. It requires the app's final `Completed` result, `isFinal` and `passed`, and an independent normalized match between the actual transcript and fixture text. Missing recognition or permission remains a failure; the task does not silently change modes.

## Evidence and success

Each run saves `artifacts/audio-harness/ansight/<task-run-id>/`:

- `fixture.wav`, `fixture.json`, `capabilities.json`, and `injection.json` identify the exact fixture and provider delivery.
- `run-result-transfer.json` and `app-result.json` bind the fresh app run to provider/artifact IDs, transfer ID, complete byte count, and result metadata.
- Capture and Whisper modes add `microphone-wav-transfer.json`, the full `microphone.wav`, `waveform-verification.json`, `wrong-fixture.wav`, and `wrong-fixture-verification.json`. Whisper also saves the pinned `whisper-model.json` and transcription provenance in `verification.json`.
- `verification.json` records the outcome and injection evidence ID; `failure.json` preserves errors. Unconfirmed recorder cleanup is reported separately when task execution remains available.

Capture and Whisper modes require `recording-sha256-matches-app`, `whole-spoken-fixture-received`, and `different-spoken-fixture-rejected`. The verifier compares the entire nonzero fixture span, permits capture delay and gain, and requires waveform correlation of at least **0.90**. It does not trim or reorder words. A different quote must fail the same comparator; an error running the comparator cannot count as the negative control.

The task's `captureVerified:true` is based on separately recorded WAV evidence. Injection itself correctly returns `captureVerified:false` and `transcriptionVerified:false`: delivery alone does not prove app capture. Capture mode makes no transcription claim. Failed tasks preserve their state and never silently reinject; successful tasks reset the harness to Ready.

## Terminal artifacts in the timeline

After persisting immutable files, the app emits `audio-harness.run.finished` with versioned run and artifact IDs. Each trigger returns one supported `app.artifacts.request` action. Explicitly connect when the host should collect these artifacts automatically:

```sh
ansight repo automation connect ai.ansight.audioharness "$PWD" --json
ansight repo automation runs ai.ansight.audioharness --json
```

Verify retained artifacts and successful trigger attempts after an actual run; registration alone is not upload evidence. Tasks independently request their exact run artifacts, so a connected trigger can create a second snapshot of the same immutable content. `Ready for snapshot` means files are available to request, not that an upload has finished.

## Agentic test

The agentic tests are authored for optional execution. Creating this workspace does not run either model-backed test. When a run is wanted, choose the capture-only or offline-transcription scenario:

```sh
ansight test run "$PWD" audio.synthetic-microphone --trace --json
ansight test run "$PWD" audio.whisper-transcription --trace --json
```

Both tests delegate the known workflow to the exact task and require recorded-audio and negative-control evidence. The Whisper scenario also requires the final transcript and model/audio provenance. Missing prerequisites must be reported rather than silently bypassed. Authoring and schema validation do not establish a live Whisper pass.
