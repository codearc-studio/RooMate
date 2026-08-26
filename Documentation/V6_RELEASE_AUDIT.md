# RooMate V6 — Full Pre-Release Audit

Audit target: **RooMate 6.0.2 (build 5)**, macOS target `com.codearc.RooMate`.

This pass audited the complete uploaded project rather than a single feature. It covered source organization, app/state lifecycle, persistence, schedule logic, live-data services/parsers, notification budgeting, sidebar/layout behavior, onboarding, search, menu-bar/floating-window behavior, asset/project metadata, iOS target hygiene, Sparkle metadata, release configuration, and repository cleanup.

## Major fixes applied

### Shared state and lifecycle

- Production user/schedule state now uses one app-lifetime `UserScheduleStore.shared` across the main window, menu bar, floating timer, and status controller.
- Store teardown cancels outstanding refresh/notification work.
- The main scene has a stable WindowGroup ID so menu-bar actions can recreate/open the app window before navigating.
- Dock reopen and close-vs-quit behavior were tightened.
- Reset is batched to avoid a cascade of redundant saves and notification rebuilds.

### Schedule and notifications

- V6 exposes Day, Week, and Plan, including Semester Planner. Study Planner remains deferred to V7+.
- Main-window minimum is 1040×680 to keep sidebar/detail layouts usable.
- Special schedules flow through Today, Schedule, sidebar context, menu bar, floating timer, and class notifications.
- Additional/after-school My Clubs meetings participate in schedule, menu-bar, timer, and class-style notification resolution.
- Primary class blocks win when an extra club meeting overlaps a normal class.
- Schedule notification requests are capped at 48; individually saved Sports game reminders are capped at 12 to leave app-wide headroom.
- Fresh/reset notification state remains off until the user opts in.

### Sports

- Removed the unreachable mock/legacy Sports model/view stack.
- `SportsStore` now owns one source-backed `liveGames` domain.
- Refreshes validate HTTP responses, preserve last-good data on failure, and ignore stale generations.
- A 2xx response must still match the expected Sports CSV header before it can replace last-good data, preventing HTML/error bodies from appearing as a valid empty schedule.
- CSV parsing rejects malformed dates and missing-team rows while preserving quoted fields and status inference.
- Sports row identity is stable rather than random UUID-based.
- Team following and My Team were removed for 6.0.2 while team pages are refreshed. Matchup names remain on games, and individually saved game reminders are bounded and remain available.

### Events

- Source-specific caches prevent one calendar source from showing another source's data.
- Slow/older requests cannot overwrite a newer selected source.
- Failed refreshes preserve last-valid data when available.
- HTTP responses are validated, and a 2xx body must actually identify itself as iCalendar data before it can replace last-good events.
- Cancellation is handled explicitly.

### Dining

- Switching to a date that fails to load no longer leaves the previous day's menu under the newly selected date.
- Index failures preserve usable cached/current data when possible.
- Request generations prevent stale responses from winning.
- URL/station handling was hardened and avoidable force unwraps were removed.

### Clubs and remote configuration

- Club Directory uses a stable Google Sheets A:I contract with named-header support and positional fallback, and rejects obvious HTML/Google error payloads instead of treating them as an empty directory.
- Directory refreshes are generation-guarded so older requests cannot overwrite newer results.
- Announcements use the production `Announcements` Google Sheet with the V6 A:K contract (ID, Title, Message, Priority, Icon, Start Date, End Date, Link, Dismissible, Minimum Version, Status), plus missing-tab/empty-feed tolerance.
- Special Schedules keep their remote index/day-tab model and local fallback behavior.

### Search and UI safety

- Command-K search covers app pages, configured classes, My Clubs, events, sports games, and currently loaded dining items.
- Removed the old runtime switch back to the classic Athletics UI; V6 routes to Sports.
- Removed avoidable force unwraps from reusable dashboard/schedule/dining code.
- Fixed floating timer sizing and duplicate drag handling.
- Sidebar remains user-resizable and protected destinations remain reachable.

### Project/repository cleanup

Removed obsolete/dead material:

