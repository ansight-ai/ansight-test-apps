# Demo speech

`speech.wav` is the audio used by `audio.demo` on iOS and Android.

Expected transcript: **To be or not to be that is the question.**

The text is from William Shakespeare’s *Hamlet*, Act 3, scene 1. The checked-in
recording uses the macOS Samantha voice: mono 16 kHz PCM16, with one second of
silence at each end. Keep the same WAV on both platforms.

To regenerate it on macOS with `say` and `ffmpeg`, run from `audio-harness/`:

```sh
./scripts/make-audio-fixture.sh
```
