# Ansight QR pairing — .NET MAUI

A standalone Ansight QR pairing sample, using `Ansight.Maui` 1.8.1 on Android and iOS. Open `Ansight.QrPairingHarness.csproj` and run **Debug**. The application ID is `ai.ansight.testapps.qrpairing`.

## Included behavior

- SDK startup, automatic simulator/emulator registration, and saved physical-device enrollment.
- **Scan Ansight enrollment QR**, **Connect using saved enrollment**, **Disconnect**, and **Forget saved enrollment**.
- Live SDK connection status, saved-enrollment availability, and actionable errors with network state and technical reason codes.
- A persisted capture on/off preference. Disabling capture uses `Runtime.Deactivate()`, stopping host discovery and streaming. Virtual targets start active on each launch.
- A **Remote tools** control with remembered user consent on physical devices, a prompt before the first tool execution, and immediate revocation for subsequent requests. Simulators and emulators allow tools automatically.
- A connection notification on physical iOS devices, including notification permission handling in an iOS partial class.
- A single capture configuration: FPS, battery, connectivity, network, touches, screenshots and annotation support; 400 ms sampling, 120 s retention, and 750 ms / quality 65 / 720 px screenshots with a visual tree on touch. HTTP bodies are enabled only on virtual devices.
- A synthetic test-event button and stable automation IDs for live checks.

The SDK owns enrollment storage, remembered Wi-Fi/host profiles, trust, expiration, automatic reconnect and connection serialization. This app does not store or parse enrollment secrets, maintain a host list, or run a retry loop. Capture and remote-tools consent preferences are app-owned. Local interface/profile availability remains subject to OS permissions and SDK behavior.

All integration classes live in `Ansight/`. `AnsightConnectionService` is a small UI adapter; platform notification code is in its `.iOS.cs` partial. Connection-error formatting is independent of MAUI so its checks run without a device.

The developer UI uses English. An application adopting it should apply its own access policy before enabling capture or showing pairing actions.

## Build and run

Install the .NET 10 SDK and MAUI Android/iOS workloads, with the corresponding Android SDK/JDK and Xcode. This suite pins SDK 10.0.300 and MAUI 10.0.71.

```sh
cd qr-pairing/maui
dotnet build Ansight.QrPairingHarness.csproj -f net10.0-android -c Debug
dotnet build Ansight.QrPairingHarness.csproj -f net10.0-ios -c Debug \
  -p:RuntimeIdentifier=iossimulator-arm64
dotnet run --project tests/QrPairingChecks.csproj
```

Use `iossimulator-x64` on an Intel Mac. Simulator builds use ad-hoc signing, including the SDK’s native frameworks; do not disable signing. Physical iOS deployment requires your own development team, signing identity and provisioning profile; none are included. Android scanning uses the SDK's Google Code Scanner integration and needs Google Play services. The Android scanner owns its native interface; the app supplies the Ansight title on platforms where the SDK supports it.

For a physical iPhone, build with an installed development identity and a provisioning profile that includes the device. Signing values stay local to the build command:

```sh
dotnet build Ansight.QrPairingHarness.csproj -f net10.0-ios -c Debug \
  -p:RuntimeIdentifier=ios-arm64 \
  '-p:CodesignKey=<Apple Development identity>' \
  '-p:CodesignProvision=<profile name or UUID>'
ansight device install ios <device-id> \
  bin/Debug/net10.0-ios/ios-arm64/Ansight.QrPairingHarness.app --json
ansight device launch ios <device-id> ai.ansight.testapps.qrpairing --json
```

A paired, reachable iPhone can be deployed over Wi-Fi. Use `ansight device list --ios --physical --all --json` to find its identifier.

Start or reuse the local host, then launch the Debug app from your IDE:

```sh
ansight host status --json
# Only when no host is running:
ansight host run
```

A simulator or emulator registers automatically. For a physical phone on a network that can reach the computer, open **Pair Any App** in Ansight, or generate its generic QR:

