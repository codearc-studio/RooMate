# RooMate

RooMate is an independent, unofficial student companion for macOS. It brings a student's school day into one native app: schedule context, dining, athletics, clubs, events, RooPAC planning, useful links, notifications, and lightweight menu-bar tools.

RooMate is an independent, unofficial student project. It is not an official school application and is not endorsed by or affiliated with the school. School-specific data and terminology are used only where needed to provide the companion experience.

## RooMate 6

Version 6 is the current macOS development line. The schedule is the shared backbone for the main window, Today view, sidebar NOW / UP NEXT context, menu-bar companion, floating timer, special schedules, clubs, and class notifications.

### Main experiences

- **Today** — current and next block, live progress, day overview, announcements, upcoming context, and contextual actions.
- **Schedule** — personalized Level 1–7 / Music schedule with Day, Week, and Semester Planner views, special-day overrides, club meetings, and selected sports game reminders.
- **Dining** — live menu dates, meal periods, stations, search/filtering, dietary and allergen tags, details, and favorites.
- **Sports** — source-backed games, filters/search, athletics calendar, schedule integration, and individual game reminders. Dedicated team pages are temporarily unavailable and can return in a later update.
- **Clubs** — remote club directory plus local My Clubs setup, Monday/Wednesday club periods, extra meetings, rooms/notes, and schedule integration.
- **Events** — school calendar feeds with source filtering, search, saved events, details, and Day/Week/Month calendar views.
- **PacTrack** — RooPAC requirement planning and activity tracking based on grade-level requirements.
- **Links** — built-in school/student resources plus favorites and custom links.
- **Profile & Settings** — identity, grade, appearance, schedule setup, notifications, sidebar customization, background behavior, and app preferences.

### macOS-native companion features

- Menu-bar companion with current block, progress, time remaining, Next Up, and the rest of the day.
- Optional always-on-top floating timer with compact mode and click-through support.
- Global Command-K search across app pages, configured classes, My Clubs, events, games, and loaded dining items.
- Optional Open at Login and keep-running-on-window-close behavior.
- Sparkle update integration for direct macOS distribution.

## Project layout

- `RooMate/` — macOS application source.
- `RooMate iOS/` — experimental iOS target; not feature-parity with the macOS app.
- `Assets.xcassets/` — shared macOS asset catalog.
- `RooMate.icon/` — Icon Composer source used by the macOS target.
- `Documentation/` — architecture and release/audit notes.
- `appcast.xml` — Sparkle update feed.

See `PROJECT_STRUCTURE.md` for the source map and `Documentation/V6_RELEASE_AUDIT.md` for the current release audit.

## Dependencies

- SwiftUI / AppKit
- Sparkle 2.9.5 or later within the 2.x line
- TelemetryDeck 2.14 or later within the 2.x line

The checked-in SwiftPM lock currently resolves Sparkle 2.9.6 and TelemetryDeck 2.14.0, both within the project's allowed 2.x package ranges. Keep `Package.resolved` committed with the release candidate so the tested dependency set stays reproducible.

RooMate also reads remote public/shared data sources used by its features, including calendar feeds, Google Sheets, and the dining provider's web data.

## Distribution status

RooMate 6.0.3 is the current release source. Its notarized universal archive contains bundle version 6.0.3, build 6, requires macOS 14 or later, and is represented by the matching signed item in `appcast.xml`. The earlier archive labeled RooMate 6.0.1 contains bundle version 6.0, build 4; that historical identity is preserved in the feed so Sparkle compares the actual released bundles correctly.

## Development note

RooMate contains several large SwiftUI feature files that are candidates for modularization after the V6 release. They were intentionally not mechanically split during the pre-release cleanup because doing so without a full macOS/Xcode type-check and UI regression pass would create unnecessary release risk.
