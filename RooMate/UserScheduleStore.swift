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
    @Published var specialBlockReplacements: [SpecialBlock: ClassAssignment.ReplacementClass] = [:] { didSet { Task { @MainActor in self.save() } } }
    @Published var clubs: [Club] = [] { didSet { Task { @MainActor in self.save() } } }
    @Published var appearance: AppearancePreference = .system { didSet { Task { @MainActor in self.save() } } }
    @Published var cardColorStyle: CardColorStyle = .colors { didSet { Task { @MainActor in self.save() } } }
    
    @Published var completedTodoIDs: Set<String> = [] { didSet { Task { @MainActor in self.save() } } }
    
    @Published var notificationsEnabled: Bool = true { didSet { Task { @MainActor in self.save() } } }
    @Published private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    
    @Published var notifyClassStartingSoon: Bool = true { didSet { Task { @MainActor in self.save() } } }
    @Published var notifyClassEndingSoon: Bool = false { didSet { Task { @MainActor in self.save() } } }
    
    private let defaultsKey = "UserScheduleAssignments"
    private let specialDefaultsKey = "UserSpecialBlockColors"
    private let specialFreeDefaultsKey = "UserSpecialBlockFree"
    private let specialBlockReplacementsKey = "UserSpecialBlockReplacements"
    private let clubsDefaultsKey = "UserClubs"
    private let appearanceDefaultsKey = "UserAppearancePreference"
    private let cardStyleDefaultsKey = "UserCardColorStyle"
    private let completedTodosKey = "CompletedTodoIDs"
    private let notificationsEnabledKey = "NotificationsEnabled"
    private let notifyClassStartingSoonKey = "NotifyClassStartingSoon"
    private let notifyClassEndingSoonKey = "NotifyClassEndingSoon"
    
    init() { load(); Task { await refreshNotificationStatus() } }
    
    func refreshNotificationStatus() async {
        #if canImport(UserNotifications)
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        await MainActor.run { self.notificationAuthStatus = status }
        #endif
    }
    
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
    
    func displayTitle(for block: SpecialBlock, on weekday: Weekday) -> String {
        // Check if there's a replacement for this block on this day
        if let replacement = specialBlockReplacements[block] {
            // If daysNotFree is empty, it applies to all days (for blocks without day selection like Conscious Communities)
            // If daysNotFree is not empty, check if this specific day is in the set
            let appliesToThisDay = replacement.daysNotFree.isEmpty || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
            if appliesToThisDay {
                return replacement.title.isEmpty ? displayTitle(for: block) : replacement.title
            }
        }
        return displayTitle(for: block)
    }
    
    func displayTeacher(for block: SpecialBlock, on weekday: Weekday) -> String? {
        // Check if there's a replacement for this block on this day
        if let replacement = specialBlockReplacements[block] {
            // If daysNotFree is empty, it applies to all days (for blocks without day selection like Conscious Communities)
            // If daysNotFree is not empty, check if this specific day is in the set
            let appliesToThisDay = replacement.daysNotFree.isEmpty || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
            if appliesToThisDay {
                return replacement.teacher.isEmpty ? nil : replacement.teacher
            }
        }
        return nil
    }
    
    func displayRoom(for block: SpecialBlock, on weekday: Weekday) -> String? {
        // Check if there's a replacement for this block on this day
        if let replacement = specialBlockReplacements[block] {
            // If daysNotFree is empty, it applies to all days (for blocks without day selection like Conscious Communities)
            // If daysNotFree is not empty, check if this specific day is in the set
            let appliesToThisDay = replacement.daysNotFree.isEmpty || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
            if appliesToThisDay {
                return replacement.room.isEmpty ? nil : replacement.room
            }
        }
        return nil
    }
    
    // MARK: - Music Block Special Handling
    // Music Block is a Level but has replacements stored as a SpecialBlock (.musicClubs)
    // These methods check the special block replacements for music
    
    func displayMusicTitle(on weekday: Weekday) -> String? {
        // Check if there's a music replacement for this day
        if let replacement = specialBlockReplacements[.musicClubs] {
            // If daysNotFree is empty, it applies to all days (for blocks without day selection)
            // If daysNotFree is not empty, check if this specific day is in the set
            let appliesToThisDay = replacement.daysNotFree.isEmpty || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
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
            let appliesToThisDay = replacement.daysNotFree.isEmpty || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
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
            let appliesToThisDay = replacement.daysNotFree.isEmpty || replacement.daysNotFree.contains(weekday.calendarWeekdayIndex)
            if appliesToThisDay {
                return replacement.room.isEmpty ? nil : replacement.room
            }
        }
        return nil
     }
 
    // MARK: - Persistence
    
    private func save() {
    let d = Self.defaults
    do { d.set(try JSONEncoder().encode(assignments), forKey: defaultsKey) } catch { print("Failed to save assignments: \(error)") }
    do { d.set(try JSONEncoder().encode(specialColors), forKey: specialDefaultsKey) } catch { print("Failed to save special block colors: \(error)") }
    do { d.set(try JSONEncoder().encode(specialFree), forKey: specialFreeDefaultsKey) } catch { print("Failed to save special block free flags: \(error)") }
    do { d.set(try JSONEncoder().encode(specialBlockReplacements), forKey: specialBlockReplacementsKey) } catch { print("Failed to save special block replacements: \(error)") }
    do { d.set(try JSONEncoder().encode(clubs), forKey: clubsDefaultsKey) } catch { print("Failed to save clubs: \(error)") }
    do { d.set(try JSONEncoder().encode(appearance), forKey: appearanceDefaultsKey) } catch { print("Failed to save appearance: \(error)") }
    do { d.set(try JSONEncoder().encode(cardColorStyle), forKey: cardStyleDefaultsKey) } catch { print("Failed to save card color style: \(error)") }
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

// Reset user-customizable preferences to sensible defaults
func resetToDefaults() {
    assignments = [:]
    specialColors = [:]
    specialFree = [:]
    specialBlockReplacements = [:]
    clubs = []
    appearance = .system
    cardColorStyle = .colors
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
    if let data = d.data(forKey: specialBlockReplacementsKey) { if let decoded = try? JSONDecoder().decode([SpecialBlock: ClassAssignment.ReplacementClass].self, from: data) { self.specialBlockReplacements = decoded } }
    if let data = d.data(forKey: clubsDefaultsKey) { if let decoded = try? JSONDecoder().decode([Club].self, from: data) { self.clubs = decoded } }
    if let data = d.data(forKey: appearanceDefaultsKey) { if let decoded = try? JSONDecoder().decode(AppearancePreference.self, from: data) { self.appearance = decoded } }
    if let data = d.data(forKey: cardStyleDefaultsKey) { if let decoded = try? JSONDecoder().decode(CardColorStyle.self, from: data) { self.cardColorStyle = decoded } }
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
