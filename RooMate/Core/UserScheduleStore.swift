import Combine
import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif
#if canImport(UserNotifications)
  import UserNotifications
#endif

extension Notification.Name {
  static let rooMateDidReset = Notification.Name("RooMateDidReset")
  static let rooMateScheduleDidChange = Notification.Name("RooMateScheduleDidChange")
  static let rooMateAppearanceDidChange = Notification.Name("RooMateAppearanceDidChange")
  static let rooMateRefreshOfficialSchedules = Notification.Name("RooMateRefreshOfficialSchedules")
  static let rooMateNotificationPreferencesDidChange = Notification.Name(
    "RooMateNotificationPreferencesDidChange")
  static let rooMateSportsPreferencesDidChange = Notification.Name(
    "RooMateSportsPreferencesDidChange")
  static let rooMateEventPreferencesDidChange = Notification.Name(
    "RooMateEventPreferencesDidChange")
}

struct ScheduleBlockPresentation {
  let title: String
  let subtitle: String
  let teacher: String?
  let room: String?
  let color: Color
  let systemImage: String
  let isFree: Bool
  let clubIDs: [UUID]

  var isClub: Bool { !clubIDs.isEmpty }
}

@MainActor
final class UserScheduleStore: ObservableObject {
  /// One app-lifetime schedule store keeps the main window, menu bar, floating
  /// timer, and notification scheduler in sync and prevents duplicate refresh loops.
  static let shared = UserScheduleStore()

  private static let defaults: UserDefaults = {
    let suiteName = "dev.roomate.prefs"
    return UserDefaults(suiteName: suiteName) ?? .standard
  }()

  @Published var assignments: [Level: ClassAssignment] = [:] {
    didSet { persistScheduleChange(refreshNotifications: true) }
  }
  @Published var specialColors: [SpecialBlock: CodableColor] = [:] {
    didSet { persistScheduleChange(refreshNotifications: false) }
  }
  @Published var specialFree: [SpecialBlock: Bool] = [:] {
    didSet { persistScheduleChange(refreshNotifications: true) }
  }
  @Published var specialBlockReplacements: [SpecialBlock: ClassAssignment.ReplacementClass] = [:] {
    didSet { persistScheduleChange(refreshNotifications: true) }
  }
  @Published var clubs: [Club] = [] {
    didSet { persistScheduleChange(refreshNotifications: true) }
  }
  @Published var appearance: AppearancePreference = .system {
    didSet { persistAppearanceChange() }
  }

  // V6 uses the full class color treatment everywhere. Keep this property for
  // source compatibility with existing views, but it is no longer user-configurable.
  @Published var cardColorStyle: CardColorStyle = .colors
  @Published private(set) var remoteSpecialScheduleFeed: RemoteSpecialScheduleFeed = .empty
  @Published private(set) var remoteSpecialSchedulesRefreshing = false
  @Published private(set) var remoteSpecialScheduleError: String?
  @Published private(set) var remoteAnnouncements: [RooMateAnnouncement] = []
  @Published private(set) var announcementsRefreshing = false
  @Published private(set) var announcementError: String?
  @Published private(set) var announcementsLastUpdated: Date?
  @Published private(set) var announcementsUsingSavedData = false
  @Published private(set) var dismissedAnnouncementIDs: Set<String> = []

  // Semester Planner ships in V6 and stays separate from the larger Study Planner,
  // which remains future work for V7.
  @Published var semesterPlanAssignments: [Level: ClassAssignment] = [:] {
    didSet { persistSimpleChange() }
  }
  @Published var completedTodoIDs: Set<String> = [] {
    didSet { persistSimpleChange() }
  }

  @Published var notificationsEnabled: Bool = false {
    didSet { persistNotificationChange(broadcast: true) }
  }
  @Published private(set) var notificationPauseUntil: Date? = nil {
    didSet { persistNotificationChange(broadcast: true) }
  }
  @Published private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

  @Published var notifyClassStartingSoon: Bool = true {
    didSet { persistNotificationChange() }
  }
  @Published var notifyClassEndingSoon: Bool = false {
    didSet { persistNotificationChange() }
  }
  @Published var notifyClubMeetings: Bool = true {
    didSet { persistNotificationChange() }
  }
  @Published var notifyDiningLunch: Bool = false {
    didSet { persistNotificationChange() }
  }
  @Published var notifySpecialScheduleMorning: Bool = true {
    didSet { persistNotificationChange() }
  }

  @Published var rooPACCurrentGrade: RooPACGrade = .ninth {
    didSet { persistSimpleChange() }
  }
  @Published var rooPacPlans: [RooPACActivityType: RooPACPlan] = [:] {
    didSet { persistSimpleChange() }
  }
  @Published var profileName: String = "" {
    didSet { persistSimpleChange() }
  }
  @Published var profileGraduationYear: Int? = nil {
    didSet {
      syncGradeFromGraduationYear()
      persistSimpleChange()
    }
  }
  @Published var profileAvatar: ProfileAvatarChoice = .initials {
    didSet { persistSimpleChange() }
  }
  @Published var profileAccent: ProfileAccentChoice = .orange {
    didSet { persistSimpleChange() }
  }
  /// Optional arbitrary profile color. When nil, `profileAccent` provides the
  /// preset/migration fallback used by older RooMate versions.
  @Published var profileCustomAccent: CodableColor? = nil {
    didSet { persistSimpleChange() }
  }
  @Published var profileGreetingEnabled: Bool = true {
    didSet { persistSimpleChange() }
  }

  // Sidebar customization: ordering and visibility are stored by tab title.
  @Published var sidebarOrder: [String] = [] {
    didSet { persistSimpleChange() }
  }
  @Published var sidebarFavorites: Set<String> = [] {
    didSet { persistSimpleChange() }
  }
  @Published var sidebarHidden: Set<String> = [] {
    didSet { persistSimpleChange() }
  }

