#!/usr/bin/env bash
# Packs build/Blockbottle.app into build/Blockbottle.dmg. Run after build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="build/dmg"
DMG="build/Blockbottle.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Blockbottle.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Packaging/README-FIRST.txt "$STAGE/"
hdiutil create -volname Blockbottle -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Built $DMG"
