import Combine
import Foundation

@MainActor
final class MenuStore: ObservableObject {
  @Published private(set) var availableDates: [MenuDateEntry] = []
  @Published private(set) var currentMenu: MenuDaySnapshot?
  @Published private(set) var lastError: Error?
  @Published private(set) var isLoading: Bool = false
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var isShowingSavedData = false
  @Published private(set) var selectedDate: MenuDateEntry?
  @Published private(set) var selectedMealPeriodID: String?
  @Published var filters = MenuFilterState()

  private let service = MenuService()
  private var task: Task<Void, Never>?
  private var cache: [MenuDateEntry: MenuDaySnapshot] = [:]
  private var requestGeneration = 0

  private struct CachedMenu: Codable {
    let entry: MenuDateEntry
    let snapshot: MenuDaySnapshot
  }

  private struct CachePayload: Codable {
    let dates: [MenuDateEntry]
    let menus: [CachedMenu]
  }

  init() {
    guard let cached = PersistentRemoteCache.load(CachePayload.self, named: "dining") else {
      return
    }
    availableDates = cached.value.dates
    cache = Dictionary(uniqueKeysWithValues: cached.value.menus.map { ($0.entry, $0.snapshot) })
    lastUpdated = cached.refreshedAt
    isShowingSavedData = !cache.isEmpty

    if let preferred = preferredDate(from: availableDates), let snapshot = cache[preferred] {
      selectedDate = preferred
      currentMenu = snapshot
      updateSelectedMealPeriod(using: snapshot)
    }
  }

