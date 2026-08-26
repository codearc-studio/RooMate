import Combine
import Foundation

#if canImport(UserNotifications)
  import UserNotifications
#endif

/// Source-backed athletics store. RooMate intentionally keeps this model small:
/// the live Google Sheet is authoritative for games/team names, while roster and
/// coach data stay out of the app until there is a verified source.
@MainActor
final class SportsStore: ObservableObject {
  @Published private(set) var liveGames: [SportsGame] = []
  @Published private(set) var lastError: Error?
  @Published private(set) var isLoading = false
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var isShowingSavedData = false

  private var refreshTask: Task<Void, Never>?
  private var gameNotificationTask: Task<Void, Never>?
  private var refreshGeneration = 0

  private let gameNotificationPrefix = "roomate.sports."
  private let csvURLString =
    "https://docs.google.com/spreadsheets/d/1qjS03N92vjx6MXc0PTgOJfTSsY6HAJKFCpu0rVuoyOk/gviz/tq?tqx=out:csv"

  init() {
    if let cached = PersistentRemoteCache.load([SportsGame].self, named: "sports") {
      liveGames = cached.value
      lastUpdated = cached.refreshedAt
      isShowingSavedData = !cached.value.isEmpty
    }
    refresh()
  }

  func refresh() {
    refreshTask?.cancel()
    refreshGeneration += 1
    let generation = refreshGeneration
    isLoading = true

    refreshTask = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        guard let csvURL = URL(string: csvURLString) else {
          throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: csvURL)
        try Task.checkCancellation()

        guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode)
        else {
          throw URLError(.badServerResponse)
        }

        guard SportsCSVParser.hasExpectedHeader(in: data) else {
          throw SportsStoreError.invalidFeed
        }

        let parsed = SportsCSVParser.parseSportsGames(from: data)
        try Task.checkCancellation()
        guard generation == refreshGeneration else { return }

