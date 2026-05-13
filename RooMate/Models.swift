import SwiftUI
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Card color style used across UI
enum CardColorStyle: String, CaseIterable, Identifiable, Codable, Equatable {
    case none
    case subtle
    case colors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Minimal"
        case .subtle: "Subtle"
        case .colors: "Vibrant"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "square"
        case .subtle: "square.dashed"
        case .colors: "square.fill"
        }
    }
}

// MARK: - Appearance

enum AppearancePreference: String, CaseIterable, Identifiable, Codable, Equatable {
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

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Models

enum Level: String, CaseIterable, Identifiable, Codable, Hashable {
    case level1, level2, level3, level4, level5, level6, level7, music

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .level1: "Level 1"
        case .level2: "Level 2"
        case .level3: "Level 3"
        case .level4: "Level 4"
        case .level5: "Level 5"
        case .level6: "Level 6"
        case .level7: "Level 7"
        case .music:  "Music Block"
        }
    }

    var defaultColor: Color {
        switch self {
        case .level1: .blue
        case .level2: .indigo
        case .level3: .purple
        case .level4: .teal
        case .level5: .orange
        case .level6: .green
        case .level7: .pink
        case .music:  .cyan
        }
    }
}

enum SpecialBlock: String, CaseIterable, Identifiable, Codable, Hashable {
    case assembly
    case officeHours
    case advisory
    case worship
    case consciousCommunities
    case lunch
    case lunchAndClubs
    case musicClubs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assembly: "Assembly"
        case .officeHours: "Office Hours"
        case .advisory: "Advisory"
        case .worship: "Meeting For Worship"
        case .consciousCommunities: "Conscious Communities"
        case .lunch: "Lunch"
        case .lunchAndClubs: "Lunch & Clubs"
        case .musicClubs: "Music Block + Clubs"
        }
    }

    var systemImage: String {
        switch self {
        case .assembly: "megaphone.fill"
        case .officeHours: "person.crop.circle.badge.questionmark"
        case .advisory: "person.2.fill"
        case .worship: "hands.and.sparkles.fill"
        case .consciousCommunities: "leaf.fill"
        case .lunch: "fork.knife"
        case .lunchAndClubs: "fork.knife.circle"
        case .musicClubs: "music.note.list"
        }
    }

    var defaultColor: Color {
        switch self {
        case .assembly: .gray
        case .officeHours: .mint
        case .advisory: .brown
        case .worship: .yellow
        case .consciousCommunities: .green
        case .lunch: .orange
        case .lunchAndClubs: .orange
        case .musicClubs: .cyan
        }
    }
}

enum BlockKind: Codable, Hashable {
    case level(Level)
    case special(SpecialBlock)

    enum CodingKeys: String, CodingKey { case type, value }
    enum KindType: String, Codable { case level, special }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        switch type {
        case .level:
            let value = try container.decode(Level.self, forKey: .value)
            self = .level(value)
        case .special:
            let value = try container.decode(SpecialBlock.self, forKey: .value)
            self = .special(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .level(let level):
            try container.encode(KindType.level, forKey: .type)
            try container.encode(level, forKey: .value)
        case .special(let special):
            try container.encode(KindType.special, forKey: .type)
            try container.encode(special, forKey: .value)
        }
    }
}

struct BellBlock: Identifiable, Hashable {
    let id = UUID()
    let kind: BlockKind
    let start: DateComponents
    let end: DateComponents
}

struct Club: Identifiable, Hashable, Codable {
    struct OtherMeeting: Identifiable, Hashable, Codable {
        let id: UUID
        var weekday: Int
        var startTime: Date
        var endTime: Date

        init(id: UUID = UUID(), weekday: Int = 2, startTime: Date = Date(), endTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()) {
            self.id = id
            self.weekday = weekday
            self.startTime = startTime
            self.endTime = endTime
        }
    }

    let id: UUID
    var name: String
    var meetsMondayClub: Bool
    var meetsWednesdayClub: Bool
    var otherDaysNote: String
    var otherMeetings: [OtherMeeting]

    init(id: UUID = UUID(), name: String = "", meetsMondayClub: Bool = false, meetsWednesdayClub: Bool = false, otherDaysNote: String = "", otherMeetings: [OtherMeeting] = []) {
        self.id = id
        self.name = name
        self.meetsMondayClub = meetsMondayClub
        self.meetsWednesdayClub = meetsWednesdayClub
        self.otherDaysNote = otherDaysNote
        self.otherMeetings = otherMeetings
    }
}

struct ClassItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let teacher: String
    let room: String
    let startTime: String
    let endTime: String
    let color: Color
}

