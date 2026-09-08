# Audio harness

This dedicated app folder contains the MAUI app, shared code, speech fixtures, scripts, build configuration, and Ansight workspace for synthetic microphone testing on iOS and Android. Run its build and automation commands from this folder:

```sh
cd /Users/matthewrobbins/Development/git/ansight-test-apps/audio-harness
```

| App | Platforms | Purpose |
| --- | --- | --- |
| [Audio Harness](apps/Ansight.AudioHarness/README.md) | iOS Simulator and Android Emulator | Receive synthetic microphone audio, validate native transcripts, or save microphone WAVs for waveform verification. |

The audio harness exercises speech injected by the host into the device's microphone path. Its documentation covers building, fixture generation, audio routing, and observable assertions. Eight synthesized Shakespeare and famous-quote WAVs are included in [fixtures/audio/quotes](fixtures/audio/quotes/README.md).

The [Ansight workspace](ansight/README.md) contains the `audio.synthetic-microphone` agentic test, `audio.inject-and-verify` and `audio.quote-corpus` deterministic TypeScript tasks, and terminal-event artifact triggers. The tasks use `ansight.device.injectAudio()` on the selected running session and verify the app's actual microphone recording or final transcript.
