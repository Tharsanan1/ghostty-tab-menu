#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="Zellij Session Menu.app"
LEGACY_APP_NAME="Ghostty Tab Menu.app"
APP_DIR="$BUILD_DIR/$APP_NAME"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP="$INSTALL_DIR/$APP_NAME"
LEGACY_INSTALL_APP="$INSTALL_DIR/$LEGACY_APP_NAME"

"$ROOT_DIR/scripts/build.sh"

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_APP"
rm -rf "$LEGACY_INSTALL_APP"
cp -R "$APP_DIR" "$INSTALL_APP"

echo "Installed: $INSTALL_APP"
echo "Open it with:"
echo "  open \"$INSTALL_APP\""
