# Quote audio fixtures

Eight short synthetic tracks: four Shakespeare excerpts and four other famous quotations. `manifest.json` contains the expected spoken text, attribution, original source, and generation settings. Filenames are relative to this directory. Source line breaks, initial capitals, and excerpt-ending punctuation are normalized for speech; the words are preserved.

Generate all eight directly into this directory from the dedicated `audio-harness/` folder:

```sh
./scripts/make-quote-fixtures.py
```

This requires macOS `say` with Samantha and `ffmpeg`. It writes files without playing audio. Each WAV is mono 16 kHz PCM16, attenuated to 25%, with one second of silence at each end. Every track must remain shorter than 15 seconds. `generated-manifest.json` records measured duration, sample format, peak level, byte count, and SHA-256 for the actual local files; it is ignored because generation metadata can vary by macOS voice version.

The quotes use public-domain source text and the Samantha synthetic voice. The eight canonical WAVs are included as repository fixtures. Regenerating on another macOS release can change timing and bytes. Use the same WAV on both platforms when comparing results.

For iOS microphone injection after selecting BlackHole as Simulator's audio input:

```sh
./scripts/play-to-audio-device.sh --device BlackHole2ch_UID fixtures/audio/quotes/shakespeare-hamlet.wav
```

Wait for the harness to report `Listening` before playback, and compare the final transcript with that fixture's `text` from the manifest. A successful synthesis or playback command alone is not a transcription test pass.
