# AGENTS.md

## Project
CalendarBridge is a native macOS menu bar app in SwiftUI that syncs calendar events into a selected Apple Calendar.

Project root:
- `/Users/daniel.sanchezotero/Documents/personal/projects/calendar-sync`

Xcode project:
- `CalendarBridge.xcodeproj`

## Current direction
Do **not** continue investing in Outlook HxStore reverse-engineering as the primary path.

### Required pivot
The user has their **work Exchange account already added to macOS Internet Accounts / Apple Calendar**.
The app should now be evolved to support:
- **source**: Apple Calendar, including Exchange-backed calendars visible in EventKit
- **destination**: personal Apple Calendar

Primary use case:
- copy upcoming work events into a personal calendar so they are visible on devices that do not have the work account

## Mandatory product constraints
- Keep the app **native macOS**
- Keep it as a **menu bar app**
- Keep sync limited to the **next 7 days**
- Keep **sync frequency** options: 1h, 4h, 12h, 24h
- Keep **Force Update**
- Only update/remove events created by CalendarBridge

## Important caution
Prevent sync loops.

When implementing Apple Calendar source mode:
- do not allow source and destination to be the same calendar
- ignore CalendarBridge-mirrored events when reading source events
- preserve the existing note marker approach for reconciliation

Marker currently used in notes:
- `[CalendarBridge source=...]`

## Recommended next steps
1. Read `HANDOFF_NEXT_AGENT.md`
2. Inspect these files first:
   - `CalendarBridge/App/AppState.swift`
   - `CalendarBridge/Models/AppSettings.swift`
   - `CalendarBridge/Models/CalendarModels.swift`
   - `CalendarBridge/Services/AppleCalendarService.swift`
   - `CalendarBridge/Services/SyncEngine.swift`
   - `CalendarBridge/Views/SyncConfigurationView.swift`
3. Add a source type selector:
   - Apple Calendar
   - Outlook
4. Implement Apple Calendar source fetching through EventKit
5. Refactor sync engine to support Apple source
6. Build and test with `xcodebuild`

## Suggested implementation shape
- Introduce a source-agnostic event model, for example `SyncEventRecord`
- Keep Outlook code around, but Apple Calendar source should become the preferred path
- `AppleCalendarService` should expose:
  - readable source calendars
  - writable destination calendars
  - source event fetching in the next 7 days

## Known background
The app currently contains:
- Outlook JXA automation
- HxStore fallback
- debug logging
- next-7-days sync scope
- note-marker-based mirrored event matching

The HxStore path proved unreliable because Outlook cache records can bundle multiple meetings and expose incomplete timestamps.

## Build
```bash
xcodebuild -project CalendarBridge.xcodeproj -scheme CalendarBridge -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

Open in Xcode:
```bash
open CalendarBridge.xcodeproj
```

## Recent handoff commit
- `cbe80fd` Add handoff for Apple Calendar source pivot
