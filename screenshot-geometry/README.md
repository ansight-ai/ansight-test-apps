# Screenshot geometry — MAUI

A small Android/iOS app for `includeSystemUiMetadata` and `ignoreSystemUi`. It shows a deterministic app clock, two purple blocks and one blue block. Buttons advance the clock, change one purple block to red, and reset the scene. App ID: `ai.ansight.testapps.screenshotgeometry`.

The `screenshots.geometry` task checks:

- Capture-time normalized safe-area data and the app-window capture target.
- Metadata retained with the exact `frameId`.
- Per-capture opt-out, including retained evidence, and an explicit error if masks require missing metadata.
- System bars marked absent by app-window renderers; their masks must not hide the app clock.
- An explicit app-clock rectangle excludes the clock change from scoring.
- A changed block outside that rectangle still fails and produces retained difference regions.

A safe-area inset is not a mask. These app-window captures exclude OS status/navigation glyphs. Exact iOS cutout bounds are unknown and must not be guessed. Host unit fixtures separately exercise display captures with a present status bar, overlapping masks, unknown geometry and stream ordering.

## Build and run

Use current SDK and CLI source containing screenshot geometry support. The project finds `../../ansight/ansight-sdk` from this suite's directory, or accepts `-p:AnsightSdkRoot=/absolute/path/to/ansight-sdk`.

```sh
dotnet build screenshot-geometry/maui/Ansight.ScreenshotGeometryHarness.csproj -f net10.0-android -c Debug
ansight test validate screenshot-geometry screenshots.geometry --json
ansight test run screenshot-geometry screenshots.geometry \
  --app screenshot-geometry/maui/bin/Debug/net10.0-android/ai.ansight.testapps.screenshotgeometry-Signed.apk \
  --platform android --device-id emulator-5554 --json
```

```sh
dotnet build screenshot-geometry/maui/Ansight.ScreenshotGeometryHarness.csproj \
  -f net10.0-ios -c Debug -p:RuntimeIdentifier=iossimulator-arm64
ansight test run screenshot-geometry screenshots.geometry \
  --app screenshot-geometry/maui/bin/Debug/net10.0-ios/iossimulator-arm64/Ansight.ScreenshotGeometryHarness.app \
  --platform ios --device-id <simulator-udid> --json
```

Periodic capture defaults to metadata on. Build with `-p:IncludeSystemUiMetadata=false` to exercise periodic opt-out; the task still tests explicit per-capture true/false independently. A separate development host can use `-p:AnsightHostDiscoveryPort=<port>`.

`harness.clock_bounds` is a read-only tool with no arguments. It reports the clock rectangle from native view layout, normalized against the captured window, with two pixels/points of resampling padding. Its class and registration are compiled only with `DEBUG`; non-Debug builds disable remote tools. This fixture is for local development.

Comparisons and their images are retained in the session for replay. No external image assessment provider is used. Stop the app after testing; retain the host/session to review evidence.

## Periodic setting tests

`screenshots.periodic-enabled` reads a retained periodic image before the task takes any screenshots and expects metadata. Run it with the default build. Build with `-p:IncludeSystemUiMetadata=false`, then run `screenshots.periodic-disabled` against that binary to prove opt-out. Run these tests individually against the matching build; do not run both against one binary. The main `screenshots.geometry` test passes with either build because on-demand options are independent.

When metadata is disabled, the host may resume its external device capture provider and store WebP images. The disabled test checks that images remain available without geometry, independent of encoding.

## Verified locally

Android emulator API 33 and iOS simulator 26.4 passed the 18-assertion main journey and the four-assertion periodic-enabled case. iOS also passed periodic opt-out (two assertions) and the full main journey with periodic metadata disabled, proving per-capture independence. All apps were stopped after testing. See [verification-results.json](verification-results.json) for retained session IDs and the checks performed. Physical cutouts, rotation, split-screen and multiple windows remain outside this fixture's verified coverage.
