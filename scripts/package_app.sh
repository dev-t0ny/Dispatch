#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Dispatch.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
PLIST_PATH="$APP_DIR/Contents/Info.plist"
TEMPLATE_PLIST="$ROOT_DIR/packaging/Info.plist"
RELEASE_BIN="$ROOT_DIR/.build/arm64-apple-macosx/release/Dispatch"
ZIP_PATH="$DIST_DIR/Dispatch-macos.zip"

mkdir -p "$DIST_DIR"

swift build -c release --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$RELEASE_BIN" "$MACOS_DIR/Dispatch"
cp "$TEMPLATE_PLIST" "$PLIST_PATH"

codesign --force --sign - "$APP_DIR"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

printf "Built app bundle: %s\n" "$APP_DIR"
printf "Built zip archive: %s\n" "$ZIP_PATH"