  private let defaultsKey = "UserScheduleAssignments"
  private let specialDefaultsKey = "UserSpecialBlockColors"
  private let specialFreeDefaultsKey = "UserSpecialBlockFree"
  private let specialBlockReplacementsKey = "UserSpecialBlockReplacements"
  private let clubsDefaultsKey = "UserClubs"
  private let appearanceDefaultsKey = "UserAppearancePreference"
  private let cardStyleDefaultsKey = "UserCardColorStyle"
  private let semesterPlanAssignmentsKey = "SemesterPlanAssignments"
  private let completedTodosKey = "CompletedTodoIDs"
  private let notificationsEnabledKey = "NotificationsEnabled"
  private let notificationPauseUntilKey = "NotificationPauseUntil"
  private let notifyClassStartingSoonKey = "NotifyClassStartingSoon"
  private let notifyClassEndingSoonKey = "NotifyClassEndingSoon"
  private let notifyClubMeetingsKey = "NotifyClubMeetings"
  private let notifyDiningLunchKey = "NotifyDiningLunch"
  private let notifySpecialScheduleMorningKey = "NotifySpecialScheduleMorning"
  private let rooPACCurrentGradeKey = "RooPACCurrentGrade"
  private let rooPacPlansKey = "RooPACPlans"
  private let profileNameKey = "ProfileName"
  private let profileGraduationYearKey = "ProfileGraduationYear"
  private let profileAvatarKey = "ProfileAvatar"
  private let profileAccentKey = "ProfileAccent"
  private let profileCustomAccentKey = "ProfileCustomAccent"
  private let profileGreetingEnabledKey = "ProfileGreetingEnabled"
  private let sidebarOrderKey = "SidebarOrder"
  private let sidebarFavoritesKey = "SidebarFavorites"
  private let sidebarHiddenKey = "SidebarHidden"
  private let dismissedAnnouncementsKey = "DismissedAnnouncementIDs"
  private let legacyRooPacPlannedCreditsKey = "RooPACPlannedCredits"
  private let scheduleNotificationPrefix = "roomate.schedule."
  private var notificationRefreshTask: Task<Void, Never>?
  private var remoteSpecialScheduleRefreshTask: Task<Void, Never>?
  private var remoteSpecialSchedulePeriodicTask: Task<Void, Never>?
  private var announcementRefreshTask: Task<Void, Never>?
  private var announcementPeriodicTask: Task<Void, Never>?
  private var isLoadingPersistedState = false

  init() {
    remoteSpecialScheduleFeed = RemoteSpecialScheduleService.cachedFeed()
    if let cached = PersistentRemoteCache.load(
      [RooMateAnnouncement].self,
      named: "announcements"
    ) {
      remoteAnnouncements = cached.value
      announcementsLastUpdated = cached.refreshedAt
      announcementsUsingSavedData = !cached.value.isEmpty
    }
    isLoadingPersistedState = true
    load()
    isLoadingPersistedState = false
    refreshProfileDerivedData()

    Task {
      await refreshNotificationStatus()
      await refreshOfficialSpecialSchedules(force: true)
      await refreshAnnouncements(force: true)
      await refreshScheduleNotifications()
    }

    startOfficialSpecialScheduleRefreshLoop()
    startAnnouncementRefreshLoop()
  }

  deinit {
    notificationRefreshTask?.cancel()
    remoteSpecialScheduleRefreshTask?.cancel()
    remoteSpecialSchedulePeriodicTask?.cancel()
    announcementRefreshTask?.cancel()
    announcementPeriodicTask?.cancel()
  }

  private func persistSimpleChange() {
    guard !isLoadingPersistedState else { return }

    Task { @MainActor [weak self] in
      self?.save()
    }
  }

  private func persistNotificationChange(broadcast: Bool = false) {
    guard !isLoadingPersistedState else { return }

    if broadcast {
      NotificationCenter.default.post(
        name: .rooMateNotificationPreferencesDidChange,
        object: nil
      )
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      self.save()
      await self.refreshScheduleNotifications()
    }
  }

  private func persistScheduleChange(refreshNotifications: Bool) {
    guard !isLoadingPersistedState else { return }

    Task { @MainActor [weak self] in
      guard let self else { return }
      self.save()
      if refreshNotifications {
        await self.refreshScheduleNotifications()
      }
      NotificationCenter.default.post(
        name: .rooMateScheduleDidChange,
        object: nil
      )
    }
  }

  private func persistAppearanceChange() {
    guard !isLoadingPersistedState else { return }

    Task { @MainActor [weak self] in
      guard let self else { return }
      self.save()
      NotificationCenter.default.post(
        name: .rooMateAppearanceDidChange,
        object: nil
      )
    }
  }

  var profileDisplayName: String {
    let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Your Profile" : trimmed
  }

  /// The actual color used by Profile/Today/sidebar avatar UI. V6 keeps the
  /// preset enum for backwards compatibility but also allows any ColorPicker value.
  var profileAccentColor: Color {
    profileCustomAccent?.swiftUIColor ?? profileAccent.color
  }

  var profileFirstName: String? {
    let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.split(separator: " ").first else { return nil }
    return String(first)
  }

  var profileInitials: String {
    let pieces = profileName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
      .prefix(2)
    let value = pieces.compactMap(\.first).map(String.init).joined().uppercased()
    return value.isEmpty ? "R" : value
  }

  var profileCurrentGrade: RooPACGrade? {
    guard let year = profileGraduationYear else { return nil }
    return RooPACGrade.current(forGraduationYear: year)
  }

  var hasProfile: Bool {
    !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || profileGraduationYear != nil
  }

  func refreshProfileDerivedData(reference: Date = Date()) {
    syncGradeFromGraduationYear(reference: reference)
  }

  func clearProfile() {
    profileName = ""
    profileGraduationYear = nil
    profileAvatar = .initials
    profileAccent = .orange
    profileCustomAccent = nil
    profileGreetingEnabled = true
  }

  private func syncGradeFromGraduationYear(reference: Date = Date()) {
    guard let year = profileGraduationYear,
      let grade = RooPACGrade.current(forGraduationYear: year, reference: reference),
      grade != rooPACCurrentGrade
    else { return }
    rooPACCurrentGrade = grade
  }

  // MARK: - Official special schedules

