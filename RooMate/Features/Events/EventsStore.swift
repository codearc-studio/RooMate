import Combine
import Foundation

#if canImport(UserNotifications)
  import UserNotifications
#endif

/// Observable store that fetches and holds school calendar events.
@MainActor
final class EventsStore: ObservableObject {
  @Published private(set) var events: [CalendarEvent] = []
  @Published private(set) var lastError: Error?
  @Published private(set) var isLoading = false
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var isShowingSavedData = false
  @Published private(set) var selectedSources: Set<CalendarSource> = [.allEvents]
  @Published var selectedGrouping: CalendarGroupingMode = .day {
    didSet { Self.defaults.set(selectedGrouping.rawValue, forKey: selectedGroupingKey) }
  }

  private var task: Task<Void, Never>?
  private var savedEventNotificationTask: Task<Void, Never>?
  private var cache: [Set<CalendarSource>: [CalendarEvent]] = [:]
  private var cacheTime: [Set<CalendarSource>: Date] = [:]

  private static let defaults: UserDefaults = {
    let suiteName = "dev.roomate.prefs"
    return UserDefaults(suiteName: suiteName) ?? .standard
  }()

  private let legacySelectedSourceKey = "EventsSelectedSource"
  private let selectedSourcesKey = "EventsSelectedSources"
  private let selectedGroupingKey = "EventsSelectedGrouping"
  private let cacheExpiration: TimeInterval = 4 * 60 * 60
  private let eventNotificationPrefix = "roomate.events."

  init() {
    loadPersistedPreferences()
    restorePersistentCache(for: selectedSources)
    loadEvents(for: selectedSources, forceRefresh: true)
  }

  func refresh() {
    loadEvents(for: selectedSources, forceRefresh: true)
  }

  func setSources(_ sources: Set<CalendarSource>) {
    let normalized = normalize(sources)
    guard normalized != selectedSources else {
      if events.isEmpty { loadEvents(for: normalized) }
      return
    }

    selectedSources = normalized
    persistSelectedSources()
    loadEvents(for: normalized)
  }

  func toggleSource(_ source: CalendarSource) {
    if source == .allEvents {
      setSources([.allEvents])
      return
    }

    var updated = selectedSources
    updated.remove(.allEvents)
    if updated.contains(source) {
      updated.remove(source)
    } else {
      updated.insert(source)
    }

    // Never leave Events with no visible calendars. If the final individual
    // source is removed, fall back to the All Events convenience selection.
    setSources(updated.isEmpty ? [.allEvents] : updated)
  }

  var selectionTitle: String {
    if selectedSources.contains(.allEvents) { return CalendarSource.allEvents.title }
    let ordered = CalendarSource.individualCases.filter { selectedSources.contains($0) }
    if ordered.count == 1 { return ordered[0].title }
    return "\(ordered.count) Calendars"
  }

  var selectionDetail: String {
    if selectedSources.contains(.allEvents) {
      return "All school calendars"
    }
    return CalendarSource.individualCases
      .filter { selectedSources.contains($0) }
      .map(\.title)
      .joined(separator: ", ")
  }

  private func normalize(_ sources: Set<CalendarSource>) -> Set<CalendarSource> {
    if sources.isEmpty || sources.contains(.allEvents) {
      return [.allEvents]
    }
    return Set(CalendarSource.individualCases.filter { sources.contains($0) })
  }

  private func persistSelectedSources() {
    let values = selectedSources.map(\.rawValue).sorted()
    if let data = try? JSONEncoder().encode(values) {
      Self.defaults.set(data, forKey: selectedSourcesKey)
    }
  }

  private func loadPersistedPreferences() {
    if let data = Self.defaults.data(forKey: selectedSourcesKey),
      let values = try? JSONDecoder().decode([String].self, from: data)
    {
      let decoded = Set(values.compactMap(CalendarSource.init(rawValue:)))
      selectedSources = normalize(decoded)
    } else if let rawSource = Self.defaults.string(forKey: legacySelectedSourceKey),
      let source = CalendarSource(rawValue: rawSource)
    {
      // V5/V6 migration: old builds supported exactly one source.
      selectedSources = [source]
      persistSelectedSources()
    }

    if let rawGrouping = Self.defaults.string(forKey: selectedGroupingKey),
      let grouping = CalendarGroupingMode(rawValue: rawGrouping)
    {
      selectedGrouping = grouping
    }
  }

