# CalendarBridge

CalendarBridge is a macOS menu bar app that keeps two calendars in sync.

It is designed for people who want events copied from one calendar to another automatically, without manual re-entry.

## What it does

- Runs from the macOS menu bar
- Syncs events between a selected **Source** and **Destination** calendar
- Supports Apple Calendar sources (including Exchange calendars visible in macOS Calendar)
- Optional **Bidirectional sync** for Apple calendars
- Lets you choose:
  - Sync frequency (1h, 4h, 12h, 24h)
  - Sync window (7, 14, 30 days)

### Sync rules

- **Create/Update** events sync based on your mode
- In **Bidirectional sync**, edits can flow both ways
- **Deletions sync only Source → Destination** (source is protected)

---

## Install

1. Open this repository’s **Releases** page.
2. Download the latest macOS build (`.dmg` recommended, `.zip` also available).
3. Install:
   - `.dmg`: drag `CalendarBridge.app` to **Applications**
   - `.zip`: unzip and move `CalendarBridge.app` to **Applications**
4. Open CalendarBridge from Applications.

---

## First launch (macOS security prompt)

If the app is unsigned, macOS may block first launch.

Use one of these:

- In Finder → Applications, right-click **CalendarBridge** → **Open**
- Or System Settings → **Privacy & Security** → **Open Anyway**

---

## Setup in the app

1. Grant **Calendar access** when prompted.
2. Choose your **Source calendar**.
3. Choose your **Destination calendar**.
4. (Optional) Enable **Bidirectional sync**.
5. Choose sync frequency and sync window.
6. Click **Sync Now** (or wait for scheduled sync).

---

## Run locally

Build and launch the app locally with:

```bash
./scripts/run-local.sh
```

Useful options:

- `./scripts/run-local.sh --debug` to build Debug instead of Release
- `./scripts/run-local.sh --signed` to allow code signing during the build

Because CalendarBridge is a menu bar app, it launches into the macOS menu bar rather than the Dock.

---

## Troubleshooting

### I do not see my calendars
- Make sure accounts are added in macOS Calendar
- Reopen CalendarBridge
- Confirm permission in System Settings → Privacy & Security → Calendars

### Events are not syncing
- Verify source and destination are correct
- Ensure source and destination are not the same calendar
- Check whether bidirectional mode is on/off as expected
- Trigger **Sync Now** once to test

### App won’t open
- Use the first-launch Gatekeeper steps above

---

## Privacy

CalendarBridge uses macOS Calendar/EventKit permissions to read and write only selected calendars.

- No CalendarBridge account required
- Data is processed locally by the app
- You can revoke access anytime in macOS privacy settings

---

## Uninstall

1. Quit CalendarBridge from the menu bar.
2. Delete `CalendarBridge.app` from Applications.
3. (Optional) Remove Calendar permission in macOS settings.

---

For maintainers/release automation docs, see `docs/RELEASE_SIGNING.md`.
