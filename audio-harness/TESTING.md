# Testing synthetic microphone input

Run these checks from this dedicated app folder. Build and install the Debug harness using the [app instructions](apps/Ansight.AudioHarness/README.md), and complete the [worker setup](ansight/README.md#prepare-the-worker) first. Detailed task contracts and evidence paths are in the [workspace guide](ansight/README.md).

## Prerequisites and discovery

- **Android:** a running emulator with an authenticated audio gRPC endpoint, host microphone disabled, and microphone permission granted to the harness. Emulator **37.1.11 can still crash during native injection** despite preflight guards. Stale, unknown, or unexpectedly loud input must remain a rejection; do not bypass the guard or automatically retry a failed injection.
- **iOS:** exactly one booted simulator, BlackHole installed, and Simulator **I/O → Audio Input → BlackHole 2ch** selected. Ansight needs Accessibility permission to verify that selection. Restart simulators that were already booted when BlackHole was installed or CoreAudio restarted, then select the route again. Keep Mac audio defaults unchanged.
- Run audio cases serially. The harness must be foreground and connected to the current resident host; capture mode does not require a speech service.

```sh
cd /Users/matthewrobbins/Development/git/ansight-test-apps/audio-harness
ansight version --json
ansight host status --json
ansight doctor --json
ansight device list --json
ansight session list --connected --app-id ai.ansight.audioharness --json
```

For iOS, also run `ansight doctor --require device.ios.audio.blackhole --json`. Choose the exact connected session whose platform and device match the intended target; rediscover after an app or host restart.

```sh
AUDIO_SESSION_ID='replace-with-the-exact-connected-session-id'
ansight session show "$AUDIO_SESSION_ID" --json
ansight audio capabilities --session "$AUDIO_SESSION_ID" --json
npm run --prefix ansight check
ansight test validate "$PWD" --json
ansight task list --app-id ai.ansight.audioharness --repository "$PWD" --json
```

An idle Android app can correctly report `microphone-not-ready`. Capabilities are diagnostics, not a recording test. Ground the task's automation IDs in a fresh live visual tree as described in the [workspace guide](ansight/README.md#validate-and-discover).

## Single-fixture proof, then all eight quotes

Connect the terminal-event triggers before the run when checking automatic timeline snapshots:

```sh
ansight repo automation connect ai.ansight.audioharness "$PWD" --json
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id "$AUDIO_SESSION_ID" \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"capture"}' --json
```

Require a fresh app run ID, its saved result JSON and actual microphone WAV, matching recording SHA-256, whole-fixture correlation at least **0.90**, and rejection of the different-quote control. Delivery success alone is insufficient. A successful task returns the app to Ready; a failure retains evidence and must not count as a pass.

After the single case passes, run the corpus on that platform:

```sh
ansight task run audio.quote-corpus \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id "$AUDIO_SESSION_ID" \
  --input '{"mode":"capture"}' --json
```

Repeat discovery and both commands for the other platform. Require all **eight child results** to pass on each platform before reporting a complete corpus pass. The corpus stops on failure and has a 300-second deadline; retained partial results are not a completed corpus. See the [fixture manifest](fixtures/audio/quotes/manifest.json) for individual IDs when separate runs are needed.

To check the direct CLI interface separately, select **Capture only** in the app, start capture, and wait for **Listening**, then immediately run:

```sh
ansight audio inject --session "$AUDIO_SESSION_ID" \
  --file fixtures/audio/quotes/shakespeare-hamlet.wav \
  --timeout-ms 30000 --wait-for-microphone-ms 5000 --json
```

Stop capture in the app afterward and inspect its exact-run artifacts. The CLI does not press Start or Stop, and a successful delivery still needs independent recording verification.

## Timeline, artifact transfer, and media review

```sh
ansight repo automation runs ai.ansight.audioharness --json
ansight session artifacts "$AUDIO_SESSION_ID" --limit 100 --json
ansight session serve "$AUDIO_SESSION_ID" --open
```

In the session viewer:

1. Find the terminal event and snapshots from `audio-harness.runs`. Match `metadata.runId` to the tested run; verify both `run-result` and `microphone-wav` completed with the expected byte counts. Check successful trigger attempts separately from the task's explicit requests; duplicate snapshots of the same immutable run are possible.
2. Confirm the microphone WAV displays an audio icon and audio player, while the JSON result displays the appropriate document/report icon. Open the JSON and verify the same run and capture metadata.
3. Play, pause, and seek the WAV. Confirm duration and audible content correspond to the quote, with no truncation. Confirm downloading/exporting retains the complete recording. Playback is an additional UI check; retain the task's independent waveform and wrong-fixture results as the capture proof.
4. Check both local and team session lists in light and dark themes: Android sessions have green platform badges and iOS sessions have blue platform badges. Confirm each row keeps its app icon and that selecting the row still shows the correct session with a visible selection state.

Evidence is retained under `artifacts/audio-harness/ansight/<task-run-id>/`; see the [evidence checklist](ansight/README.md#evidence-and-success). The app's `Ready for snapshot` label only means files are available, not that the host received them.

## Optional native transcription

Test speech recognition separately after capture verification. It requires an available native recognizer, the relevant permissions, and potentially network access:

```sh
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id "$AUDIO_SESSION_ID" \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"transcript"}' --json
```

Require a final `Completed` result, `isFinal:true`, `passed:true`, and an independent match with the fixture text. An unavailable Apple Speech or Android recognition service is a transcription failure, even when microphone capture passed. The [agentic test](ansight/README.md#agentic-test) is a separate optional run.

## Validation status

Recorded on **2026-09-08** with CLI and resident host build **2026090805**, from Ansight commit `e1a86312`. All 16 embedded web assets were verified byte-for-byte against the intended media and icon build.

| Check | Verified result |
| --- | --- |
| Android single Hamlet capture | Passed 16 assertions; correlation **1.0**; different-quote control rejected. |
| iOS eight-quote capture corpus | **8/8 passed**, with 18 parent and 128 child assertions; correlations **0.990326–0.999380**; all eight different-quote controls rejected. |
| Android eight-quote corpus | **Failed after 1/8 passed.** The second quote, Macbeth, was rejected before injection because input energy was unexpectedly high while the host microphone was disabled. |
| Packaged local session viewer | Green Android and blue iOS badges passed. A **14.704-second** WAV loaded, advanced during muted playback, supported seeking, and cleaned up after closing with no media errors. |

Android single task `dc4b66a043da4e0abef46a5c12fcce56` used session `ai-ansight-audioharness-1532`. Both automatic terminal-artifact triggers succeeded, and five artifact exports completed. The Android corpus parent was `b7a5946cedd648d487d76409df522368`; its failed Macbeth child was `53728a9727264ceb9c425a1cd1e48177`.

iOS corpus parent task `cc05b889f003442a92ccec24e18c9025` used session `ai-ansight-audioharness-1533` on simulator `4594102E-88A3-4242-8851-F959C4C9DBBC`. Its audit verified **40 retained artifacts, 16 successful automatic triggers, and eight delivery exports**. The harness finished Ready with its microphone idle.

Local evidence is retained in the ignored `artifacts/audio-harness/ansight-live-20260908/` directory, including `android/single-2026090805.json`, `android/single-pass-trigger-audit-2026090805.json`, `android/corpus-2026090805.json`, `ios/corpus-final-proof.json`, and `media-final0805/summary.json`. Each task's full recording and comparison files remain under its evidence directory described above.

**Next priority:** reproduce and fix repeated capture on Android Emulator 37.1.11. After the recorder reopens, the emulator log repeats CoreAudio errors including `Could not initialize record`, `Could not set audio format change listener`, and `kAudioHardwareIllegalOperationError`. Use an explicitly prepared, freshly cold-started emulator to isolate whether the failure depends on retained audio state, then repeat the single case and corpus. Preserve failed-run evidence; do not add automatic retries or weaken the quiet-input guard. The Android corpus is not a full pass.

The final browser smoke covered the local session list and one muted WAV. Full local/team list checks in both light and dark themes remain manual regression guidance above. No native transcription run was performed on this final build.
