#!/usr/bin/env bash
# Builds build/Blockbottle.app (arm64, ad-hoc signed). Run on macOS.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP="build/Blockbottle.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Blockbottle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Blockbottle"
sed "s/<string>0.1.0<\/string>/<string>${VERSION}<\/string>/" Packaging/Info.plist > "$APP/Contents/Info.plist"
cp Packaging/Monocraft.ttf Packaging/Monocraft-LICENSE.txt "$APP/Contents/Resources/"

# App icon from the 1024px master.
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Packaging/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Packaging/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP"
