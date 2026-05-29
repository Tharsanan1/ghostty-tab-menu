# Zellij Session Menu

Small macOS menu bar helper for jumping to Ghostty tabs that are running Zellij sessions.

## Behavior

- Shows only a menu bar icon.
- Lists current Zellij sessions when the icon is clicked.
- Focuses the Ghostty tab that matches the selected active Zellij session.
- Marks exited sessions and sessions that are not currently open in a Ghostty tab.
- Lets you pin session names so matching sessions appear at the top.
- Keeps pinned names even when the session is temporarily missing.

## Install

```bash
./scripts/install.sh
open "$HOME/Applications/Zellij Session Menu.app"
```

The first time it talks to Ghostty, macOS may ask for Automation permission.
Allow access so the helper can read and focus Ghostty tabs. The app also needs
`zellij` to be available from your login shell path.

## Uninstall

```bash
./scripts/uninstall.sh
```
