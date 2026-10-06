#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$script_dir/build/iphoneos"
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$output_dir"
mkdir -p "$output_dir/module-cache"

xcrun swiftc \
  -target arm64-apple-ios18.0 \
  -sdk "$sdk_path" \
  -swift-version 5 \
  -module-cache-path "$output_dir/module-cache" \
  -parse-as-library \
  -emit-library -static \
  -module-name BoulderCaptureBridge \
  -framework UIKit -framework SwiftUI -framework RealityKit -framework ARKit \
  "$script_dir/BoulderCaptureBridge.swift" \
  "$script_dir/SceneMeshCapture.swift" \
  "$script_dir/GlbPreview.swift" \
  "$script_dir/DepthSpaceCapture.swift" \
  "$script_dir/ObjToGlb.swift" \
  -o "$output_dir/libBoulderCaptureBridge.a"

symbols="$(xcrun nm -gU "$output_dir/libBoulderCaptureBridge.a")"
[[ "$symbols" == *"_BoulderCapture_Present"* ]]
[[ "$symbols" == *"_BoulderCapture_IsSupported"* ]]
[[ "$symbols" == *"_SceneMesh_Present"* ]]
[[ "$symbols" == *"_SceneMesh_PresentWithQuality"* ]]
[[ "$symbols" == *"_SceneMesh_PresentGlb"* ]]
