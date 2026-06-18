#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_PRODUCT_NAME="DynamicIsland"
APP_DISPLAY_NAME="Dynamic Island"
BUNDLE_ID="cx.dynamicisland.mvp"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CODESIGN_IDENTITY="${DYNAMIC_ISLAND_CODESIGN_IDENTITY:-${ISLAND_CODESIGN_IDENTITY:-}}"
DEBUG_MUSIC_SIGNAL_FILE="${ISLAND_DEBUG_MUSIC_SIGNAL_FILE:-/tmp/dynamic-island-music-signal.json}"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk -F '"' '/valid identities found/ { next } /"/ { print $2; exit }'
  )"
fi

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="-"
fi

pkill -x "$APP_PRODUCT_NAME" >/dev/null 2>&1 || true

swift build --product "$APP_PRODUCT_NAME"
BUILD_BINARY="$(swift build --show-bin-path)/$APP_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Dynamic Island checks Music and Spotify playback state to show compact playback indicators.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
codesign -dv "$APP_BUNDLE" >/dev/null 2>&1

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_debug_music_signal_app() {
  mkdir -p "$(dirname "$DEBUG_MUSIC_SIGNAL_FILE")"
  if [[ ! -f "$DEBUG_MUSIC_SIGNAL_FILE" ]]; then
    printf '{"isPlaying":true,"title":"Debug Track","artist":"Signal Preview","direction":null,"progress":0}\n' >"$DEBUG_MUSIC_SIGNAL_FILE"
  fi
  /usr/bin/open -n "$APP_BUNDLE" --env ISLAND_DEBUG_MUSIC_SIGNAL_FILE="$DEBUG_MUSIC_SIGNAL_FILE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_PRODUCT_NAME\""
    ;;
  --debug-music-signal|debug-music-signal)
    open_debug_music_signal_app
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_PRODUCT_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--debug-music-signal|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
