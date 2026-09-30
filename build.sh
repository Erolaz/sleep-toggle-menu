#!/bin/bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")" && pwd)"
output_dir="$(dirname "$source_dir")"
app_path="$output_dir/Sleep Toggle Menu.app"
build_dir="${SLEEP_TOGGLE_BUILD_DIR:-$(mktemp -d /private/tmp/sleep-toggle-menu-build.XXXXXX)}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$build_dir/cache"
sdk_path="$(xcrun --show-sdk-path)"
xcrun swiftc -sdk "$sdk_path" -module-cache-path "$build_dir/cache" -framework AppKit \
    "$source_dir/make-icon.swift" -o "$build_dir/make-icon"
"$build_dir/make-icon" "$build_dir/AppIcon.iconset"
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
cp "$build_dir/AppIcon.iconset/icon_512x512@2x.png" "$output_dir/Sleep Toggle Menu Icon.png"
cp "$source_dir/install-permission.sh" "$app_path/Contents/Resources/install-permission.sh"
chmod 644 "$app_path/Contents/Resources/install-permission.sh"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -O -sdk "$sdk_path" \
        -target "${arch}-apple-macosx13.0" -module-cache-path "$build_dir/cache" \
        -framework AppKit "$source_dir/main.swift" -o "$build_dir/SleepToggleMenu-$arch"
done
lipo -create "$build_dir/SleepToggleMenu-arm64" "$build_dir/SleepToggleMenu-x86_64" \
    -output "$app_path/Contents/MacOS/SleepToggleMenu"
cp "$source_dir/Info.plist" "$app_path/Contents/Info.plist"
chmod 755 "$app_path/Contents/MacOS/SleepToggleMenu"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
"$app_path/Contents/MacOS/SleepToggleMenu" --self-test
ditto -c -k --keepParent "$app_path" "$output_dir/Sleep Toggle Menu.zip"
printf 'Built: %s\nTemporary build cache: %s\n' "$app_path" "$build_dir"
