# Audio demo testing

Use the [demo instructions](ansight/README.md) to prepare and run `audio.demo`.
The old multi-mode tasks and agentic wrappers have been removed.

The results below are historical verification records from the earlier suite;
they do not establish a live pass for the simplified task.

## Validation status

### Offline Whisper — 9 September 2026

Final coverage is **8/8 quotes on iOS** and **three distinct quotes on Android**. The final task source is `e36ce2f`, exercised on resident host **0.38.6-local / 2026090902**. All observed final-case transcripts, microphone waveforms and wrong-quote controls passed. The Android eight-quote corpus remains unverified.

The same prepared `base.en` model and MAUI app code produced the correct Hamlet transcript from the actual device microphone on both platforms. Each deterministic run passed **30 assertions**, including the immutable recording hash, whole-speech waveform comparison, different-quote rejection, pinned model hash, source-audio provenance, final transcript, and reset to Ready.

| Platform | Recorded microphone | Whole-speech correlation | Wrong-quote correlation | Whisper processing |
| --- | --- | --- | --- | --- |
| iOS 26.4 Simulator | 48 kHz stereo, 7.2 seconds | **0.997694** | **0.229510**, rejected | **1.311 seconds** |
| Android 16 Emulator | 16 kHz mono, 26.528 seconds | **1.000000** | **0.228454**, rejected | **1.194 seconds** |

iOS single task `7296803860d84d55bf6c7dde6af91dbb` used session `ai-ansight-audioharness-1538` with CLI **0.38.6 / 2026090901**. Android single task `a6929a1385bd44b9b42bfe6db09ee56d` used session `ai-ansight-audioharness-1539` with **0.38.6-local / 2026090902**, built from keyboard fix `d90de7c1`. Android's total task time was 74.5 seconds including UI automation and artifact checks; that is separate from its 1.194-second inference time.

For each single, both automatic terminal triggers completed and their retained timeline JSON and WAV were exported independently. Each export matched the task's copy byte for byte; the WAV hash also matched `transcription.sourceAudioSha256`. Audit receipts are `artifacts/audio-harness/whisper-20260909/ios-single-audit/summary.json` and `android-single-audit/summary.json`.

The final iOS Whisper corpus then passed **8/8 quotes** on **2026090902** with task source `e36ce2f`: parent `54ea1149ed0344a29d9cbbdd70e9abdf`, session `ai-ansight-audioharness-1540`, **18 parent assertions and 31 assertions per child**, completed in **141.726 seconds**. All eight final transcripts matched. Whole-speech correlations ranged from **0.990140 to 0.999533**, all eight wrong-quote controls were rejected, and inference took **1.073–1.259 seconds** per recording. The read-only audit verified eight distinct app runs, recording hashes, fixture identities and completed injections from the retained files. Its receipt is `ios-corpus-audit/summary.json`; the single-run audits above independently verify the automatic timeline path.

The first iOS Whisper corpus passed four quotes, then failed during Lincoln playback. A host output change to EarPods preceded a CoreAudio configuration notification that stopped the playback engine; the helper reported a timeout and the app rejected its silent recording before inference. The investigation does not establish who changed the output or the complete internal causal chain. The failed parent `decf19a2cf1d445c9420978fed05d2aa` and `ios-playback-failure/summary.json` remain retained. Keep the host audio configuration stable during a run; incomplete delivery must not be counted as a transcription pass.

Android subsequently passed Macbeth in the same emulator session, with **29/29 assertions**, correlation **1.0**, a rejected different-quote control (**0.138043**), and **1.041 seconds** of Whisper processing. Task `e4bfc428f1e8478fb0c824575bbb30f7` completed in 60.08 seconds. The emulator was not cold-booted or recovered between the successful Hamlet and Macbeth runs. This proves two distinct quotes and recorder reopening; an eight-quote Android Whisper corpus has not passed.

The final Android Descartes case used the current verified-input task and passed **30/30 assertions**, correlation **1.0**, and a rejected wrong-quote control (**0.183608**). Its exact final transcript was `I think, therefore I am.`; inference took **1.050 seconds**, and the full task took **63.710 seconds**. Task `d33dc5e8743a4a49aed6fa5eb02b5d28` used the same session `ai-ansight-audioharness-1539`, with no emulator restart across the three successful quotes. Its retained recording hash matches both app capture metadata and Whisper source-audio metadata. `android-final-task.json` and `validation-summary.json` retain the final result and coverage limits.

