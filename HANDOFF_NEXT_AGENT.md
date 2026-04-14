# CalendarBridge handoff for next agent

## Project location
`/Users/daniel.sanchezotero/Documents/personal/projects/calendar-sync`

## Current goal
Pivot CalendarBridge away from Outlook/HxStore as the primary source.

### New required behavior
The user has their **work Exchange account already added to macOS Internet Accounts / Apple Calendar**.
They still need the app because they want to **copy events from the work calendar into a personal Apple calendar**, so the events appear on devices where the work account is unavailable.

### Recommended new architecture
Use **Apple Calendar as both source and destination**:
- **Source**: any readable Apple Calendar, especially the Exchange-backed work calendar already present on the Mac
- **Destination**: a writable personal Apple Calendar
- Continue syncing only the **next 7 days**
- Continue using the existing mirrored-event marker in notes so only app-created events are updated/deleted

Outlook/HxStore can remain as legacy or fallback code, but should no longer be the main path.

---

## What exists already
This is a native macOS menu bar app using:
- SwiftUI `MenuBarExtra`
- EventKit for Apple Calendar access
- Outlook JXA automation
- HxStore fallback parser for Outlook local cache

### Main files
- `CalendarBridge/App/CalendarBridgeApp.swift`
- `CalendarBridge/App/AppState.swift`
- `CalendarBridge/Models/AppSettings.swift`
- `CalendarBridge/Models/CalendarModels.swift`
- `CalendarBridge/Models/OutlookFetchResult.swift`
- `CalendarBridge/Services/AppleCalendarService.swift`
- `CalendarBridge/Services/OutlookScriptService.swift`
- `CalendarBridge/Services/HxStoreFallbackService.swift`
- `CalendarBridge/Services/SyncEngine.swift`
- `CalendarBridge/Views/MenuBarContentView.swift`
- `CalendarBridge/Views/SettingsView.swift`
- `CalendarBridge/Views/SyncConfigurationView.swift`
- `CalendarBridge/Resources/hxstore_extract.py`

### Recent commits
- `4f7359f` Add HxStore format 416 meeting extraction
- `b77237c` Normalize HxStore times to meeting quarter-hour boundaries
- `b89de0c` Stop relying on stale EventKit identifiers
- `5dc13e6` Adjust HxStore timing and add source preview logging
- `2d8dcbb` Add sync debug log and fix picker warnings
- `d20f5dc` Limit sync scope to next 7 days
- `f316d2f` Add HxStore fallback for Outlook calendar sync
- `6625213` Improve empty Outlook sync diagnostics
- `8ca3b32` Initial CalendarBridge menu bar app

Current working tree was clean before writing this handoff note.

---

## Why the pivot is needed
Outlook automation can list calendars but often returns zero events.
HxStore fallback partially works, but it is not reliable enough.

Observed issues with HxStore path:
- many meetings missing
- proprietary undocumented storage
- some records bundle multiple meetings in one blob
- date coverage inconsistent
- timing needed heuristic correction
- not a robust long-term solution

User agreed this is not a solid direction.

---

## Important current code behavior

### Sync window
The app currently syncs only the **upcoming 7 days** via:
- `SyncWindow.upcomingSevenDays()` in `CalendarBridge/Models/CalendarModels.swift`

### Mirrored event matching
The app no longer relies on stale EventKit event IDs.
It matches mirrored events by a marker stored in notes:
- marker format: `[CalendarBridge source=...]`

Relevant methods in `AppleCalendarService.swift`:
- `mirroredEventIdentifiers(destinationCalendarID:window:)`
- `removeMirroredEventsNotIn(destinationCalendarID:window:validSourceKeys:)`
- `removeMirroredEventsOutsideWindow(destinationCalendarID:window:)`
- `upsertEvent(record:destinationCalendarID:existingEventID:)`

This matching strategy should be reused for the Apple-to-Apple source sync.

### Current model naming is Outlook-specific
`OutlookEventRecord` is the current generic-ish event payload, but it is Outlook-named.
For the pivot, consider renaming or replacing it with a source-agnostic model, for example:
- `SyncEventRecord`

Current `sourceKey` format in `CalendarBridge/Models/CalendarModels.swift` is:
- `outlook:<sourceCalendarID>:<base>`

For Apple-source sync, use something like:
- `apple:<sourceCalendarID>:<eventIdentifier or calendarItemIdentifier>`

Be careful to choose a stable enough source key for Apple Calendar events.

---

## Recommended implementation plan

### 1. Add source-type support to settings
Update `AppSettings.swift` with a source kind enum, for example:
- `.appleCalendar`
- `.outlook`

