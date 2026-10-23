# Pencil HID + SDK verification harness

This iPad Simulator app includes the local **Ansight aggregate SDK**, enables screenshot and touch recording, and reads Pencil properties directly from UIKit in its canvas. It writes those raw observations to `Documents/pencil-observations.json`. The saved session separately contains the SDK's captured touch stream.

Build `PencilHarness.xcodeproj` in Debug or Release for Simulator. `project.yml` is the XcodeGen source. This development harness explicitly opts into experimental pen input and discovers a host on port **49332**; the regular installed host uses its own ports.

```sh
ansight host run --data-dir /absolute/path/to/pencil-host --discovery-port 49332 --websocket-port 49333 --serve-port 49331 --serve-path /ansight
```

Use a CLI built from the matching `ansight-cli` checkout, install and launch the app on an iPad Simulator, and confirm the live SDK session with `ansight session list --data-dir ... --json`.

Register the workspace, then discover and run the task:

```sh
ansight workspace init /absolute/path/to/this/ios --app-id ai.ansight.testapps.pencil --data-dir /absolute/path/to/pencil-host
ansight task list --app-id ai.ansight.testapps.pencil --data-dir /absolute/path/to/pencil-host
ansight task run pencil.hid-demo --app-id ai.ansight.testapps.pencil --session-id <session> --data-dir /absolute/path/to/pencil-host --json
```

The task plays `ansight/fixtures/pencil-demo.pen.json` through `ansight.ui.playPen({ file, mode: "hid+sdk", target: "pencil-canvas", hoverRecognizer: "pencil-hover" })`, then makes ten assertions on captured Pencil contact, pressure, tilt, azimuth, roll, hover distance and taps. It retains a final screenshot. The same file works with `ansight ui play-pen --file ... --mode hid+sdk --session ...`.

Hybrid mode uses native HID for Pencil contact and position. The optional `AnsightPencil` package's write-policy `ui.simulate_pen` tool temporarily supplies app-visible pressure and angles and dispatches hover to existing Pencil hover recognizers. The implementation compiles in **Simulator** builds, including Release, and is inactive unless `.withSimulatorPenInput()` is included in the SDK options builder. The harness uses `readWrite` access and makes no separate registration call. Recorded samples label their simulation source. This is app behavior verification, not hardware fidelity testing. Hooks remain installed but pass through after playback; existing swizzlers, recognizers and PencilKit require compatibility testing.

Terminate the app when verification completes so the recording ends. Leave the host running for replay. The development run from 2026-10-21 passed all ten assertions with 68 captured contact samples and 24 hover samples on iOS 26.4. A following HID-only tap verified normal getters were restored.

Hybrid playback now requires a unique native target accessibility identifier. Hover additionally requires one named, idle Pencil recognizer attached directly to that view. Contact properties require matching transport timestamps and touch/view/window identity; there is no position-only fallback. See [the isolation and compatibility contract](https://www.ansight.ai/docs/sdk/pencil) for scope, hook-conflict checks and framework limitations.

## Isolation verification

`PencilIsolationTests` runs inside this SDK-equipped app and requires a connected host with touch capture active. Ten tests cover target ambiguity/bounds, touch and timestamp isolation, wrong/stale runs, moved/detached targets, busy/ambiguous/removed hover recognizers, unrelated ancestor/sibling recognizers, competing hooks before/during playback, and terminal hover callback values. Run with `xcodebuild test -project PencilHarness.xcodeproj -scheme PencilHarness -destination 'platform=iOS Simulator,id=<device-id>'`.

The strengthened implementation was verified in captured session `ai-ansight-testapps-pencil-021`: all ten `pencil.hid-demo` assertions passed (68 contact samples and 24 hover samples). CLI contact-only hybrid playback received pressure 0.8; subsequent HID-only input received UIKit pressure 0 with no SDK override label. The app's own hover-ended callbacks retained the expected positions. The app was stopped and the recording finalized. Detailed evidence is retained in the sibling CLI checkout at `artifacts/pencil-isolation-result/verification.json`.
