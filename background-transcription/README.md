# Background Transcription Spike

Two small, native test apps answer one question: can an Ansight-instrumented app continue a user-initiated audio transcription after it enters the background?

Both apps provide two modes: injected archival speech and the physical device microphone. The injected mode offers bundled 20-, 30-, and 60-second 16 kHz mono WAV fixtures. Device-microphone mode additionally supports 2-, 5-, 10-, and 20-minute recordings. Long microphone runs roll into a fresh recognition request whenever the platform finalizes a short utterance, accumulating each segment until the selected recording duration ends. Both modes persist every phase to app storage and emit matching Ansight events, so the result can be checked after foregrounding even if the UI was not capturable while backgrounded. On every terminal result, an Ansight repository trigger requests the native app's immutable JSON result and attaches it to the session timeline as an artifact.

Debug builds use Ansight's full native developer capture profile: one-second JPEG frames, touch-triggered before/after visual trees, touch input, lifecycle and screen-view events, memory/FPS/battery/open-file telemetry, native crash capture, app-provided session logs, full standard-tool discovery, and the transcript artifact provider. Starting a run also performs an instrumented `HEAD https://www.ansight.ai/` request so the network lane is populated with a real sanitized request record. iOS uses the SDK's automatic `URLSession` capture and Android submits the typed `HttpURLConnection` record explicitly. Release builds disable periodic screenshots and remote-tool discovery.

The shared launcher icon uses the official Ansight mark with a waveform and transcript-line cue. Its project master is `assets/app-icon-master.png`; platform-sized copies live in the iOS asset catalog and Android density-specific mipmap folders.

The fixtures are excerpts from Franklin D. Roosevelt's authentic December 8, 1941 “Day of Infamy” address. They retain the archival voice, room acoustics, broadcast noise, cadence, and applause; they are not synthesized or re-enacted. See [fixture provenance and transcripts](fixtures/README.md).

| Platform | Background primitive | Speech primitive | Minimum OS |
| --- | --- | --- | --- |
| iOS | `BGContinuedProcessingTask` plus `audio` background mode | `SFSpeechURLRecognitionRequest` or `SFSpeechAudioBufferRecognitionRequest` | iOS 26 |
| Android | `mediaProcessing` or `microphone` foreground service | `SpeechRecognizer`, optionally with `EXTRA_AUDIO_SOURCE` | Android 15 / API 35 |

Microphone capture starts immediately from the visible app before it is backgrounded. This is intentional: both platforms permit a correctly declared, user-initiated microphone session to continue in the background, but restrict starting microphone access from an already-backgrounded app.

## Expected evidence

Each run writes the following phases and matching `background_transcription.*` Ansight events:

1. `scheduled`
2. `preparing` (a 10-second validation window for injected audio; momentary for microphone mode)
3. `transcribing`
4. `completed`, `cancelled`, `interrupted`, `failed`, or `expired`

The durable result records timestamps, the selected fixture or microphone input and duration, recognized text, whether the app was backgrounded during the run, and any platform error. Expected transcripts for all three excerpts are checked in with the fixtures.

Speech recognition availability and exact punctuation depend on the recognizer installed on the device. Test on physical devices; simulators/emulators are useful for build and lifecycle checks but do not guarantee an available speech service.

## Physical-device enrollment

Start the resident host and issue a generic enrollment invite:

```sh
ansight host status --json
ansight pairing issue --qr
```

On either native app, open **Ansight enrollment** and tap **Scan enrollment QR**. Scan the terminal QR code. The SDK securely stores the installation registration in app-private storage and reconnects on later launches. Use **Clear enrollment** when the device must be registered again against a different or replaced host.

## iOS

Requirements: Xcode 26+, an iOS 26+ physical device, and speech-recognition permission.

```sh
cd ios
xcodegen generate
open BackgroundTranscriptionSpike.xcodeproj
```

The shared scheme first builds the Ansight package's macOS policy tool into the location expected by Xcode 26.4. This works around an Xcode package-plugin host-tool path issue and is also used by command-line builds.

Select a development team if needed, run the app, connect Ansight, and choose a mode and duration. For **Injected speech**, tap **Start background transcription** and background the app during the countdown. For **Device mic**, tap Start, begin speaking, and then background the app; recording begins immediately while the app is still eligible to activate its audio session. The 2-, 5-, 10-, and 20-minute options appear only in Device mic mode. Tap the red **Stop background transcription** control after foregrounding to cancel an active run.

