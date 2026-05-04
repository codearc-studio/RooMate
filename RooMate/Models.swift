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

        enum CodingKeys: String, CodingKey {
            case title, teacher, room, isFree
        }

        init(title: String, teacher: String, room: String, isFree: Bool = false) {
            self.title = title
            self.teacher = teacher
            self.room = room
            self.isFree = isFree
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            self.teacher = try container.decodeIfPresent(String.self, forKey: .teacher) ?? ""
            self.room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
            self.isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(title, forKey: .title)
            try container.encode(teacher, forKey: .teacher)
            try container.encode(room, forKey: .room)
            try container.encode(isFree, forKey: .isFree)
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

// MARK: - Canvas Todo Models

struct CanvasTodoItem: Codable, Identifiable, Hashable {
    let id: String

    let type: String?
    let assignment: CanvasAssignment?
    let contextType: String?
    let courseID: Int?
    let contextName: String?
    let htmlURL: String?
    let needsGradingCount: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case assignment
        case contextType = "context_type"
        case courseID = "course_id"
        case contextName = "context_name"
        case htmlURL = "html_url"
        case needsGradingCount = "needs_grading_count"
    }

    init(id: String? = nil,
         type: String?,
         assignment: CanvasAssignment?,
         contextType: String?,
         courseID: Int?,
         contextName: String?,
         htmlURL: String?,
         needsGradingCount: Int?) {
        self.type = type
        self.assignment = assignment
        self.contextType = contextType
        self.courseID = courseID
        self.contextName = contextName
        self.htmlURL = htmlURL
        self.needsGradingCount = needsGradingCount

        if let id = id, !id.isEmpty {
            self.id = id
        } else if let aid = assignment?.id {
            self.id = "assign:\(aid)"
        } else if let aurl = assignment?.htmlURL {
            self.id = "aurl:\(aurl)"
        } else if let url = htmlURL {
            self.id = "url:\(url)"
        } else {
            let composite = [
                type ?? "",
                contextType ?? "",
                String(courseID ?? -1),
                contextName ?? ""
            ].joined(separator: "|")
            if composite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.id = UUID().uuidString
            } else {
                self.id = "comp:\(composite)"
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type)
        let assignment = try container.decodeIfPresent(CanvasAssignment.self, forKey: .assignment)
        let contextType = try container.decodeIfPresent(String.self, forKey: .contextType)
        let courseID = try container.decodeIfPresent(Int.self, forKey: .courseID)
        let contextName = try container.decodeIfPresent(String.self, forKey: .contextName)
        let htmlURL = try container.decodeIfPresent(String.self, forKey: .htmlURL)
        let needsGradingCount = try container.decodeIfPresent(Int.self, forKey: .needsGradingCount)

        self.init(
            id: nil,
            type: type,
            assignment: assignment,
            contextType: contextType,
            courseID: courseID,
            contextName: contextName,
            htmlURL: htmlURL,
            needsGradingCount: needsGradingCount
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(assignment, forKey: .assignment)
        try container.encode(contextType, forKey: .contextType)
        try container.encode(courseID, forKey: .courseID)
        try container.encode(contextName, forKey: .contextName)
        try container.encode(htmlURL, forKey: .htmlURL)
        try container.encode(needsGradingCount, forKey: .needsGradingCount)
    }
}

struct CanvasAssignment: Codable, Hashable {
    let id: Int?
    let name: String?
    let dueAt: String?
    let htmlURL: String?
    let courseID: Int?
    let pointsPossible: Double?

    // New fields to show richer info on Homework page
    let submissionTypes: [String]?
    let description: String?
    let lockedForUser: Bool?
    let lockExplanation: String?
    let unlockAt: String?
    let lockAt: String?
    let gradingType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case dueAt = "due_at"
        case htmlURL = "html_url"
        case courseID = "course_id"
        case pointsPossible = "points_possible"

        case submissionTypes = "submission_types"
        case description
        case lockedForUser = "locked_for_user"
        case lockExplanation = "lock_explanation"
        case unlockAt = "unlock_at"
        case lockAt = "lock_at"
        case gradingType = "grading_type"
    }
}

// MARK: - Courses and Grades Models

struct CanvasCourse: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let courseCode: String?
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case courseCode = "course_code"
        case htmlURL = "html_url"
    }
}

struct CanvasEnrollment: Codable, Hashable {
    let id: Int?
    let userID: Int?
    let courseID: Int?
    let type: String?
    let enrollmentState: String?

    let computedCurrentScore: Double?
    let computedFinalScore: Double?
    let computedCurrentGrade: String?
    let computedFinalGrade: String?

    let currentScore: Double?
    let finalScore: Double?
    let currentGrade: String?
    let finalGrade: String?

    let grades: Grades?

    struct Grades: Codable, Hashable {
        let currentScore: Double?
        let finalScore: Double?
        let currentGrade: String?
        let finalGrade: String?

        enum CodingKeys: String, CodingKey {
            case currentScore = "current_score"
            case finalScore = "final_score"
            case currentGrade = "current_grade"
            case finalGrade = "final_grade"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case courseID = "course_id"
        case type
        case enrollmentState = "enrollment_state"
        case computedCurrentScore = "computed_current_score"
        case computedFinalScore = "computed_final_score"
        case computedCurrentGrade = "computed_current_grade"
        case computedFinalGrade = "computed_final_grade"
        case currentScore = "current_score"
        case finalScore = "final_score"
        case currentGrade = "current_grade"
        case finalGrade = "final_grade"
        case grades
    }

    var summary: GradeSummary {
        let currentScore = computedCurrentScore
            ?? grades?.currentScore
            ?? self.currentScore
        let finalScore = computedFinalScore
            ?? grades?.finalScore
            ?? self.finalScore
        let currentGrade = computedCurrentGrade
            ?? grades?.currentGrade
            ?? self.currentGrade
        let finalGrade = computedFinalGrade
            ?? grades?.finalGrade
            ?? self.finalGrade
        return GradeSummary(
            currentScore: currentScore,
            finalScore: finalScore,
            currentLetter: currentGrade,
            finalLetter: finalGrade
        )
    }
}

struct GradeSummary: Codable, Hashable {
    let currentScore: Double?
    let finalScore: Double?
    let currentLetter: String?
    let finalLetter: String?

    var displayCurrent: String {
        if let letter = currentLetter, !letter.isEmpty {
            if let score = currentScore {
                return String(format: "%@ (%.1f%%)", letter, score)
            }
            return letter
        }
        if let score = currentScore {
            return String(format: "%.1f%%", score)
        }
        return "—"
    }

    var displayFinal: String {
        if let letter = finalLetter, !letter.isEmpty {
            if let score = finalScore {
                return String(format: "%@ (%.1f%%)", letter, score)
            }
            return letter
        }
        if let score = finalScore {
            return String(format: "%.1f%%", score)
        }
        return "—"
    }
}

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