An intervening Macbeth attempt (`c307bef4e62840ce9414849368112618`) expired before injection because Start and the subsequent status-label navigation consumed the 30-second recording window. Its unrelated recognized output failed the expected-phrase assertion. Task fix `5e2fadf` removes that extra navigation on Android and immediately invokes the unchanged guest-microphone readiness/quiet-input checks. The successful repeat has one fewer assertion because it omits only the iOS-specific visible `Listening` check; transcript, recording, provenance and negative-control assertions remain intact.

The second iOS attempt (`65fd65243d474fc0a8b404943af3b60e`) stopped on its first quote with `loopback-no-active-client`, before audio delivery. After selecting Simulator **Audio Output → MacBook Pro Speakers**, rechecking BlackHole input, and relaunching only the harness, the fresh SDK session is `ai-ansight-audioharness-1540`. The repair changed no Mac audio defaults; `ios-route-repair/summary.json` retains its scope and route evidence.

The next attempt (`09701fafa13a4bbe893d8f77f4d01a7d`) correctly captured and transcribed Hamlet, with correlation **0.997831** and a rejected wrong-quote control, but the app's expected phrase still held its default quick-brown-fox text. Its final assertion correctly failed. The task now explicitly focuses the field and asserts its fresh displayed value before recording, so an unapplied edit stops before audio injection. This preserved attempt is a test-setup failure, not a Whisper recognition failure.

The final eight-quote pass used that repaired route and the verified-input task. Earlier partial and failed attempts remain separate in `validation-summary.json` and their original evidence directories.

Earlier setup failures remain preserved: Simulator HID rejected the original typographic dash before recording, the old Android AVD lacked installation space, and Android's keyboard-visibility parser rejected a safe dismissal before Start. Equivalent ASCII expectation entry, a separate 8 GiB AVD, and the CLI keyboard parser fix addressed those specific setup issues without weakening transcript or waveform assertions. Final TypeScript checks, both test-schema validations and task discovery passed without warnings; the receipt is `workspace/final-authoring-verified-input/summary.json`. No agentic test or MAUI unit test was run.

### Capture and media baseline — 8 September 2026

Recorded with CLI and resident host build **2026090805**, from Ansight commit `e1a86312`. All 16 embedded web assets were verified byte-for-byte against the intended media and icon build.

| Check | Verified result |
| --- | --- |
| Android single Hamlet capture | Passed 16 assertions; correlation **1.0**; different-quote control rejected. |
| iOS eight-quote capture corpus | **8/8 passed**, with 18 parent and 128 child assertions; correlations **0.990326–0.999380**; all eight different-quote controls rejected. |
| Android eight-quote corpus | **Failed after 1/8 passed.** The second quote, Macbeth, was rejected before injection because input energy was unexpectedly high while the host microphone was disabled. |
| Packaged local session viewer | Green Android and blue iOS badges passed. A **14.704-second** WAV loaded, advanced during muted playback, supported seeking, and cleaned up after closing with no media errors. |

Android single task `dc4b66a043da4e0abef46a5c12fcce56` used session `ai-ansight-audioharness-1532`. Both automatic terminal-artifact triggers succeeded, and five artifact exports completed. The Android corpus parent was `b7a5946cedd648d487d76409df522368`; its failed Macbeth child was `53728a9727264ceb9c425a1cd1e48177`.

iOS corpus parent task `cc05b889f003442a92ccec24e18c9025` used session `ai-ansight-audioharness-1533` on simulator `4594102E-88A3-4242-8851-F959C4C9DBBC`. Its audit verified **40 retained artifacts, 16 successful automatic triggers, and eight delivery exports**. The harness finished Ready with its microphone idle.

Local evidence is retained in the ignored `artifacts/audio-harness/ansight-live-20260908/` directory, including `android/single-2026090805.json`, `android/single-pass-trigger-audit-2026090805.json`, `android/corpus-2026090805.json`, `ios/corpus-final-proof.json`, and `media-final0805/summary.json`. Each task's full recording and comparison files remain under its evidence directory described above.

**Remaining issue at that checkpoint:** repeated capture on Android Emulator 37.1.11. After the recorder reopened, the emulator log repeated CoreAudio errors including `Could not initialize record`, `Could not set audio format change listener`, and `kAudioHardwareIllegalOperationError`. An explicitly prepared, freshly cold-started emulator can isolate dependence on retained audio state. Preserve failed-run evidence; do not add automatic retries or weaken the quiet-input guard. That Android corpus was not a full pass.

The final browser smoke covered the local session list and one muted WAV. Full local/team list checks in both light and dark themes remain manual regression guidance above. No native transcription run was performed on this final build.
