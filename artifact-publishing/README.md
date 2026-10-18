# App-initiated artifact publishing

A .NET 10 MAUI app and deterministic Ansight task validating artifacts published
by the app itself. App ID: `ai.ansight.testapps.artifacts`.

The buttons call `ArtifactPublisher.PublishAsync`; there is no custom artifact
provider or remote tool. The task uses UI automation to tap them, then reads the
host's retained artifacts. The test has a `taskId` and no agent prompt.

`artifacts.publish` checks:

- Exact UTF-8 contents, including accented text and an emoji, MIME type, and byte count.
- A 131,089-byte file spanning three 64 KiB transfer chunks. Its SHA-256 must
  match after the app deletes its source file.
- Repeated publication of the same artifact ID creates separate snapshots.
- Invalid metadata creates no retained artifact.
- Cancellation after the first chunk propagates, creates no retained artifact,
  and leaves the connection usable for another successful publication.

The reset button clears only app counters. The task compares against an initial
artifact baseline, so it can also run repeatedly within a connected session.

## Build

Requires .NET 10 with MAUI workloads, the Android SDK or Xcode, and an Ansight
CLI/SDK containing app-initiated artifact publication. The app automatically
uses a sibling `ansight/ansight-sdk` or `ansight-sdk` source checkout. Set
`-p:AnsightSdkRoot=/absolute/path/to/ansight-sdk` for another layout. To test a
released package instead, set `-p:AnsightPackageVersion=<version>`; older
packages without `ArtifactPublisher` cannot run this harness.

From the repository root:

```sh
dotnet build artifact-publishing/maui/Ansight.ArtifactHarness.csproj \
  -f net10.0-android -t:SignAndroidPackage

dotnet build artifact-publishing/maui/Ansight.ArtifactHarness.csproj \
  -f net10.0-ios -p:RuntimeIdentifier=iossimulator-arm64
```

Android embeds its assemblies for direct installation. iOS simulator builds use
ad hoc signing. Read/Write built-in tools are enabled for UI automation. This
app is for local testing.

## Run

Start or reuse the resident Ansight host, then initialize/register the workspace
and validate its deterministic task:

```sh
ansight workspace init artifact-publishing --app-id ai.ansight.testapps.artifacts
npm --prefix artifact-publishing/ansight ci
npm --prefix artifact-publishing/ansight run typecheck
ansight test validate artifact-publishing --json
ansight task list --app-id ai.ansight.testapps.artifacts --repository artifact-publishing --json
```

Choose a booted target from `ansight device list --json`, then run:

```sh
ansight test run artifact-publishing artifacts.publish --platform android \
  --device-id <emulator-serial> \
  --app "$PWD/artifact-publishing/maui/bin/Debug/net10.0-android/ai.ansight.testapps.artifacts-Signed.apk" --json

ansight test run artifact-publishing artifacts.publish --platform ios \
  --device-id <simulator-udid> \
  --app "$PWD/artifact-publishing/maui/bin/Debug/net10.0-ios/iossimulator-arm64/Ansight.ArtifactHarness.app" --json
```

Keep each result's session ID and named assertions. The current CLI records a
trace by default and stops the app it launched. Verify the exact session reports
`isConnected: false` with `ansight session show <session-id> --json`; when using
an older CLI or attaching a session, terminate the test app explicitly with
`ansight device terminate <platform> <device-id> ai.ansight.testapps.artifacts`.
Leave the device and host running for replay. Obtain its replay link with
`ansight session serve <session-id> --json`.

For an isolated development host, set `-p:AnsightHostDiscoveryPort=<port>` at
build time and use that port for the host's discovery listener. The default is
45123. Pass the isolated host's `--data-dir` consistently to CLI operations.

## Verify retention after restarting the host

After a fresh passing run and after stopping the app, export and compare every
published file through the CLI:

```sh
python3 artifact-publishing/scripts/verify-retained.py <session-id> [<another-session-id>]
```

The script expects exactly three report snapshots and one binary in each fresh
session. It checks filenames, MIME types, byte lengths, and exact contents. To
prove durability, stop and restart the resident host once no other sessions or
jobs need it, then rerun the same command. The script neither launches an app nor
restarts a shared host. It exports into a temporary directory and removes only
those temporary copies; all recordings remain retained.

## Verified locally — 18 October 2026

CLI 1.5.1 build `2026101801` was built, signed, installed locally, and used with
the SDK source checkout containing artifact publication. No public release was
published. Both application targets build successfully; SDK builds emit
existing duplicate-type/native-library or obsolete API warnings.

| Target | Task result | Duration | Retained session |
| --- | --- | --- | --- |
| Android 13 / API 33, Pixel 3a arm64 emulator | 32/32 assertions passed | 62.3 s | `ai-ansight-testapps-artifacts-2269` |
| iOS 26.4, iPhone 17e arm64 simulator | 32/32 assertions passed | 11.9 s | `ai-ansight-testapps-artifacts-2268` |

The apps were stopped and both sessions reported `isConnected: false`. All eight
files exported with identical contents before and after restarting the idle
resident host. Each session retained exactly three 101-byte reports and one
131,089-byte binary; no invalid or cancelled artifact was retained. The binary
SHA-256 was `1ec3437cee3cccf3647e130524ade52848571960a3340ae33573beef17d330b3`.

Both runs included traces, screenshots, visual trees, and named assertions.
An earlier attempt stopped at capability preflight because the task incorrectly
declared action names as capabilities; the corrected declaration uses
`ui.semantic`, `app.tools`, and `evidence.artifacts`. No SDK or host publication
changes were needed during these live checks.

These runs exercise the MAUI SDK on Android and iOS. They do not establish live
coverage for the separate JavaScript, Flutter, Kotlin, or Swift public APIs,
physical devices, larger upload limits, or forced host termination.

## Additive requirements verified — 18 October 2026

CLI 1.5.1 build `2026101802` was installed locally after simplifying descriptor
versioning. Tasks and triggers keep separate schemas; each accepts version `1`
or an omitted version, with optional `requires` fields. The harness now uses
version `1` with its existing capability requirements.

- android: 32/32 assertions passed in 76.6 s; retained session `ai-ansight-testapps-artifacts-2271`.
- ios: 32/32 assertions passed in 16.2 s; retained session `ai-ansight-testapps-artifacts-2270`.

Both apps were stopped after the runs. The keyboard harness also passed
workspace validation and task discovery with its version-1 app-tool requirement.
The earlier restart-retention checks remain recorded above.