  private func loadEvents(for sources: Set<CalendarSource>, forceRefresh: Bool = false) {
    let normalized = normalize(sources)
    restorePersistentCache(for: normalized)
    task?.cancel()

    if !forceRefresh, let cached = cache[normalized], isCacheValid(for: normalized) {
      events = cached
      lastError = nil
      lastUpdated = cacheTime[normalized]
      isShowingSavedData = false
      isLoading = false
      Task { await refreshSavedEventNotifications() }
      return
    }

    isLoading = true
    lastError = nil

    task = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        guard let sourceURL = CalendarSource.feedURL(for: normalized) else {
          throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: sourceURL)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode)
        else {
          throw URLError(.badServerResponse)
        }

        guard let calendarText = String(data: data, encoding: .utf8),
          calendarText.localizedCaseInsensitiveContains("BEGIN:VCALENDAR"),
          calendarText.localizedCaseInsensitiveContains("END:VCALENDAR")
        else {
          throw EventsStoreError.invalidCalendarData
        }

        let parsed = ICSParser.parseEvents(from: calendarText)
        if calendarText.localizedCaseInsensitiveContains("BEGIN:VEVENT"), parsed.isEmpty {
          throw EventsStoreError.invalidCalendarData
        }
        try Task.checkCancellation()

        let refreshedAt = Date()
        cache[normalized] = parsed
        cacheTime[normalized] = refreshedAt
        try? PersistentRemoteCache.save(
          parsed,
          refreshedAt: refreshedAt,
          named: cacheName(for: normalized)
        )
        lastError = nil
        RemoteDataHealthStore.shared.recordSuccess(.events, refreshedAt: refreshedAt)

