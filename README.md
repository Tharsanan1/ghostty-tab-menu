# Zellij Session Menu

Small macOS menu bar helper for jumping to Ghostty tabs that are running Zellij sessions.

## Behavior

- Shows only a menu bar icon.
- Lists current active Zellij sessions when the icon is clicked.
- Focuses the Ghostty tab that matches the selected active Zellij session.
- Opens a new Ghostty tab and attaches to the selected session when no matching tab is open.
- Lets each session save links such as issues, pull requests, CI runs, and docs.
- Opens saved session links in Google Chrome individually or all at once.
- Polls saved GitHub PR links every 30 seconds with `gh` and notifies when PR activity changes.
- Marks sessions with unread PR activity until the changed PR link is opened or cleared.
- Lets you pin session names so matching sessions appear at the top.
- Keeps pinned names even when the session is temporarily missing.

## Build and Run

```bash
./scripts/build.sh
open "./build/Zellij Session Menu.app"
```

The first time it talks to Ghostty, macOS may ask for Automation permission.
Allow access so the helper can read and focus Ghostty tabs. The app also needs
`zellij` to be available from your login shell path.

## Links

Copy one URL, or multiple comma- or newline-separated URLs, open a session
submenu, then choose "Add Link from Clipboard".
Saved links are stored locally in user defaults and keyed by Zellij session name.

Saved GitHub PR links are checked with the authenticated `gh` CLI. The first
check records a quiet baseline; later checks notify with the session name when a
PR gets new activity such as comments, reviews, approvals, requested changes,
commits, merges, or state changes.

## Install

```bash
./scripts/install.sh
open "$HOME/Applications/Zellij Session Menu.app"
```

## Uninstall

```bash
./scripts/uninstall.sh
```
