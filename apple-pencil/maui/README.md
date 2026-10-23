# Precompiled MAUI Pencil verification

This iPad Simulator harness uses **NuGet package references** to `Ansight.Maui` and the optional `Ansight.Pencil`. It does not compile SDK Swift sources as part of the app build. Its native canvas reads the normal UIKit Pencil properties from C# and saves independent observations to `Library/pencil-observations.json` (under MAUI's app data directory). Ansight also records screenshots and touch samples.

Build both Apple bindings and the `Ansight.Maui` / `Ansight.Pencil` dependency graphs in **Release**, package all matching Ansight dependencies from the same checkout into a local feed, then restore this app from that feed using an isolated package cache. Mixing a freshly built core with older aggregate packages can fail at startup even when their package versions match. An existing cached package with the same version must not substitute for the local build. Use a clean binding rebuild when validating native changes and inspect the **packaged** framework, not only Xcode's intermediate output. Run multi-target SDK builds serially as in the release script (`-p:BuildInParallel=false -maxcpucount:1`).

The harness targets .NET 9 / MAUI 9 and discovers the isolated host on port **49332**, with the replay server at **49331**. Start the host using the instructions in `../ios/README.md`.

## Two launch modes

- Default launch: no simulation opt-in, under the read-only tool guard. `ui.simulate_pen` must not appear in its catalog. `pen-capability.json` reports `optedIn: false` and `nativeCapability: false`.
- Launch with `--pen-simulation`: calls `options.WithSimulatorPenInput()` during `UseAnsight` configuration. The Simulator tool becomes available through its exact write grant; unrelated write tools remain blocked. The same Release core and separate Pencil frameworks are used in either mode. Package presence alone does not opt in.

After launching with opt-in, register this workspace and run `pencil.hid-demo` against its exact SDK session. The task plays `ansight/fixtures/pencil-demo.pen.json`, verifies ten assertions against captured contact/hover properties, and retains a screenshot. Compare those captures with the canvas's independent `pencil-observations.json` readings. A subsequent HID-only tap should have no simulation source tag and use ordinary UIKit properties.

Terminate the dedicated harness after verification so the SDK recording ends. Leave the host and Simulator available for replay.

## Existing pen integrations

This is experimental interception, disabled by default. A permitted hybrid run installs process-wide UIKit getter swizzles. Matching simulated Pencil events use the requested properties; other input calls the previous implementations. Synthetic hover drives existing Pencil hover recognizers. Simulation data is cleared after the run, but the installed hooks remain as pass-throughs until app exit. Other swizzlers, gesture arbitration, coalesced events and PencilKit internals need separate compatibility testing. The harness proves this UIKit/MAUI path, not universal pen-framework compatibility.

Hybrid playback now requires a unique native target accessibility identifier. Hover additionally requires one named, idle Pencil recognizer attached directly to that view. Contact properties require matching transport timestamps and touch/view/window identity; there is no position-only fallback. See [the isolation and compatibility contract](https://www.ansight.ai/docs/sdk/pencil) for scope, hook-conflict checks and framework limitations.

## Toolchain and relocated build

Use the Xcode version required by the installed .NET 9 iOS workload. The verified workload `26.0.9785` requires Xcode 26.0; select it for this command with `DEVELOPER_DIR`, without changing the machine-wide Xcode selection. After restoring matching local packages, build from this directory:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.0.0.app/Contents/Developer dotnet build Pencil.Maui.csproj -c Debug -p:RuntimeIdentifier=iossimulator-arm64 -p:EnableCodeSigning=false --no-restore
```

Adjust the Xcode path to the matching installed toolchain. Restore with the local feed and isolated package cache described above before using `--no-restore`.
