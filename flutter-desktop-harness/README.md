# Flutter desktop harness

This checked-in macOS app runs the full Flutter feature harness from the sibling
`ansight-sdk` repository and records its deterministic integration scenario in
the local Ansight host.

The app uses bundle id `ai.ansight.flutter.harness`. Its UI and fixture
implementation come from `ansight-sdk/src/flutter/example`, while this project
owns the persistent macOS runner and recording workflow.

## Record and verify

Start the resident host, then run:

```sh
ansight host run
./scripts/record.sh
```

The script runs `integration_test/recording_test.dart`, resolves the exact new
macOS session, names and pins it in Ansight, verifies retained screenshots,
Flutter visual trees, FPS samples, Flutter pointer/touch records, metrics,
events, and logs, exports the correlated frame to
`validation/latest-screenshot.jpg`, and writes exact evidence IDs and
timestamps to `validation/latest-session.json`.

The screenshot, visual-tree, and touch evidence come from Flutter's render,
widget, and pointer-event layers. Native AppKit UI inspection and touch capture
outside the Flutter boundary, QR, and purchase capabilities remain outside this
harness.
