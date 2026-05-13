import Foundation
import Combine

/// Observable store that fetches and holds school calendar events
@MainActor
final class EventsStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var isLoading: Bool = false
    @Published var selectedSource: CalendarSource = .allEvents {
        didSet { Self.defaults.set(selectedSource.rawValue, forKey: selectedSourceKey) }
    }
    @Published var selectedGrouping: CalendarGroupingMode = .day {
        didSet { Self.defaults.set(selectedGrouping.rawValue, forKey: selectedGroupingKey) }
    }
    
    private var task: Task<Void, Never>? = nil
    private var cache: [CalendarSource: [CalendarEvent]] = [:]
    private var cacheTime: [CalendarSource: Date] = [:]
    private static let defaults: UserDefaults = {
        let suiteName = "dev.roomate.prefs"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()
    private let selectedSourceKey = "EventsSelectedSource"
    private let selectedGroupingKey = "EventsSelectedGrouping"
    
    /// Cache expiration time (4 hours)
    private let cacheExpiration: TimeInterval = 4 * 60 * 60
    
    init() {
        loadPersistedPreferences()
    }
    
    func refresh() {
        loadEvents(for: selectedSource, forceRefresh: true)
    }
    
    func setSource(_ source: CalendarSource) {
        selectedSource = source
        loadEvents(for: source)
    }

    private func loadPersistedPreferences() {
        if let rawSource = Self.defaults.string(forKey: selectedSourceKey), let source = CalendarSource(rawValue: rawSource) {
            selectedSource = source
        }
        if let rawGrouping = Self.defaults.string(forKey: selectedGroupingKey), let grouping = CalendarGroupingMode(rawValue: rawGrouping) {
            selectedGrouping = grouping
        }
    }
    
    private func loadEvents(for source: CalendarSource, forceRefresh: Bool = false) {
        task?.cancel()
        
        // Check cache if not forcing refresh
        if !forceRefresh, let cachedEvents = cache[source], isCacheValid(for: source) {
            self.events = cachedEvents
            self.lastError = nil
            return
        }
        
        isLoading = true
        lastError = nil
        
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: source.url)
                let parsed = ICSParser.parseEvents(from: data)
                
                // Update cache
                await MainActor.run {
                    self.cache[source] = parsed
                    self.cacheTime[source] = Date()
                    self.events = parsed
                    self.isLoading = false
                }
            } catch {
                if (error as NSError).code == NSURLErrorCancelled { return }
                await MainActor.run {
                    self.lastError = error
                    self.events = []
                    self.isLoading = false
                }
            }
        }
    }
    
    private func isCacheValid(for source: CalendarSource) -> Bool {
        guard let cacheTime = cacheTime[source] else { return false }
        return Date().timeIntervalSince(cacheTime) < cacheExpiration
    }
    
    deinit {
        task?.cancel()
    }
}
