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

final class UserScheduleStore: ObservableObject {
    private static let defaults: UserDefaults = {
        let suiteName = "dev.roomate.prefs"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }()

    @Published var assignments: [Level: ClassAssignment] = [:] { didSet { save() } }
    @Published var specialColors: [SpecialBlock: CodableColor] = [:] { didSet { save() } }
    @Published var appearance: AppearancePreference = .system { didSet { save() } }
    @Published var cardColorStyle: CardColorStyle = .colors { didSet { save() } }

    @Published var canvasDomain: String = "afs.instructure.com" { didSet { save() } }
    @Published var canvasToken: String = "" { didSet { save() } }

    @Published private(set) var canvasTodos: [CanvasTodoItem] = []
    @Published private(set) var isFetchingTodos: Bool = false
    @Published private(set) var fetchError: String?

    @Published private(set) var courses: [CanvasCourse] = []
    @Published private(set) var gradesByCourse: [Int: GradeSummary] = [:]
    @Published private(set) var isFetchingGrades: Bool = false
    @Published private(set) var gradesError: String?

    @Published var completedTodoIDs: Set<String> = [] { didSet { save() } }

    @Published var notificationsEnabled: Bool = true { didSet { save() } }
    @Published private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    @Published var notifyClassStartingSoon: Bool = true { didSet { save() } }
    @Published var notifyClassEndingSoon: Bool = false { didSet { save() } }

    @Published var pendingAnnouncement: UpdateAnnouncement? { didSet { } }

    @Published private(set) var lastTodosHTTPStatus: Int?
    @Published private(set) var lastCoursesHTTPStatus: Int?
    let lastTodosEndpoint: String = "/api/v1/users/self/todo"
    let lastCoursesEndpoint: String = "/api/v1/courses"

    private let defaultsKey = "UserScheduleAssignments"
    private let specialDefaultsKey = "UserSpecialBlockColors"
    private let appearanceDefaultsKey = "UserAppearancePreference"
    private let cardStyleDefaultsKey = "UserCardColorStyle"
    private let canvasDomainKey = "CanvasDomain"
    private let canvasTokenKey = "CanvasToken"
    private let completedTodosKey = "CompletedCanvasTodoIDs"
    private let notificationsEnabledKey = "NotificationsEnabled"
    private let notifyClassStartingSoonKey = "NotifyClassStartingSoon"
    private let notifyClassEndingSoonKey = "NotifyClassEndingSoon"

    private let lastShownUpdateNumberKey = "LastShownUpdateNumber"
    private let updateFeedURLString = "https://docs.google.com/spreadsheets/d/e/2PACX-1vQzOVA2twWoSkiRYwAdAjjkT7pOBD1GdngOTx9BrsTklmLa1ddsMnS48o1S4yPnETcaf2ah3UJs_GLr/pub?gid=60316779&single=true&output=csv"

    private let api = CanvasAPI()
    private let updateFeed = UpdateFeed()

    private var didSignalCanvasUsageThisLaunch = false

    init() { load(); Task { await refreshNotificationStatus() } }

    func assignment(for level: Level) -> ClassAssignment {
        assignments[level] ?? .default(for: level)
    }

    func set(_ assignment: ClassAssignment, for level: Level) {
        assignments[level] = assignment
    }

