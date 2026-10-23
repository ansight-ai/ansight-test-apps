# Flutter Apple Pencil harness

This standalone app has a `lib/main.dart` entry point with Ansight touch/JPEG capture, `ansight_pencil`, discovery port 49432 and an explicitly bound drawing surface. SDK dependencies resolve from the local checkout.

Start the isolated host with `ansight host run --data-dir <absolute-framework-host-data> --serve-port 49431 --discovery-port 49432 --websocket-port 49433`.

From this Flutter app directory:

```sh
flutter pub get
flutter build ios --simulator --debug --no-pub --target lib/main.dart
xcrun simctl install <udid> build/ios/iphonesimulator/Runner.app
xcrun simctl launch <udid> ai.ansight.pencil.flutter
ansight app register ai.ansight.pencil.flutter --codebase "$PWD" --data-dir <framework-host-data>
ansight session list --data-dir <framework-host-data> --json
ansight task run pencil.sdk-demo --app-id ai.ansight.pencil.flutter --repository "$PWD" --session-id <exact-connected-session> --data-dir <framework-host-data> --json
```

The 92-sample fixture verifies ten SDK capture assertions. The existing Listener records independent callback values to the app container's `Documents/pencil-framework-observations.json`. It receives 90 callbacks: 4 down, 60 move, 4 up, 22 hover. Flutter proximity removal is a pointer lifecycle event, not `Listener.onPointerHover`; the separate widget test verifies MouseRegion enter/exit. The SDK retains 93 samples including the cleanup hover exit.

Follow with a short HID-only contact and confirm the Listener receives it with `pencil: null`. Read the app container path with `xcrun simctl get_app_container <udid> ai.ansight.pencil.flutter data`. Retain both callback observations and SDK evidence.

Terminate this dedicated instance with `ansight device terminate ios <udid> ai.ansight.pencil.flutter --data-dir <framework-host-data> --json`, verify its session is disconnected, and keep the host running for replay.

See the [Flutter consumer guide](https://www.ansight.ai/docs/sdk/flutter/pencil).
