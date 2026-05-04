import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import TelemetryDeck

@MainActor
final class UserScheduleStore: ObservableObject {
    private static let defaults: UserDefaults = {
        let suiteName = "dev.roomate.prefs"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()

    @Published var assignments: [Level: ClassAssignment] = [:] { didSet { Task { @MainActor in self.save() } } }
    @Published var specialColors: [SpecialBlock: CodableColor] = [:] { didSet { Task { @MainActor in self.save() } } }
    @Published var specialFree: [SpecialBlock: Bool] = [:] { didSet { Task { @MainActor in self.save() } } }
    @Published var clubs: [Club] = [] { didSet { Task { @MainActor in self.save() } } }
    @Published var appearance: AppearancePreference = .system { didSet { Task { @MainActor in self.save() } } }
    @Published var cardColorStyle: CardColorStyle = .colors { didSet { Task { @MainActor in self.save() } } }

    // Preference to show/hide Special Schedules
    @Published var showSpecialSchedules: Bool = true { didSet { Task { @MainActor in self.save() } } }

    @Published var canvasDomain: String = "afs.instructure.com" { didSet { Task { @MainActor in self.save() } } }
    @Published var canvasToken: String = "" { didSet { Task { @MainActor in self.save() } } }

    @Published private(set) var canvasTodos: [CanvasTodoItem] = []
    @Published private(set) var isFetchingTodos: Bool = false
    @Published private(set) var fetchError: String?

    @Published private(set) var courses: [CanvasCourse] = []
    @Published private(set) var gradesByCourse: [Int: GradeSummary] = [:]
    @Published private(set) var isFetchingGrades: Bool = false
    @Published private(set) var gradesError: String?

    // Per-course assignments state
    @Published private(set) var assignmentsByCourse: [Int: [CanvasAssignment]] = [:]
    @Published private(set) var assignmentsErrorByCourse: [Int: String] = [:]
    @Published private(set) var isFetchingAssignmentsForCourse: Set<Int> = []

    @Published var completedTodoIDs: Set<String> = [] { didSet { Task { @MainActor in self.save() } } }

    @Published var notificationsEnabled: Bool = true { didSet { Task { @MainActor in self.save() } } }
    @Published private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    @Published var notifyClassStartingSoon: Bool = true { didSet { Task { @MainActor in self.save() } } }
    @Published var notifyClassEndingSoon: Bool = false { didSet { Task { @MainActor in self.save() } } }

    @Published var pendingAnnouncement: UpdateAnnouncement? { didSet { } }

    @Published private(set) var lastTodosHTTPStatus: Int?
    @Published private(set) var lastCoursesHTTPStatus: Int?
    let lastTodosEndpoint: String = "/api/v1/users/self/todo"
    let lastCoursesEndpoint: String = "/api/v1/courses"

    // NEW: Dated special schedules fetched from Google Sheet
    @Published private(set) var datedSpecials: [DatedSpecialSchedule] = []
    @Published private(set) var isFetchingDatedSpecials: Bool = false
    @Published private(set) var datedSpecialsError: String?

    private let defaultsKey = "UserScheduleAssignments"
    private let specialDefaultsKey = "UserSpecialBlockColors"
    private let specialFreeDefaultsKey = "UserSpecialBlockFree"
    private let clubsDefaultsKey = "UserClubs"
    private let appearanceDefaultsKey = "UserAppearancePreference"
    private let cardStyleDefaultsKey = "UserCardColorStyle"
    private let canvasDomainKey = "CanvasDomain"
    private let canvasTokenKey = "CanvasToken"
    private let completedTodosKey = "CompletedCanvasTodoIDs"
    private let notificationsEnabledKey = "NotificationsEnabled"
    private let notifyClassStartingSoonKey = "NotifyClassStartingSoon"
    private let notifyClassEndingSoonKey = "NotifyClassEndingSoon"

    // Preference key for Special Schedules visibility
    private let showSpecialSchedulesKey = "ShowSpecialSchedules"

    private let lastShownUpdateNumberKey = "LastShownUpdateNumber"
    private let updateFeedURLString = "https://docs.google.com/spreadsheets/d/e/2PACX-1vQzOVA2twWoSkiRYwAdAjjkT7pOBD1GdngOTx9BrsTklmLa1ddsMnS48o1S4yPnETcaf2ah3UJs_GLr/pub?gid=60316779&single=true&output=csv"

    // NEW: Index sheet for special schedules
    private let specialsIndexURLString = "https://docs.google.com/spreadsheets/d/e/2PACX-1vTSiypnPYj6Fs2SWrH6NQju7Cp8Ky1OWcYDT4_dwBWn397rGlyP_D2WqZEtnI0fRSy-8YpKm3JeGJ-1/pub?gid=287965335&single=true&output=csv"

    private let api = CanvasAPI()
    private let updateFeed = UpdateFeed()
    private let specialsFeed = SpecialScheduleFeed()

    private var didSignalCanvasUsageThisLaunch = false

    // Track an in-flight grades refresh to avoid overlap
    private var gradesRefreshTask: Task<Void, Never>?

    init() { load(); Task { await refreshNotificationStatus() } }

    func assignment(for level: Level) -> ClassAssignment {
        assignments[level] ?? .default(for: level)
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

    func colorForCanvasCourseName(_ courseName: String?) -> Color {
        guard let name = courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .accentColor
        }
        let lower = name.lowercased()
        for (level, assignment) in assignments {
            guard !assignment.isFree else { continue }
            let title = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !title.isEmpty && (lower == title || lower.contains(title) || title.contains(lower)) {
                return assignment.color.swiftUIColor
            }
            let levelName = level.displayName.lowercased()
            if lower == levelName || lower.contains(levelName) || levelName.contains(lower) {
                return assignment.color.swiftUIColor
            }
        }
        for level in Level.allCases {
            let levelName = level.displayName.lowercased()
            if lower == levelName || lower.contains(levelName) || levelName.contains(lower) {
                return level.defaultColor
            }
        }
        return .accentColor
    }

    private func sendCanvasUsageOnceIfNeeded() {
        guard !didSignalCanvasUsageThisLaunch else { return }
        guard !canvasDomain.isEmpty, !canvasToken.isEmpty else { return }
        didSignalCanvasUsageThisLaunch = true
        TelemetryDeck.signal("UsedCanvasAPI")
    }

    private func sendTelemetry(_ name: String, endpoint: String?, status: Int?) {
        if let endpoint, let status {
            TelemetryDeck.signal(name, parameters: [
                "endpoint": endpoint,
                "status": "\(status)"
            ])
        } else {
            TelemetryDeck.signal(name)
        }
    }

    func clearCanvasToken() {
        canvasToken = ""
        let d = Self.defaults
        d.removeObject(forKey: canvasTokenKey)
        #if DEBUG
        print("Saved Canvas settings - domain: \(canvasDomain), tokenLength: 0")
        #endif
        d.synchronize()
    }

    // MARK: - Specials feed

    func refreshDatedSpecials() async {
        guard let url = URL(string: specialsIndexURLString) else { return }
        isFetchingDatedSpecials = true
        datedSpecialsError = nil
        defer { isFetchingDatedSpecials = false }
        do {
            let items = try await specialsFeed.fetchAll(from: url)
            self.datedSpecials = items
        } catch {
            self.datedSpecials = []
            self.datedSpecialsError = (error as NSError).localizedDescription
        }
    }

    // Specials on a specific calendar date (ignores time)
    func specials(on date: Date) -> [DatedSpecialSchedule] {
        let cal = Calendar.current
        return datedSpecials.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    // Return blocks for a given date, using a dated special if present, else default weekly by weekday
    func overrideBlocks(for date: Date, weekday: Weekday) -> [BellBlock] {
        if let special = specials(on: date).first {
            return special.blocks
        }
        return BellSchedule.weekly[weekday] ?? []
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

    // MARK: - Canvas APIs
    func refreshCanvasTodos() async {
        sendCanvasUsageOnceIfNeeded()
        isFetchingTodos = true
        fetchError = nil
        lastTodosHTTPStatus = nil
        do {
            let items = try await api.fetchTodos(domain: canvasDomain, token: canvasToken)
            self.canvasTodos = items
            self.lastTodosHTTPStatus = 200
            let currentIDs = Set(items.map { $0.id })
            completedTodoIDs = completedTodoIDs.intersection(currentIDs)
        } catch {
            // Treat cancellations as benign
            if (error is CancellationError) || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled) {
                // Don’t surface cancellation
            } else {
                self.fetchError = (error as NSError).localizedDescription
                self.canvasTodos = []
                let ns = error as NSError
                if ns.domain == "CanvasAPI" {
                    self.lastTodosHTTPStatus = ns.code
                }
            }
        }
        isFetchingTodos = false
    }

    func refreshCanvasCoursesAndGrades() async {
        // Coalesce overlapping refreshes
        if isFetchingGrades {
            return
        }

        sendCanvasUsageOnceIfNeeded()
        isFetchingGrades = true
        gradesError = nil
        lastCoursesHTTPStatus = nil

        // Track this refresh task (so a caller could choose to cancel in the future if desired)
        gradesRefreshTask = Task { [canvasDomain, canvasToken] in
            do {
                let fetchedCourses = try await api.fetchCourses(domain: canvasDomain, token: canvasToken)
                self.courses = fetchedCourses
                self.lastCoursesHTTPStatus = 200

                var summaries: [Int: GradeSummary] = [:]

                try await withThrowingTaskGroup(of: (Int, GradeSummary?).self) { group in
                    for course in fetchedCourses {
                        group.addTask { [domain = canvasDomain, token = canvasToken] in
                            do {
                                #if DEBUG
                                print("[Grades] Fetching enrollments for course \(course.id) – \(course.name)")
                                #endif
                                let enrollments = try await self.api.fetchEnrollments(domain: domain, token: token, courseID: course.id)
                                #if DEBUG
                                print("[Grades] Course \(course.id): returned \(enrollments.count) enrollments -> types:", enrollments.map { $0.type ?? "nil" })
                                #endif
                                if let e = enrollments.first(where: { ($0.type ?? "").localizedCaseInsensitiveContains("student") }) {
                                    let s = await e.summary
                                    #if DEBUG
                                    print("[Grades] Course \(course.id): using student enrollment. currentScore=\(String(describing: s.currentScore)) currentLetter=\(String(describing: s.currentLetter)) finalScore=\(String(describing: s.finalScore)) finalLetter=\(String(describing: s.finalLetter))")
                                    #endif
                                    return (course.id, s)
                                } else if let any = enrollments.first {
                                    let s = await any.summary
                                    #if DEBUG
                                    print("[Grades] Course \(course.id): no student enrollment; using first. currentScore=\(String(describing: s.currentScore)) currentLetter=\(String(describing: s.currentLetter))")
                                    #endif
                                    return (course.id, s)
                                } else {
                                    #if DEBUG
                                    print("[Grades] Course \(course.id): no enrollments found")
                                    #endif
                                    return (course.id, nil)
                                }
                            } catch {
                                // Suppress cancellation as a benign outcome
                                let ns = error as NSError
                                if error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) {
                                    #if DEBUG
                                    // Optional: quiet log
                                    // print("[Grades] Enrollments fetch cancelled for course \(course.id)")
                                    #endif
                                    return (course.id, nil)
                                } else {
                                    #if DEBUG
                                    print("[Grades] Enrollments fetch failed for course \(course.id): \(error)")
                                    #endif
                                    return (course.id, nil)
                                }
                            }
                        }
                    }
                    for try await (courseID, summary) in group {
                        if let summary {
                            summaries[courseID] = summary
                        } else {
                            #if DEBUG
                            print("[Grades] Course \(courseID): summary is nil")
                            #endif
                        }
                    }
                }

                self.gradesByCourse = summaries
            } catch {
                // Treat cancellations as benign
                if (error is CancellationError) || ((error as NSError).domain == NSURLErrorDomain && (error as NSError).code == NSURLErrorCancelled) {
                    // Don’t surface cancellation
                } else {
                    self.gradesError = (error as NSError).localizedDescription
                    self.courses = []
                    self.gradesByCourse = [:]
                    let ns = error as NSError
                    if ns.domain == "CanvasAPI" {
                        self.lastCoursesHTTPStatus = ns.code
                    }
                }
            }
            self.isFetchingGrades = false
            self.gradesRefreshTask = nil
        }

        // Await completion of this specific refresh
        await gradesRefreshTask?.value
    }

    func refreshAssignments(for courseID: Int, force: Bool = false) async {
        sendCanvasUsageOnceIfNeeded()

        if !force, let existing = assignmentsByCourse[courseID], !existing.isEmpty { return }
        if isFetchingAssignmentsForCourse.contains(courseID) { return }

        isFetchingAssignmentsForCourse.insert(courseID)
        assignmentsErrorByCourse[courseID] = nil
        defer { isFetchingAssignmentsForCourse.remove(courseID) }

        guard !canvasDomain.isEmpty, !canvasToken.isEmpty else {
            assignmentsByCourse[courseID] = []
            assignmentsErrorByCourse[courseID] = "Missing Canvas settings"
            return
        }

        do {
            let items = try await api.fetchAssignments(domain: canvasDomain, token: canvasToken, courseID: courseID)
            assignmentsByCourse[courseID] = items
            assignmentsErrorByCourse[courseID] = nil
        } catch {
            // Suppress cancellation
            let ns = error as NSError
            if error is CancellationError || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) {
                // Keep existing data; no error message
            } else {
                assignmentsByCourse[courseID] = assignmentsByCourse[courseID] ?? []
                assignmentsErrorByCourse[courseID] = ns.localizedDescription
            }
        }
    }

