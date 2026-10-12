# Verification — 13 October 2026

## Build checks

| Check | Result |
| --- | --- |
| Android Debug APK build | Passed, 0 warnings / 0 errors |
| iOS Debug arm64 simulator app build | Passed, 0 warnings / 0 errors |
| Android Release compile | Passed, 0 warnings / 0 errors |
| iOS Release compile | Passed, 0 warnings / 0 errors |
| Evaluated Release project | No Ansight package references or integration source files |
| Connection failure checks | Passed: expired QR, network failure, unknown reason, legacy message, empty message |

The iOS simulator build needs ad-hoc signing for the bundled native frameworks. An initial build with signing disabled was rejected by iOS before managed startup; the project now configures simulator signing and the subsequent launch passed.

## Live iOS Simulator check

- Target: iPhone 17e, iOS 26.4, SDK capture using Ansight 1.8.1.
- App ID: `ai.ansight.testapps.qrpairing`.
- First retained session: `ai-ansight-testapps-qrpairing-2090`.
- Relaunch session: `ai-ansight-testapps-qrpairing-2091`.
- Started with no enrollment payload or host address. The SDK connected to the existing local host automatically.
- UI showed connected status, capture enabled and the expected pairing actions.
- Session metadata confirmed the capture settings: 750 ms / quality 65 / 720 px screenshots, visual tree on touch, 400 ms telemetry, 120 s retention, FPS and battery enabled.
- The Debug remote-tools catalog was available: 61 tools across MAUI, UI, reflection, data, preferences, secure storage, files and clipboard. Catalog discovery did not execute those tools.
- Tapped `pairing.event`: the UI changed to “Test event recorded.” The retained post-action frame is `20261012224917597-4414fc8a420044158330987cce460370` at 22:49:17 UTC. Independent event-payload inspection was not completed because the installed CLI rejected its documented log-filter syntax.
- Tapped `pairing.disconnect`: the SDK returned “Session disconnected.” Its automatic probe then reconnected while capture remained active. Post-action SDK screenshot capture was briefly unavailable during disconnection; the resulting UI was inspected with a simulator screenshot instead.
- Tapped `pairing.capture` to disable capture: the UI showed the inactive explanation, connection actions became unavailable and `session show` reported `isConnected: false`. Before/after trees are retained under action `ui-action-2c257a0de4ff419089533cd18b3bc391`.
- Terminated and relaunched the app: it activated and connected automatically again, matching the virtual-device startup policy.
- Final cleanup terminated only this app. Both sessions are disconnected and the connected-session query returned zero matches. The shared host and simulator were left running.

Local replay:

```sh
ansight session serve ai-ansight-testapps-qrpairing-2090 --json
```

The commands that changed device/app state were `ansight device install`, `launch` and `terminate`; a persistent `ansight app interact` session tapped the test-event and disconnect buttons, and `ansight ui tap` disabled capture. The app was not running before this check. No cloud share or upload was performed.

## Device checks still required

Android runtime/scanner testing, real QR expiration/consumption, permission denial, remembered physical enrollment across restarts, Wi-Fi/host switching, and physical iOS connection notification delivery remain unverified. Physical iOS scanning and the notification permission prompt were subsequently exercised as recorded below. The README contains the manual checklist.

## Physical iPhone deployment — 13 October 2026

The sample was moved into `qr-pairing/maui`, and the suite/index links and build instructions were updated. Sample source, comments and documentation use generic Ansight wording.

- Built the Debug `net10.0-ios` / `ios-arm64` app from the new location: 0 warnings / 0 errors.
- Used an existing Ansight Apple Development identity and a development profile containing the iPhone. Signing settings were supplied to the build command, not saved in the sample.
- Verified the app signature with `codesign --verify --deep --strict`.
- The connection-failure checks passed from the relocated `tests` project.
- Deployed over the paired Wi-Fi connection to the iPhone 16 Pro. The CLI installation command timed out, but a fresh installed-app query confirmed `ai.ansight.testapps.qrpairing`, display name **Ansight QR Pairing**, version **1.0**, build **1**. No second install was attempted.

The app was launched successfully, and a subsequent CoreDevice process query confirmed it was still running. It was left open on the iPhone for the user.

This confirms build, signing, installation and launch. The subsequent physical QR enrollment check is recorded below.


## Physical QR enrollment — first attempt timeout, second attempt connected

- Session: `ai-ansight-testapps-qrpairing-2092`, physical iPhone 16 Pro, Ansight SDK 1.8.1.
- Investigation interval: 12 October 2026, 22:58:44–22:59:49 UTC (13 October, 09:58:44–09:59:49 Sydney time).
- The host received the first enrollment request at 22:58:50.535 UTC and recorded acceptance at 22:58:50.548. No WebSocket handshake followed for that attempt. The retained app events show the connection-failure alert at 22:58:59.273; the user reported a UDP timeout. A further request using the same enrollment reached the host at 22:58:59.919 but also did not establish a live connection.
- A fresh QR enrollment reached the host at 22:59:21.170 UTC. The WebSocket opened at 22:59:21.382, and the remote-tools catalog and capture streams arrived.
- The user confirmed the second attempt succeeded and iOS requested notification permission. The sample requests this permission after a successful physical-device connection; it is independent of UDP enrollment. This verifies the prompt, not notification delivery.
- The host received the synthetic `QR pairing sample: test event` event, captured at 22:59:48.922 UTC, confirming end-to-end event delivery.
- Root cause of the first UDP timeout is unresolved. Host acceptance proves the request arrived; it does not prove that the reply reached the phone before its timeout. No packet-level or native permission-transition evidence was captured, so permission timing and packet loss are not established causes.

The investigation was read-only and did not restart the shared host or interrupt the app. First-attempt physical enrollment remains an open reliability finding; successful enrollment on the second attempt does not close it.


## Remote-tools consent update — 13 October 2026

The sample now includes a remote-tools control and app-owned consent on physical devices. The complete SDK tool registry is wrapped after all default suites are registered; each tool retains its original identity, policy, availability, prerequisites and JSON invocation contract. Simulators and emulators bypass the consent prompt. Authenticated host grants remain enforced by the SDK.

- Android Debug and signed iPhone Debug builds: passed, 0 warnings / 0 errors.
- iOS Release compile: passed, 0 warnings / 0 errors. Evaluated Release inputs contain no Ansight package or integration source.
- Consent checks passed for denial before execution, approval, remembered consent across helper instances, revocation, concurrent requests sharing approval, revocation during a pending prompt, cancellation without persisting approval, metadata/availability preservation and both legacy/JSON execution paths. Existing connection-failure checks also passed.
- Before this update, the physical session catalog contained 61 tools: 31 read, 11 write and 19 critical. Its authenticated grant allowed read only; write and critical tools reported `tool_policy_not_granted`. The app's consent switch does not elevate that grant.

The automated checks exercise consent and dispatch independently of MAUI dialogs. Physical consent-dialog interaction, persisted consent across an actual app restart and post-consent remote execution still require device validation; they are not claimed by the unit checks.

The updated signed Debug app was installed successfully over Wi-Fi on the iPhone 16 Pro using CoreDevice, confirmed by a fresh installed-app query, and launched successfully. The sample was left open for the user to review the Remote tools control. Existing app data was retained.

After launch the physical iPhone connected as `ai-ansight-testapps-qrpairing-2093` without this deployment issuing or scanning a new QR. Its retained catalog still contains all 61 tools, with 31 read tools eligible under the host grant and write/critical tools denied by `tool_policy_not_granted`. Catalog inspection did not execute a tool or accept consent for the user.
