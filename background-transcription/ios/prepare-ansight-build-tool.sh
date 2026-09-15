#!/bin/sh
set -eu

project_directory="${PROJECT_DIR:-$(pwd)}"
configuration="${CONFIGURATION:-Debug}"
sdk_package_path="$project_directory/../../../ansight-sdk/src/ios"
scratch_path="$project_directory/Build/ansight-host-tool"
destination_directory="$project_directory/Build/Products/$configuration"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"

case "$configuration" in
    Release)
        swift_configuration="release"
        ;;
    *)
        swift_configuration="debug"
        ;;
esac

SDKROOT="$macos_sdk" swift build \
    --package-path "$sdk_package_path" \
    --product AnsightBuildTool \
    --configuration "$swift_configuration" \
    --scratch-path "$scratch_path"

mkdir -p "$destination_directory"
cp "$scratch_path/$swift_configuration/AnsightBuildTool" "$destination_directory/AnsightBuildTool"