    func refreshUpdateAnnouncement() async {
        guard let url = URL(string: updateFeedURLString) else { return }
        do {
            let rows = try await updateFeed.fetch(from: url)
            #if DEBUG
            print("Updates: fetched \(rows.count) total")
            #endif
            let visible = rows.filter { $0.visible }
            #if DEBUG
            print("Updates: \(visible.count) visible")
            #endif
            guard !visible.isEmpty else {
                self.pendingAnnouncement = nil
                return
            }
            let latest = visible.sorted(by: { compareVersions($0.updateNumber, $1.updateNumber) == .orderedDescending }).first ?? visible.first!
            #if DEBUG
            print("Updates: selected \(latest.updateNumber)")
            #endif
            self.pendingAnnouncement = latest
        } catch {
            #if DEBUG
            print("Updates: fetch failed with error: \(error)")
            #endif
        }
    }

    func markAnnouncementShown(_ updateNumber: String) {
        let d = Self.defaults
        d.set(updateNumber, forKey: lastShownUpdateNumberKey)
        d.synchronize()
    }

    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        func components(_ s: String) -> [Int] {
            s.split(separator: ".").compactMap { Int($0) }
        }
        let ac = components(a)
        let bc = components(b)
        let maxCount = max(ac.count, bc.count)
        for i in 0..<maxCount {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return a.compare(b, options: .numeric)
    }

