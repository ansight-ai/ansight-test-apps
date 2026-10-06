# Motion feature suite

Small native apps for checking what an app actually receives when a virtual device is shaken.

| Platform | Bundle or package ID | Check |
| --- | --- | --- |
| Android Emulator | `ai.ansight.testapps.motionharness` | Ansight task injects acceleration through the emulator sensor and asserts the app detects both a shake and a custom sample. |
| iOS Simulator | `ai.ansight.testapps.motionharness` | Ansight task posts a UIKit shake gesture and asserts the app detects it. The Simulator menu offers a manual check. |

## Android

Build with JDK 17 and the Android SDK:

```sh
cd android
./gradlew :app:assembleDebug
adb -s emulator-5554 install -r app/build/outputs/apk/debug/app-debug.apk
```

Replace `emulator-5554` with your emulator's ADB serial. Launch **Motion Harness** and check that it shows **Sensor ready**. Keep it in the foreground. The app registers an Android `SensorManager` accelerometer listener and shows the sample count, last values, shake status, and custom sample status. **RESET COUNTERS** clears those observations.

Return to the Motion Harness root and use an Ansight CLI build containing `ansight.device.shake()` and `ansight.device.playAccelerometer()`:

```sh
cd ..
ansight test validate . --json
ansight task list --app-id ai.ansight.testapps.motionharness --repository "$PWD" --json
ansight task run motion.shake-and-samples --app-id ai.ansight.testapps.motionharness --repository "$PWD" --device-id emulator-5554 --json
```

The task requires a running Ansight host and a connected app session. It resets the counters, sends six alternating shake pulses, checks the app's **Shake detected** state, then sends a custom 32 m/s² X-axis sample and checks **Custom sample observed**. The matching test definition is at [`ansight/tests/motion.shake-and-samples.json`](ansight/tests/motion.shake-and-samples.json).

## iOS Simulator

Build the included Xcode project with Xcode and the local `ansight/ansight-sdk` checkout:

```sh
cd ios
xcodebuild -project MotionHarness.xcodeproj -scheme MotionHarness -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath ../build/ios/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The `project.yml` file is available to regenerate the project with `xcodegen generate`.

Run the app in an iOS Simulator and keep it foregrounded with a connected Ansight session. From the Motion Harness root, run:

```sh
cd ..
ansight task run motion.ios-shake --app-id ai.ansight.testapps.motionharness --repository "$PWD" --device-id SIMULATOR_UDID --json
```

The task calls `ansight.device.shake()` and waits for **Shake detected** in the app. The matching test definition is at [`ansight/tests/motion.ios-shake.json`](ansight/tests/motion.ios-shake.json). You can also choose **Device > Shake Gesture** in Simulator to check the app manually. **RESET COUNTERS** clears the count. iOS sends a fixed UIKit gesture; timed accelerometer samples remain Android only.

The [SDK capture apps](../../ansight/ansight-sdk/test-apps/motion/README.md) verify opt-in motion event capture
in the Android and iOS SDKs.
