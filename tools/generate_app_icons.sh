#!/usr/bin/env bash
# Regenerates the iOS app icon set from the master artwork.
#
# Renders tools/make_app_icon.swift at 1024x1024, then downsamples it into every
# size ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json declares.
#
# Usage: tools/generate_app_icons.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
iconset="$repo_root/taxi_game/ios/Runner/Assets.xcassets/AppIcon.appiconset"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

master="$build_dir/icon-1024.png"

echo "Building renderer..."
swiftc -O -o "$build_dir/make_app_icon" "$repo_root/tools/make_app_icon.swift"
"$build_dir/make_app_icon" "$master"

# Launch-screen mark: taxi alone on transparency, composited by the storyboard
# over its asphalt background.
mark="$build_dir/mark.png"
"$build_dir/make_app_icon" "$mark" --mark
launchset="$repo_root/taxi_game/ios/Runner/Assets.xcassets/LaunchImage.imageset"
for entry in "LaunchImage.png:200" "LaunchImage@2x.png:400" "LaunchImage@3x.png:600"; do
    sips -z "${entry##*:}" "${entry##*:}" "$mark" --out "$launchset/${entry%%:*}" >/dev/null
done

# filename:pixel-size — mirrors Contents.json. Two entries share 120px
# (40pt @3x and 60pt @2x); both files must exist.
sizes="
Icon-App-20x20@1x.png:20
Icon-App-20x20@2x.png:40
Icon-App-20x20@3x.png:60
Icon-App-29x29@1x.png:29
Icon-App-29x29@2x.png:58
Icon-App-29x29@3x.png:87
Icon-App-40x40@1x.png:40
Icon-App-40x40@2x.png:80
Icon-App-40x40@3x.png:120
Icon-App-60x60@2x.png:120
Icon-App-60x60@3x.png:180
Icon-App-76x76@1x.png:76
Icon-App-76x76@2x.png:152
Icon-App-83.5x83.5@2x.png:167
Icon-App-1024x1024@1x.png:1024
"

echo "Writing icons to $iconset"
for entry in $sizes; do
    name="${entry%%:*}"
    px="${entry##*:}"
    sips -z "$px" "$px" "$master" --out "$iconset/$name" >/dev/null
    printf '  %-28s %sx%s\n' "$name" "$px" "$px"
done

# The marketing icon must carry no alpha channel; Apple rejects uploads that do.
alpha="$(sips -g hasAlpha "$iconset/Icon-App-1024x1024@1x.png" | awk '/hasAlpha/ {print $2}')"
if [ "$alpha" != "no" ]; then
    echo "ERROR: marketing icon has an alpha channel" >&2
    exit 1
fi

echo "Done. Marketing icon alpha: $alpha"