    func binding(for level: Level) -> Binding<ClassAssignment> {
        Binding(
            get: { self.assignments[level] ?? .default(for: level) },
            set: { self.assignments[level] = $0 }
        )
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

    @MainActor
    func clearCanvasToken() {
        canvasToken = ""
        let d = Self.defaults
        d.removeObject(forKey: canvasTokenKey)
        #if DEBUG
        print("Saved Canvas settings - domain: \(canvasDomain), tokenLength: 0")
        #endif
        d.synchronize()
    }

    @MainActor
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
            self.fetchError = (error as NSError).localizedDescription
            self.canvasTodos = []
            let ns = error as NSError
            if ns.domain == "CanvasAPI" {
                self.lastTodosHTTPStatus = ns.code
            }
        }
        isFetchingTodos = false
    }

    @MainActor
    func refreshCanvasCoursesAndGrades() async {
        sendCanvasUsageOnceIfNeeded()
        isFetchingGrades = true
        gradesError = nil
        lastCoursesHTTPStatus = nil
        do {
            let fetchedCourses = try await api.fetchCourses(domain: canvasDomain, token: canvasToken)
            self.courses = fetchedCourses
            self.lastCoursesHTTPStatus = 200

            var summaries: [Int: GradeSummary] = [:]

            try await withThrowingTaskGroup(of: (Int, GradeSummary?).self) { group in
                for course in fetchedCourses {
                    group.addTask { [domain = self.canvasDomain, token = self.canvasToken] in
                        do {
                            let enrollments = try await self.api.fetchEnrollments(domain: domain, token: token, courseID: course.id)
                            if let e = enrollments.first(where: { ($0.type ?? "").localizedCaseInsensitiveContains("student") }) {
                                return await (course.id, e.summary)
                            } else if let any = enrollments.first {
                                return await (course.id, any.summary)
                            } else {
                                return (course.id, nil)
                            }
                        } catch {
                            return (course.id, nil)
                        }
                    }
                }
                for try await (courseID, summary) in group {
                    if let summary { summaries[courseID] = summary }
                }
            }

            self.gradesByCourse = summaries
        } catch {
            self.gradesError = (error as NSError).localizedDescription
            self.courses = []
            self.gradesByCourse = [:]
            let ns = error as NSError
            if ns.domain == "CanvasAPI" {
                self.lastCoursesHTTPStatus = ns.code
            }
        }
        isFetchingGrades = false
    }

    @MainActor
    func refreshUpdateAnnouncement() async {
        guard let url = URL(string: updateFeedURLString) else { return }
        do {
            let rows = try await updateFeed.fetch(from: url)
            let visible = rows.filter { $0.visible }
            guard !visible.isEmpty else {
                self.pendingAnnouncement = nil
                return
            }
            let latest = visible.sorted(by: { compareVersions($0.updateNumber, $1.updateNumber) == .orderedDescending }).first ?? visible.first!
            self.pendingAnnouncement = latest
        } catch {
            // ignore
        }
    }

    @MainActor
    func markAnnouncementShown(_ updateNumber: String) {
        let d = Self.defaults
        d.set(updateNumber, forKey: lastShownUpdateNumberKey)
        d.synchronize()
        self.pendingAnnouncement = nil
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

    // MARK: - Notifications (macOS)

    @MainActor
    func refreshNotificationStatus() async {
        #if canImport(UserNotifications)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        self.notificationAuthStatus = settings.authorizationStatus
        #endif
    }

    @MainActor
    func requestNotificationPermission() async {
        #if canImport(UserNotifications)
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await refreshNotificationStatus()
        } catch {
        }
        #endif
    }

    @MainActor
    func openSystemNotificationSettings() {
        #if canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    @MainActor
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
        d.synchronize()
    }

    private func load() {
        let d = Self.defaults
        if let data = d.data(forKey: defaultsKey) { if let decoded = try? JSONDecoder().decode([Level: ClassAssignment].self, from: data) { self.assignments = decoded } }
        if let data = d.data(forKey: specialDefaultsKey) { if let decoded = try? JSONDecoder().decode([SpecialBlock: CodableColor].self, from: data) { self.specialColors = decoded } }
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

enum CardColorStyle: String, CaseIterable, Identifiable, Codable {
    case none
    case subtle
    case colors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Minimal"
        case .subtle: "Subtle"
        case .colors: "Colorful"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "rectangle"
        case .subtle: "rectangle.dashed"
        case .colors: "rectangle.fill.on.rectangle.fill"
        }
    }
}
