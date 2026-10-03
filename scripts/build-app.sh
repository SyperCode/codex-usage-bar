#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
app_name="Codex Usage Bar"
bundle_dir="$project_dir/dist/$app_name.app"
contents_dir="$bundle_dir/Contents"
arm_build="$project_dir/.build/arm64"
intel_build="$project_dir/.build/x86_64"
asset_catalog="$project_dir/.build/GeneratedAssets.xcassets"
app_icon_set="$asset_catalog/AppIcon.appiconset"

cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.build/module-cache"

swift build \
    --disable-sandbox \
    --scratch-path "$arm_build" \
    --cache-path "$project_dir/.build/cache" \
    -c release \
    --arch arm64 \
    --product CodexUsageBar

swift build \
    --disable-sandbox \
    --scratch-path "$intel_build" \
    --cache-path "$project_dir/.build/cache" \
    -c release \
    --arch x86_64 \
    --product CodexUsageBar

arm_bin_dir="$(swift build --scratch-path "$arm_build" --cache-path "$project_dir/.build/cache" -c release --arch arm64 --show-bin-path)"
intel_bin_dir="$(swift build --scratch-path "$intel_build" --cache-path "$project_dir/.build/cache" -c release --arch x86_64 --show-bin-path)"

rm -rf "$bundle_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"

xcrun lipo -create \
    "$arm_bin_dir/CodexUsageBar" \
    "$intel_bin_dir/CodexUsageBar" \
    -output "$contents_dir/MacOS/CodexUsageBar"
cp "Supporting/Info.plist" "$contents_dir/Info.plist"

rm -rf "$asset_catalog"
mkdir -p "$app_icon_set"
sips -z 16 16 "Assets/AppIcon.png" --out "$app_icon_set/icon_16x16.png" >/dev/null
sips -z 32 32 "Assets/AppIcon.png" --out "$app_icon_set/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "Assets/AppIcon.png" --out "$app_icon_set/icon_32x32.png" >/dev/null
sips -z 64 64 "Assets/AppIcon.png" --out "$app_icon_set/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "Assets/AppIcon.png" --out "$app_icon_set/icon_128x128.png" >/dev/null
sips -z 256 256 "Assets/AppIcon.png" --out "$app_icon_set/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "Assets/AppIcon.png" --out "$app_icon_set/icon_256x256.png" >/dev/null
sips -z 512 512 "Assets/AppIcon.png" --out "$app_icon_set/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "Assets/AppIcon.png" --out "$app_icon_set/icon_512x512.png" >/dev/null
cp "Assets/AppIcon.png" "$app_icon_set/icon_512x512@2x.png"
cp "Supporting/AppIconContents.json" "$app_icon_set/Contents.json"

xcrun actool "$asset_catalog" \
    --compile "$contents_dir/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$project_dir/.build/AppIcon-Info.plist"

codesign --force --deep --sign - "$bundle_dir"

echo "$bundle_dir"
