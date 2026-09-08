# Audio Harness

A small .NET MAUI app for checking whether synthetic speech reaches an iOS Simulator or Android Emulator through its microphone. Both platforms can transcribe captured audio offline with Whisper, use a native speech provider, or save microphone samples for waveform verification. Application ID: `ai.ansight.audioharness`.

```text
Host WAV playback/injector → virtual device microphone → microphone WAV → offline Whisper → final transcript
                                                                      → whole-waveform assertion
                                                     → native speech recognizer → final transcript
```

The host injects the speech track. The app receives ordinary microphone audio. **Use Whisper** is enabled by default: it transcribes the WAV produced by the native microphone recorder. Disabling it selects Apple Speech or Android's installed speech provider. **Record audio without transcription** skips recognition regardless of the Whisper setting. The expected phrase is only the final assertion; it is never supplied to either recognizer as audio, a prompt, or a hint. The injected fixture file is never passed directly to the app's transcription engine.

## Build and install

Run commands from the dedicated `audio-harness/` folder within `ansight-test-apps`. `global.json` selects .NET SDK `10.0.100` with patch roll-forward. The current local setup uses the installed iOS 26.4 workload; Android needs its .NET workload, SDK, and JDK. iOS builds require macOS and compatible Xcode.

```sh
python3 scripts/prepare-whisper-model.py
dotnet build apps/Ansight.AudioHarness/Ansight.AudioHarness.csproj -f net10.0-ios -p:RuntimeIdentifier=iossimulator-arm64
dotnet build apps/Ansight.AudioHarness/Ansight.AudioHarness.csproj -f net10.0-android
```

For an explicitly selected booted simulator or emulator, replace the target placeholders:

```sh
xcrun simctl install <SIMULATOR_UDID> apps/Ansight.AudioHarness/bin/Debug/net10.0-ios/iossimulator-arm64/Ansight.AudioHarness.app
xcrun simctl launch <SIMULATOR_UDID> ai.ansight.audioharness
adb -s <EMULATOR_SERIAL> install -r apps/Ansight.AudioHarness/bin/Debug/net10.0-android/ai.ansight.audioharness-Signed.apk
```

Open **Audio Harness** on Android after installation. Debug builds include `Ansight.Maui` `1.4.0-preview.5` and automatically probe for a resident Ansight host. Release builds omit that SDK reference. The microphone/transcription flow works independently of a host connection.

For an ARM64 emulator with limited storage, this smaller package was used locally:

```sh
dotnet build apps/Ansight.AudioHarness/Ansight.AudioHarness.csproj -f net10.0-android -r android-arm64 -p:AndroidIncludeDebugSymbols=false -p:AndroidUseAssemblyStore=true -p:AndroidEnableAssemblyCompression=true
adb -s <EMULATOR_SERIAL> install --no-incremental -r apps/Ansight.AudioHarness/bin/Debug/net10.0-android/android-arm64/ai.ansight.audioharness-Signed.apk
```

This retains the Debug configuration and Ansight SDK but omits Android debugging support, so `adb run-as` is unavailable. Use **Copy result** or the SDK artifact provider for result export from that package.

## Offline Whisper model

Run `python3 scripts/prepare-whisper-model.py` from the dedicated app folder before building. It downloads the pinned `base.en` model to `apps/Ansight.AudioHarness/Resources/Raw/models/ggml-base.en.bin`, verifies its **147,964,211-byte** size and SHA-256, and leaves the binary ignored by Git. `python3 scripts/prepare-whisper-model.py --verify-only` verifies an existing file without downloading. The versioned `whisper-model.json` beside it records the exact source revision, digest and license attribution. Both manifest and prepared model are bundled as MAUI assets.

Allow device storage for the installed package, Android installation staging, and the app's additional **148 MB** model copy. The local ARM64 Whisper APK was **173,944,954 bytes** (about 166 MiB). Installing it on the existing nearly full emulator failed before launch; a dedicated `Ansight_Audio_Whisper_API36` AVD with an **8 GiB data partition** installed successfully and had about 6.65 GiB free before first-use model preparation. This is a tested configuration, not a measured minimum. Preserve existing AVD data when preparing a separate test device.

