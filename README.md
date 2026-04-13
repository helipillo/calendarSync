# CalendarBridge

Native macOS menu bar app built with SwiftUI that syncs one Microsoft Outlook calendar into a selected Apple Calendar.

## Features
- Menu bar app with native SwiftUI UI
- Select Outlook source calendar
- Select Apple Calendar destination calendar
- Choose sync frequency: 1h, 4h, 12h, 24h
- Force update button
- Automatic scheduled sync
- Syncs through macOS automation for Outlook and EventKit for Apple Calendar
- Mirrors recurring rules when Outlook exposes valid iCalendar recurrence data

## Requirements
- macOS 13+
- Microsoft Outlook for Mac installed
- Apple Calendar access granted
- Automation permission granted so the app can control Outlook

## Open in Xcode
```bash
open CalendarBridge.xcodeproj
```

## Build from terminal
```bash
xcodebuild -project CalendarBridge.xcodeproj -scheme CalendarBridge -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Notes
- Recommended destination is a dedicated Apple Calendar like `Work Outlook Mirror`.
- The app tracks events it created and updates or removes only those mirrored events.
- Very complex recurring exceptions or edge cases from Outlook may still need future refinement.
