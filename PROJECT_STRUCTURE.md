# RooMate Project Structure

The macOS target uses Xcode file-system-synchronized groups, so most source folders on disk appear directly in Xcode.

```text
RooMate/
├── RooMate.xcodeproj/
├── Assets.xcassets/                  # Shared/macOS visual assets
├── RooMate.icon/                     # Icon Composer source
├── appcast.xml                       # Sparkle feed
├── README.md
├── CURRENT_BUILD_NOTES.txt
├── PROJECT_STRUCTURE.md
├── Documentation/
│   ├── V6_RELEASE_AUDIT.md
│   └── PacTrack/
├── RooMate/                          # macOS target
│   ├── App/
│   │   ├── ContentView.swift         # Main shell/sidebar + onboarding
│   │   ├── RooMateApp.swift          # App/scene lifecycle + commands
│   │   ├── RooMateMenuBar.swift      # Menu bar + floating timer
│   │   └── RooMateSearchSheet.swift  # Global Command-K search
│   ├── Core/
│   │   ├── BellSchedule.swift
│   │   ├── ClubDirectoryService.swift
│   │   ├── DesignTokens.swift
│   │   ├── Models.swift
│   │   ├── RemoteAnnouncementService.swift
│   │   ├── RemoteSpecialScheduleService.swift
│   │   ├── TelemetryTracker.swift
│   │   ├── UIHelpers.swift
│   │   └── UserScheduleStore.swift   # Shared user/schedule state + persistence
│   ├── Features/
│   │   ├── Clubs/
│   │   ├── Dashboard/
│   │   ├── Dining/
│   │   ├── Events/
│   │   ├── Links/
│   │   ├── PacTrack/
│   │   ├── Profile/
│   │   ├── Schedule/
│   │   ├── Settings/
│   │   └── Sports/
│   ├── Info.plist
│   └── RooMate.entitlements
└── RooMate iOS/                      # Experimental iOS target
    ├── Assets.xcassets/
    ├── ContentView.swift
    ├── RooMate_iOSApp.swift
    └── SettingsView_iOS.swift
```

## State ownership

`UserScheduleStore.shared` is the single app-lifetime source for user schedule/profile/preferences used by the main macOS UI, menu-bar companion, floating timer, and status controller. Avoid creating production `UserScheduleStore()` instances in feature views.

Feature-specific remote stores own their own data domains:

- `SportsStore` — athletics schedule/game data + My Team reminders.
- `EventsStore` — ICS event feeds and source-specific caches.
- `MenuStore` / `MenuService` — dining index/menu loading and cache behavior.
- `ClubDirectoryStore` — remote club directory.
- `RemoteSpecialScheduleService` — date-specific special schedules.
- `RemoteAnnouncementService` — lightweight in-app announcements.

## V6 / V7 boundary

RooMate V6 Schedule ships Day, Week, and Semester Planner modes. Semester Planner is the one-semester-ahead class planning tool; the separate, larger Study Planner concept remains V7 work.
