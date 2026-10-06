# Boulder Capture Spike

Standalone iOS .NET MAUI spike for capturing a climbing boulder or its surrounding space on a LiDAR iPhone. The main **Scan whole space with LiDAR** flow displays ARKit's live structural mesh over the camera while scanning. It also records camera-aligned depth and color frames. After capture it builds a RealityKit preview and a visual glTF 2.0 GLB from those paired frames, plus a separate `space-structure.glb` containing ARKit's coarse environment mesh. **Photo area scan (experimental)** uses RealityKit Object Capture and on-device photogrammetry to create a textured USDZ and approximate textured GLB for a smaller surface.

## Build and run

This suite copy uses app ID `ai.ansight.testapps.realitykitcapture` and `Ansight.Maui` 1.6.2.

Requires .NET 10 MAUI iOS, Xcode, an iOS 18+ LiDAR device, and an Apple development signing identity. The project currently uses the Red-Point team and Matthew Robbins development certificate.

```sh
dotnet build BoulderCaptureSpike.csproj -c Debug -p:RuntimeIdentifier=ios-arm64
xcrun devicectl device install app --device <device-id> bin/Debug/net10.0-ios/ios-arm64/BoulderCaptureSpike.app
xcrun devicectl device process launch --device <device-id> ai.ansight.testapps.realitykitcapture
```

The debug build includes Ansight. Start an Ansight host before launching the app to receive a session automatically, or use **Connect Ansight**. GPU-backed Ansight screenshots are enabled for this diagnostic build so the AR surface is visible in recordings. The readback previously coincided with a RealityKit capture crash on iOS 26.6.1; build with `-p:EnableAnsightGpuCapture=false` if it recurs. Release builds omit the Ansight package.

## Capture

1. Choose **Balanced** or **High detail** in **Processing quality**, then tap **Scan whole space with LiDAR** and walk slowly around the area. High detail samples more views, uses the full 256×192 depth grid, and fuses positions at 1.8 cm rather than 3 cm. It takes longer to finish and produces a larger GLB. Both modes cap visual faces per view to limit memory use. The live mesh overlay and patch/triangle counters should grow as ARKit maps more of the space. Use **Hide live mesh** to check the camera view alone.
2. Tap **Finish space scan**. The app triangulates camera-aligned depth views, merges overlapping samples into a small voxel grid, and builds a texture atlas from the corresponding camera colors. It uses the same visual geometry for the GLB and RealityKit preview, and saves the coarse scene mesh as a separate structural GLB. The status shows each processing stage.
3. Close the preview, then tap **View exported GLB** to reopen the actual saved file in RealityKit. Drag to rotate and pinch to zoom. **Share GLB** exports the file, and **Share diagnostics** exports the native and .NET logs if a scan fails. The app remembers the last completed GLB across launches.

The visual GLB uses a lightweight voxel merge of camera-depth surfaces. It is not a watertight reconstruction, but it keeps color attached to the depth pixels that observed each surface and removes duplicate triangles from overlapping views. Balanced captures up to 24 distinct views; High detail captures up to 32. Both skip low-confidence depth pixels and avoid mipmaps on the per-triangle color atlas so unrelated faces do not bleed into one another. Hidden surfaces and tiny or transparent objects can still be missing. The photo path can generate finer textures, but it tends to center on a smaller visual feature.

## Ansight workspace

The debug app emits `boulder.scan.glb.ready` with the finished scan UUID after both GLBs have been written. The included `ansight/` workspace defines `scans.attach-visual-glb`, which requests the textured GLB from the app's read-only `boulder.scan` artifact provider in 512 KB transfer chunks. It appears beside the capture screenshots and events in the matching Ansight session timeline. The structural GLB remains available from the same provider for manual inspection. Sending both large GLBs simultaneously caused a transfer timeout in the first live test; a single 27 MB visual GLB completed in 17.5 seconds with larger chunks. Ansight's file viewer supports an inline 3D GLB preview. The workspace is registered with this app ID on the local Ansight host, and the scan trigger is connected. On a new host, run these commands from this app folder to enable the same setup:

```sh
ansight app register ai.ansight.testapps.realitykitcapture --codebase "$PWD"
ansight repo automation connect ai.ansight.testapps.realitykitcapture "$PWD"
ansight repo automation inspect ai.ansight.testapps.realitykitcapture "$PWD" --json
```

The trigger runs when a completed scan emits `boulder.scan.glb.ready`; connecting it does not replay earlier scans.

## Implementation notes

- `Native/SceneMeshCapture.swift` owns the native ARKit session. ARView's scene-understanding debug overlay displays the structural mesh during capture. `ARMeshAnchor` geometry becomes the separate structural GLB.
- `Native/DepthSpaceCapture.swift` pairs each LiDAR depth sample with its camera color, transforms depth surfaces into AR world coordinates, and merges overlapping samples into a voxel grid.
- `Native/ObjToGlb.swift` writes the GLB, and also converts Object Capture's OBJ plus texture output for the photo path.
- `Native/GlbPreview.swift` reads the app's saved single-mesh GLB layout and renders it in RealityKit.
- `ScanArtifactProvider.cs` provides completed visual and structural GLBs to Ansight by scan UUID.
- `Native/BoulderCaptureBridge.swift` keeps the optional Object Capture flow and checks its USDZ by loading it with `Entity(contentsOf:)`.
- The native bridge is compiled into a static iOS library by `Native/build-ios.sh` and called from MAUI through C ABI exports.
- The generated MAUI splash storyboard is required for the modern iPhone's full-screen viewport.

## Verified on iPhone 16 Pro

- Signed debug app installed and launched under the Red-Point Apple team.
- Ansight connected and recorded a physical-device session.
- Photo scan captured 31 images, generated USDZ and GLB on device, and loaded USDZ in RealityKit. The resulting GLB had a valid glTF 2.0 header, mesh, and embedded texture.
- The full-screen launch screen changed the reported viewport from 320×480 to 402×874 points.
- A complete LiDAR scan exported 146,114 triangles to a valid GLB and loaded its mesh into a RealityKit preview. The newer live-overlay and colored-atlas build is installed for device validation.