  private func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
      print("[DiningStore] \(message())")
    #endif
  }

  func refresh() {
    debugLog("Refreshing menu index.")
    task?.cancel()
    requestGeneration += 1
    let generation = requestGeneration
    lastError = nil

    task = Task { [weak self] in
      guard let self else { return }
      self.isLoading = true
      defer {
        if generation == self.requestGeneration {
          self.isLoading = false
        }
      }

      do {
        let dates = try await self.service.loadIndex()
        try Task.checkCancellation()
        guard generation == self.requestGeneration else { return }

        guard let preferred = self.preferredDate(from: dates) else {
          throw MenuServiceError.noDatesFound
        }

        // Do not discard a previously usable index/menu until the new
        // index has actually loaded successfully. This keeps a transient
        // dining outage from blanking the entire feature.
        self.availableDates = dates
        debugLog("Selecting preferred date: \(preferred.dateString)")
        await self.loadDate(
          preferred,
          forceRefresh: true,
          preserveFilters: true,
          generation: generation
        )
      } catch is CancellationError {
        return
      } catch {
        guard generation == self.requestGeneration else { return }
        self.record(error: error, context: "Refresh failed")
      }
    }
  }

  func selectDate(_ entry: MenuDateEntry) {
    debugLog("Selected date: \(entry.dateString)")
    task?.cancel()
    requestGeneration += 1
    let generation = requestGeneration

    task = Task { [weak self] in
      guard let self else { return }
      self.isLoading = true
      defer {
        if generation == self.requestGeneration {
          self.isLoading = false
        }
      }
      await self.loadDate(
        entry,
        forceRefresh: false,
        preserveFilters: true,
        generation: generation
      )
    }
  }

  func reloadSelectedDate() {
    guard let selectedDate else {
      refresh()
      return
    }

    debugLog("Reloading \(selectedDate.dateString).")
    task?.cancel()
    requestGeneration += 1
    let generation = requestGeneration

    task = Task { [weak self] in
      guard let self else { return }
      self.isLoading = true
      defer {
        if generation == self.requestGeneration {
          self.isLoading = false
        }
      }
      await self.loadDate(
        selectedDate,
        forceRefresh: true,
        preserveFilters: true,
        generation: generation
      )
    }
  }

  func selectMealPeriod(_ mealPeriodID: String) {
    debugLog("Selected meal period: \(mealPeriodID)")
    selectedMealPeriodID = mealPeriodID
  }

  var mealPeriods: [MenuMealPeriod] {
    currentMenu?.mealPeriods ?? []
  }

  var visibleStations: [MenuStation] {
    guard let currentMenu, let selectedMealPeriodID else { return [] }
    let trackingOutput = currentMenu.visibleStations(for: selectedMealPeriodID, filters: filters)
    return trackingOutput
  }

  var visibleRecipeCount: Int {
    visibleStations.reduce(0) { $0 + $1.recipes.count }
  }

  private func loadDate(
    _ entry: MenuDateEntry,
    forceRefresh: Bool,
    preserveFilters: Bool,
    generation: Int
  ) async {
    guard generation == requestGeneration else { return }
    selectedDate = entry
    lastError = nil

    if !forceRefresh, let cached = cache[entry] {
      debugLog("Using cached menu for \(entry.dateString).")
      currentMenu = cached
      updateSelectedMealPeriod(using: cached)
      return
    }

    // Once the date label changes, never leave the previous day's food
    // visible underneath it while the new page is loading/failing.
    if currentMenu?.date != entry.date {
      currentMenu = nil
      selectedMealPeriodID = nil
    }

    do {
      let snapshot = try await service.loadSnapshot(for: entry)
      try Task.checkCancellation()
      guard generation == requestGeneration, selectedDate == entry else { return }

      cache[entry] = snapshot
      currentMenu = snapshot
      updateSelectedMealPeriod(using: snapshot)
      let refreshedAt = Date()
      lastUpdated = refreshedAt
      isShowingSavedData = false
      persistCache(refreshedAt: refreshedAt)
      RemoteDataHealthStore.shared.recordSuccess(.dining, refreshedAt: refreshedAt)
      lastError = nil
      debugLog("Loaded menu with \(visibleRecipeCount) visible recipes.")
    } catch is CancellationError {
      return
    } catch {
      guard generation == requestGeneration else { return }
      record(error: error, context: "Menu load failed")
      if let cached = cache[entry] {
        currentMenu = cached
        updateSelectedMealPeriod(using: cached)
      }
      if !preserveFilters {
        filters = MenuFilterState()
      }
    }
  }

  private func record(error: Error, context: String) {
    debugLog("\(context): \(error.localizedDescription)")
    TelemetryTracker.trackScraperFailure(
      signal: "Scraper.DiningMenuFailed",
      target: "Dining",
      errorType: (error is URLError) ? "NetworkError" : "ParseError",
    )
    lastError = error
    isShowingSavedData = currentMenu != nil || !cache.isEmpty
    RemoteDataHealthStore.shared.recordFailure(
      .dining,
      error: error,
      usingSavedData: isShowingSavedData,
      lastUpdated: lastUpdated
    )
  }

  private func persistCache(refreshedAt: Date) {
    let menus = cache.map { CachedMenu(entry: $0.key, snapshot: $0.value) }
      .sorted { $0.entry.date < $1.entry.date }
    try? PersistentRemoteCache.save(
      CachePayload(dates: availableDates, menus: menus),
      refreshedAt: refreshedAt,
      named: "dining"
    )
  }

  private func updateSelectedMealPeriod(using menu: MenuDaySnapshot) {
    if let current = selectedMealPeriodID, menu.mealPeriods.contains(where: { $0.id == current }) {
      selectedMealPeriodID = current
    } else {
      selectedMealPeriodID = menu.mealPeriods.first?.id
    }
    debugLog("Active meal period: \(selectedMealPeriodID ?? "None")")
  }

  private func preferredDate(from entries: [MenuDateEntry]) -> MenuDateEntry? {
    if let selectedDate,
      let existing = entries.first(where: { $0.dateString == selectedDate.dateString })
    {
      return existing
    }

    let calendar = Calendar.current
    if let today = entries.first(where: { calendar.isDateInToday($0.date) }) {
      return today
    }

    let now = Date()
    if let upcoming = entries.first(where: { $0.date >= calendar.startOfDay(for: now) }) {
      return upcoming
    }

    return entries.first
  }

  deinit {
    task?.cancel()
  }
}