  private func scheduleCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar
  }

  func remoteSpecialScheduleDay(on date: Date) -> RemoteSpecialScheduleDay? {
    let key = RemoteSpecialScheduleService.dateKey(for: date)
    return remoteSpecialScheduleFeed.days.first { $0.dateKey == key }
  }

  func isSchoolClosed(on date: Date) -> Bool {
    remoteSpecialScheduleDay(on: date)?.isSchoolClosed == true
  }

  func scheduleWeekday(for date: Date) -> Weekday? {
    if isSchoolClosed(on: date) { return nil }

    switch scheduleCalendar().component(.weekday, from: date) {
    case 2: return .monday
    case 3: return .tuesday
    case 4: return .wednesday
    case 5: return .thursday
    case 6: return .friday
    default: return nil
    }
  }

  func bellBlocks(for date: Date) -> [BellBlock] {
    if let remoteDay = remoteSpecialScheduleDay(on: date) {
      guard !remoteDay.isSchoolClosed else { return [] }
      return remoteDay.items.map { $0.bellBlock() }
    }

    guard let weekday = scheduleWeekday(for: date) else { return [] }
    return BellSchedule.weekly[weekday] ?? []
  }

  var officialSpecialSchedulesLastUpdated: Date? {
    let date = remoteSpecialScheduleFeed.refreshedAt
    return date == .distantPast ? nil : date
  }

  func refreshOfficialSpecialSchedules(force: Bool = false) async {
    if !force, let lastUpdated = officialSpecialSchedulesLastUpdated,
      Date().timeIntervalSince(lastUpdated) < 15 * 60
    {
      return
    }

    remoteSpecialScheduleRefreshTask?.cancel()
    remoteSpecialSchedulesRefreshing = true

    let previous = remoteSpecialScheduleFeed
    let task = Task { @MainActor in
      do {
        let feed = try await RemoteSpecialScheduleService.refresh(previous: previous)
        guard !Task.isCancelled else { return }
        remoteSpecialScheduleFeed = feed
        remoteSpecialScheduleError = nil
        RemoteDataHealthStore.shared.recordSuccess(
          .specialSchedules,
          refreshedAt: feed.refreshedAt
        )
        #if DEBUG
          print("[SpecialSchedules] Store updated with \(feed.days.count) official days.")
        #endif
      } catch {
        guard !Task.isCancelled else { return }
        remoteSpecialScheduleError = error.localizedDescription
        RemoteDataHealthStore.shared.recordFailure(
          .specialSchedules,
          error: error,
          usingSavedData: !previous.days.isEmpty,
          lastUpdated: previous.refreshedAt == .distantPast ? nil : previous.refreshedAt
        )
        #if DEBUG
          print("[SpecialSchedules] Refresh failed: \(error.localizedDescription)")
        #endif
        // Keep the last-known-good cached feed.
      }

      remoteSpecialSchedulesRefreshing = false
      await refreshScheduleNotifications()
    }

    remoteSpecialScheduleRefreshTask = task
    await task.value
  }

  private func startOfficialSpecialScheduleRefreshLoop() {
    remoteSpecialSchedulePeriodicTask?.cancel()
    remoteSpecialSchedulePeriodicTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2 * 60 * 60 * 1_000_000_000)
        guard !Task.isCancelled, let self else { return }
        await self.refreshOfficialSpecialSchedules(force: true)
      }
    }
  }

  // MARK: - Notification pause

  func isNotificationPauseActive(reference: Date = Date()) -> Bool {
    guard let notificationPauseUntil else { return false }
    return notificationPauseUntil > reference
  }

  func pauseNotifications(for interval: TimeInterval) {
    guard interval > 0 else { return }
    notificationPauseUntil = Date().addingTimeInterval(interval)
  }

  func pauseNotificationsForToday(reference: Date = Date()) {
    let calendar = scheduleNotificationCalendar()
    let startOfToday = calendar.startOfDay(for: reference)
    guard
      let tomorrow = calendar.date(
        byAdding: .day,
        value: 1,
        to: startOfToday
      )
    else { return }

    notificationPauseUntil = tomorrow
  }

  func resumeNotifications() {
    notificationPauseUntil = nil
  }

  func refreshNotificationStatus() async {
    #if canImport(UserNotifications)
      let status = await UNUserNotificationCenter.current()
        .notificationSettings()
        .authorizationStatus
      notificationAuthStatus = status
    #endif
  }

  /// Called when the user explicitly changes the notification switch in
  /// Settings. RooMate only asks macOS for permission from this action.
  func setNotificationsEnabled(_ enabled: Bool) async {
    #if canImport(UserNotifications)
      if enabled {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
          do {
            let granted = try await center.requestAuthorization(
              options: [.alert, .sound, .badge]
            )
            notificationsEnabled = granted
          } catch {
            notificationsEnabled = false
          }
        case .authorized, .provisional:
          notificationsEnabled = true
        case .denied:
          notificationsEnabled = false
        @unknown default:
          notificationsEnabled = false
        }
      } else {
        notificationPauseUntil = nil
        notificationsEnabled = false
        clearScheduleNotifications()
      }

      await refreshNotificationStatus()
      await refreshScheduleNotifications()
    #else
      notificationsEnabled = enabled
    #endif
  }

  /// Rebuild the next few school days of local reminders. RooMate keeps one
  /// bounded schedule bucket so class, club, Dining, and special-day reminders
  /// leave room for Sports and saved-event notifications under Apple's pending limit.
  func refreshScheduleNotifications() async {
    #if canImport(UserNotifications)
      notificationRefreshTask?.cancel()

      let enabled = notificationsEnabled
      let classStartSoon = notifyClassStartingSoon
      let classEndSoon = notifyClassEndingSoon
      let clubReminders = notifyClubMeetings
      let diningReminders = notifyDiningLunch
      let specialScheduleReminders = notifySpecialScheduleMorning

      let task = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationAuthStatus = settings.authorizationStatus

        let authorized =
          settings.authorizationStatus == .authorized
          || settings.authorizationStatus == .provisional

        guard enabled, authorized,
          classStartSoon || classEndSoon || clubReminders || diningReminders
            || specialScheduleReminders
        else {
          clearScheduleNotifications()
          return
        }

        let pending = await center.pendingNotificationRequests()
        let oldIDs =
          pending
          .map(\.identifier)
          .filter { $0.hasPrefix(scheduleNotificationPrefix) }

        if !oldIDs.isEmpty {
          center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }

        let now = Date()
        let pauseUntil = notificationPauseUntil.flatMap {
          $0 > now ? $0 : nil
        }
        let calendar = scheduleNotificationCalendar()
        var requests: [UNNotificationRequest] = []

        func canSchedule(_ fireDate: Date) -> Bool {
          guard fireDate > now else { return false }
          return pauseUntil.map { fireDate >= $0 } ?? true
        }

        // Special schedules and closures deserve one quiet morning heads-up.
        // Iterate calendar days directly because school-closed days are
        // intentionally excluded from `scheduleWeekday(for:)`.
        if specialScheduleReminders {
          for offset in 0..<8 {
            guard
              let date = calendar.date(byAdding: .day, value: offset, to: now),
              let specialDay = remoteSpecialScheduleDay(on: date),
              let fireDate = calendar.date(
                bySettingHour: 7,
                minute: 15,
                second: 0,
                of: date
              ),
              canSchedule(fireDate)
            else {
              continue
            }

            let note = specialDay.note.trimmingCharacters(in: .whitespacesAndNewlines)
            requests.append(
              notificationRequest(
                id: "\(scheduleNotificationPrefix)special.\(specialDay.dateKey)",
                fireDate: fireDate,
                title: specialDay.isSchoolClosed
                  ? "\(specialDay.displayTitle) today"
                  : "\(specialDay.displayTitle) today",
                body: note.isEmpty
                  ? (specialDay.isSchoolClosed
                    ? "RooMate has no school-day schedule for today."
                    : "RooMate has already updated today's schedule.")
                  : note
              )
            )

            if requests.count >= 40 { break }
          }
        }

        var schoolDays: [(date: Date, weekday: Weekday)] = []
        for offset in 0..<14 {
          guard
            let date = calendar.date(
              byAdding: .day,
              value: offset,
              to: now
            ), let weekday = scheduleWeekday(for: date)
          else {
            // Weekends and remotely managed school-closed dates do not
            // count toward the five upcoming school days.
            continue
          }

          schoolDays.append((calendar.startOfDay(for: date), weekday))
          if schoolDays.count == 5 { break }
        }

        for schoolDay in schoolDays {
          let blocks = bellBlocks(for: schoolDay.date)
          let presentationWeekday = scheduleWeekday(for: schoolDay.date) ?? schoolDay.weekday

          // Dining is intentionally a single useful reminder rather than one
          // notification per menu item. It points students to the live menu.
          if diningReminders,
            let lunchBlock = blocks.first(where: { block in
              guard block.isPrimaryTimelineBlock else { return false }
              switch block.kind {
              case .special(.lunch), .special(.lunchAndClubs):
                return true
              default:
                return schedulePresentation(for: block, on: presentationWeekday)
                  .title.localizedCaseInsensitiveContains("lunch")
              }
            }),
            let lunchStart = notificationDate(on: schoolDay.date, time: lunchBlock.start)
          {
            let fireDate = lunchStart.addingTimeInterval(-15 * 60)
            if canSchedule(fireDate) {
              requests.append(
                notificationRequest(
                  id:
                    "\(scheduleNotificationPrefix)dining.\(Int(lunchStart.timeIntervalSince1970))",
                  fireDate: fireDate,
                  title: "Lunch is in 15 minutes",
                  body: "Open Dining to check today's menu before lunch starts."
                )
              )
            }
          }

          for block in blocks {
            guard block.isPrimaryTimelineBlock else { continue }

            let presentation = schedulePresentation(
              for: block,
              on: presentationWeekday
            )

            guard
              let startDate = notificationDate(
                on: schoolDay.date,
                time: block.start
              ),
              let endDate = notificationDate(
                on: schoolDay.date,
                time: block.end
              )
            else {
              continue
            }

            // A My Clubs takeover can occur on a Level or special block. Treat
            // it as a club reminder instead of accidentally sending a class one.
            if presentation.isClub {
              if clubReminders {
                let fireDate = startDate.addingTimeInterval(-5 * 60)
                if canSchedule(fireDate) {
                  requests.append(
                    notificationRequest(
                      id:
                        "\(scheduleNotificationPrefix)club.block.\(Int(startDate.timeIntervalSince1970)).\(block.id.uuidString)",
                      fireDate: fireDate,
                      title: "\(presentation.title) starts in 5 minutes",
                      body: notificationBody(
                        subtitle: presentation.subtitle,
                        timeLabel: "Starts \(notificationTime(startDate))"
                      )
                    )
                  )
                }
              }
              if requests.count >= 40 { break }
              continue
            }

            guard case .level(let level) = block.kind, !presentation.isFree else {
              continue
            }

            let title = presentation.title
            let subtitle = presentation.subtitle

            if classStartSoon {
              let fireDate = startDate.addingTimeInterval(-5 * 60)
              if canSchedule(fireDate) {
                requests.append(
                  notificationRequest(
                    id:
                      "\(scheduleNotificationPrefix)start.\(Int(startDate.timeIntervalSince1970)).\(level.id)",
                    fireDate: fireDate,
                    title: "\(title) starts in 5 minutes",
                    body: notificationBody(
                      subtitle: subtitle,
                      timeLabel: "Starts \(notificationTime(startDate))"
                    )
                  )
                )
              }
            }

            if classEndSoon {
              let fireDate = endDate.addingTimeInterval(-5 * 60)
              if canSchedule(fireDate) {
                requests.append(
                  notificationRequest(
                    id:
                      "\(scheduleNotificationPrefix)end.\(Int(endDate.timeIntervalSince1970)).\(level.id)",
                    fireDate: fireDate,
                    title: "\(title) ends in 5 minutes",
                    body: notificationBody(
                      subtitle: subtitle,
                      timeLabel: "Ends \(notificationTime(endDate))"
                    )
                  )
                )
              }
            }

            if requests.count >= 40 { break }
          }

          // Additional My Clubs meetings live alongside the bell schedule
          // instead of replacing a class, so schedule them separately.
          if clubReminders, requests.count < 40 {
            let calendarWeekday = calendar.component(.weekday, from: schoolDay.date)

            for club in clubs {
              let clubName = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
              guard !clubName.isEmpty else { continue }

              for meeting in club.otherMeetings where meeting.weekday == calendarWeekday {
                guard
                  let startDate = notificationDate(
                    on: schoolDay.date,
                    timeOfDay: meeting.startTime
                  ),
                  let endDate = notificationDate(
                    on: schoolDay.date,
                    timeOfDay: meeting.endTime
                  ), endDate > startDate
                else {
                  continue
                }

                let fireDate = startDate.addingTimeInterval(-5 * 60)
                guard canSchedule(fireDate) else { continue }

                let room = club.room.trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitle = room.isEmpty ? "Club meeting" : "Club meeting • \(room)"
                requests.append(
                  notificationRequest(
                    id:
                      "\(scheduleNotificationPrefix)club.start.\(meeting.id.uuidString).\(Int(startDate.timeIntervalSince1970))",
                    fireDate: fireDate,
                    title: "\(clubName) starts in 5 minutes",
                    body: notificationBody(
                      subtitle: subtitle,
                      timeLabel: "Starts \(notificationTime(startDate))"
                    )
                  )
                )

                if requests.count >= 40 { break }
              }

              if requests.count >= 40 { break }
            }
          }

          if requests.count >= 40 { break }
        }

        for request in requests.prefix(40) {
          try? await center.add(request)
        }
      }

      notificationRefreshTask = task
      await task.value
    #endif
  }

  func clearScheduleNotifications() {
    #if canImport(UserNotifications)
      Task {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers =
          pending
          .map(\.identifier)
          .filter { $0.hasPrefix(scheduleNotificationPrefix) }

        if !identifiers.isEmpty {
          center.removePendingNotificationRequests(
            withIdentifiers: identifiers
          )
        }
      }
    #endif
  }

  #if canImport(UserNotifications)
    private func notificationRequest(
      id: String,
      fireDate: Date,
      title: String,
      body: String
    ) -> UNNotificationRequest {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default

      var components = scheduleNotificationCalendar().dateComponents(
        [.year, .month, .day, .hour, .minute],
        from: fireDate
      )

      components.timeZone = scheduleNotificationCalendar().timeZone

      let trigger = UNCalendarNotificationTrigger(
        dateMatching: components,
        repeats: false
      )

      return UNNotificationRequest(
        identifier: id,
        content: content,
        trigger: trigger
      )
    }

    private func notificationBody(
      subtitle: String,
      timeLabel: String
    ) -> String {
      let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? timeLabel : "\(trimmed) • \(timeLabel)"
    }

    private func notificationTime(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = scheduleNotificationCalendar().timeZone
      formatter.dateFormat = "h:mm a"
      return formatter.string(from: date)
    }

    private func notificationDate(
      on day: Date,
      time: DateComponents
    ) -> Date? {
      let calendar = scheduleNotificationCalendar()
      var components = calendar.dateComponents(
        [.year, .month, .day],
        from: day
      )
      components.hour = time.hour
      components.minute = time.minute
      components.second = 0
      return calendar.date(from: components)
    }

    private func notificationDate(
      on day: Date,
      timeOfDay: Date
    ) -> Date? {
      let calendar = scheduleNotificationCalendar()
      let time = calendar.dateComponents([.hour, .minute], from: timeOfDay)

      var components = calendar.dateComponents(
        [.year, .month, .day],
        from: day
      )
      components.hour = time.hour
      components.minute = time.minute
      components.second = 0
      return calendar.date(from: components)
    }

    private func scheduleNotificationCalendar() -> Calendar {
      var calendar = Calendar.current
      calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
      return calendar
    }

    private func weekdayForNotificationDate(_ date: Date) -> Weekday? {
      switch scheduleNotificationCalendar().component(.weekday, from: date) {
      case 2: .monday
      case 3: .tuesday
      case 4: .wednesday
      case 5: .thursday
      case 6: .friday
      default: nil
      }
    }
  #endif

  func assignment(for level: Level) -> ClassAssignment {
    assignments[level] ?? .default(for: level)
  }

  func semesterPlanAssignment(for level: Level) -> ClassAssignment {
    semesterPlanAssignments[level] ?? .default(for: level)
  }

  func semesterPlanBinding(for level: Level) -> Binding<ClassAssignment> {
    Binding(
      get: { self.semesterPlanAssignments[level] ?? .default(for: level) },
      set: { self.semesterPlanAssignments[level] = $0 }
    )
  }

  func copyCurrentScheduleToSemesterPlan() {
    semesterPlanAssignments = Dictionary(
      uniqueKeysWithValues: Level.allCases.map { level in
        (level, assignment(for: level))
      }
    )
  }

  func clearSemesterPlan() {
    semesterPlanAssignments = [:]
  }

  func set(_ assignment: ClassAssignment, for level: Level) {
    assignments[level] = assignment
    syncDerivedMusicClubsFreeState()
  }

  func binding(for level: Level) -> Binding<ClassAssignment> {
    Binding(
      get: { self.assignments[level] ?? .default(for: level) },
      set: {
        self.assignments[level] = $0
        self.syncDerivedMusicClubsFreeState()
      }
    )
  }

  private func syncDerivedMusicClubsFreeState() {
    specialFree[.musicClubs] = assignment(for: .music).displayIsFree(on: .monday)
  }

  func colorBinding(for block: SpecialBlock) -> Binding<Color> {
    Binding(
      get: { self.specialColors[block]?.swiftUIColor ?? block.defaultColor },
      set: { self.specialColors[block] = CodableColor($0) }
    )
  }

  func color(for block: SpecialBlock) -> Color {
    specialColors[block]?.swiftUIColor ?? block.defaultColor
  }

  func isTodoCompleted(_ id: String) -> Bool {
    completedTodoIDs.contains(id)
  }

  func toggleTodoCompleted(_ id: String) {
    if completedTodoIDs.contains(id) {
      completedTodoIDs.remove(id)
    } else {
      completedTodoIDs.insert(id)
    }
  }

  func displayTitle(for block: SpecialBlock) -> String {
    let clubNames: [String]
    switch block {
    case .musicClubs:
      clubNames = clubs.compactMap { club in
        guard club.meetsMondayClub else { return nil }
        let trimmed = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
    case .lunchAndClubs:
      clubNames = clubs.compactMap { club in
        guard club.meetsWednesdayClub else { return nil }
        let trimmed = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
      }
    default:
      return block.title
    }

    return clubNames.isEmpty ? block.title : clubNames.joined(separator: ", ")
  }

  private func matchingClubs(for kind: BlockKind, on weekday: Weekday) -> [Club] {
    let weekdayIndex = weekday.calendarWeekdayIndex
    var seen = Set<UUID>()

    return clubs.filter { club in
      let trimmedName = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedName.isEmpty else { return false }

      let builtInMatch: Bool
      switch kind {
      case .special(.musicClubs):
        builtInMatch = weekdayIndex == Weekday.monday.calendarWeekdayIndex && club.meetsMondayClub
      case .special(.lunchAndClubs):
        builtInMatch =
          weekdayIndex == Weekday.wednesday.calendarWeekdayIndex && club.meetsWednesdayClub
      default:
        builtInMatch = false
      }

      let explicitMatch = club.blockMeetings.contains {
        $0.weekday == weekdayIndex && $0.block == kind
      }

      guard builtInMatch || explicitMatch else { return false }
      return seen.insert(club.id).inserted
    }
  }

  private func clubPresentation(for kind: BlockKind, on weekday: Weekday)
    -> ScheduleBlockPresentation?
  {
    let matched = matchingClubs(for: kind, on: weekday)
    guard !matched.isEmpty else { return nil }

    let titles =
      matched
      .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let rooms =
      matched
      .map { $0.room.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .reduce(into: [String]()) { result, room in
        if !result.contains(room) { result.append(room) }
      }

    let room = rooms.isEmpty ? nil : rooms.joined(separator: ", ")
    var subtitlePieces = [
      matched.count == 1 ? "Club" : "\(matched.count) clubs"
    ]
    if let room {
      subtitlePieces.append(room)
    }

    return ScheduleBlockPresentation(
      title: titles.joined(separator: ", "),
      subtitle: subtitlePieces.joined(separator: " • "),
      teacher: nil,
      room: room,
      color: matched.first?.displayColor ?? .purple,
      systemImage: matched.count == 1
        ? (matched.first?.displayIconName ?? ClubIconOption.group.systemImage)
        : ClubIconOption.group.systemImage,
      isFree: false,
      clubIDs: matched.map(\.id)
    )
  }

  /// The single source of truth for how a bell-schedule block should appear.
  /// Clubs assigned to an exact Level/special block take precedence over the
  /// normal class/special-block presentation for that weekday.
  func schedulePresentation(for kind: BlockKind, on weekday: Weekday) -> ScheduleBlockPresentation {
    if let club = clubPresentation(for: kind, on: weekday) {
      return club
    }

    switch kind {
    case .level(let level):
      let assignment = assignment(for: level)

      if level == .music {
        let musicTitle = displayMusicTitle(on: weekday)
        let teacher = displayMusicTeacher(on: weekday) ?? assignment.displayTeacher(on: weekday)
        let room = displayMusicRoom(on: weekday) ?? assignment.displayRoom(on: weekday)
        let subtitle = [teacher, room]
          .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: " • ")

        return ScheduleBlockPresentation(
          title: musicTitle ?? assignment.displayTitle(for: level, on: weekday),
          subtitle: subtitle,
          teacher: teacher,
          room: room,
          color: musicTitle == nil ? assignment.displayColor(on: weekday) : color(for: .musicClubs),
          systemImage: musicTitle == nil
            ? assignment.displaySystemImage(for: level, on: weekday)
            : SpecialBlock.musicClubs.systemImage,
          isFree: assignment.displayIsFree(on: weekday) && musicTitle == nil,
          clubIDs: []
        )
      }

      return ScheduleBlockPresentation(
        title: assignment.displayTitle(for: level, on: weekday),
        subtitle: assignment.displaySubtitle(on: weekday),
        teacher: assignment.displayTeacher(on: weekday),
        room: assignment.displayRoom(on: weekday),
        color: assignment.displayColor(on: weekday),
        systemImage: assignment.displaySystemImage(for: level, on: weekday),
        isFree: assignment.displayIsFree(on: weekday),
        clubIDs: []
      )

    case .special(let special):
      let teacher = displayTeacher(for: special, on: weekday)
      let room = displayRoom(for: special, on: weekday)
      let subtitle = [teacher, room]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")

      return ScheduleBlockPresentation(
        title: displayTitle(for: special, on: weekday),
        subtitle: subtitle,
        teacher: teacher,
        room: room,
        color: color(for: special),
        systemImage: special.systemImage,
        isFree: isSpecialBlockFree(special, on: weekday),
        clubIDs: []
      )

    case .custom(let title):
      return ScheduleBlockPresentation(
        title: title,
        subtitle: "",
        teacher: nil,
        room: nil,
        color: .indigo,
        systemImage: "calendar.badge.clock",
        isFree: false,
        clubIDs: []
      )
    }
  }

  /// Presentation for a concrete schedule item. Official remote schedule metadata
  /// can override a title and append a day-specific detail while preserving the
  /// student's personal Level mapping underneath.
  func schedulePresentation(for block: BellBlock, on weekday: Weekday) -> ScheduleBlockPresentation
  {
    let base = schedulePresentation(for: block.kind, on: weekday)
    let title = block.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = block.detail?.trimmingCharacters(in: .whitespacesAndNewlines)

    let subtitlePieces = [detail, base.subtitle]
      .compactMap { value -> String? in
        guard let value, !value.isEmpty else { return nil }
        return value
      }

    return ScheduleBlockPresentation(
      title: (title.flatMap { $0.isEmpty ? nil : $0 } ?? base.title),
      subtitle: subtitlePieces.joined(separator: " • "),
      teacher: base.teacher,
      room: base.room,
      color: base.color,
      systemImage: block.timelineType == .marker
        ? "flag.fill" : (block.timelineType == .extra ? "sparkles" : base.systemImage),
      isFree: base.isFree,
      clubIDs: base.clubIDs
    )
  }

  func displayTitle(for block: SpecialBlock, on weekday: Weekday) -> String {
    if let club = clubPresentation(for: .special(block), on: weekday) {
      return club.title
    }

    if let replacement = specialBlockReplacements[block] {
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.title.isEmpty ? displayTitle(for: block) : replacement.title
      }
    }
    return displayTitle(for: block)
  }

  func displayTeacher(for block: SpecialBlock, on weekday: Weekday) -> String? {
    if clubPresentation(for: .special(block), on: weekday) != nil {
      return nil
    }

    if let replacement = specialBlockReplacements[block] {
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.teacher.isEmpty ? nil : replacement.teacher
      }
    }
    return nil
  }

  func displayRoom(for block: SpecialBlock, on weekday: Weekday) -> String? {
    if let club = clubPresentation(for: .special(block), on: weekday) {
      return club.room
    }

    if let replacement = specialBlockReplacements[block] {
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.room.isEmpty ? nil : replacement.room
      }
    }
    return nil
  }

  func displayColor(for block: SpecialBlock, on weekday: Weekday) -> Color {
    clubPresentation(for: .special(block), on: weekday)?.color ?? color(for: block)
  }

  func displaySystemImage(for block: SpecialBlock, on weekday: Weekday) -> String {
    clubPresentation(for: .special(block), on: weekday)?.systemImage ?? block.systemImage
  }

  func isSpecialBlockFree(_ block: SpecialBlock, on weekday: Weekday) -> Bool {
    if clubPresentation(for: .special(block), on: weekday) != nil {
      return false
    }

    if let replacement = specialBlockReplacements[block] {
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.isFree
      }
    }

    switch block {
    case .lunch:
      return true
    case .lunchAndClubs:
      return !clubs.contains(where: {
        $0.meetsWednesdayClub && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      })
    case .musicClubs:
      if clubs.contains(where: {
        $0.meetsMondayClub && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }) {
        return false
      }
      return specialFree[block] ?? assignment(for: .music).displayIsFree(on: .monday)
    default:
      return specialFree[block] ?? false
    }
  }

  // MARK: - Music Block Special Handling
  // Music Block is a Level but has replacements stored as a SpecialBlock (.musicClubs)
  // These methods check the special block replacements for music

  func displayMusicTitle(on weekday: Weekday) -> String? {
    // Check if there's a music replacement for this day
    if let replacement = specialBlockReplacements[.musicClubs] {
      // If daysNotFree is empty, it applies to all days (for blocks without day selection)
      // If daysNotFree is not empty, check if this specific day is in the set
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.title.isEmpty ? nil : replacement.title
      }
    }
    return nil
  }

  func displayMusicTeacher(on weekday: Weekday) -> String? {
    // Check if there's a music replacement for this day
    if let replacement = specialBlockReplacements[.musicClubs] {
      // If daysNotFree is empty, it applies to all days (for blocks without day selection)
      // If daysNotFree is not empty, check if this specific day is in the set
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.teacher.isEmpty ? nil : replacement.teacher
      }
    }
    return nil
  }

  func displayMusicRoom(on weekday: Weekday) -> String? {
    // Check if there's a music replacement for this day
    if let replacement = specialBlockReplacements[.musicClubs] {
      // If daysNotFree is empty, it applies to all days (for blocks without day selection)
      // If daysNotFree is not empty, check if this specific day is in the set
      let appliesToThisDay =
        replacement.daysNotFree.isEmpty
        || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
      if appliesToThisDay {
        return replacement.room.isEmpty ? nil : replacement.room
      }
    }
    return nil
  }

  // MARK: - Remote announcements

  var currentAppVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  func activeAnnouncements(at reference: Date = Date()) -> [RooMateAnnouncement] {
    remoteAnnouncements
      .filter { !dismissedAnnouncementIDs.contains($0.id) }
      .filter { $0.isActive(at: reference, appVersion: currentAppVersion) }
      .sorted {
        if $0.level.priority != $1.level.priority {
          return $0.level.priority > $1.level.priority
        }
        return ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast)
      }
  }

  func dismissAnnouncement(_ announcement: RooMateAnnouncement) {
    guard announcement.dismissible else { return }
    dismissedAnnouncementIDs.insert(announcement.id)
    TelemetryTracker.trackAnnouncementDismissed(level: announcement.level.rawValue)
    save()
  }

  func refreshAnnouncements(force: Bool = false) async {
    announcementRefreshTask?.cancel()

    let task = Task { @MainActor [weak self] in
      guard let self else { return }

      if !RemoteAnnouncementService.isConfigured {
        self.announcementError = nil
        self.announcementsRefreshing = false
        return
      }

      self.announcementsRefreshing = true
      defer { self.announcementsRefreshing = false }

      do {
        let announcements = try await RemoteAnnouncementService.fetchAnnouncements()
        guard !Task.isCancelled else { return }
        let previousIDs = Set(self.remoteAnnouncements.map(\.id))
        let refreshedAt = Date()
        self.remoteAnnouncements = announcements
        self.announcementsLastUpdated = refreshedAt
        self.announcementsUsingSavedData = false
        self.announcementError = nil
        try? PersistentRemoteCache.save(
          announcements,
          refreshedAt: refreshedAt,
          named: "announcements"
        )
        RemoteDataHealthStore.shared.recordSuccess(
          .announcements,
          refreshedAt: refreshedAt
        )
        let newIDs = Set(announcements.map(\.id))
        if force || previousIDs != newIDs {
          TelemetryTracker.trackAnnouncementFeedLoaded(
            totalCount: announcements.count,
            activeCount: self.activeAnnouncements().count
          )
        }
      } catch {
        guard !Task.isCancelled else { return }
        TelemetryTracker.trackScraperFailure(
          signal: "Scraper.AnnouncementsFailed",
          target: "Announcements",
          errorType: (error is URLError) ? "NetworkError" : "ParseError"
        )

        // Announcements are intentionally non-critical infrastructure.
        // If the optional Announcements tab does not exist yet, RooMate
        // simply keeps the last good feed (or nothing) and carries on.
        if force || self.remoteAnnouncements.isEmpty {
          self.announcementError = error.localizedDescription
        }
        self.announcementsUsingSavedData = !self.remoteAnnouncements.isEmpty
        RemoteDataHealthStore.shared.recordFailure(
          .announcements,
          error: error,
          usingSavedData: self.announcementsUsingSavedData,
          lastUpdated: self.announcementsLastUpdated
        )
        #if DEBUG
          print("[Announcements] Refresh failed: \(error.localizedDescription)")
        #endif
      }
    }

    announcementRefreshTask = task
    await task.value
  }

  private func startAnnouncementRefreshLoop() {
    announcementPeriodicTask?.cancel()

    announcementPeriodicTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
        guard !Task.isCancelled, let self else { return }
        await self.refreshAnnouncements()
      }
    }
  }

  // MARK: - Persistence

  private func save() {
    let d = Self.defaults
    let encoder = JSONEncoder()

    func encodeAndSet<T: Encodable>(_ value: T, forKey key: String, label: String) {
      do {
        d.set(try encoder.encode(value), forKey: key)
      } catch {
        #if DEBUG
          print("[Persistence] Failed to save \(label): \(error)")
        #endif
      }
    }

    encodeAndSet(assignments, forKey: defaultsKey, label: "assignments")
    encodeAndSet(specialColors, forKey: specialDefaultsKey, label: "special block colors")
    encodeAndSet(specialFree, forKey: specialFreeDefaultsKey, label: "special block free flags")
    encodeAndSet(
      specialBlockReplacements, forKey: specialBlockReplacementsKey,
      label: "special block replacements")
    encodeAndSet(clubs, forKey: clubsDefaultsKey, label: "clubs")
    encodeAndSet(appearance, forKey: appearanceDefaultsKey, label: "appearance")
    encodeAndSet(
      semesterPlanAssignments, forKey: semesterPlanAssignmentsKey, label: "semester plan")
    encodeAndSet(Array(completedTodoIDs), forKey: completedTodosKey, label: "completed IDs")

    d.set(notificationsEnabled, forKey: notificationsEnabledKey)
    if let notificationPauseUntil {
      d.set(notificationPauseUntil, forKey: notificationPauseUntilKey)
    } else {
      d.removeObject(forKey: notificationPauseUntilKey)
    }
    d.set(notifyClassStartingSoon, forKey: notifyClassStartingSoonKey)
    d.set(notifyClassEndingSoon, forKey: notifyClassEndingSoonKey)
    d.set(notifyClubMeetings, forKey: notifyClubMeetingsKey)
    d.set(notifyDiningLunch, forKey: notifyDiningLunchKey)
    d.set(notifySpecialScheduleMorning, forKey: notifySpecialScheduleMorningKey)

    encodeAndSet(sidebarOrder, forKey: sidebarOrderKey, label: "sidebar order")
    encodeAndSet(Array(sidebarFavorites), forKey: sidebarFavoritesKey, label: "sidebar favorites")
    encodeAndSet(Array(sidebarHidden), forKey: sidebarHiddenKey, label: "sidebar hidden set")
    encodeAndSet(
      Array(dismissedAnnouncementIDs), forKey: dismissedAnnouncementsKey,
      label: "dismissed announcements")
    encodeAndSet(rooPACCurrentGrade, forKey: rooPACCurrentGradeKey, label: "RooPAC grade")
    encodeAndSet(rooPacPlans, forKey: rooPacPlansKey, label: "RooPAC planner")

    d.set(profileName, forKey: profileNameKey)
    if let profileGraduationYear {
      d.set(profileGraduationYear, forKey: profileGraduationYearKey)
    } else {
      d.removeObject(forKey: profileGraduationYearKey)
    }
    encodeAndSet(profileAvatar, forKey: profileAvatarKey, label: "profile avatar")
    encodeAndSet(profileAccent, forKey: profileAccentKey, label: "profile accent")
    if let profileCustomAccent {
      encodeAndSet(
        profileCustomAccent, forKey: profileCustomAccentKey, label: "custom profile accent")
    } else {
      d.removeObject(forKey: profileCustomAccentKey)
    }
    d.set(profileGreetingEnabled, forKey: profileGreetingEnabledKey)
  }

  // Reset user-customizable preferences to sensible defaults
  func resetToDefaults() {
    // Suppress the normal per-property persistence hooks while applying the
    // reset. Persist once at the end so reset cannot launch dozens of duplicate
    // save/notification tasks.
    isLoadingPersistedState = true

    assignments = [:]
    specialColors = [:]
    specialFree = [:]
    specialBlockReplacements = [:]
    clubs = []
    appearance = .system
    cardColorStyle = .colors
    semesterPlanAssignments = [:]
    completedTodoIDs = []
    notificationsEnabled = false
    notificationPauseUntil = nil
    notifyClassStartingSoon = true
    notifyClassEndingSoon = false
    notifyClubMeetings = true
    notifyDiningLunch = false
    notifySpecialScheduleMorning = true
    rooPACCurrentGrade = .ninth
    rooPacPlans = [:]
    clearProfile()

    // Special schedules are official RooMate content now, not a user preference.
    Self.defaults.removeObject(forKey: "SpecialScheduleOverrides")

    sidebarOrder = []
    sidebarFavorites = []
    sidebarHidden = []
    dismissedAnnouncementIDs = []
    syncDerivedMusicClubsFreeState()

    isLoadingPersistedState = false
    save()

    NotificationCenter.default.post(name: .rooMateDidReset, object: nil)
    NotificationCenter.default.post(name: .rooMateScheduleDidChange, object: nil)
    NotificationCenter.default.post(name: .rooMateAppearanceDidChange, object: nil)
    NotificationCenter.default.post(name: .rooMateNotificationPreferencesDidChange, object: nil)

    Task { @MainActor [weak self] in
      await self?.refreshScheduleNotifications()
    }
  }

  private func load() {
    let d = Self.defaults
    if let data = d.data(forKey: defaultsKey) {
      if let decoded = try? JSONDecoder().decode([Level: ClassAssignment].self, from: data) {
        self.assignments = decoded
      }
    }
    if let data = d.data(forKey: specialDefaultsKey) {
      if let decoded = try? JSONDecoder().decode([SpecialBlock: CodableColor].self, from: data) {
        self.specialColors = decoded
      }
    }
    if let data = d.data(forKey: specialFreeDefaultsKey) {
      if let decoded = try? JSONDecoder().decode([SpecialBlock: Bool].self, from: data) {
        self.specialFree = decoded
      }
    }
    if let data = d.data(forKey: specialBlockReplacementsKey) {
      if let decoded = try? JSONDecoder().decode(
        [SpecialBlock: ClassAssignment.ReplacementClass].self, from: data)
      {
        self.specialBlockReplacements = decoded
      }
    }
    if let data = d.data(forKey: clubsDefaultsKey) {
      if let decoded = try? JSONDecoder().decode([Club].self, from: data) { self.clubs = decoded }
    }
    if let data = d.data(forKey: appearanceDefaultsKey) {
      if let decoded = try? JSONDecoder().decode(AppearancePreference.self, from: data) {
        self.appearance = decoded
      }
    }
    d.removeObject(forKey: cardStyleDefaultsKey)
    cardColorStyle = .colors
    if let data = d.data(forKey: semesterPlanAssignmentsKey),
      let decoded = try? JSONDecoder().decode([Level: ClassAssignment].self, from: data)
    {
      self.semesterPlanAssignments = decoded
    }
    if let data = d.data(forKey: completedTodosKey),
      let array = try? JSONDecoder().decode([String].self, from: data)
    {
      self.completedTodoIDs = Set(array)
    }
    if d.object(forKey: notificationsEnabledKey) != nil {
      self.notificationsEnabled = d.bool(forKey: notificationsEnabledKey)
    }
    if let pauseUntil = d.object(forKey: notificationPauseUntilKey) as? Date,
      pauseUntil > Date()
    {
      self.notificationPauseUntil = pauseUntil
    } else {
      d.removeObject(forKey: notificationPauseUntilKey)
    }
    if d.object(forKey: notifyClassStartingSoonKey) != nil {
      self.notifyClassStartingSoon = d.bool(forKey: notifyClassStartingSoonKey)
    }
    if d.object(forKey: notifyClassEndingSoonKey) != nil {
      self.notifyClassEndingSoon = d.bool(forKey: notifyClassEndingSoonKey)
    }
    if d.object(forKey: notifyClubMeetingsKey) != nil {
      self.notifyClubMeetings = d.bool(forKey: notifyClubMeetingsKey)
    }
    if d.object(forKey: notifyDiningLunchKey) != nil {
      self.notifyDiningLunch = d.bool(forKey: notifyDiningLunchKey)
    }
    if d.object(forKey: notifySpecialScheduleMorningKey) != nil {
      self.notifySpecialScheduleMorning = d.bool(forKey: notifySpecialScheduleMorningKey)
    }
    if let data = d.data(forKey: rooPACCurrentGradeKey),
      let decoded = try? JSONDecoder().decode(RooPACGrade.self, from: data)
    {
      self.rooPACCurrentGrade = decoded
    }
    if let data = d.data(forKey: rooPacPlansKey),
      let decoded = try? JSONDecoder().decode([RooPACActivityType: RooPACPlan].self, from: data)
    {
      self.rooPacPlans = decoded
    } else if let data = d.data(forKey: legacyRooPacPlannedCreditsKey),
      let decoded = try? JSONDecoder().decode([RooPACActivityType: Int].self, from: data)
    {
      self.rooPacPlans = Dictionary(
        uniqueKeysWithValues: decoded.map {
          (
            $0.key,
            RooPACPlan(isSelected: $0.value > 0, overrideCredits: $0.value > 0 ? $0.value : nil)
          )
        })
    }
    if let value = d.string(forKey: profileNameKey) { self.profileName = value }
    if d.object(forKey: profileGraduationYearKey) != nil {
      self.profileGraduationYear = d.integer(forKey: profileGraduationYearKey)
    }
    if let data = d.data(forKey: profileAvatarKey),
      let value = try? JSONDecoder().decode(ProfileAvatarChoice.self, from: data)
    {
      self.profileAvatar = value
    }
    if let data = d.data(forKey: profileAccentKey),
      let value = try? JSONDecoder().decode(ProfileAccentChoice.self, from: data)
    {
      self.profileAccent = value
    }
    if let data = d.data(forKey: profileCustomAccentKey),
      let value = try? JSONDecoder().decode(CodableColor.self, from: data)
    {
      self.profileCustomAccent = value
    }
    if d.object(forKey: profileGreetingEnabledKey) != nil {
      self.profileGreetingEnabled = d.bool(forKey: profileGreetingEnabledKey)
    }
    if let data = d.data(forKey: sidebarOrderKey),
      let decoded = try? JSONDecoder().decode([String].self, from: data)
    {
      self.sidebarOrder = decoded
    }
    if let data = d.data(forKey: sidebarFavoritesKey),
      let decoded = try? JSONDecoder().decode([String].self, from: data)
    {
      self.sidebarFavorites = Set(decoded)
    }
    if let data = d.data(forKey: sidebarHiddenKey),
      let decoded = try? JSONDecoder().decode([String].self, from: data)
    {
      self.sidebarHidden = Set(decoded)
    }
    if let data = d.data(forKey: dismissedAnnouncementsKey),
      let decoded = try? JSONDecoder().decode([String].self, from: data)
    {
      self.dismissedAnnouncementIDs = Set(decoded)
    }
  }
}