    // MARK: - Notifications

    func refreshNotificationStatus() async {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.notificationAuthStatus = settings.authorizationStatus
        #endif
    }

    func requestNotificationPermission() async {
        #if canImport(UserNotifications)
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshNotificationStatus()
        } catch {
        }
        #endif
    }

    func openSystemNotificationSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    func sendTestNotification() async {
        #if canImport(UserNotifications)
        guard notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "RooMate"
        content.subtitle = "Notifications are working!"
        content.body = "This is a test notification from Settings."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        do {
            try await center.add(req)
        } catch {
        }
        #endif
    }

    private func save() {
        let d = Self.defaults
        do { d.set(try JSONEncoder().encode(assignments), forKey: defaultsKey) } catch { print("Failed to save assignments: \(error)") }
        do { d.set(try JSONEncoder().encode(specialColors), forKey: specialDefaultsKey) } catch { print("Failed to save special block colors: \(error)") }
        do { d.set(try JSONEncoder().encode(specialFree), forKey: specialFreeDefaultsKey) } catch { print("Failed to save special block free flags: \(error)") }
        do { d.set(try JSONEncoder().encode(clubs), forKey: clubsDefaultsKey) } catch { print("Failed to save clubs: \(error)") }
        do { d.set(try JSONEncoder().encode(appearance), forKey: appearanceDefaultsKey) } catch { print("Failed to save appearance: \(error)") }
        do { d.set(try JSONEncoder().encode(cardColorStyle), forKey: cardStyleDefaultsKey) } catch { print("Failed to save card color style: \(error)") }
        d.set(canvasDomain, forKey: canvasDomainKey)
        if !canvasToken.isEmpty { d.set(canvasToken, forKey: canvasTokenKey) }
        do {
            let data = try JSONEncoder().encode(Array(completedTodoIDs))
            d.set(data, forKey: completedTodosKey)
        } catch {
            print("Failed to save completed IDs: \(error)")
        }
        d.set(notificationsEnabled, forKey: notificationsEnabledKey)
        d.set(notifyClassStartingSoon, forKey: notifyClassStartingSoonKey)
        d.set(notifyClassEndingSoon, forKey: notifyClassEndingSoonKey)
        d.set(showSpecialSchedules, forKey: showSpecialSchedulesKey)
        d.synchronize()
    }

    // Reset user-customizable preferences to sensible defaults
    func resetToDefaults() {
        assignments = [:]
        specialColors = [:]
        specialFree = [:]
        clubs = []
        appearance = .system
        cardColorStyle = .colors
        showSpecialSchedules = true
        canvasDomain = ""
        canvasToken = ""
        completedTodoIDs = []
        notificationsEnabled = true
        notifyClassStartingSoon = true
        notifyClassEndingSoon = false
        syncDerivedMusicClubsFreeState()
        Task { @MainActor in save() }
    }

    private func load() {
        let d = Self.defaults
        if let data = d.data(forKey: defaultsKey) { if let decoded = try? JSONDecoder().decode([Level: ClassAssignment].self, from: data) { self.assignments = decoded } }
        if let data = d.data(forKey: specialDefaultsKey) { if let decoded = try? JSONDecoder().decode([SpecialBlock: CodableColor].self, from: data) { self.specialColors = decoded } }
        if let data = d.data(forKey: specialFreeDefaultsKey) { if let decoded = try? JSONDecoder().decode([SpecialBlock: Bool].self, from: data) { self.specialFree = decoded } }
        if let data = d.data(forKey: clubsDefaultsKey) { if let decoded = try? JSONDecoder().decode([Club].self, from: data) { self.clubs = decoded } }
        if let data = d.data(forKey: appearanceDefaultsKey) { if let decoded = try? JSONDecoder().decode(AppearancePreference.self, from: data) { self.appearance = decoded } }
        if let data = d.data(forKey: cardStyleDefaultsKey) { if let decoded = try? JSONDecoder().decode(CardColorStyle.self, from: data) { self.cardColorStyle = decoded } }
        if let domain = d.string(forKey: canvasDomainKey) { self.canvasDomain = domain }
        if let token = d.string(forKey: canvasTokenKey) { self.canvasToken = token }
        if let data = d.data(forKey: completedTodosKey),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            self.completedTodoIDs = Set(array)
        }
        if d.object(forKey: notificationsEnabledKey) != nil {
            self.notificationsEnabled = d.bool(forKey: notificationsEnabledKey)
        }
        if d.object(forKey: notifyClassStartingSoonKey) != nil {
            self.notifyClassStartingSoon = d.bool(forKey: notifyClassStartingSoonKey)
        }
        if d.object(forKey: notifyClassEndingSoonKey) != nil {
            self.notifyClassEndingSoon = d.bool(forKey: notifyClassEndingSoonKey)
        }
        if d.object(forKey: showSpecialSchedulesKey) != nil {
            self.showSpecialSchedules = d.bool(forKey: showSpecialSchedulesKey)
        } else {
            self.showSpecialSchedules = true
        }
        syncDerivedMusicClubsFreeState()
    }
}

// MARK: - Appearance & Card Style

enum AppearancePreference: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}