The app consumes the local `ansight-sdk/src/ios` Swift package from the sibling Ansight SDK checkout, matching the SDK's own native harness setup. The continued-processing identifier is permitted as a wildcard in `Info.plist`; each user-initiated run registers and submits its own concrete identifier.

## Android

Requirements: Android Studio or JDK 17 plus an Android SDK with API 35.

```sh
cd android
./gradlew :app:assembleDebug
```

Install on an Android 15+ device, run the app, connect Ansight, and choose a mode and duration. Injected speech retains the 10-second countdown. Device-microphone recognition starts immediately and is promoted to a visible microphone foreground service before the app is backgrounded; its duration picker additionally exposes 2, 5, 10, and 20 minutes.

The app uses `ai.ansight:ansight-android:1.4.0`. The selected speech recognition service must support injected audio through `RecognizerIntent.EXTRA_AUDIO_SOURCE`; unsupported providers produce an explicit failed result rather than silently switching to the microphone.

The app requests microphone permission only for **Device mic**. In injected mode, a recognizer that ignores `EXTRA_AUDIO_SOURCE` may fail; that provider limitation is surfaced explicitly rather than silently switching the test to microphone input.

## Pass criteria

- The app enters the background during `preparing` or `transcribing`.
- The OS-visible background task/service remains active.
- The durable run reaches `completed` without returning to the foreground.
- `backgroundedDuringRun` is `true`.
- The transcript materially matches the expected fixture text.
- Ansight contains start, phase, lifecycle, and terminal events for the same run ID.
- The `background-transcription.capture-terminal` trigger succeeds and the terminal timeline event has a `transcription-<duration>s-<run-id>.json` artifact containing the durable result.

## Ansight trigger

The workspace in `ansight/` is registered to App ID `ai.ansight.testapps.backgroundtranscription`, which is shared by the iOS and Android builds. The trigger matches the canonical `background_transcription.terminal` event, validates its contract, and requests `background-transcription.runs/transcript-result` for the exact run ID. Completed, cancelled, interrupted, failed, and expired runs all produce artifacts, preserving partial transcripts and the terminal reason.

Validate the source-controlled trigger without executing it:

```sh
npm --prefix ansight install
npm exec --prefix ansight -- tsc -p ansight/triggers/tsconfig.json
ansight repo automation inspect ai.ansight.testapps.backgroundtranscription . --json
```

## Automated background-audio test

The workspace includes an agentic test and the deterministic task it invokes:

- `background-transcription.microphone-background-audio` selects **Device mic**
  with a 20-second run, backgrounds the app, injects the authentic 10-second FDR
  fixture through the virtual microphone, and always foregrounds the app again.
- The task waits for the terminal app state, requests the exact transcript artifact,
  reads its JSON back from retained session evidence, and verifies completion,
  microphone input, background execution, and a non-empty transcript.
- The task declares `platforms: ["ios", "android"]`,
  `deviceKinds: ["virtual"]`, and the native `frameworks` it supports. The test
  references that task with `taskId`; physical devices are excluded because
  Ansight audio injection is virtual-device-only.

Grant speech-recognition and microphone permission once before the automated run,
then run one simulator or emulator serially. Do not use `--parallel` for audio:

```sh
ansight test validate .
ansight test run . background-transcription.microphone-background-audio \
  --platform ios --device-kind virtual
```

Use `--platform android` for the Android emulator. The selected host build must
include `ansight.lifecycle.background()` and `ansight.lifecycle.foreground()`.

## Important limits

- Ansight observes the lifecycle and app-emitted telemetry; it does not keep an app alive or bypass platform scheduling.
- iOS deliberately pauses screenshot, visual-tree, and touch streaming once the app is backgrounded. Logs, app events, metrics, network records, and artifacts continue only while the OS grants execution time.
- When iOS suspends the process after its background work ends, the live WebSocket disconnects by design. The SDK reconnects on foreground; the app reconciles a nonterminal persisted run as `interrupted` when it can no longer be restored.
- Force-quitting the iOS app cancels the continued-processing task. Android users can also stop the foreground service.
- iOS speech recognition can require network access depending on locale/device support.
- Android injected-file recognition is recognizer-provider dependent. This is deliberately surfaced as part of the feasibility result.
