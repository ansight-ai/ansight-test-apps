# Ansight test apps

Small apps for validating features in the Ansight CLI and SDKs.

| Suite | Platforms | Device requirement | Purpose |
| --- | --- | --- | --- |
| [Annotations](annotations/README.md) | iOS, Android | Simulator or emulator | Verify native in-app annotation capture and same-session host delivery. |
| [Artifact Publishing — MAUI](artifact-publishing/README.md) | .NET MAUI on Android and iOS | Emulator or simulator | Verify app-initiated artifact uploads, retained file integrity, repeated publication, rejection, and partial-transfer cancellation. |
| [Audio](audio/README.md) | iOS, Android | Simulator or emulator | Inject speech through the virtual microphone and verify the recording or native transcript. |
| [Background Transcription](background-transcription/README.md) | iOS 26+, Android 15+ | Physical device for native speech validation; simulator or emulator for the automated injection test | Validate transcription while an Ansight-instrumented app is backgrounded. |
| [Evergine Tools](evergine-tools/README.md) | .NET MAUI on iOS and Android | iOS simulator verified; Android unverified | Prototype Evergine scene inspection and camera control through Ansight remote tools. |
| [Flutter](flutter/README.md) | Flutter on macOS 10.15+ | Mac host | Exercise the Flutter SDK through its full feature harness and retain an evidence-backed Ansight session. |
| [Keyboard — MAUI](keyboard/README.md) | .NET MAUI on Android and iOS | Emulator or simulator | Verify keyboard dismissal preserves the root page, input values, and app responsiveness. |
| [Modal Surface](modal-surface/README.md) | Native Android | Emulator | Verify touches in a modal window and screenshots of controls over a GPU surface. |
| [Motion](motion/README.md) | Native Android and iOS | Android emulator or iOS simulator | Verify app-observed accelerometer injection on Android and automated UIKit shake delivery on iOS. |
| [QR Pairing — MAUI](qr-pairing/maui/README.md) | .NET MAUI on iOS and Android | Simulator/emulator for local registration; physical device for QR enrollment | Reusable Ansight pairing, remembered enrollment, reconnect, diagnostics and capture controls. |
| [RealityKit](reality-kit/README.md) | .NET MAUI on iOS 18+ | **Physical LiDAR iPhone required** | Capture a space or object with ARKit and RealityKit, export GLB assets, and attach the visual scan to an Ansight session. |
| [Telemetry — MAUI](telemetry/README.md) | .NET MAUI on Android and iOS | Emulator or simulator | Verify fractional metrics, units, nested/overlapping spans, outcomes, incomplete spans, and MAUI appearance properties. |
| [SDK-less Notes](sdkless-notes/README.md) | Native iOS and Android | Simulator or emulator | Validate local SQLite notes without an Ansight SDK or third-party runtime. |

## SDK-free sample registration

Enable automatic recording for the iOS and Android Notes samples, without selecting devices:

```sh
./sdkless-notes/scripts/register-sample-apps.sh
```

Remove their watches and app metadata while retaining recordings and installed apps:

```sh
./sdkless-notes/scripts/deregister-sample-apps.sh
```

See the [SDK-less Notes setup](sdkless-notes/README.md#register-and-deregister-automatic-recording) for details.
