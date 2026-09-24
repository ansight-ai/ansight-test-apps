# SDK-less Notes

Temporary native test harness for SDK-less simulator/emulator execution. Both apps let you create, edit, delete, and reopen notes stored in a local SQLite database. **Neither app contains the Ansight SDK, an SDK bootstrap/plugin, a pairing configuration, or third-party runtime dependencies.** Platform APIs provide the UI, storage, and animation.

| | iOS | Android |
| --- | --- | --- |
| App ID | `ai.ansight.testapps.sdklessnotes` | `ai.ansight.testapps.sdklessnotes` |
| UI | Swift / UIKit | Java / Android views |
| Database | `Documents/notes.sqlite` | `files/notes.sqlite` |
| Minimum OS | iOS 17 (simulator build) | Android 8 / API 26 |
| Package | `build/ios/Build/Products/Debug-iphonesimulator/SDKLessNotes.app` | `android/app/build/outputs/apk/debug/app-debug.apk` |

## Prepared local devices and verification

Both apps were built and installed on dedicated devices on 2026-09-24:

- iOS: **SDK-less Notes**, iOS 26.4, `B02B8721-9231-4DAE-8E79-9DC55ADE1393`.
- Android: **Ansight_SDKless_Notes_API36**, Android 16 / API 36, serial `emulator-5580` (booted headlessly for validation).

App ID on both: `ai.ansight.testapps.sdklessnotes`. The devices contain sample notes from validation.

Verified: Swift store checks; two iOS UI tests (create/edit/delete, persistence after termination/relaunch, sample scrolling); Android platform instrumentation CRUD checks; Android visible-UI create/save/relaunch; external SQLite extraction and `integrity_check=ok` on both. The actual Ansight external providers returned CPU and memory on both platforms and **60 rendered FPS** on the animated Android app (one observed sample on a software-rendered emulator, not a performance benchmark). Android used `adb-run-as` on a Google Play image without root. iOS FPS remains unavailable.

The Android runtime dependency graph reports **No dependencies**, its APK requests no permissions, and the iOS app links only Apple system/Swift libraries and SQLite. No Ansight SDK is linked into either app. The standalone Android and iOS test bundles are separate from the app binaries.

## Build

Run from this directory. iOS requires Xcode and XcodeGen. Android requires JDK 17, an Android SDK with platform 34, and the checked-in Gradle wrapper. Android builds are debuggable so `adb run-as` can read their private files, including on a Google Play emulator without root.

```sh
./scripts/build-ios.sh
./scripts/build-android.sh
```

The Android build also produces a separate platform-instrumentation test APK. It is not a runtime dependency of the notes app. The iOS UI tests likewise live in a separate test bundle. Neither test uses the Ansight SDK.

## Install and launch

Select an exact virtual device from `xcrun simctl list devices available` or `adb devices -l`.

```sh
# iOS: replace IOS_SIMULATOR_UDID with the chosen simulator identifier.
xcrun simctl boot IOS_SIMULATOR_UDID
xcrun simctl install IOS_SIMULATOR_UDID build/ios/Build/Products/Debug-iphonesimulator/SDKLessNotes.app
xcrun simctl launch IOS_SIMULATOR_UDID ai.ansight.testapps.sdklessnotes

# Android: replace emulator-5580 if using another emulator.
adb -s emulator-5580 install -r android/app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5580 shell am start -n ai.ansight.testapps.sdklessnotes/dev.sdkless.notes.MainActivity
```

## Exercise the app

1. Tap **New note**, fill **Title** and **Note body**, then **Save note**.
2. Reopen the note, edit it, and save again.
3. Terminate and relaunch the app. Verify the edited text persisted.
4. Open the note, tap **Delete note**, and confirm.
5. Tap **Add samples** to add 50 notes for scrolling. Each tap adds another 50.
6. Enable **Animate** to continuously render a moving dot. This exercises Android frame-stat collection. iOS external FPS is currently unsupported by the Ansight collector.