        // Replace the feed only after a complete successful request so a
        // temporary network/server failure never blanks the Sports UI.
        guard !parsed.isEmpty else { throw SportsStoreError.invalidFeed }
        let refreshedAt = Date()
        liveGames = parsed
        lastUpdated = refreshedAt
        isShowingSavedData = false
        lastError = nil
        isLoading = false
        try? PersistentRemoteCache.save(parsed, refreshedAt: refreshedAt, named: "sports")
        RemoteDataHealthStore.shared.recordSuccess(.sports, refreshedAt: refreshedAt)
        await refreshSavedGameNotifications()
      } catch is CancellationError {
        // A newer refresh owns the loading state now.
      } catch {
        guard generation == refreshGeneration else { return }
        TelemetryTracker.trackScraperFailure(
          signal: "Scraper.ScheduleSyncFailed",
          target: "Sports",
          errorType: (error is URLError) ? "NetworkError" : "ParseError",
        )
        lastError = error
        isShowingSavedData = !liveGames.isEmpty
        isLoading = false
        RemoteDataHealthStore.shared.recordFailure(
          .sports,
          error: error,
          usingSavedData: isShowingSavedData,
          lastUpdated: lastUpdated
        )
      }
    }
  }

  /// Rebuild reminders only for games the user explicitly saved. Team-following
  /// preferences remain untouched for a possible future return, but they no
  /// longer influence notifications or any active RooMate experience.
  func refreshSavedGameNotifications() async {
    #if canImport(UserNotifications)
      gameNotificationTask?.cancel()

      let gamesSnapshot = liveGames
      let task = Task { @MainActor [weak self] in
        guard let self else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let oldIDs =
          pending
          .map(\.identifier)
          .filter { $0.hasPrefix(self.gameNotificationPrefix) }

        if !oldIDs.isEmpty {
          center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }

        let savedGameIDs = Set(
          (UserDefaults.standard.string(forKey: "RooMateSportsGameReminders") ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )

        let scheduleDefaults = UserDefaults(suiteName: "dev.roomate.prefs")
        let masterEnabled = scheduleDefaults?.bool(forKey: "NotificationsEnabled") ?? false

        guard masterEnabled, !savedGameIDs.isEmpty else { return }

        let settings = await center.notificationSettings()
        guard
          settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else {
          return
        }

        let now = Date()
        let pauseUntil = (scheduleDefaults?.object(forKey: "NotificationPauseUntil") as? Date)
          .flatMap { $0 > now ? $0 : nil }
        let horizon = Calendar.current.date(byAdding: .day, value: 21, to: now) ?? now

        let upcoming = gamesSnapshot.compactMap { game -> (SportsGame, Date)? in
          guard savedGameIDs.contains(game.id),
            game.status != .cancelled,
            game.status != .eliminated,
            let startDate = self.combinedGameDate(for: game),
            startDate > now,
            startDate <= horizon
          else {
            return nil
          }

          return (game, startDate)
        }
        .sorted { $0.1 < $1.1 }

        var requests: [UNNotificationRequest] = []

        for (game, startDate) in upcoming {
          let fireDate = startDate.addingTimeInterval(-60 * 60)
          guard fireDate > now else { continue }
          if let pauseUntil, fireDate < pauseUntil { continue }

          let content = UNMutableNotificationContent()
          content.title = "\(game.team) game in 1 hour"

          let opponent = game.opponent.trimmingCharacters(in: .whitespacesAndNewlines)
          let matchup = opponent.isEmpty ? "Game" : "vs \(opponent)"
          let location = gameLocationLabel(game.location)
          content.body = [matchup, location, "Starts \(notificationTime(startDate))"]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
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
              identifier: gameNotificationIdentifier(game: game, startDate: startDate),
              content: content,
              trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
              )
            )
          )

          // Schedule bucket uses up to 40 and saved Events up to 8, leaving
          // enough room for this bounded Sports bucket under the app-wide cap.
          if requests.count >= 12 { break }
        }

        for request in requests.prefix(12) {
          try? await center.add(request)
        }
      }

      gameNotificationTask = task
      await task.value
    #endif
  }

  func clearSavedGameNotifications() {
    #if canImport(UserNotifications)
      Task { @MainActor [weak self] in
        guard let self else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers =
          pending
          .map(\.identifier)
          .filter { $0.hasPrefix(self.gameNotificationPrefix) }

        if !identifiers.isEmpty {
          center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
      }
    #endif
  }

  deinit {
    refreshTask?.cancel()
    gameNotificationTask?.cancel()
  }

  private func combinedGameDate(for game: SportsGame) -> Date? {
    guard let day = game.date else { return nil }

    let time = game.time.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !time.isEmpty else { return nil }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .current

    for format in ["h:mm a", "h:mma", "hh:mm a", "H:mm", "HH:mm"] {
      formatter.dateFormat = format
      if let parsed = formatter.date(from: time) {
        var calendar = Calendar.current
        calendar.timeZone = formatter.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: parsed)
        return calendar.date(
          bySettingHour: components.hour ?? 0,
          minute: components.minute ?? 0,
          second: 0,
          of: day
        )
      }
    }

    return nil
  }

  private func notificationTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
  }

  private func gameLocationLabel(_ raw: String) -> String {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "H": "Home"
    case "A": "Away"
    default: raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private func gameNotificationIdentifier(
    game: SportsGame,
    startDate: Date
  ) -> String {
    let raw = "\(game.team).\(game.opponent)"
      .lowercased()
      .map { character in
        character.isLetter || character.isNumber ? character : "-"
      }
    return "\(gameNotificationPrefix)\(String(raw)).\(Int(startDate.timeIntervalSince1970))"
  }
}

private enum SportsStoreError: LocalizedError {
  case invalidFeed

  var errorDescription: String? {
    "The Sports schedule returned an unexpected data format."
  }
}
