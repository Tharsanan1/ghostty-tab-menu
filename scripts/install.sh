#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="Ghostty Tab Menu.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP="$INSTALL_DIR/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc \
  -O \
  -framework AppKit \
  "$ROOT_DIR/Sources/GhosttyTabMenu/main.swift" \
  -o "$APP_DIR/Contents/MacOS/GhosttyTabMenu"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP"
cp -R "$APP_DIR" "$INSTALL_APP"

echo "Installed: $INSTALL_APP"
echo "Open it with:"
echo "  open \"$INSTALL_APP\""