        // A slow request from an old source combination may finish after the
        // user changes calendars. Cache it, but never paint over the new choice.
        if selectedSources == normalized {
          events = parsed
          lastUpdated = refreshedAt
          isShowingSavedData = false
          isLoading = false
          await refreshSavedEventNotifications()
        }
      } catch is CancellationError {
        // A newer request owns the visible loading state.
      } catch {
        if (error as NSError).code == NSURLErrorCancelled { return }

        TelemetryTracker.trackScraperFailure(
          signal: "Scraper.ScheduleSyncFailed",
          target: "Events",
          errorType: (error is URLError) ? "NetworkError" : "ParseError",
        )

        guard selectedSources == normalized else { return }
        lastError = error
        // Preserve the last valid source-combination cache instead of
        // blanking the screen on a transient network/parser failure.
        if let cached = cache[normalized] {
          events = cached
        }
        lastUpdated = cacheTime[normalized]
        isShowingSavedData = cache[normalized] != nil
        RemoteDataHealthStore.shared.recordFailure(
          .events,
          error: error,
          usingSavedData: isShowingSavedData,
          lastUpdated: lastUpdated
        )
        isLoading = false
      }
    }
  }

  private func isCacheValid(for sources: Set<CalendarSource>) -> Bool {
    guard let time = cacheTime[sources] else { return false }
    return Date().timeIntervalSince(time) < cacheExpiration
  }

  private func cacheName(for sources: Set<CalendarSource>) -> String {
    let values = sources.map(\.rawValue).sorted().joined(separator: "-")
    return "events-\(values)"
  }

  private func restorePersistentCache(for sources: Set<CalendarSource>) {
    let normalized = normalize(sources)
    guard cache[normalized] == nil,
      let cached = PersistentRemoteCache.load(
        [CalendarEvent].self,
        named: cacheName(for: normalized)
      )
    else { return }

    cache[normalized] = cached.value
    cacheTime[normalized] = cached.refreshedAt
    if selectedSources == normalized {
      events = cached.value
      lastUpdated = cached.refreshedAt
      isShowingSavedData = true
    }
  }

  // MARK: - Saved event notifications

  /// Rebuild event reminders. Users can choose saved events only, every event
  /// from their selected calendars, or both. Timed events fire 30 minutes
  /// before start; all-day events fire at 8:00 AM on the event day.
  func refreshSavedEventNotifications() async {
    #if canImport(UserNotifications)
      savedEventNotificationTask?.cancel()
      let eventsSnapshot = events

      let task = Task { @MainActor [weak self] in
        guard let self else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let oldIDs = pending.map(\.identifier).filter {
          $0.hasPrefix(self.eventNotificationPrefix)
        }
        if !oldIDs.isEmpty {
          center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }

        let standard = UserDefaults.standard
        let savedRemindersEnabled =
          standard.object(forKey: "RooMateNotifySavedEvents") == nil
          ? false
          : standard.bool(forKey: "RooMateNotifySavedEvents")
        let calendarRemindersEnabled =
          standard.object(forKey: "RooMateNotifyCalendarEvents") == nil
          ? false
          : standard.bool(forKey: "RooMateNotifyCalendarEvents")

        let scheduleDefaults = UserDefaults(suiteName: "dev.roomate.prefs")
        let masterEnabled = scheduleDefaults?.bool(forKey: "NotificationsEnabled") ?? false
        guard savedRemindersEnabled || calendarRemindersEnabled, masterEnabled else { return }

        let settings = await center.notificationSettings()
        guard
          settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }

        let bookmarkedKeys = Set(
          (standard.string(forKey: "RooMateEventBookmarks") ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        )
        let now = Date()
        let pauseUntil = (scheduleDefaults?.object(forKey: "NotificationPauseUntil") as? Date)
          .flatMap { $0 > now ? $0 : nil }
        let horizon = Calendar.current.date(byAdding: .day, value: 45, to: now) ?? now

        let upcoming =
          eventsSnapshot
          .filter { event in
            let isSaved = bookmarkedKeys.contains(self.stableKey(for: event))
            let wanted = calendarRemindersEnabled || (savedRemindersEnabled && isSaved)
            return wanted && event.startDate > now && event.startDate <= horizon
          }
          .sorted { $0.startDate < $1.startDate }

        var requests: [UNNotificationRequest] = []
        for event in upcoming {
          let fireDate: Date
          if self.isLikelyAllDay(event) {
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
            guard
              let morning = calendar.date(
                bySettingHour: 8,
                minute: 0,
                second: 0,
                of: event.startDate
              )
            else { continue }
            fireDate = morning
          } else {
            fireDate = event.startDate.addingTimeInterval(-30 * 60)
          }

          guard fireDate > now else { continue }
          if let pauseUntil, fireDate < pauseUntil { continue }

          let content = UNMutableNotificationContent()
          let isSaved = bookmarkedKeys.contains(self.stableKey(for: event))
          if isSaved && savedRemindersEnabled {
            content.title =
              self.isLikelyAllDay(event)
              ? "Saved event today"
              : "Saved event in 30 minutes"
          } else {
            content.title =
              self.isLikelyAllDay(event)
              ? "School event today"
              : "School event in 30 minutes"
          }
          let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          content.body = location.isEmpty ? event.title : "\(event.title) • \(location)"
          content.sound = .default

          var calendar = Calendar.current
          calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
          var components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
          )
          components.timeZone = calendar.timeZone

          requests.append(
            UNNotificationRequest(
              identifier:
                "\(self.eventNotificationPrefix)\(Int(event.startDate.timeIntervalSince1970)).\(abs(self.stableKey(for: event).hashValue))",
              content: content,
              trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
          )

          if requests.count >= 8 { break }
        }

        for request in requests.prefix(8) {
          try? await center.add(request)
        }
      }

      savedEventNotificationTask = task
      await task.value
    #endif
  }

  func clearSavedEventNotifications() {
    #if canImport(UserNotifications)
      Task { @MainActor [weak self] in
        guard let self else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter {
          $0.hasPrefix(self.eventNotificationPrefix)
        }
        if !identifiers.isEmpty {
          center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
      }
    #endif
  }

  private func stableKey(for event: CalendarEvent) -> String {
    let timestamp = Int(event.startDate.timeIntervalSince1970)
    let location = event.location ?? ""
    return "\(timestamp)|\(event.title)|\(location)"
      .replacingOccurrences(of: "\n", with: " ")
  }

  private func isLikelyAllDay(_ event: CalendarEvent) -> Bool {
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    let components = calendar.dateComponents([.hour, .minute, .second], from: event.startDate)
    return components.hour == 0 && components.minute == 0 && components.second == 0
  }

  deinit {
    task?.cancel()
    savedEventNotificationTask?.cancel()
  }
}

private enum EventsStoreError: LocalizedError {
  case invalidCalendarData

  var errorDescription: String? {
    "The calendar feed returned an unexpected data format."
  }
}