Expected fields to add:
- `sourceType`
- `selectedSourceAppleCalendarID`
- keep `selectedOutlookCalendarID` only if preserving Outlook mode
- keep `selectedAppleCalendarID` as destination calendar ID

Update `isConfigured` to depend on selected source type.

### 2. Add source calendar loading from EventKit
`AppleCalendarService.swift` already has `fetchWritableCalendars()`.
Add a new method for readable source calendars, likely all event calendars, for example:
- `fetchReadableCalendars() -> [AppleCalendarRef]`

You may want to differentiate source calendars in UI, maybe by `sourceTitle` and `title`.
The Exchange work calendar should appear here via EventKit if the account is present in macOS Internet Accounts.

### 3. Add Apple Calendar source event fetch
In `AppleCalendarService.swift`, add a method like:
- `fetchEvents(calendarID: String, window: SyncWindow) -> [SyncEventRecord]`

It should:
- read events from the chosen source calendar in the 7-day window
- skip events that were mirrored by CalendarBridge into the destination to avoid loops if user ever points source at destination
- map EventKit events into the generic sync record
- preserve title, start, end, all-day, location, notes if useful
- optionally skip declined/cancelled entries if EventKit exposes enough data, but not required for first pass

### 4. Make the sync engine source-agnostic
`SyncEngine.swift` currently depends directly on `OutlookScriptService.fetchEvents(...)`.
Refactor so it can fetch from either:
- Apple Calendar source
- Outlook source

Clean approach:
- introduce a protocol like `CalendarSourceService`
- or simpler, branch in `AppState.syncNow()` / `SyncEngine.sync(...)` based on `settings.sourceType`

For the new user need, Apple-source path is the priority.

### 5. Update UI
Files to update:
- `CalendarBridge/Views/SyncConfigurationView.swift`
- `CalendarBridge/Views/MenuBarContentView.swift`
- `CalendarBridge/Views/SettingsView.swift`
- possibly `CalendarBridge/App/AppState.swift`

UI changes needed:
- add **Source Type** picker: `Apple Calendar` or `Outlook`
- if Apple Calendar source selected:
  - show source Apple calendar picker
- if Outlook source selected:
  - show current Outlook source picker
- destination remains Apple Calendar picker

Recommended text update:
- stop describing app as only Outlook-to-Apple
- describe it as syncing from either Outlook or an Apple/Exchange calendar into a personal Apple calendar

### 6. AppState changes
`AppState.swift` currently stores:
- `outlookCalendars`
- `appleCalendars`

Likely add:
- `sourceAppleCalendars`
- keep `appleCalendars` as writable destination calendars, or rename clearly

Also update:
- `selectedOutlookCalendarName()`
- `selectedAppleCalendarName()`
- add `selectedSourceCalendarName()` and `selectedDestinationCalendarName()`

Refresh flow should likely be:
- request calendar access
- load readable Apple source calendars
- load writable Apple destination calendars
- optionally load Outlook calendars only if Outlook mode is selected, or still always load

### 7. Keep current cleanup behavior
Keep deletion/update limited to the same 7-day window.
This was explicitly requested by the user.

---

## Suggested minimal first version of the pivot
If you want the fastest solid result, do this first:
- implement **only Apple Calendar source mode**
- leave Outlook code present but unused
- let user pick:
  - source Apple calendar, including Exchange work calendar
  - destination personal Apple calendar
  - sync frequency
  - force update

This is probably enough to solve the user problem cleanly.
You can keep Outlook mode as a later optional source.

---

## Known UX notes from user feedback
- User liked the current app UI and menu bar behavior
- User wants background visibility, so keep or improve debug logging
- User specifically asked for only next 7 days, not full history
- User confirmed their Exchange account is already present in Apple Internet Accounts on Mac
- Main need is that events appear in a personal calendar for cross-device visibility

---

## Build command
```bash
xcodebuild -project CalendarBridge.xcodeproj -scheme CalendarBridge -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Open project:
```bash
open CalendarBridge.xcodeproj
```

---

## Recommended next agent message to user
Something like:
- "I’m pivoting the app to use your Exchange calendar through Apple Calendar as the source and your personal calendar as the destination. That should be much more reliable than Outlook cache parsing. I’ll wire the new source picker and keep the 7-day sync window."

---

## Caution
If implementing Apple-to-Apple sync, avoid infinite loops and accidental self-sync:
- do not allow source and destination to be the same calendar
- or at minimum short-circuit and show a clear error
- ignore CalendarBridge-mirrored events when reading source events

That is the most important correctness rule for this pivot.
