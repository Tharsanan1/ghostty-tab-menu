#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="Zellij Session Menu.app"
APP_DIR="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc \
  -O \
  -framework AppKit \
  "$ROOT_DIR/Sources/GhosttyTabMenu/main.swift" \
  -o "$APP_DIR/Contents/MacOS/GhosttyTabMenu"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "Built: $APP_DIR"
