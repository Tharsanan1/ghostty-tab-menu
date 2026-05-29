# Ghostty Tab Menu

Small macOS menu bar helper for switching between Ghostty tabs.

## Behavior

- Shows only a menu bar icon.
- Lists current Ghostty tabs when the icon is clicked.
- Opens a selected tab by Ghostty window id and tab index.
- Lets you pin tab names so live matching tabs appear at the top.
- Keeps pinned names even when the tab is temporarily missing.

## Install

```bash
./scripts/install.sh
open "$HOME/Applications/Ghostty Tab Menu.app"
```

The first time it talks to Ghostty, macOS may ask for Automation permission.
Allow access so the helper can read and focus Ghostty tabs.

## Uninstall

```bash
./scripts/uninstall.sh
```
