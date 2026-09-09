# Audio harness

This dedicated app folder contains the MAUI app, shared code, speech fixtures, scripts, build configuration, and Ansight workspace for synthetic microphone testing on iOS and Android. Run its build and automation commands from this folder:

```sh
cd /Users/matthewrobbins/Development/git/ansight-test-apps/audio-harness
```

| App | Platforms | Purpose |
| --- | --- | --- |
| [Audio Harness](apps/Ansight.AudioHarness/README.md) | iOS Simulator and Android Emulator | Receive synthetic microphone audio, transcribe it offline with Whisper or native speech, and save microphone WAVs for waveform verification. |

The audio harness exercises speech injected by the host into the device's microphone path. Its documentation covers building, fixture generation, audio routing, and observable assertions. The demo uses one checked-in speech WAV: [fixtures/speech.wav](fixtures/README.md).

For a customer demo, run **[`audio.demo`](ansight/README.md)**. It injects one speech fixture and verifies that the app transcribed it, leaving the transcript visible.

Prepare the pinned offline model before building with `python3 scripts/prepare-whisper-model.py`. The app bundles the verified `base.en` model and transcribes its recorded microphone audio without downloading a model or calling a speech service at runtime. The fixture text is only the final assertion expectation. See [offline transcription setup](apps/Ansight.AudioHarness/README.md#offline-whisper-model).

Offline Whisper verification passed **all eight quotes on iOS** and **three distinct quotes on Android**, including recorder reopening in the same emulator session. The earlier verification suite checked the final transcript, microphone waveform, recording/model hashes and wrong-quote control; both platforms' initial single-run automatic timeline artifacts were independently exported and checked. The complete Android eight-quote corpus remains unverified. See the [testing guide](TESTING.md#validation-status) for exact builds, retained evidence and platform limitations.
