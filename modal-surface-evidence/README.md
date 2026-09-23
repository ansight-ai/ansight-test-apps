# Modal Surface Evidence

This Android app reproduces the two Ansight capture failures seen in Redpoint session `com-alphaoutdoors-redpoint-1763`: touches inside a separate modal window were absent, and copying a `GLSurfaceView` into screenshots covered the controls above it.

The app has a `Dialog` window containing a separately composited `SurfaceView` scene and a yellow control panel drawn over it. Its buttons and the surface respond to touches. A live counter observes touches captured by Ansight's own window callback without replacing the SDK runtime handler. The app configures `ScreenshotWithVisualTreeOnTouch` for connected sessions and automatically saves a local visual tree when an SDK-captured Down event arrives. It builds against the local `ansight-sdk` checkout, so edits to the SDK are exercised directly.

## Build and run

```sh
cd modal-surface-evidence/android
./gradlew :app:installDebug
adb shell am start -n ai.ansight.testapps.modalsurfaceevidence/ai.ansight.modalsurfaceevidence.MainActivity --ez ai.ansight.modalsurfaceevidence.OPEN_MODAL true
```

The default SDK source path is `../../../ansight-sdk/src/android` relative to the Android project. Override it with `-PansightSdkRoot=/absolute/path/to/ansight-sdk/src/android` when the repositories are elsewhere.

## Regression checks

1. With the modal open, tap **TAP OVERLAY** and drag the blue and pink surface scene. The app's interaction counters and **SDK touch** Down/Move/Up counters should increase. **Auto visual tree** must change from waiting to `PASS` after the first touch, with at least two windows. This local tree is saved as `files/modal-visual-tree.json` with the triggering touch timestamp.
2. In a connected Ansight session, inspect `ansight session touches <session-id> --json` and `ansight session trees <session-id> --json`. The session must contain the modal tap and drag, and a visual tree with touch trigger metadata. Its tree must contain the dialog controls.
3. Inspect an Ansight session screenshot while the modal is open. It must show the blue surface, pink rectangle, and the complete yellow panel including its text and buttons.
4. Tap **SAVE ANSIGHT PNG** for an on-demand capture. The app must report `Screenshot: PASS` after checking yellow, blue, and pink pixels. Pull `modal-surface-evidence.png` from the app's files directory with `adb shell run-as ai.ansight.testapps.modalsurfaceevidence cat files/modal-surface-evidence.png > capture.png` to inspect the full image. This invokes the native SDK screenshot path.
5. Close and reopen the modal, then repeat the touch and automatic visual tree checks to catch stale window callbacks.

The `.NET` Android screenshot path has the same surface overlay fix in `Ansight.Core`. The native app exercises the shared Android window, `SurfaceView`, and PixelCopy behavior; validate the .NET integration in Redpoint after consuming the updated SDK package.