The installed app verifies and prepares its bundled model before opening the microphone, with a 30-second preparation limit. After Stop, it converts the recorded microphone WAV to 16 kHz mono for Whisper and limits transcription to 60 seconds. Processing happens in the app; no API key, Apple Speech availability, Android speech provider, or runtime model download is required. A missing model, invalid hash, empty transcript, timeout or cancellation produces a failed run without a native/cloud fallback.

The immutable result includes `transcription` metadata: `provider:"whisper.net"`, `model:"base.en"`, `modelSha256`, `sourceAudioSha256`, `transcriptionAudioSha256`, `sampleRate`, `channels`, and `processingMilliseconds`. The original microphone WAV remains unchanged and available through `microphone-wav`. Its hash must equal `sourceAudioSha256`; the normalized transcription input hash is retained as metadata. The [Whisper task](../../ansight/README.md#run-deterministic-verification) checks this provenance, the whole recording and a different-quote control, and the final transcript.

## Permissions

The app requests microphone access on both platforms. Capture-only and offline Whisper modes use native AVAudioEngine on iOS or AudioRecord on Android and need only that app permission. Native Apple transcription also requests speech-recognition access. Android runs AudioRecord and SpeechRecognizer in separate modes. Both iOS usage descriptions and Android's `RECORD_AUDIO` permission are declared in the platform manifests. A denied permission produces a failed run and cannot pass validation.

If access was previously denied, enable it in the app's system Settings and retry. For a dedicated iOS test simulator, microphone permission can also be restored with `xcrun simctl privacy <SIMULATOR_UDID> grant microphone ai.ansight.audioharness`; relaunch the app afterward. Speech recognition has its own permission prompt. Host audio routing and macOS microphone access for Simulator are separate from these app permissions.

## Make the speech fixture

On macOS, with `say` and `ffmpeg` available:

```sh
./scripts/make-audio-fixture.sh
```

This creates the ignored `fixtures/audio/expected.wav`: mono, 16 kHz PCM16, attenuated speech, and one second of silence at each end. The source phrase in `fixtures/audio/expected.txt` matches the app default: **The quick brown fox jumps over the lazy dog.** Recognition uses English (US). If you change the fixture text, update the app's expected phrase to match.

Eight canonical quote WAVs are included under `fixtures/audio/quotes/`, with exact expectations and source attribution in `manifest.json`. Regenerate them using `./scripts/make-quote-fixtures.py`. Use the same WAV bytes when comparing platforms.

Prepare the host runners once:

```sh
python3 -m venv .venv-audio
.venv-audio/bin/python -m pip install -r scripts/requirements-audio.txt
```

## Route audio from the host

**iOS Simulator:** install BlackHole with `brew install --cask blackhole-2ch`. Installation requires administrator authentication. If the device does not appear, restart the Mac or follow BlackHole's documented CoreAudio restart (`sudo killall -9 coreaudiod`), which briefly interrupts audio. On the tested Xcode 26.4 Simulator, select **I/O → Audio Input → BlackHole 2ch**. The Mac's default microphone and speakers can stay unchanged.

The bundled player selects BlackHole explicitly for its own output and verifies that selection during playback:

```sh
./scripts/play-to-audio-device.sh --list
./scripts/play-to-audio-device.sh --device BlackHole2ch_UID fixtures/audio/expected.wav
```

Start the harness and wait for **Listening** before playback. Enable **Record audio without transcription** to verify the microphone independently of Apple Speech. Play the complete fixture, then tap **Stop**. The app saves actual microphone buffers as PCM16 WAV and reports **Captured** with `captureFilePath` in `audio-results/latest.json`. Copy that file from the simulator's app data container, then verify it:

```sh
xcrun simctl get_app_container <SIMULATOR_UDID> ai.ansight.audioharness data
.venv-audio/bin/python scripts/verify-microphone-capture.py fixtures/audio/expected.wav <CAPTURED_WAV> --output <VERIFICATION_JSON>
```

The verifier resamples both files to 16 kHz mono and requires correlation of at least 0.90 across the entire spoken fixture. Only zero padding is excluded; capture-start delay and gain differences are allowed. An iOS **Captured** result has `captureOnly: true`, `isFinal: false`, and `passed: false`, because no transcript assertion was attempted. The separate waveform report establishes whether the injected audio was received. Apple Speech availability is not required for this mode.

The iOS corpus runner is intended for a connected Ansight session with working Simulator input delivery:

```sh
.venv-audio/bin/python scripts/run-ios-audio-corpus.py --simulator <SIMULATOR_UDID> --audio-device BlackHole2ch_UID
```

It resolves the session by the exact Simulator UDID, selects capture-only mode, records each quote, copies each fresh microphone WAV from the app container, and applies the same waveform assertion. It stops after the first infrastructure failure and retains evidence. The local Ansight attempt encountered a cached Simulator HID connection error (`Mach port invalid, device disconnected`) after a simulator reboot, before playback. Its end-to-end UI path therefore remains unverified locally.

The successful local corpus used `scripts/ios-audio-corpus-computer-use.mjs` through the Computer Use skill's `node_repl` and official `@oai/sky` client. It observes and clicks the native Simulator controls; audio playback and recording verification use the same scripts above. To repeat that fallback, foreground the intended Simulator window, enable capture-only mode, complete one initial capture, and return to Ready. In `node_repl`, use a new output directory and the exact observed window title:

```js
var sky = (await import('@oai/sky')).sky;
var createCorpus = (await import('/Users/matthewrobbins/Development/git/ansight-test-apps/audio-harness/scripts/ios-audio-corpus-computer-use.mjs')).createCorpus;
var corpus = await createCorpus({
  sky,
  simulator: '<SIMULATOR_UDID>',
  windowTitle: 'Ansight Audio Harness',
  output: '/Users/matthewrobbins/Development/git/ansight-test-apps/audio-harness/artifacts/audio-harness/ios-corpus-' + Date.now()
});
```

Call `nodeRepl.write(await corpus.runNext())` once per fixture, inspecting each result before continuing; after all eight, call `nodeRepl.write(await corpus.finish())`. The helper requires visible controls and a matching window title and leaves the app Ready with capture-only enabled. It is a Computer Use helper, not a standalone Node command.

**Android Emulator:** the verified route uses the emulator's `injectAudio` gRPC API with host microphone access disabled. No virtual audio driver is needed for this route. The legacy runner uses the sibling checkout's `../../ansight/scripts/audio-input/inject_audio.py` and the host Python environment prepared above. Before using that native-transcription runner, disable **Use Whisper** and **Record audio without transcription**. The harness must already be open, have microphone permission, and have a working Android speech provider. Use the TypeScript task's explicit `whisper` mode for offline verification.

Run from the dedicated `audio-harness/` folder, replacing the emulator serial:

```sh
.venv-audio/bin/python scripts/run-android-audio-test.py fixtures/audio/expected.wav --serial <EMULATOR_SERIAL>
```

The runner observes the Start button through Android UI automation, starts recording, and polls AudioFlinger for a non-standby microphone thread with active tracks and recent captured samples. It immediately injects the short fixture in the same process, then retrieves the harness's final JSON through **Copy result** and asserts the final transcript. Each run retains the fixture, AudioFlinger evidence, UI XML, a screenshot, the app's JSON, and a test report under `artifacts/audio-harness/`. `--injector <path>` overrides the sibling helper location; fixtures are limited to fifteen seconds, within the app's thirty-second capture limit.

For a negative assertion, inject the same speech with a deliberately different expectation:

```sh
.venv-audio/bin/python scripts/run-android-audio-test.py fixtures/audio/expected.wav --serial <EMULATOR_SERIAL> --expected 'The purple elephant sleeps beside the river.' --outcome mismatch
```

A successful mismatch test requires the app to return a final nonempty transcript with `passed: false`. The runner's own `passed: true` then means that rejection was correct. Restore the default expectation afterward using the app editor, or `--expected 'The quick brown fox jumps over the lazy dog.'` on the next positive run.

After generating the eight quote WAVs, run the whole manifest sequentially:

```sh
.venv-audio/bin/python scripts/run-android-audio-corpus.py fixtures/audio/quotes/manifest.json --serial <EMULATOR_SERIAL>
```

The corpus runner uses each manifest quote as the unchanged expectation. It retains each case and an aggregate `result.json`, reports mismatches without changing the expected text, and restores the default phrase and Ready state afterward. If the selected emulator disconnects or a preflight fails, remaining cases are marked skipped and no further injection is attempted. An optional `--output <new-directory>` makes the evidence location explicit. After repairing an infrastructure failure, `--ids <fixture-id> ...` resumes selected cases into a new evidence directory; preserve the original results too.

**Emulator 37.1.11 caveat:** its audio forwarder dereferences a null native microphone stream when `injectAudio` begins without an open guest recording. This was confirmed against the crash report, installed binary, and [upstream audio forwarder](https://android.googlesource.com/platform/external/qemu/+/refs/heads/emu-master-dev/audio/audio_forwarder.c). The guarded runner refuses to start injection unless fresh recording evidence exists; it does not enable the host microphone. Avoid a separate manual injection command after a screenshot or model round-trip, because Android may already have stopped on silence. A guest recording can still stop between observation and the RPC, so this is a tested mitigation rather than an emulator-level fix. Use one active capture/injection per emulator. RPC completion alone never establishes transcript success.

Repeated runs also exposed a broken emulator input state despite active guest recording: pre-injection power rose from the normal local noise floor near −78 dB to roughly −3 dB with host microphone access disabled. The runner now refuses injection above −40 dB when AudioFlinger reports that signal history. This avoided a subsequent crash, but required a cold boot to continue; unattended reliability of this emulator version is not established. For a dedicated stopped test AVD, an authenticated cold-boot launch is:

```sh
emulator -avd <AVD_NAME> -no-snapshot -port <EVEN_CONSOLE_PORT> -grpc <GRPC_PORT> -grpc-use-token
```

This preserves user data and disables snapshot loading/saving. The gRPC flag and token option are needed if the chosen launch method does not expose the discovery endpoint automatically. Verify that host microphone access remains disabled before running the harness.

## Run and assert

1. Open the app, select **Whisper (offline)** or **Native speech**, disable capture-only, check the expected phrase, and tap **Start listening**. Accept requested permissions. Whisper may first prepare its bundled model.
2. Wait until `capture-phase` is **Listening** before starting external fixture playback or injection.
3. Tap **Stop** after the entire padded clip. Whisper then transcribes the saved recording locally; native providers may finish after silence. The app also limits listening to approximately 30 seconds and waits for finalization.
4. Require `transcript-kind` to be **FINAL** and `validation-result` to be **PASS — phrase matched**. A partial transcript is never a pass.
5. Use **Copy result** or inspect the saved JSON. Require `isFinal: true` and `passed: true`, and retain the transcript and run ID with the fixture used.

Validation compares the whole normalized phrase in order. Ordinary punctuation, case, whitespace, and canonical Unicode differences are ignored. Negations, words, numeric signs, and decimal separators remain significant. Numbers written as words are not converted to digits. Empty transcripts, recognition failures, and cancellation cannot pass.

The UI exposes these stable automation IDs:

| Purpose | Automation IDs |
| --- | --- |
| Run controls | `start-listening`, `stop-listening`, `reset-test` |
| Recording mode | `capture-only`, `capture-only-state` |
| Transcription provider | `use-whisper`, `use-whisper-label`, `transcription-provider-state` |
| Expected input | `expected-phrase` |
| Capture state | `capture-phase`, `capture-status`, `elapsed`, `input-level` |
| Recognized output | `transcript`, `transcript-kind` |
| Assertion | `validation-result`, `validation-detail` |
| Result export | `copy-result`, `run-id`, `result-saved`, `artifact-status`, `capture-file`, `capture-frame-count` |

Controls, containers and labels in `MainPage.xaml` have unique automation IDs, as do the app and window. `capture-only-state` reads exactly `Capture only` or `Transcription`; `transcription-provider-state` reads `Whisper (offline)` or `Native speech`. Ground new selectors in the live tree before relying on them in automation. `run-id` becomes a new GUID when a run starts. Wait for `result-saved` to read `Saved` before requesting the terminal artifacts. `artifact-status` then reads `Ready for snapshot`.

Each completed, failed, cancelled, or captured run writes an immutable `audio-results/runs/<runId>/result.json` and updates `audio-results/latest.json`. **Copy result** contains the same JSON. A finalized microphone file is copied into that run's directory as `microphone.wav`. The JSON keeps schema `ansight.audio-harness-result/v1` and adds `capture` with actual WAV SHA-256, file bytes, sample rate, channels, bit depth, frame count, duration, peak/RMS amplitude, and frames exceeding −60 dBFS. `capture.available` is false when no valid recording is available; recording alone never sets the transcript `passed` flag. Android native speech may supply a final transcript without an exportable WAV; capture-only and Whisper modes supply the WAV on both platforms. iOS also retains microphone WAVs for native transcription runs that reached capture. Cancelled incomplete recordings are discarded.

Debug builds register SDK artifact provider `audio-harness.runs`. Discover it through `artifacts.query`; request `run-result` (`application/json`) or `microphone-wav` (`audio/wav`) with `arguments: { "runId": "<exact-run-id>" }`. Requests validate the run ID and read that immutable run, so a subsequent capture cannot substitute a newer result. The SDK's real `artifacts.request` transport stores requested payloads in the host session timeline.

After saving each terminal run, the app emits `audio-harness.run.finished` with JSON event details containing schema `ansight.audio-harness-terminal/v1`, `runId`, `providerId`, `resultArtifactId`, optional `captureArtifactId`, `phase`, `captureOnly`, and `captureAvailable`. Repository tasks/triggers request the artifacts from that event or the observed run ID. Provider registration itself does not upload files: SDK 1.4.0-preview.5 requires a live host artifact request. A save failure is visible and does not emit a ready event. WAV integrity and signal statistics establish what the app recorded; whole-waveform comparison with the fixture remains a separate host assertion.

Native Apple Speech and the Android provider must be available for English (US); those modes may require network access or downloaded language models. Android emulator images without a speech provider show an error in native mode. Offline Whisper avoids that dependency while keeping the same microphone input route. Level meters are diagnostics; neither a meter nor a successful build proves end-to-end injected-audio transcription. Validate it using the final assertions above.

## Offline Whisper verification — 9 September 2026

The Hamlet deterministic task passed **30/30 assertions on both iOS 26.4 Simulator and Android 16 Emulator**. Both apps produced the expected final transcript from their own recorded microphone WAV using the same pinned `base.en` model. Whole-speech waveform correlation was **0.997694 on iOS** and **1.000000 on Android**; a different spoken quote was rejected on each recording. In-app Whisper processing took **1.311 seconds** and **1.194 seconds**, respectively; full automation also includes UI, capture and evidence-transfer time.

The final iOS Whisper corpus passed **8/8 quotes**, with **31 assertions per child**, whole-speech correlations **0.990140–0.999533**, all eight wrong-quote controls rejected, and **1.073–1.259 seconds** of inference per recording. Android also passed Macbeth after reopening the recorder, followed by Descartes with the final task's **30/30 assertions**, correlation **1.0**, and **1.050 seconds** of inference. All three Android quotes used the same emulator session without a restart. The Android task skips a redundant status-label lookup so its provider checks microphone readiness immediately after Start; both platforms verify the entered expectation before recording.

Both automatic terminal triggers succeeded for each earlier single. The retained timeline result JSON and WAV were exported and matched the task copies byte for byte; their capture hash matched the recorded transcription source hash. See the [validation status](../../TESTING.md#validation-status) for exact task/build IDs, receipts and preserved failures. Three Android quotes do not establish a complete Android Whisper corpus pass.

## Earlier local verification — 8 September 2026

Both platform builds succeed and both apps connect to Ansight. The latest iOS build has no warnings; Android reports ten native dependency binding warnings and no errors. No unit tests were added.

iOS 26.4 received the default synthetic speech through BlackHole and its actual microphone input. The saved 48 kHz stereo WAV matched the entire spoken fixture with correlation **0.99547**. Comparing that recording with a different quote correctly failed at **0.14860**. Evidence is under `artifacts/audio-harness/ios-microphone-proof/`. Native Apple transcription remained unavailable after English (US) language setup, so this is a proven microphone reception result, not an iOS transcript pass.

All **eight iOS quote captures passed**, with whole-speech waveform correlations from **0.99413 to 0.99966** against the fixed 0.90 threshold. Each case retains a distinct app run ID, the fixture, separately captured microphone WAV, playback destination, verification JSON, and UI evidence. The aggregate is `artifacts/audio-harness/ios-corpus-computer-use-20260908T0701/summary.json`. The successful UI backend was Computer Use; the Ansight SDK remained connected. The app finished Ready with capture-only enabled, and the Mac's default microphone and speakers were unchanged.

Android returned a correct final transcript for the default fixture and correctly rejected a deliberately wrong expectation. All eight quote tracks then produced final transcripts: **seven matches and one real wording mismatch** (`world’s a stage` was recognized as `worlds of stage`). The corpus needed two emulator recovery episodes; the native crash and later preflight refusal are retained in `artifacts/audio-harness/android-quotes-summary-20260908.json`. The microphone route works, while unattended reliability on Emulator 37.1.11 remains limited as described above.
