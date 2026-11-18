#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Applications/VPNTrafficBar.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

mkdir -p "$MACOS"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

clang \
  -fobjc-arc \
  -mmacosx-version-min=14.0 \
  -O2 \
  -framework Foundation \
  -framework AppKit \
  -framework WebKit \
  -lsqlite3 \
  "$ROOT/src/TrafficDB.m" \
  "$ROOT/src/Fetcher.m" \
  "$ROOT/src/DashboardHTML.m" \
  "$ROOT/src/LocalClashTracker.m" \
  "$ROOT/src/main.m" \
  -o "$MACOS/VPNTrafficBar"

echo "Built: $APP_DIR"
