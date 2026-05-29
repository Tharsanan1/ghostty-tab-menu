#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Zellij Session Menu.app"
LEGACY_APP_NAME="Ghostty Tab Menu.app"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALL_APP="$INSTALL_DIR/$APP_NAME"
LEGACY_INSTALL_APP="$INSTALL_DIR/$LEGACY_APP_NAME"

if [[ -d "$INSTALL_APP" ]]; then
  rm -rf "$INSTALL_APP"
  echo "Removed: $INSTALL_APP"
else
  echo "Not installed at: $INSTALL_APP"
fi

if [[ -d "$LEGACY_INSTALL_APP" ]]; then
  rm -rf "$LEGACY_INSTALL_APP"
  echo "Removed: $LEGACY_INSTALL_APP"
fi

defaults delete local.ghostty-tab-menu pinnedZellijSessionNames 2>/dev/null || true
defaults delete local.ghostty-tab-menu pinnedGhosttyTabNames 2>/dev/null || true
