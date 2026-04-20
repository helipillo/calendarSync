# CalendarBridge

A macOS menu bar app that syncs calendar events from one calendar to another. Useful for mirroring work calendar events into a personal calendar.

## Install

1. Download the latest build from the Releases page (`.dmg` or `.zip`).
2. Move `CalendarBridge.app` to Applications.
3. If macOS blocks the app, right-click it in Applications and choose **Open**, or go to **System Settings → Privacy & Security → Open Anyway**.

## Run

```bash
./scripts/run-local.sh
```

Options:
- `./scripts/run-local.sh --debug` — build Debug instead of Release
- `./scripts/run-local.sh --signed` — allow code signing

CalendarBridge runs in the macOS menu bar, not the Dock.