struct CodableColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: Color) {
        #if canImport(AppKit)
        let ns = NSColor(color)
            .usingColorSpace(.sRGB) ?? NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
        self.r = Double(ns.redComponent)
        self.g = Double(ns.greenComponent)
        self.b = Double(ns.blueComponent)
        self.a = Double(ns.alphaComponent)
        #elseif canImport(UIKit)
        let ui = UIColor(color)
        var rr: CGFloat = 1, gg: CGFloat = 1, bb: CGFloat = 1, aa: CGFloat = 1
        if ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) {
            self.r = Double(rr); self.g = Double(gg); self.b = Double(bb); self.a = Double(aa)
        } else {
            self.r = 1; self.g = 1; self.b = 1; self.a = 1
        }
        #else
        self.r = 1; self.g = 1; self.b = 1; self.a = 1
        #endif
    }

    var swiftUIColor: Color {
        #if canImport(AppKit)
        let ns = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        return Color(nsColor: ns)
        #elseif canImport(UIKit)
        let ui = UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        return Color(uiColor: ui)
        #else
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
        #endif
    }
}

struct ClassAssignment: Codable, Hashable {
    var title: String
    var teacher: String
    var room: String
    var color: CodableColor
    var isFree: Bool = false
    var musicDaysNotFree: Set<Int> = []

    // Persisted meeting configuration
    var meetsEveryDay: Bool = true
    var daysNotMeeting: Set<Int> = []
    
    // Replacement class for days when this class doesn't meet
    var replacementClass: ReplacementClass? = nil
    
    struct ReplacementClass: Codable, Hashable {
        var title: String
        var teacher: String
        var room: String
        var isFree: Bool = false
        var daysNotFree: Set<Int> = []

        enum CodingKeys: String, CodingKey {
            case title, teacher, room, isFree, daysNotFree
        }

        init(title: String, teacher: String, room: String, isFree: Bool = false, daysNotFree: Set<Int> = []) {
            self.title = title
            self.teacher = teacher
            self.room = room
            self.isFree = isFree
            self.daysNotFree = daysNotFree
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            self.teacher = try container.decodeIfPresent(String.self, forKey: .teacher) ?? ""
            self.room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
            self.isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
            if let arr = try container.decodeIfPresent([Int].self, forKey: .daysNotFree) {
                self.daysNotFree = Set(arr)
            } else {
                self.daysNotFree = []
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(teacher, forKey: .teacher)
            try container.encode(room, forKey: .room)
            try container.encode(isFree, forKey: .isFree)
            try container.encode(Array(daysNotFree), forKey: .daysNotFree)
        }
    }

    static func `default`(for level: Level) -> ClassAssignment {
        ClassAssignment(
            title: level.displayName,
            teacher: "",
            room: "",
            color: .init(level.defaultColor),
            isFree: level == .music,
            musicDaysNotFree: [],
            meetsEveryDay: true,
            daysNotMeeting: [],
            replacementClass: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case title, teacher, room, color, isFree, musicDaysNotFree, meetsEveryDay, daysNotMeeting, replacementClass
    }

    init(title: String, teacher: String, room: String, color: CodableColor, isFree: Bool = false, musicDaysNotFree: Set<Int> = [], meetsEveryDay: Bool = true, daysNotMeeting: Set<Int> = [], replacementClass: ReplacementClass? = nil) {
        self.title = title
        self.teacher = teacher
        self.room = room
        self.color = color
        self.isFree = isFree
        self.musicDaysNotFree = musicDaysNotFree
        self.meetsEveryDay = meetsEveryDay
        self.daysNotMeeting = daysNotMeeting
        self.replacementClass = replacementClass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.teacher = try container.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        self.room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
        self.color = try container.decodeIfPresent(CodableColor.self, forKey: .color) ?? CodableColor(Color.accentColor)
        self.isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        if let arr = try container.decodeIfPresent([Int].self, forKey: .musicDaysNotFree) {
            self.musicDaysNotFree = Set(arr)
        } else {
            self.musicDaysNotFree = []
        }
        self.meetsEveryDay = try container.decodeIfPresent(Bool.self, forKey: .meetsEveryDay) ?? true
        if let arr = try container.decodeIfPresent([Int].self, forKey: .daysNotMeeting) {
            self.daysNotMeeting = Set(arr)
        } else {
            self.daysNotMeeting = []
        }
        
        self.replacementClass = try container.decodeIfPresent(ReplacementClass.self, forKey: .replacementClass)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(teacher, forKey: .teacher)
        try container.encode(room, forKey: .room)
        try container.encode(color, forKey: .color)
        try container.encode(isFree, forKey: .isFree)
        try container.encode(Array(musicDaysNotFree), forKey: .musicDaysNotFree)
        try container.encode(meetsEveryDay, forKey: .meetsEveryDay)
        try container.encode(Array(daysNotMeeting), forKey: .daysNotMeeting)
        try container.encode(replacementClass, forKey: .replacementClass)
    }
}

extension ClassAssignment {
    private func isActuallyFree(on weekday: Weekday? = nil) -> Bool {
        guard isFree else { return false }
        guard let weekday, !musicDaysNotFree.isEmpty else { return true }
        return !musicDaysNotFree.contains(weekday.calendarWeekdayIndex)
    }

    private func replacementClass(for weekday: Weekday?) -> ReplacementClass? {
        guard let weekday, !meetsEveryDay, let replacementClass, daysNotMeeting.contains(weekday.calendarWeekdayIndex) else {
            return nil
        }
        return replacementClass
    }