Controls have stable native accessibility/resource IDs. iOS IDs use hyphens (`new-note`, `note-title`, `note-body`, `save-note`, `delete-note`, `animation-toggle`); Android uses the corresponding underscores under `ai.ansight.testapps.sdklessnotes:id/`. Note saves/deletes write native log messages without logging note contents.

Notes stay entirely on the device. The Android manifest requests no network permissions. SQLite uses rollback journaling (`DELETE`), and each save completes its transaction before returning. Extract only while no write is in progress; a live file copy is not a transactional backup.

## Read the database externally

```sh
# iOS data container: the output contains the absolute database location.
xcrun simctl get_app_container IOS_SIMULATOR_UDID ai.ansight.testapps.sdklessnotes data
# Copy Documents/notes.sqlite from that returned directory.

# Android binary-safe extraction through the app UID; root is unnecessary.
adb -s emulator-5580 exec-out run-as ai.ansight.testapps.sdklessnotes cat files/notes.sqlite > /tmp/sdkless-notes-android.sqlite
sqlite3 /tmp/sdkless-notes-android.sqlite 'PRAGMA integrity_check; SELECT id,title,body FROM notes ORDER BY id;'
```

Both databases have `user_version=1` and a `notes` table with `id`, `title`, `body`, `created_at`, and `updated_at`. IDs are integer primary keys; timestamps are UTC strings. SQL parameters are bound rather than concatenated.

## Use with Ansight

Use the patched CLI **and resident host**. These commands require normal Ansight account/app access but never pair an SDK:

```sh
ansight app execute --app "$PWD/build/ios/Build/Products/Debug-iphonesimulator/SDKLessNotes.app" \
  --device-id IOS_SIMULATOR_UDID --execution-mode device \
  --prompt "Create a note titled External check with body Saved without an SDK. Save it and reopen it to verify its contents. Capture Documents/notes.sqlite from the data sandbox."

ansight app execute --app "$PWD/android/app/build/outputs/apk/debug/app-debug.apk" \
  --device-id emulator-5580 --execution-mode device \
  --prompt "Create a note titled External check with body Saved without an SDK. Save it and reopen it. Add sample notes, enable Animate, and scroll. Capture files/notes.sqlite from the data sandbox."
```

The expected capability state is SDK app tools unavailable, external file capture available, and externally collected CPU/memory available when permitted. Android `gfxinfo` FPS is renderer-dependent. These apps intentionally provide no app tools, HTTP traces, managed-heap telemetry, or SDK events.

## Automated checks

```sh
# Compiles the actual Swift SQLite store on macOS and checks CRUD and reopening.
./scripts/check-ios-store.sh

# Runs the native iOS UI flow, including termination/relaunch persistence.
xcodebuild -project ios/SDKLessNotes.xcodeproj -scheme SDKLessNotes \
  -destination 'platform=iOS Simulator,id=IOS_SIMULATOR_UDID' \
  -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test

# Runs CRUD/reopen checks in a separate disposable database on the emulator.
adb -s emulator-5580 install -r android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
adb -s emulator-5580 shell am instrument -w \
  ai.ansight.testapps.sdklessnotes.test/dev.sdkless.notes.StoreInstrumentation
```

The Android instrumentation result must contain `PASS` and `INSTRUMENTATION_CODE: -1`.

To confirm the Android app has no runtime dependencies:

```sh
cd android
./gradlew :app:dependencies --configuration debugRuntimeClasspath
```

Expect `No dependencies`. The XcodeGen specification has only the system `libsqlite3` dependency; the iOS app links Apple system frameworks and Swift libraries.

## Remove the temporary harness

Uninstall only `ai.ansight.testapps.sdklessnotes` from the selected simulator/emulator. If using the dedicated devices created for this harness, shut down/delete **SDK-less Notes** in Simulator and **Ansight_SDKless_Notes_API36** in Android Device Manager. The folder is independent of every SDK-enabled test app and may be removed after the investigation.
