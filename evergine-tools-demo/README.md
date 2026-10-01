# Evergine tools demo

A small .NET MAUI app for prototyping Ansight remote tools with the Evergine
team. It renders the Air Jordan 1 GLB from Evergine's EverSneaks sample and
exposes the live scene through three Ansight tools. There are no Redpoint
assets, services, or data dependencies.

`Assets/AirJordan.glb` is copied unchanged from the EverSneaks `Content/Models`
directory. It contains the model's meshes, materials, and textures. The scene
also has a camera and three named marker entities used by the entity query.
`EvergineToolsDemo.weproj` and the Evergine
target packages export Evergine's core render resources into the app bundle;
the GLB itself is packaged as a MAUI asset and loaded through
`Evergine.Runtimes.GLB` at runtime. The iOS and Android profiles include the
`DIFF` shader variant needed by the model's base color textures.

The Evergine project profile was adapted from Evergine's
[EverSneaks MAUI sample](https://github.com/EvergineTeam/EverSneaks) under its
MIT license; see `LICENSE-EverSneaks.txt`. The Air Jordan model is by
[makoto on Sketchfab](https://sketchfab.com/3d-models/air-jordan-1-a4b434181fbb48008ad460722fd53725),
licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
We have not changed the GLB from the copy in EverSneaks.

| Tool ID | Policy | Result |
| --- | --- | --- |
| `demo.evergine.scene_summary` | Read | Scene ID, entity count, GLB load state, camera position |
| `demo.evergine.find_entities` | Read | Bounded entities filtered by exact `name` or `tag` |
| `demo.evergine.reset_camera` | Write | Restored camera position |

Drag across the Evergine view to orbit the camera around the model. The gesture
keeps the camera's distance fixed and limits vertical rotation. **Reset view**
returns to the initial angle. **Move camera** changes the camera position; the
reset tool restores it, giving the team a visible state change to inspect. Tool
operations are dispatched to MAUI's main thread, where this iOS prototype draws
its scene.

## Build and run

Requires .NET 10 MAUI, an iOS development environment, and the Evergine
2025.10.21 packages. The packages are declared in `EvergineToolsDemo.csproj`.

```sh
dotnet build EvergineToolsDemo.csproj -c Debug -f net10.0-ios -p:TargetFrameworks=net10.0-ios -p:RuntimeIdentifier=iossimulator-arm64
ansight device install ios <simulator-id> bin/Debug/net10.0-ios/iossimulator-arm64/EvergineToolsDemo.app
ansight device launch ios <simulator-id> ai.ansight.testapps.everginetools
```

Start the local Ansight host before launching the app if it is not already
running. Ansight 1.6.1 and the three demo tools are registered only in Debug
builds. Debug builds allow Read and Write remote tools.

The Debug iOS app was built with zero warnings and errors, installed, and run
on an iPhone 17 Pro simulator with iOS 26.4. The textured Air Jordan model was
visible in the Evergine view, and Ansight reported `glbLoaded: true`. The
camera button and all three tools worked while the model rendered.

Android is included as a MAUI target, but its packaging, runtime GLB load, and
rendering have not been verified on an emulator. Its surface handler currently
updates the scene without calling `DrawFrame`.

## Exercise the tools

Get the live session ID with `ansight session list --connected`, then:

```sh
ansight app tools <session-id> --id-prefix demo.evergine --detail full
ansight app call <session-id> demo.evergine.scene_summary --arguments '{}'
ansight app call <session-id> demo.evergine.find_entities --arguments '{"name":"AirJordan1"}'
```

Tap **Move camera**, query the scene summary again, then run:

```sh
ansight app call <session-id> demo.evergine.reset_camera --arguments '{}'
```

The camera position should return to `(0, 0, 8)`. The scene includes
`DemoCamera`, `X marker`, `Y marker`, `Z marker`, and `AirJordan1` with its mesh
children. The entity query also returns a result cap and `truncated` flag.

## Prototype boundary

`Tools/EvergineDemoTools.cs` contains the candidate sample integration: tool
definitions, schemas, bounded queries, and result payloads. `DemoScene` and the
surface handlers are app code. A production integration needs an Evergine-owned
dispatch point for scenes that change on a separate simulation thread.

Useful next experiments with the Evergine team are an active-scene selector,
entity component summaries, camera pose inspection, and a durable scene
snapshot artifact. Android rendering should be verified independently.
