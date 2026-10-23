# Pencil framework verification harness

This is a dedicated iOS Simulator app with the Ansight SDK, touch capture, JPEG capture and the optional Pencil package enabled. Its local discovery port is **49432**. Use a matching host:

```sh
ansight host run --data-dir <framework-host-data> --serve-port 49431 --discovery-port 49432 --websocket-port 49433
```

Use an absolute data-directory path in every command. The default host on other ports can remain running.

## Build

Requires Node 22+, Xcode and the local SDK package builds. From this app directory, first build the sibling SDK packages:

```sh
npm --prefix ../../../ansight/ansight-sdk/src/pencil-runtime run build
npm --prefix ../../../ansight/ansight-sdk/src/capacitor ci
npm --prefix ../../../ansight/ansight-sdk/src/capacitor run build
npm --prefix ../../../ansight/ansight-sdk/src/capacitor-pencil ci --legacy-peer-deps
npm --prefix ../../../ansight/ansight-sdk/src/capacitor-pencil run build
npm install
npm run build
ANSIGHT_USE_LOCAL_SDK=1 npx cap sync ios
ANSIGHT_USE_LOCAL_SDK=1 xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Install `ios/App/Build/Products/Debug-iphonesimulator/App.app` on the chosen Simulator and launch `ai.ansight.pencil.capacitor`. The canvas uses ordinary DOM pointer handlers and calls `setPointerCapture` on down. `AnsightPencil.bindSurface` scopes playback to that element. `pencil.observations` independently exposes the DOM callback values.

## Run and retain evidence

```sh
ansight app register ai.ansight.pencil.capacitor --codebase "$PWD" --data-dir <framework-host-data>
ansight session list --data-dir <framework-host-data> --json
ansight task run pencil.sdk-demo --app-id ai.ansight.pencil.capacitor --repository "$PWD" --session-id <exact-connected-session> --data-dir <framework-host-data> --json
ansight app call <exact-connected-session> pencil.observations --arguments '{}' --data-dir <framework-host-data> --json
ansight session touches <exact-connected-session> --limit 300 --data-dir <framework-host-data> --json
```

The task plays 92 samples and asserts contact, pressure, altitude, azimuth, roll, taps and hover distance in the SDK recording. Normal finish also records a final hover exit, yielding 93 framework samples. Check the app observations and retained screenshot separately; a transport success is not an app assertion.

Follow with a short HID-only down/up file (`--mode hid`) and verify ordinary callbacks arrive without `ansightPencil` metadata. Open the session at `http://127.0.0.1:49431/ansight/?sessionId=<exact-connected-session>`.

Finally terminate only this dedicated app with `ansight device terminate ios <udid> ai.ansight.pencil.capacitor --data-dir <framework-host-data> --json`, and use `ansight session show` to confirm it is disconnected. Keep the host running for replay.

See the [consumer guide](https://www.ansight.ai/docs/sdk/cordova/pencil) for integration details and compatibility limits.
