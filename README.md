# Ansight test apps

Small apps for validating features in the Ansight CLI and SDKs.

| App | Platforms | Purpose |
| --- | --- | --- |
| [Audio Harness](audio-harness/README.md) | iOS Simulator and Android Emulator | Inject speech through the microphone and verify the actual recording or native transcript. |
| [Background Transcription Spike](background-transcription/README.md) | Native Swift (iOS 26+) and Kotlin (Android 15+) | Validate injected-speech and live-microphone transcription while an Ansight-instrumented app is backgrounded. |
| [Flutter Desktop Harness](flutter-desktop-harness/README.md) | Flutter on macOS 10.15+ | Exercise the Flutter SDK through its full feature harness and retain an evidence-backed Ansight session. |
| [Modal Surface Evidence](modal-surface-evidence/README.md) | Native Android | Verify touches in a modal window and screenshots of controls over a GPU surface. |
| [SDK-less Notes](sdkless-notes/README.md) | Native iOS Simulator and Android Emulator | Notes stored in local SQLite with no Ansight SDK or third-party runtime dependencies. |

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