- legacy mock Sports files and stale Sports architecture docs
- stale V6 note dumps superseded by this audit
- duplicate raw icon folder already represented in the asset catalog
- obsolete duplicate iOS app entry point
- old repository screenshots that no longer represent V6
- `.DS_Store`, Xcode `xcuserdata`, and other user-specific state

Project configuration cleanup:

- Removed redundant direct `TelemetryClient` product linkage; RooMate uses the `TelemetryDeck` product.
- Raised the Sparkle package requirement from the stale 2.9.2 lock to 2.9.5+ within the 2.x line. The old `Package.resolved` was removed so Xcode can resolve the updated graph once on the release Mac.
- Removed forced `Apple Development` code-sign identity so Release can resolve the appropriate distribution identity through Xcode automatic signing.
- Project-wide macOS deployment target now matches the V6 macOS target at 14.0.
- Experimental iOS target uses its own `AppIcon` asset set and does not bundle the Mac Icon Composer resource.

## Static validation completed

The audit environment is Linux, so it cannot run Xcode/AppKit/SwiftUI rendering or Apple signing tools. Within those limits, the project was checked with:

- `swift-format` across current Swift source, followed by a clean lint pass.
- `swiftc -parse` across every current Swift source file.
- Monday-Friday bell-schedule duration/overlap validation.
- Synthetic Sports CSV parser cases including quoted commas, malformed dates, missing teams, and status inference.
- Synthetic ICS cases including folded lines, escaped commas, Eastern `TZID`, UTC timestamps, and all-day events.
- Synthetic Club Directory cases covering named headers, positional fallback, booleans, quoted commas, URL normalization, unpublished rows, and duplicate filtering.
- Synthetic Announcement cases covering named/fallback columns, publication filtering, type/priority, URL normalization, version comparison, and missing/error feeds.
- Synthetic Special Schedule cases covering published/draft INDEX rows, school-closed days, blocks, overlaps, and markers.
- Foundation/networking type-check of the Dining menu models/service.
- plist validation for `Info.plist`, entitlements, and `project.pbxproj`.
- XML validation for `appcast.xml` and SVG assets.
- asset-catalog `Contents.json` and referenced-file validation.

## Intentional non-refactors

Several SwiftUI files remain large, especially `SettingsView`, `ContentView`, `SportsHubView`, `ScheduleWorkspaceView`, `DashboardView`, and `RooMateMenuBar`. They should be modularized in a V6.1/V7 maintainability pass.

They were intentionally **not** mechanically split during this release audit. Without Xcode's macOS SwiftUI type-checker and a visual regression pass, a thousands-of-lines structural refactor immediately before V6 would add more risk than value.

## Release verification status

The 6.0.2 release pass was completed on a Mac with Xcode. The app built and archived successfully, all nine focused tests passed, the final archive was Developer ID signed, uploaded to Apple, notarized, exported with its ticket, and accepted by Gatekeeper. The final Sparkle item was generated from the exact notarized ZIP and validated against its embedded bundle metadata and EdDSA signature.

The release checklist and final task report distinguish automated/static checks from interactions that were only inspected manually or could not be exhaustively simulated across every school-day state.

### Sparkle

The checked-in `appcast.xml` contains RooMate 6.0.2 build 5 using the exact final ZIP byte length and EdDSA signature. Its corrected historical 6.0.1 item uses the actual embedded identity from that released artifact: short version 6.0, build 4.

## Privacy/distribution note

RooMate initializes TelemetryDeck and sends limited named product/diagnostic signals such as navigation and remote-data failure categories. RooMate's custom signal parameters do not include the user's name, class schedule, club notes, or PacTrack plan, and scraper telemetry no longer attaches arbitrary raw error descriptions. TelemetryDeck itself still adds its standard SDK/session/device/run-context metadata, so public privacy copy should describe analytics accurately rather than calling the app telemetry-free or fully anonymous. Revisit Apple's privacy-manifest requirements if distribution changes, especially for App Store distribution.

## Release recommendation

Use this project as the RooMate 6.0.2 release source. Continue with focused 6.x reliability fixes; keep larger new systems and architectural work for V7+.
