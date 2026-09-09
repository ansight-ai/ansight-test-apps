# Audio customer demo

One task: **`audio.demo`**. It starts the microphone, injects the Hamlet quote,
stops recording, and checks that the app transcribed the quote correctly.
The transcript stays visible at the end.

## Prepare

- Build and install the [Audio Harness](../apps/Ansight.AudioHarness/README.md)
  with its bundled Whisper model. Grant microphone permission when prompted.
- iOS: use one booted simulator, with Simulator Audio Input set to BlackHole.
- Android: enable the emulator's authenticated audio endpoint and disable its
  host microphone input.

The task selects offline Whisper and enters the expected phrase. That phrase
is only used for the app's final comparison; it is not a recognition prompt.

## Run on the iOS Simulator

Copy and run this command for the installed Audio Harness on the demo’s
**iPhone 17e** simulator:

```sh
ansight app execute \
  --device-id 4594102E-88A3-4242-8851-F959C4C9DBBC \
  --app-id ai.ansight.audioharness \
  --prompt "Run the workspace task audio.demo once and report its result. Leave the transcript visible." \
  --trace \
  --json
```

Ansight launches the installed app on that simulator, connects to its new
session, and runs `audio.demo`. `--trace` records the execution trace. The app
and transcript remain visible afterward.

The app is registered to this checkout’s `audio-harness` folder. On another
machine, register the checkout once from that folder and replace the simulator
UDID above with the target device’s ID:

```sh
ansight app register ai.ansight.audioharness --codebase "$PWD"
```

No task inputs, Python environment, or external waveform verifier are needed.
A pass requires completed injection and a matching transcript after the app
saves its result. Ansight retains the normal task trace and UI evidence.

## Validate

From the `audio-harness` folder:

```sh
npm ci --prefix ansight
npm run --prefix ansight check
ansight task list --app-id ai.ansight.audioharness --repository "$PWD" --json
```

The optional terminal-event triggers collect recording artifacts. They are
independent of the demo task.
