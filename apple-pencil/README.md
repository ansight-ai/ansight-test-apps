# Apple Pencil feature suite

SDK-equipped iPad Simulator apps for validating Pencil input playback and what each framework actually receives. Each technology owns its native project, `ansight/` tasks and pen fixtures here.

| Technology | App ID | Task | Playback |
| --- | --- | --- | --- |
| [Swift / UIKit / SwiftUI](ios/README.md) | `ai.ansight.testapps.pencil` | `pencil.hid-demo` | `hid+sdk` |
| [MAUI / .NET iOS](maui/README.md) | `ai.ansight.testapps.pencil.maui` | `pencil.hid-demo` | `hid+sdk` |
| [Flutter](flutter/README.md) | `ai.ansight.pencil.flutter` | `pencil.sdk-demo` | `sdk` |
| [React Native](react-native/README.md) | `ai.ansight.pencil.reactnative` | `pencil.sdk-demo` | `sdk` |
| [Capacitor](capacitor/README.md) | `ai.ansight.pencil.capacitor` | `pencil.sdk-demo` | `sdk` |

## Local checkout layout

The unpublished packages resolve from the sibling SDK checkout:

```text
<git>/
  ansight-test-apps/apple-pencil/<technology>/
  ansight/ansight-sdk/src/
  ansight/ansight-cli/
```

Swift, Flutter, React Native and Capacitor link that source checkout. MAUI deliberately uses matching NuGet packages containing precompiled native frameworks; see its README for feed/cache isolation. This move does not change the optional Pencil SDK's installation or activation contract.

## Build, register and run

Follow the selected technology README to build and install the app. Use a CLI from the matching checkout. Native iOS/MAUI discover port **49332** (replay **49331**, WebSocket **49333**); Flutter/React Native/Capacitor discover **49432** (replay **49431**, WebSocket **49433**). Existing hosts on these ports can be reused.

Register the relocated workspaces with the host you will use:

```sh
bash scripts/register-apps.sh --data-dir /absolute/path/to/host-data
```

From the technology directory:

```sh
ansight session list --connected --data-dir /absolute/path/to/host-data --json
ansight task list --app-id <app-id> --repository "$PWD" --data-dir /absolute/path/to/host-data --json
ansight task run <task-id> --app-id <app-id> --repository "$PWD" --session-id <exact-connected-session> --data-dir /absolute/path/to/host-data --json
```

MAUI must launch with `--pen-simulation`. Every verification run in this suite requires its app's SDK connection and capture; do not substitute an external device-only capture. The feature itself can play without capture, but these tasks must retain and assert evidence. All harnesses use a read-only global tool policy: the Pencil opt-in supplies only the exact playback grants. Tasks retain a screenshot and check ten assertions covering contact, release, taps, pressure, tilt, azimuth, roll and hover distance. App observations independently expose received values. Also run a following HID-only contact to check ordinary input has no simulation override metadata. Native `PencilIsolationTests` exercise interception isolation and conflicts.

Terminate the dedicated test app after verification and confirm the exact SDK session is disconnected. Keep the recording and resident host for replay.

## Scope of the existing demos

Framework samples currently plot received points as dots; they do not yet assert a rendered continuous stroke. That rendering behavior is unchanged by this relocation. React Native uses registered callbacks, not native gesture-library arbitration; synthetic DOM events are untrusted. [Consumer guides and verification details](https://www.ansight.ai/docs/sdk/pencil) describe the supported paths.

Earlier recordings retain their original app IDs and repository paths. Flutter now has its own App ID so installing this feature app does not replace the core Flutter harness.
