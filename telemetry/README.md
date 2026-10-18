# Telemetry harness

MAUI app and deterministic Ansight task for decimal metrics, units/group metadata,
nested/overlapping/async spans, failure/cancellation outcomes, unfinished spans,
and typed MAUI font, padding, spacing, alignment, and border properties.

Build against the sibling source SDK (or pass `-p:AnsightSdkRoot=/absolute/path`):

```sh
dotnet build telemetry/maui/Ansight.TelemetryHarness.csproj -f net10.0-android -t:SignAndroidPackage
dotnet build telemetry/maui/Ansight.TelemetryHarness.csproj -f net10.0-ios -p:RuntimeIdentifier=iossimulator-arm64
```

For a development host set `-p:AnsightHostDiscoveryPort=<port>` at build time.
Initialize the workspace with `ansight workspace init telemetry --app-id ai.ansight.testapps.telemetry`.
Run `ansight task list --app-id ai.ansight.testapps.telemetry --repository telemetry --json`, then:

```sh
ansight device install <android-or-ios> <device-id> <apk-or-app-path>
ansight device launch <android-or-ios> <device-id> ai.ansight.testapps.telemetry
# Wait until the app displays Connected.
ansight task run telemetry.record --app-id ai.ansight.testapps.telemetry --repository telemetry --device-id <device-id> --json
```

The task performs named assertions against telemetry retained by the host, not
app-owned counters. Open the saved session to review separate channel lanes.
The interrupted span intentionally has no end. Stopping capture must leave it
incomplete. The harness accepts repeated runs in a session by comparing span IDs.
Unit tests in each SDK additionally cover its public/helper recording contract.

Run as a harness-suite test (installs, launches, validates, and stops the app):

```sh
ansight test validate telemetry --json
ansight test run telemetry telemetry.record --app <apk-or-app-path> --platform <android-or-ios> --device-id <device-id> --json
```

After capture ends, verify saved decimal values and span reconstruction with the built player:

```sh
node telemetry/scripts/verify-retained.mjs <ansight-player-repo> <capture-directory> [<capture-directory>...]
```

## Verified 2026-10-18

CLI 1.5.1 build 2026101804, source SDK, Android API 33 emulator and iOS 26.4 simulator.
Both suite runs passed all 35 assertions and stopped their app afterward:

- Android: `ai-ansight-testapps-telemetry-2274`, run `c2562eac21b940448c62169574180cff`.
- iOS: `ai-ansight-testapps-telemetry-2275`, run `3ac0ed0a519d47e4b8affa33993903f5`.

The retained-file check passed for both: exact values `16.67`, `0.125`, `-0.25`,
nine spans, and one incomplete span without an invented duration per capture.
Local machine-readable results are in the ignored `verification/` directory.
The player was also checked for channel lanes, decimal unit labels, saved
incomplete spans, and host-unavailable recovery. This is a MAUI device harness;
.NET, Kotlin, Swift, Flutter, React Native, and Capacitor telemetry contracts
also have SDK unit coverage, but this run did not launch apps in every framework.
