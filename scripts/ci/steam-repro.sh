#!/usr/bin/env bash
# Reproduces Blockbottle's Steam setup on a macOS runner and reports crashes.
# Usage: steam-repro.sh <gptk|staging> <sync:on|off>
set -uo pipefail
ENGINE="$1"; SYNC="$2"
WORK="$PWD/repro-$ENGINE-$SYNC"; mkdir -p "$WORK"; cd "$WORK"

arch -x86_64 /usr/bin/true 2>/dev/null || softwareupdate --install-rosetta --agree-to-license >/dev/null

case "$ENGINE" in
  gptk)    URL=https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz ;;
  staging) URL=https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/wine-staging-11.18-osx64.tar.xz ;;
esac
curl -sSL "$URL" -o engine.tar.xz && tar -xf engine.tar.xz && rm engine.tar.xz
WINE="$(find "$PWD" -path '*/bin/wine64' -type f | head -1)"
[ -n "$WINE" ] || WINE="$(find "$PWD" -path '*/bin/wine' -type f | head -1)"
echo "WINE=$WINE"
"$WINE" --version || true

export WINEPREFIX="$WORK/prefix" WINEDEBUG=fixme-all
if [ "$SYNC" = on ]; then export WINEESYNC=1 WINEMSYNC=1; fi

run_for() {  # run_for <seconds> <log> <cmd...>
  local secs=$1 log=$2; shift 2
  "$@" >"$log" 2>&1 &
  local pid=$!
  for _ in $(seq "$secs"); do kill -0 $pid 2>/dev/null || break; sleep 1; done
  kill -0 $pid 2>/dev/null && echo "(still running after ${secs}s)"
  wait $pid 2>/dev/null; echo "exit=$?"
}

echo "=== wineboot"; run_for 300 wineboot.log "$WINE" wineboot --init; tail -5 wineboot.log
curl -sSL https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe -o SteamSetup.exe
echo "=== SteamSetup /S"; run_for 300 setup.log "$WINE" SteamSetup.exe /S; tail -5 setup.log
STEAM="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
ls "$STEAM" | head -30

echo "=== steam.exe (240s)"
run_for 240 steam.log "$WINE" "C:\\Program Files (x86)\\Steam\\steam.exe"
"$(dirname "$WINE")/wineserver" -k 2>/dev/null; sleep 2

echo "=== crashes"
grep -n -B3 -A25 "page fault\|Unhandled exception" steam.log | head -150 || echo "no crash lines"
echo "=== steam.log tail"; tail -60 steam.log
for f in bootstrap_log.txt webhelper.txt cef_log.txt stderr.txt; do
  [ -f "$STEAM/logs/$f" ] && { echo "=== Steam/logs/$f"; tail -40 "$STEAM/logs/$f"; }
done
ls -la "$STEAM" | head -40
