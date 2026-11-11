#!/bin/sh
# Builds the universal (Apple silicon + Intel) Release and packs it into dist/DChimera-<version>.dmg,
# the file the in-app updater downloads from GitHub Releases. The version comes from project.yml (MARKETING_VERSION).
#   scripts/release-macos.sh
set -eu
cd "$(dirname "$0")/.."
VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
echo "Building DChimera $VERSION (arm64 + x86_64)…"
xcodegen generate >/dev/null
xcodebuild -project DChimera.xcodeproj -scheme DChimera -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet
APP=build/Build/Products/Release/DChimera.app
BUILT=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$BUILT" = "$VERSION" ] || { echo "Built version is $BUILT, expected $VERSION" >&2; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/DChimera.app"
ln -s /Applications "$STAGE/Applications"
sed "s/{VERSION}/$VERSION/g" scripts/dmg/how-to-open.txt > "$STAGE/Как открыть — How to open.txt"
mkdir -p dist
hdiutil create -volname DChimera -srcfolder "$STAGE" -ov -format UDZO "dist/DChimera-$VERSION.dmg" >/dev/null
echo "dist/DChimera-$VERSION.dmg"
