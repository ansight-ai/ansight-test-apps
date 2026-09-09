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

The immutable result includes `transcription` metadata: `provider:"whisper.net"`, `model:"base.en"`, `modelSha256`, `sourceAudioSha256`, `transcriptionAudioSha256`, `sampleRate`, `channels`, and `processingMilliseconds`. The original microphone WAV remains unchanged and available through `microphone-wav`. Its hash must equal `sourceAudioSha256`; the normalized transcription input hash is retained as metadata. The [demo task](../../ansight/README.md) checks audio injection completion and the final transcript.

## Permissions

The app requests microphone access on both platforms. Capture-only and offline Whisper modes use native AVAudioEngine on iOS or AudioRecord on Android and need only that app permission. Native Apple transcription also requests speech-recognition access. Android runs AudioRecord and SpeechRecognizer in separate modes. Both iOS usage descriptions and Android's `RECORD_AUDIO` permission are declared in the platform manifests. A denied permission produces a failed run and cannot pass validation.

If access was previously denied, enable it in the app's system Settings and retry. For a dedicated iOS test simulator, microphone permission can also be restored with `xcrun simctl privacy <SIMULATOR_UDID> grant microphone ai.ansight.audioharness`; relaunch the app afterward. Speech recognition has its own permission prompt. Host audio routing and macOS microphone access for Simulator are separate from these app permissions.

## Demo speech fixture

The demo uses the checked-in `fixtures/speech.wav`: **To be or not to be that is
the question.** It is mono 16 kHz PCM16 with one second of silence at each end.
The task sets the app’s expected phrase before recording.

Regenerate it on macOS with `say` and `ffmpeg` using
`./scripts/make-audio-fixture.sh`. See [the fixture README](../../fixtures/README.md).

## Run the demo

Run [`audio.demo`](../../ansight/README.md) through Ansight. It selects offline
Whisper, starts recording, injects `fixtures/speech.wav`, and checks the final
transcript. Ansight handles platform audio injection and microphone readiness.

The test app needs no separate audio player, Python audio environment, or host
runner. The scripts folder contains only:

- `prepare-whisper-model.py` — prepares the offline model before building.
- `make-audio-fixture.sh` — optionally regenerates the checked-in speech WAV.

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
