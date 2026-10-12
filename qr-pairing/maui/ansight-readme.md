# Ansight integration

- App ID: `ai.ansight.testapps.qrpairing`.
- Platforms: .NET MAUI Android and iOS; SDK package `Ansight.Maui` 1.8.1.
- Startup: `MauiProgram.CreateMauiApp` calls `UseAnsight(AnsightConfiguration.CreateOptions(remoteToolConsent))` before `Build`.
- Scanner: main page **Scan Ansight enrollment QR**, automation ID `pairing.scan`, calls `Runtime.HostConnection` through `AnsightConnectionService.ScanAsync` with `HostConnectionRequest.QrCode("Scan Ansight enrollment QR")`.
- Tool policy: Debug includes the all-in-one remote tools for this synthetic harness. Physical devices require remembered app consent through `AnsightRemoteToolConsent`; `UserConfirmedAnsightTool` wraps the full SDK registry after registration. The SDK still enforces the authenticated connection grant. Release excludes Ansight. Unattended provisioning requires an explicit build opt-in.
- Saved enrollment and remembered network/host selection: SDK-owned. `ForgetEnrollment` calls `ClearSavedConfigs`; no custom config store exists.
- Capture preference: `AnsightConfiguration` stores only `ansight.capture-enabled` in app preferences.
- Remote-tools preference: `ansight.remote-tools-allowed`, surfaced by `pairing.remote-tools` and `pairing.remote-tools-status`. Virtual targets allow automatically.
- Error details: `AnsightConnectionFailureMessage` plus `AnsightNetworkStatus`; no credentials are displayed or copied into the sample.
- Physical iOS connection notifications: `AnsightConnectionService.iOS.cs`.

```sh
ansight host status --json
# Start only if needed, in a separate terminal:
ansight host run
# For a physical device; display transiently, do not save the payload:
ansight pairing issue --qr
ansight session list --connected --app-id ai.ansight.testapps.qrpairing --json
ansight app tools <session-id> --detail summary --include-unavailable --max-results 50 --json
```

Build/check commands and the manual device matrix are in [README.md](README.md). Results are in [VERIFICATION.md](VERIFICATION.md).