    func displayTitle(for level: Level, on weekday: Weekday? = nil) -> String {
        if let replacement = replacementClass(for: weekday) {
            return replacement.displayTitle
        }

        if isActuallyFree(on: weekday) { return "Free Period" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? level.displayName : trimmed
    }

    func displaySubtitle(on weekday: Weekday? = nil) -> String {
        if let replacement = replacementClass(for: weekday) {
            return replacement.displaySubtitle
        }

        guard !isActuallyFree(on: weekday) else { return "" }
        return [teacher, room].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " • ")
    }

    func displayTeacher(on weekday: Weekday? = nil) -> String? {
        if let replacement = replacementClass(for: weekday) {
            let trimmed = replacement.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !isActuallyFree(on: weekday) else { return nil }
        let trimmed = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func displayRoom(on weekday: Weekday? = nil) -> String? {
        if let replacement = replacementClass(for: weekday) {
            let trimmed = replacement.room.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        guard !isActuallyFree(on: weekday) else { return nil }
        let trimmed = room.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func displayColor(on weekday: Weekday? = nil) -> Color {
        if let replacement = replacementClass(for: weekday) {
            return replacement.displayColor
        }

        return isActuallyFree(on: weekday) ? .secondary : color.swiftUIColor
    }

    func displayIsFree(on weekday: Weekday? = nil) -> Bool {
        if let replacement = replacementClass(for: weekday) {
            return replacement.isFree
        }

        return isActuallyFree(on: weekday)
    }
}

extension ClassAssignment.ReplacementClass {
    var displayTitle: String {
        if isFree { return "Free Period" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Replacement Class" : trimmed
    }

    var displaySubtitle: String {
        guard !isFree else { return "" }
        return [teacher, room].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " • ")
    }

    var displayColor: Color {
        isFree ? .secondary : .accentColor
    }
}

// Removed.

// MARK: - Homework

struct HomeworkItem: Identifiable, Codable, Hashable {
    enum Priority: String, CaseIterable, Codable, Hashable, Identifiable {
        case none, low, medium, high
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "None"
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            }
        }
        var color: Color {
            switch self {
            case .none: .secondary
            case .low: .green
            case .medium: .orange
            case .high: .red
            }
        }
        var systemImage: String {
            switch self {
            case .none: "line.3.horizontal"
            case .low: "arrow.down"
            case .medium: "arrow.right"
            case .high: "arrow.up"
            }
        }
    }

    var id: UUID = UUID()
    var title: String
    var notes: String
    var dueDate: Date?
    var level: Level?
    var completed: Bool = false
    var priority: Priority = .none
    var color: CodableColor?

    var effectiveColor: Color {
        if let color {
            return color.swiftUIColor
        } else if let level {
            return level.defaultColor
        } else {
            return .accentColor
        }
    }
}

// MARK: - Weekday

enum Weekday: CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday

    var id: Self { self }

    var title: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        }
    }

    var systemImage: String {
        switch self {
        case .monday: "1.square"
        case .tuesday: "2.square"
        case .wednesday: "3.square"
        case .thursday: "4.square"
        case .friday: "5.square"
        }
    }
}

extension Weekday {
    var calendarWeekdayIndex: Int {
        switch self {
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        }
    }
}

// MARK: - Calendar Event

struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date?
    let location: String?
    
    init(id: UUID = UUID(), title: String, startDate: Date, endDate: Date? = nil, location: String? = nil) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
    }
    
    /// Returns formatted start date and time for display
    var formattedStartDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }
    
    /// Returns formatted end date and time for display
    var formattedEndDate: String? {
        guard let endDate = endDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: endDate)
    }
    
    /// Returns true if the event spans multiple days
    var isMultiDay: Bool {
        guard let endDate = endDate else { return false }
        let calendar = Calendar.current
        let startDay = calendar.component(.day, from: startDate)
        let endDay = calendar.component(.day, from: endDate)
        let startMonth = calendar.component(.month, from: startDate)
        let endMonth = calendar.component(.month, from: endDate)
        let startYear = calendar.component(.year, from: startDate)
        let endYear = calendar.component(.year, from: endDate)
        
        return startYear != endYear || startMonth != endMonth || startDay != endDay
    }
}

// MARK: - Calendar Source

enum CalendarSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case allEvents = "All Events"
    case allSchool = "All School"
    case upperSchool = "Upper School"
    case middleSchool = "Middle School"
    case lowerSchool = "Lower School"
    
    var id: String { rawValue }
    
    var title: String { rawValue }
    
    var url: URL {
        let baseURL = "https://www.abingtonfriends.net/fs/calendar-manager/events.ics"
        let queryString: String
        
        switch self {
        case .allEvents:
            queryString = "?calendar_ids[]=7&calendar_ids[]=6&calendar_ids[]=5&calendar_ids[]=4"
        case .allSchool:
            queryString = "?calendar_ids=7"
        case .upperSchool:
            queryString = "?calendar_ids=6"
        case .middleSchool:
            queryString = "?calendar_ids=5"
        case .lowerSchool:
            queryString = "?calendar_ids=4"
        }
        
        return URL(string: baseURL + queryString) ?? URL(fileURLWithPath: "")
    }
}

enum CalendarGroupingMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}