```sh
ansight pairing issue --qr
```

In the app, tap **Scan Ansight enrollment QR**. Allow camera/local-network access when requested. A successful scan connects and lets the SDK remember the installation and network. Relaunching the app should reconnect without scanning. No prior app registration, embedded config, host address, certificate or token is required.

```sh
ansight session list --connected --app-id ai.ansight.testapps.qrpairing --json
ansight app tools <session-id> --detail summary --include-unavailable --max-results 50 --json
```

## Remote tools

The aggregate SDK registers the standard MAUI, visual-tree, reflection, database, files, preferences, secure-storage and clipboard tools. Android also includes its platform diagnostics. The app wraps the completed tool registry using `UserConfirmedAnsightTool`, preserving each tool's policy, schemas, prerequisites, availability and structured JSON execution.

On a physical phone, **Remote tools** starts off. Turn it on to review and accept the consent prompt, or approve the first permitted remote-tool request. Cancelling leaves access blocked. Approval is remembered across launches; turning the switch off revokes it for subsequent requests. It does not cancel a tool already executing. Discovering the catalog does not prompt. On simulators and emulators the switch displays the automatic allowance.

Consent and the authenticated connection grant are independent. The SDK still enforces each tool's read/write/critical policy; approving app consent does not elevate a read-only enrollment. Use an enrollment with the required grant when testing write or critical tools. Capture and pairing work without remote-tools consent, and iOS notification permission is unrelated.

## Build policy

Only **Debug** references Ansight and exposes pairing or remote tools. Release builds exclude the integration files and package, and show a disabled-harness message. This intentionally provides a safe default for a customer sample.

Debug builds allow cellular/hotspot connections to the host. Unattended provisioning is off by default; opt in only for your test infrastructure using `-p:AnsightUnattendedProvisioningEnabled=true`. Ordinary pairing does not require it.

## Verification checklist

Run these on physical Android and iOS devices for complete QR coverage:

1. Fresh install: enable capture, scan a fresh generic QR and confirm a connected session for this App ID.
2. Restart: reconnect without scanning. Repeat on two known Wi-Fi networks/hosts to exercise SDK-managed profile selection.
3. Disconnect: the current connection closes. With capture still enabled, SDK auto-probe may reconnect (observed on iOS Simulator); disable capture when you want it to stay disconnected. Exercise saved-enrollment reconnect on a physical device.
4. Disable capture and forget enrollment: the saved indicator clears. Re-enable capture and scan a fresh QR to enroll again. Virtual targets can register again automatically, so they cannot prove physical-device enrollment was forgotten.
5. Cancel the scanner; deny camera/local-network permission; try an expired or already-consumed QR. Check that the flow exits and failure information remains actionable.
6. Disable capture: discovery and the session stop. On a physical device, restart and confirm capture remains off. Re-enable and reconnect.
7. On physical iOS, allow or deny the connection notification prompt and confirm pairing still succeeds in either case. Foreground banner presentation follows the app/OS notification policy.
8. Remote tools: cancel the consent prompt and verify a permitted tool returns `ansight_remote_tools_not_allowed`; approve and retry a harmless read tool. Restart to confirm consent persists, then switch off and verify a subsequent request needs consent again. Check write/critical denial with a read-only connection grant.
9. Record a test event and confirm it in the connected session. Release builds must expose neither the SDK nor pairing actions.

See [verification results](VERIFICATION.md) for what was actually exercised. Physical camera scanning, remembered Wi-Fi switching and iOS notification delivery require device validation; a simulator session is not proof of these flows.

## Copy into another app

Add the package and `UseAnsight` call in `MauiProgram.cs`, copy the `Ansight/` integration folder, and expose the actions from your developer screen. Keep the platform privacy declarations and apply your own build/access policy. Preserve SDK ownership of saved enrollment and reconnect behavior.

[Ansight integration notes](ansight-readme.md) list the key entry points and CLI commands.
