# Pencil framework verification harness

This is a dedicated iOS Simulator app with the Ansight SDK, touch capture, JPEG capture and the optional Pencil package enabled. Its local discovery port is **49432**. Use a matching host:

```sh
ansight host run --data-dir <framework-host-data> --serve-port 49431 --discovery-port 49432 --websocket-port 49433
```

Use an absolute data-directory path in every command. The default host on other ports can remain running.

## Build

Requires Node, Xcode, CocoaPods and XcodeGen. From this directory:

```sh
npm install
npm run bundle
cd ios
xcodegen generate
pod install
cd ..
xcodebuild -workspace ios/PencilReactNative.xcworkspace -scheme PencilReactNative -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The bundle is embedded; Metro does not need to run during verification. The project uses React Native 0.86 and React 19.2.7, including the new architecture. Native dependencies installed by CocoaPods belong to React Native/the core SDK as well as the optional Pencil pods; they are not all new Pencil dependencies.

Install `ios/Build/Products/Debug-iphonesimulator/PencilReactNative.app` on the chosen Simulator and launch `ai.ansight.pencil.reactnative`. The drawing View uses `usePencilSurface` with its ordinary pointer callbacks. Its AppDelegate enables RN's `RCTSetDispatchW3CPointerEvents(true)` before creating the factory; this is the app's ordinary pointer setup, not an SDK global change. `pencil.observations` independently exposes what those callbacks received.

## Run and retain evidence

```sh
ansight app register ai.ansight.pencil.reactnative --codebase "$PWD" --data-dir <framework-host-data>
ansight session list --data-dir <framework-host-data> --json
ansight task run pencil.sdk-demo --app-id ai.ansight.pencil.reactnative --repository "$PWD" --session-id <exact-connected-session> --data-dir <framework-host-data> --json
ansight app call <exact-connected-session> pencil.observations --arguments '{}' --data-dir <framework-host-data> --json
ansight session touches <exact-connected-session> --limit 300 --data-dir <framework-host-data> --json
```

The task plays 92 samples and asserts contact, pressure, altitude, azimuth, roll, taps and hover distance in the SDK recording. Normal finish also records a final hover exit, yielding 93 framework samples. Check the app observations and retained screenshot separately; a transport success is not an app assertion.

Follow with a short HID-only down/up file (`--mode hid`) and verify ordinary callbacks arrive without `ansightPencil` metadata. Open the session at `http://127.0.0.1:49431/ansight/?sessionId=<exact-connected-session>`.

Finally terminate only this dedicated app with `ansight device terminate ios <udid> ai.ansight.pencil.reactnative --data-dir <framework-host-data> --json`, and use `ansight session show` to confirm it is disconnected. Keep the host running for replay.

See the [consumer guide](https://www.ansight.ai/docs/sdk/react-native/pencil) for integration details and compatibility limits.
