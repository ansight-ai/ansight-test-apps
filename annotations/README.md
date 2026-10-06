# Annotations feature suite

This workspace tests the native annotation engine in the local
`ansight-sdk` checkout. The apps are the SDK's native Android and iOS
harnesses, so the test exercises the aggregate package and its public
`Annotate.PresentAsync()` path.

| Platform | App ID | Workspace |
| --- | --- | --- |
| iOS Simulator | `ai.ansight.ios.native-harness` | [iOS test](ios/ansight/tests/annotation.live-roundtrip.yaml) |
| Android Emulator | `ai.ansight.harness` | [Android test](android/ansight/tests/annotation.live-roundtrip.yaml) |

The iOS workspace test and the Android runner open the native editor, draw a
freehand stroke, and save exact feedback text. `verify-session.py` then checks
that a `sdk.annotatedFeedback` annotation appears in the **same Ansight
session** with freehand geometry, a screenshot, and a visual tree. Neither
test creates a host-side annotation.

Build the local harness apps first:

```sh
(cd ../../ansight/ansight-sdk/src/android && ./gradlew :harness:assembleDebug)

(cd ../../ansight/ansight-sdk/test-apps/core/ios && \
  xcodebuild -project AnsightNativeHarness.xcodeproj -scheme AnsightNativeHarness \
    -configuration Debug -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath Build build CODE_SIGNING_ALLOWED=NO)
```

From this directory, validate definitions and run on selected targets:

```sh
ansight test validate ios --json
ansight test validate android --json

ansight test run ios annotation.live-roundtrip --device-id SIMULATOR_UDID --app ../../ansight/ansight-sdk/test-apps/core/ios/Build/Products/Debug-iphonesimulator/AnsightNativeHarness.app --trace --json
python3 verify-session.py SESSION_ID_FROM_IOS_TEST 'annotation e2e ios roundtrip'

python3 run-android.py EMULATOR_ID --apk ../../ansight/ansight-sdk/test-apps/core/android/build/outputs/apk/debug/harness-debug.apk
```

The app and CLI host must connect. Run against Debug app builds; Release
builds disable the annotation editor. These tests cover connected delivery.
The Android workspace JSON records the equivalent agentic scenario; the
`run-android.py` path drives the emulator directly because the current
workspace runner can miss its connected Android session.
