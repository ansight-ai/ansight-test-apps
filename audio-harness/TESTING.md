# Testing synthetic microphone input

Run these checks from this dedicated app folder. Build and install the Debug harness using the [app instructions](apps/Ansight.AudioHarness/README.md), and complete the [worker setup](ansight/README.md#prepare-the-worker) first. Detailed task contracts and evidence paths are in the [workspace guide](ansight/README.md).

## Prerequisites and discovery

- **Android:** a running emulator with an authenticated audio gRPC endpoint, host microphone disabled, and microphone permission granted to the harness. Emulator **37.1.11 can still crash during native injection** despite preflight guards. Stale, unknown, or unexpectedly loud input must remain a rejection; do not bypass the guard or automatically retry a failed injection.
- **iOS:** exactly one booted simulator, BlackHole installed, and Simulator **I/O → Audio Input → BlackHole 2ch** selected. Use a stable Simulator **I/O → Audio Output** selection; the local setup explicitly selected **MacBook Pro Speakers** after an EarPods route change interrupted capture/playback. Keep that configuration stable throughout a corpus. Ansight needs Accessibility permission to verify the input selection. Restart simulators that were already booted when BlackHole was installed or CoreAudio restarted, then select the route again. These are Simulator settings; keep Mac audio defaults unchanged.
- Run audio cases serially. The harness must be foreground and connected to the current resident host. Capture mode needs no speech service; Whisper needs the prepared model bundled into the app, and native transcript mode needs the platform speech service.

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

## Offline Whisper transcription

Prepare the model **before building/installing** the updated app:

```sh
python3 scripts/prepare-whisper-model.py
python3 scripts/prepare-whisper-model.py --verify-only
```

The script uses the checked-in `Resources/Raw/models/whisper-model.json` manifest to pin `base.en`, its source revision, size and SHA-256. The approximately 148 MB model binary is ignored by Git and bundled as a MAUI asset. Preparation needs network access once; the installed app does not download the model or call a speech service. See [model setup](apps/Ansight.AudioHarness/README.md#offline-whisper-model).

Ground `use-whisper` and `transcription-provider-state` in a fresh live visual tree from the new build before running. Whisper mode selects **Whisper (offline)** with capture-only disabled. On Android it injects immediately after Start and lets the provider wait up to 10 seconds for the actual guest microphone, preserving its quiet-input guard. On iOS it first waits for visible **Listening** after model preparation, since the provider cannot inspect guest capture readiness. Both paths stop recording after delivery and transcribe that saved microphone WAV locally:

```sh
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id "$AUDIO_SESSION_ID" \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"whisper"}' --json
```

Require all of the capture-mode proof plus a matching final transcript. Check `transcription.provider` is `whisper.net`, `model` is `base.en`, and `modelSha256` matches the pinned manifest. `transcription.sourceAudioSha256` must match both the immutable capture metadata and the downloaded microphone WAV. The result also records the 16 kHz mono transcription input hash and processing duration; that normalized hash is metadata, not a separately exported recording. Expected text is used only for the final assertion and never supplied as a Whisper prompt.

The task maps typographic dashes and curly apostrophes to equivalent ASCII when typing the expected phrase, because Simulator HID cannot enter those characters. This preserves the app's normalized words and leaves the original fixture/audio unchanged. It explicitly focuses the field, types, dismisses the keyboard, and verifies the displayed expectation before Start. `expected-input.json` retains the intended input; `expected-input-observation.json` retains the observed field value. A silently unapplied edit must fail before recording.

After a single pass, `audio.quote-corpus` accepts `--input '{"mode":"whisper"}'`. Its 300-second deadline includes all eight children; run individual fixtures if offline inference or UI automation exceeds that budget. The single task allows 180 seconds overall, up to 35 seconds for iOS's visible model-preparation/listening state, a 10-second provider microphone-readiness wait, and a 60-second terminal-result wait. Android performs no UI status lookup between Start and injection, or extra scroll before Stop, so UI navigation does not consume the recording window. A timed-out or incomplete corpus remains a failure.

The optional agentic scenario is `audio.whisper-transcription`; schema validation does not run it. The new controls have been observed in both platforms' live accessibility trees, and the single-fixture Whisper workflow has passed on both platforms. The results below distinguish those transcript proofs from the earlier capture-only runs.

## Optional native transcription

Test speech recognition separately after capture verification. It requires an available native recognizer, the relevant permissions, and potentially network access:

```sh
ansight task run audio.inject-and-verify \
  --app-id ai.ansight.audioharness --repository "$PWD" --session-id "$AUDIO_SESSION_ID" \
  --input '{"fixtureId":"shakespeare-hamlet","mode":"transcript"}' --json
```

This mode explicitly selects **Native speech** by disabling the Whisper switch. Require a final `Completed` result, `isFinal:true`, `passed:true`, and an independent match with the fixture text. An unavailable Apple Speech or Android recognition service is a transcription failure, even when microphone capture passed. The [agentic tests](ansight/README.md#agentic-test) are separate optional runs.

## Validation status

### Offline Whisper — 9 September 2026

Final coverage is **8/8 quotes on iOS** and **three distinct quotes on Android**. The final task source is `e36ce2f`, exercised on resident host **0.38.6-local / 2026090902**. All observed final-case transcripts, microphone waveforms and wrong-quote controls passed. The Android eight-quote corpus remains unverified.

The same prepared `base.en` model and MAUI app code produced the correct Hamlet transcript from the actual device microphone on both platforms. Each deterministic run passed **30 assertions**, including the immutable recording hash, whole-speech waveform comparison, different-quote rejection, pinned model hash, source-audio provenance, final transcript, and reset to Ready.

| Platform | Recorded microphone | Whole-speech correlation | Wrong-quote correlation | Whisper processing |
| --- | --- | --- | --- | --- |
| iOS 26.4 Simulator | 48 kHz stereo, 7.2 seconds | **0.997694** | **0.229510**, rejected | **1.311 seconds** |
| Android 16 Emulator | 16 kHz mono, 26.528 seconds | **1.000000** | **0.228454**, rejected | **1.194 seconds** |

iOS single task `7296803860d84d55bf6c7dde6af91dbb` used session `ai-ansight-audioharness-1538` with CLI **0.38.6 / 2026090901**. Android single task `a6929a1385bd44b9b42bfe6db09ee56d` used session `ai-ansight-audioharness-1539` with **0.38.6-local / 2026090902**, built from keyboard fix `d90de7c1`. Android's total task time was 74.5 seconds including UI automation and artifact checks; that is separate from its 1.194-second inference time.

For each single, both automatic terminal triggers completed and their retained timeline JSON and WAV were exported independently. Each export matched the task's copy byte for byte; the WAV hash also matched `transcription.sourceAudioSha256`. Audit receipts are `artifacts/audio-harness/whisper-20260909/ios-single-audit/summary.json` and `android-single-audit/summary.json`.

The final iOS Whisper corpus then passed **8/8 quotes** on **2026090902** with task source `e36ce2f`: parent `54ea1149ed0344a29d9cbbdd70e9abdf`, session `ai-ansight-audioharness-1540`, **18 parent assertions and 31 assertions per child**, completed in **141.726 seconds**. All eight final transcripts matched. Whole-speech correlations ranged from **0.990140 to 0.999533**, all eight wrong-quote controls were rejected, and inference took **1.073–1.259 seconds** per recording. The read-only audit verified eight distinct app runs, recording hashes, fixture identities and completed injections from the retained files. Its receipt is `ios-corpus-audit/summary.json`; the single-run audits above independently verify the automatic timeline path.

The first iOS Whisper corpus passed four quotes, then failed during Lincoln playback. A host output change to EarPods preceded a CoreAudio configuration notification that stopped the playback engine; the helper reported a timeout and the app rejected its silent recording before inference. The investigation does not establish who changed the output or the complete internal causal chain. The failed parent `decf19a2cf1d445c9420978fed05d2aa` and `ios-playback-failure/summary.json` remain retained. Keep the host audio configuration stable during a run; incomplete delivery must not be counted as a transcription pass.

Android subsequently passed Macbeth in the same emulator session, with **29/29 assertions**, correlation **1.0**, a rejected different-quote control (**0.138043**), and **1.041 seconds** of Whisper processing. Task `e4bfc428f1e8478fb0c824575bbb30f7` completed in 60.08 seconds. The emulator was not cold-booted or recovered between the successful Hamlet and Macbeth runs. This proves two distinct quotes and recorder reopening; an eight-quote Android Whisper corpus has not passed.

The final Android Descartes case used the current verified-input task and passed **30/30 assertions**, correlation **1.0**, and a rejected wrong-quote control (**0.183608**). Its exact final transcript was `I think, therefore I am.`; inference took **1.050 seconds**, and the full task took **63.710 seconds**. Task `d33dc5e8743a4a49aed6fa5eb02b5d28` used the same session `ai-ansight-audioharness-1539`, with no emulator restart across the three successful quotes. Its retained recording hash matches both app capture metadata and Whisper source-audio metadata. `android-final-task.json` and `validation-summary.json` retain the final result and coverage limits.

An intervening Macbeth attempt (`c307bef4e62840ce9414849368112618`) expired before injection because Start and the subsequent status-label navigation consumed the 30-second recording window. Its unrelated recognized output failed the expected-phrase assertion. Task fix `5e2fadf` removes that extra navigation on Android and immediately invokes the unchanged guest-microphone readiness/quiet-input checks. The successful repeat has one fewer assertion because it omits only the iOS-specific visible `Listening` check; transcript, recording, provenance and negative-control assertions remain intact.

The second iOS attempt (`65fd65243d474fc0a8b404943af3b60e`) stopped on its first quote with `loopback-no-active-client`, before audio delivery. After selecting Simulator **Audio Output → MacBook Pro Speakers**, rechecking BlackHole input, and relaunching only the harness, the fresh SDK session is `ai-ansight-audioharness-1540`. The repair changed no Mac audio defaults; `ios-route-repair/summary.json` retains its scope and route evidence.

The next attempt (`09701fafa13a4bbe893d8f77f4d01a7d`) correctly captured and transcribed Hamlet, with correlation **0.997831** and a rejected wrong-quote control, but the app's expected phrase still held its default quick-brown-fox text. Its final assertion correctly failed. The task now explicitly focuses the field and asserts its fresh displayed value before recording, so an unapplied edit stops before audio injection. This preserved attempt is a test-setup failure, not a Whisper recognition failure.

The final eight-quote pass used that repaired route and the verified-input task. Earlier partial and failed attempts remain separate in `validation-summary.json` and their original evidence directories.

Earlier setup failures remain preserved: Simulator HID rejected the original typographic dash before recording, the old Android AVD lacked installation space, and Android's keyboard-visibility parser rejected a safe dismissal before Start. Equivalent ASCII expectation entry, a separate 8 GiB AVD, and the CLI keyboard parser fix addressed those specific setup issues without weakening transcript or waveform assertions. Final TypeScript checks, both test-schema validations and task discovery passed without warnings; the receipt is `workspace/final-authoring-verified-input/summary.json`. No agentic test or MAUI unit test was run.

### Capture and media baseline — 8 September 2026

Recorded with CLI and resident host build **2026090805**, from Ansight commit `e1a86312`. All 16 embedded web assets were verified byte-for-byte against the intended media and icon build.

| Check | Verified result |
| --- | --- |
| Android single Hamlet capture | Passed 16 assertions; correlation **1.0**; different-quote control rejected. |
| iOS eight-quote capture corpus | **8/8 passed**, with 18 parent and 128 child assertions; correlations **0.990326–0.999380**; all eight different-quote controls rejected. |
| Android eight-quote corpus | **Failed after 1/8 passed.** The second quote, Macbeth, was rejected before injection because input energy was unexpectedly high while the host microphone was disabled. |
| Packaged local session viewer | Green Android and blue iOS badges passed. A **14.704-second** WAV loaded, advanced during muted playback, supported seeking, and cleaned up after closing with no media errors. |

Android single task `dc4b66a043da4e0abef46a5c12fcce56` used session `ai-ansight-audioharness-1532`. Both automatic terminal-artifact triggers succeeded, and five artifact exports completed. The Android corpus parent was `b7a5946cedd648d487d76409df522368`; its failed Macbeth child was `53728a9727264ceb9c425a1cd1e48177`.

iOS corpus parent task `cc05b889f003442a92ccec24e18c9025` used session `ai-ansight-audioharness-1533` on simulator `4594102E-88A3-4242-8851-F959C4C9DBBC`. Its audit verified **40 retained artifacts, 16 successful automatic triggers, and eight delivery exports**. The harness finished Ready with its microphone idle.

Local evidence is retained in the ignored `artifacts/audio-harness/ansight-live-20260908/` directory, including `android/single-2026090805.json`, `android/single-pass-trigger-audit-2026090805.json`, `android/corpus-2026090805.json`, `ios/corpus-final-proof.json`, and `media-final0805/summary.json`. Each task's full recording and comparison files remain under its evidence directory described above.

**Remaining issue at that checkpoint:** repeated capture on Android Emulator 37.1.11. After the recorder reopened, the emulator log repeated CoreAudio errors including `Could not initialize record`, `Could not set audio format change listener`, and `kAudioHardwareIllegalOperationError`. An explicitly prepared, freshly cold-started emulator can isolate dependence on retained audio state. Preserve failed-run evidence; do not add automatic retries or weaken the quiet-input guard. That Android corpus was not a full pass.

The final browser smoke covered the local session list and one muted WAV. Full local/team list checks in both light and dark themes remain manual regression guidance above. No native transcription run was performed on this final build.
