# CalendarBridge

CalendarBridge is a native macOS menu bar app that syncs events between calendars using EventKit.

## What it does
- Runs as a menu bar app (no main window)
- Syncs from a selected source calendar to a destination calendar
- Supports source type:
  - Apple Calendar (recommended, including Exchange calendars visible in macOS Calendar)
  - Outlook (legacy path)
- Optional **bidirectional** mode for Apple calendars
  - Edits sync both ways
  - Deletions sync only **Source → Destination** (source is protected)
- Sync window options: 7, 14, or 30 days
- Sync frequency: 1h, 4h, 12h, 24h
- Force sync from menu

## Requirements
- macOS 13+
- Calendar access granted
- If using Outlook source: Outlook for Mac + automation permission

## Build locally
```bash
xcodebuild \
  -project CalendarBridge.xcodeproj \
  -scheme CalendarBridge \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Open in Xcode:
```bash
open CalendarBridge.xcodeproj
```

---

## GitHub Releases (first releasable version)
This repo includes a GitHub Actions workflow to build release artifacts on tag push.

Workflow file:
- `.github/workflows/macos-release.yml`

Artifacts produced:
- `CalendarBridge-<tag>-macos-unsigned.dmg`
- `CalendarBridge-<tag>-macos-unsigned.zip`
- `SHA256SUMS.txt`

### Create a release
```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow will build and publish a GitHub pre-release with artifacts.

## Install (end users)
1. Download `.dmg` (recommended) or `.zip` from GitHub Releases.
2. Move `CalendarBridge.app` to `/Applications`.
3. First launch: right-click app, choose **Open**.

Note: this first public version is unsigned, so macOS may show a security prompt.

---

## Future stable distribution (recommended)
For frictionless install, add Apple Developer signing + notarization in a later release.
