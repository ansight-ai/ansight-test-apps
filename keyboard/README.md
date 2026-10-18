# Keyboard dismissal regression

A .NET 10 MAUI app reproducing Evergine's root-page keyboard regression. The app
has an Entry and Editor directly on its root ContentPage, with no navigation
wrapper or Back interception. Sending Back after the keyboard closes can
background the Android activity, so the harness preserves that failure mode.

App ID: `ai.ansight.testapps.keyboard`.

The deterministic `keyboard.root-dismissal` task and workspace test:

1. Open the Entry keyboard, replace its text, and confirm the keyboard is open.
2. Dismiss through `ansight.keyboard.dismiss()` and verify the root page and text.
3. Dismiss again while closed; require no input action and prove the app still
   handles a button tap.
4. Repeat with the Editor after changing focus, then verify both texts, the root
   page, the response counter, and the final closed keyboard state.

The test requires the SDK's `ui.dismiss_keyboard` tool and the fixed CLI. It also
checks that open-keyboard dismissal uses `app-input-method`; a Back-based host
must not pass merely because one attempt happened to leave the app open. Missing
keyboard visibility or an unavailable tool fails the run instead of skipping it.
The stale-visibility race is covered separately by the CLI's KeyboardOperationTests.

## Build

Requires the .NET 10 MAUI workload and Android SDK or Xcode. The app uses the same
package version convention as the other samples: NuGet `Ansight.Maui` 1.8.1 by
default. That published SDK predates the safe-dismissal tool. To verify this fix
before release, build against the SDK checkout containing it:

```sh
cd keyboard/maui
dotnet build Ansight.KeyboardHarness.csproj -f net10.0-android -t:SignAndroidPackage \
  -p:AnsightSdkRoot=/absolute/path/to/ansight-sdk
```

For a later published package, omit `AnsightSdkRoot` and set
`-p:AnsightPackageVersion=<version-containing-the-fix>`. To build iOS, use
`-f net10.0-ios -p:RuntimeIdentifier=iossimulator-arm64` instead. The sample
allows Read/Write Ansight tools and is intended only for testing.

## Run

From `keyboard`, initialize or register the workspace, then install the signed
APK returned by the build on the explicitly selected emulator:

```sh
ansight workspace init . --app-id ai.ansight.testapps.keyboard
npm --prefix ansight ci
npm --prefix ansight run typecheck
ansight test validate . --json
ansight test run . keyboard.root-dismissal --platform android \
  --device-id <emulator-serial> --app /absolute/path/to/the-Signed.apk --json
```

This test has a `taskId` and no prompt, so it runs the deterministic task without
an AI runner. It can also attach with `--session-id <id>` instead of launch
options. View the test run's named assertions and session replay. After the run:

```sh
ansight device terminate android <emulator-serial> ai.ansight.testapps.keyboard
```

For manual checks, use the Entry and Editor with `ansight keyboard open`,
`is-open`, and `dismiss`, then tap **Verify app responds**. **Reset test** restores
the two initial values and response counter. There is deliberately no app button
that substitutes a direct SDK call for the host keyboard command under test.

## Isolated host development

The build property `AnsightHostDiscoveryPort` defaults to `45123`. To test a
locally built CLI without replacing a shared resident host, choose a free UDP
port, build with `-p:AnsightHostDiscoveryPort=<port>`, and start the fixed CLI with
`host run --data-dir <isolated-state> --discovery-port <port>
--websocket-port <other-free-port> --serve-port 0`. Pass that same `--data-dir`
to workspace registration, test, and replay commands. The SDK is pinned to the
chosen discovery port. Keep each build's host configuration with its evidence.

## Verification

On 18 October 2026, the task passed all **21 named assertions** in 103 seconds
on the Android 13/API 33 arm64 emulator, using .NET 10 and the local CLI/SDK fixes.
The root page stayed open, both typed values survived, and the response counter
reached 2. Both repeated dismissals performed no input. The three-minute task
budget leaves room for slower devices and before/after evidence capture.

The Android APK and iOS Simulator target both build. iOS UI execution and the
original Windows 11/Android 15 combination have not been verified here. The
Android build emits existing SDK duplicate-type/native-library and obsolete API
warnings; the harness itself builds without errors. The app was stopped after
the passing run, and its replay was retained locally.
