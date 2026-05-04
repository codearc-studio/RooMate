/*import SwiftUI
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

 // MARK: - Models

 enum Level: String, CaseIterable, Identifiable, Codable, Hashable {
     case level1, level2, level3, level4, level5, level6, level7, music
  
     var id: String { rawValue }

     var displayName: String {
         switch self {
         case .level1: "Level 1"
         case .level2: "Level  2"
         case .level3: "Level 3"
         case .level4: "Level 4"
         case .level5: "Level 5"
         case .level6: "Level 6"
         case .level7: "Level 7"
         case .music:  "Music Block"
         }
     }

     // Provide a default color per level (used if user hasn't picked one)
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
     case worship // Meeting for Worship
     case consciousCommunities
     case lunch
     case lunchAndClubs
     case musicClubs // "Music Block + Clubs"

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

     // Default colors for special blocks; can be overridden by user preferences
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
     let start: DateComponents // hour/minute
     let end: DateComponents
 }

 // Temporary in-file model for placeholder data (reused for rendering user assignments)
 struct ClassItem: Identifiable, Hashable {
     let id = UUID()
     let title: String
     let teacher: String
     let room: String
     let startTime: String
     let endTime: String
     let color: Color
 }

 // Persistable color representation (RGBA)
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

      // New: persisted meeting configuration for this class
      var meetsEveryDay: Bool = true
      var daysNotMeeting: Set<Int> = [] // weekday indices (1..7)

      static func `default`(for level: Level) -> ClassAssignment {
          ClassAssignment(
              title: level == .music ? "Free / Music" : level.displayName,
              teacher: "",
              room: "",
              color: .init(level.defaultColor),
              meetsEveryDay: true,
              daysNotMeeting: []
          )
      }

      // Custom decoding to remain compatible with older saved data that lacks the new keys
      enum CodingKeys: String, CodingKey {
          case title, teacher, room, color, meetsEveryDay, daysNotMeeting
      }

      init(title: String, teacher: String, room: String, color: CodableColor, meetsEveryDay: Bool = true, daysNotMeeting: Set<Int> = []) {
          self.title = title
          self.teacher = teacher
          self.room = room
          self.color = color
          self.meetsEveryDay = meetsEveryDay
          self.daysNotMeeting = daysNotMeeting
      }

      init(from decoder: Decoder) throws {
          let container = try decoder.container(keyedBy: CodingKeys.self)
          self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
          self.teacher = try container.decodeIfPresent(String.self, forKey: .teacher) ?? ""
          self.room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
          self.color = try container.decodeIfPresent(CodableColor.self, forKey: .color) ?? CodableColor(Color.accentColor)
          self.meetsEveryDay = try container.decodeIfPresent(Bool.self, forKey: .meetsEveryDay) ?? true
          if let arr = try container.decodeIfPresent([Int].self, forKey: .daysNotMeeting) {
              self.daysNotMeeting = Set(arr)
          } else {
              self.daysNotMeeting = []
          }
      }

      func encode(to encoder: Encoder) throws {
          var container = encoder.container(keyedBy: CodingKeys.self)
          try container.encode(title, forKey: .title)
          try container.encode(teacher, forKey: .teacher)
          try container.encode(room, forKey: .room)
          try container.encode(color, forKey: .color)
          try container.encode(meetsEveryDay, forKey: .meetsEveryDay)
          try container.encode(Array(daysNotMeeting), forKey: .daysNotMeeting)
      }
  }

 // MARK: - Canvas Todo Models

 // Canvas "to-do" item (simplified for assignments/quizzes)
 struct CanvasTodoItem: Codable, Identifiable, Hashable {
     // Stable, stored id
     let id: String

     let type: String?            // "assignment", "grading", etc.
     let assignment: CanvasAssignment?
     let contextType: String?     // e.g., "Course"
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
         // no "id" key from API; we synthesize
     }

     // Synthesize a stable identifier
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

     enum CodingKeys: String, CodingKey {
         case id
         case name
         case dueAt = "due_at"
         case htmlURL = "html_url"
         case courseID = "course_id"
         case pointsPossible = "points_possible"
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
     // Enrollment metadata
     let id: Int?
     let userID: Int?
     let courseID: Int?
     let type: String?
     let enrollmentState: String?

     // Preferred computed fields
     let computedCurrentScore: Double?
     let computedFinalScore: Double?
     let computedCurrentGrade: String?
     let computedFinalGrade: String?

     // Fallback non-computed fields (some instances still use these)
     let currentScore: Double?
     let finalScore: Double?
     let currentGrade: String?
     let finalGrade: String?

     // Nested grades object (common in many Canvas instances)
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
         // Prefer computed_* if present, else nested grades.*, else top-level fallback
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
             }//dylanisthebest
             return letter
         }
         if let score = finalScore {
             return String(format: "%.1f%%", score)
         }
         return "—"
     }
 }

 // MARK: - Homework (Canvas-backed)

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

 // MARK: - Appearance

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

 // MARK: - Card Color Style

 enum CardColorStyle: String, CaseIterable, Identifiable, Codable {
     case none
     case subtle
     case colors

     var id: String { rawValue }
     ;
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

 // MARK: - Bell Schedule (hard-coded)

 struct BellSchedule {
     static let weekly: [Weekday: [BellBlock]] = [
         .monday: [
             special(.assembly, "8:00 AM", "8:10 AM"),
             level(.level1, "8:15 AM", "9:02 AM"),
             level(.level7, "9:05 AM", "10:02 AM"),
             special(.officeHours, "10:05 AM", "10:22 AM"),
             level(.level4, "10:25 AM", "11:12 AM"),
             level(.level6, "11:15 AM", "12:12 PM"),
             special(.musicClubs, "12:15 PM", "12:52 PM"),
             special(.lunch, "12:55 PM", "1:27 PM"),
             level(.level3, "1:30 PM", "2:17 PM"),
             level(.level5, "2:20 PM", "3:10 PM")
         ],
         .tuesday: [
             special(.assembly, "8:00 AM", "8:10 AM"),
             level(.level7, "8:15 AM", "9:02 AM"),
             level(.level4, "9:05 AM", "10:02 AM"),
             special(.officeHours, "10:05 AM", "10:22 AM"),
             level(.music, "10:25 AM", "11:12 AM"),
             level(.level1, "11:15 AM", "12:12 PM"),
             special(.advisory, "12:15 PM", "12:52 PM"),
             special(.lunch, "12:55 PM", "1:27 PM"),
             level(.level6, "1:30 PM", "2:17 PM"),
             level(.level2, "2:20 PM", "3:10 PM")
         ],
         .wednesday: [
             level(.level6, "8:00 AM", "8:52 AM"),
             level(.level2, "8:55 AM", "9:52 AM"),
             special(.officeHours, "9:55 AM", "10:12 AM"),
             level(.level5, "10:15 AM", "11:02 AM"),
             level(.level3, "11:05 AM", "11:52 AM"),
             special(.worship, "11:55 AM", "12:30 PM"),
             special(.lunchAndClubs, "12:30 PM", "1:30 PM"),
             level(.level4, "1:30 PM", "2:17 PM"),
             level(.level7, "2:20 PM", "3:10 PM")
         ],
         .thursday: [
             special(.assembly, "8:00 AM", "8:10 AM"),
             level(.level3, "8:15 AM", "9:02 AM"),
             level(.level5, "9:05 AM", "10:02 AM"),
             special(.officeHours, "10:05 AM", "10:22 AM"),
             level(.music, "10:25 AM", "11:12 AM"),
             level(.level1, "11:15 AM", "12:12 PM"),
             special(.consciousCommunities, "12:15 PM", "12:52 PM"),
             special(.lunch, "12:55 PM", "1:27 PM"),
             level(.level2, "1:30 PM", "2:17 PM"),
             level(.level6, "2:20 PM", "3:10 PM")
         ],
         .friday: [
             level(.music, "8:00 AM", "8:57 AM"),
             level(.level3, "9:00 AM", "9:57 AM"),
             level(.level5, "10:00 AM", "10:47 AM"),
             special(.officeHours, "10:50 AM", "11:02 AM"),
             level(.level2, "11:05 AM", "11:52 AM"),
             level(.level4, "11:55 AM", "12:42 PM"),
             special(.lunch, "12:45 PM", "1:27 PM"),
             level(.level7, "1:30 PM", "2:17 PM"),
             level(.level1, "2:20 PM", "3:10 PM")
         ]
     ]

     // Helpers to build blocks with time strings
     private static func time(_ string: String) -> DateComponents {
         let formatter = DateFormatter()
         formatter.locale = Locale(identifier: "en_US_POSIX")
         formatter.dateFormat = "h:mm a"
         guard let date = formatter.date(from: string) else {
             return DateComponents(hour: 0, minute: 0)
         }
         let cal = Calendar.current
         let comps = cal.dateComponents([.hour, .minute], from: date)
         return comps
     }

     private static func level(_ level: Level, _ start: String, _ end: String) -> BellBlock {
         BellBlock(kind: .level(level), start: time(start), end: time(end))
     }

     private static func special(_ kind: SpecialBlock, _ start: String, _ end: String) -> BellBlock {
         BellBlock(kind: .special(kind), start: time(start), end: time(end))
     }
 }

 // MARK: - Canvas API Client

 actor CanvasAPI {
     func fetchTodos(domain: String, token: String) async throws -> [CanvasTodoItem] {
         guard !domain.isEmpty, !token.isEmpty else {
             return []
         }
         var comps = URLComponents()
         comps.scheme = "https"
         comps.host = domain
         comps.path = "/api/v1/users/self/todo"
         guard let url = comps.url else { return [] }

         var req = URLRequest(url: url)
         req.httpMethod = "GET"
         req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

         let (data, response) = try await URLSession.shared.data(for: req)
         guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
         guard (200..<300).contains(http.statusCode) else {
             throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                 NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode)"
             ])
         }

         let decoder = JSONDecoder()
         decoder.keyDecodingStrategy = .useDefaultKeys
         let items = try decoder.decode([CanvasTodoItem].self, from: data)
         return items
     }

     func fetchCourses(domain: String, token: String) async throws -> [CanvasCourse] {
         guard !domain.isEmpty, !token.isEmpty else { return [] }

         func buildInitialURL() -> URL? {
             var comps = URLComponents()
             comps.scheme = "https"
             comps.host = domain
             comps.path = "/api/v1/courses"
             // Use simpler params that are broadly accepted
             comps.queryItems = [
                 URLQueryItem(name: "enrollment_type", value: "student"),
                 URLQueryItem(name: "per_page", value: "100")
             ]
             return comps.url
         }

         func buildFallbackURL() -> URL? {
             var comps = URLComponents()
             comps.scheme = "https"
             comps.host = domain
             comps.path = "/api/v1/courses"
             // No query params (broadest compatibility)
             return comps.url
         }

         var all: [CanvasCourse] = []

         // Try initial (safer) params first; if we hit a 5xx on the first page, retry once with fallback.
         var nextURL: URL? = buildInitialURL()
         var usedFallback = false

         while let url = nextURL {
             var req = URLRequest(url: url)
             req.httpMethod = "GET"
             req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

             let (data, response) = try await URLSession.shared.data(for: req)
             guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

             if !(200..<300).contains(http.statusCode) {
                 // If first attempt with initial params yields 5xx, retry from start with fallback URL once.
                 if !usedFallback, (500..<600).contains(http.statusCode) {
                     usedFallback = true
                     all.removeAll()
                     nextURL = buildFallbackURL()
                     continue
                 }
                 throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                     NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode) for courses"
                 ])
             }

             let page = try JSONDecoder().decode([CanvasCourse].self, from: data)
             all.append(contentsOf: page)

             if let link = http.value(forHTTPHeaderField: "Link") {
                 nextURL = Self.parseLinkHeader(link)["next"]
             } else {
                 nextURL = nil
             }
         }

         return all
     }

     func fetchEnrollments(domain: String, token: String, courseID: Int) async throws -> [CanvasEnrollment] {
         guard !domain.isEmpty, !token.isEmpty else { return [] }

         func buildInitialURL() -> URL? {
             var comps = URLComponents()
             comps.scheme = "https"
             comps.host = domain
             comps.path = "/api/v1/courses/\(courseID)/enrollments"
             comps.queryItems = [
                 URLQueryItem(name: "user_id", value: "self"),
                 URLQueryItem(name: "include[]", value: "grades"),
                 URLQueryItem(name: "include[]", value: "total_scores"),
                 URLQueryItem(name: "per_page", value: "100")
             ]
             return comps.url
         }

         var all: [CanvasEnrollment] = []
         var nextURL: URL? = buildInitialURL()

         while let url = nextURL {
             var req = URLRequest(url: url)
             req.httpMethod = "GET"
             req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

             let (data, response) = try await URLSession.shared.data(for: req)
             guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
             guard (200..<300).contains(http.statusCode) else {
                 throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                     NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode) for enrollments"
                 ])
             }

             let page = try JSONDecoder().decode([CanvasEnrollment].self, from: data)
             all.append(contentsOf: page)

             if let link = http.value(forHTTPHeaderField: "Link") {
                 nextURL = Self.parseLinkHeader(link)["next"]
             } else {
                 nextURL = nil
             }
         }

         return all
     }

     private static func parseLinkHeader(_ header: String) -> [String: URL] {
         var result: [String: URL] = [:]
         let parts = header.split(separator: ",")
         for part in parts {
             let sections = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
             guard let urlPart = sections.first,
                   urlPart.hasPrefix("<"), urlPart.hasSuffix(">") else { continue }
             let urlString = urlPart.dropFirst().dropLast()
             var rel: String?
             for sec in sections.dropFirst() {
                 let pair = sec.split(separator: "=")
                 if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == "rel" {
                     rel = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                 }
             }
             if let rel, let url = URL(string: String(urlString)) {
                 result[rel] = url
             }
         }
         return result
     }
 }

 // MARK: - Update Announcement Models/Fetcher

 struct UpdateAnnouncement: Identifiable, Equatable, Codable {
     let id: String           // same as updateNumber for identity
     let visible: Bool
     let updateNumber: String
     let changelog: String
     let url: URL?

     init(visible: Bool, updateNumber: String, changelog: String, urlString: String?) {
         self.visible = visible
                self.updateNumber = updateNumber
         self.changelog = changelog
         if let s = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
             self.url = URL(string: s)
         } else {
             self.url = nil
         }
         self.id = updateNumber
     }
 }

 actor UpdateFeed {
     // CSV is small; simple parse tailored to 4 columns with optional quoted fields.
     func fetch(from url: URL) async throws -> [UpdateAnnouncement] {
         let (data, response) = try await URLSession.shared.data(from: url)
         guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
             throw URLError(.badServerResponse)
         }
         guard let text = String(data: data, encoding: .utf8) else { return [] }
         return parseCSV(text: text)
     }

     private func parseCSV(text: String) -> [UpdateAnnouncement] {
         // Split into lines, detect header row
         let lines = text.split(whereSeparator: \.isNewline).map(String.init)
         guard !lines.isEmpty else { return [] }

         // Map header indices
         let header = splitCSVRow(lines[0])
         func index(of name: String) -> Int? {
             header.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
         }
         guard
             let visIdx = index(of: "Visibility"),
             let numIdx = index(of: "Update Number"),
             let logIdx = index(of: "Changelog"),
             let urlIdx = index(of: "URL")
         else {
             // If header missing or different, try positional parsing
             return lines.dropFirst().compactMap { row in
                 let cols = splitCSVRow(row)
                 guard cols.count >= 4 else { return nil }
                 return makeAnnouncement(cols[0], cols[1], cols[2], cols[3])
             }
         }

         return lines.dropFirst().compactMap { row in
             let cols = splitCSVRow(row)
             guard cols.count > max(visIdx, numIdx, logIdx, urlIdx) else { return nil }
             return makeAnnouncement(cols[visIdx], cols[numIdx], cols[logIdx], cols[urlIdx])
         }
     }

     private func makeAnnouncement(_ vis: String, _ num: String, _ log: String, _ url: String) -> UpdateAnnouncement? {
         let v = vis.trimmingCharacters(in: .whitespacesAndNewlines)
         let visible = v.caseInsensitiveCompare("Visible") == .orderedSame
         let number = num.trimmingCharacters(in: .whitespacesAndNewlines)
         guard !number.isEmpty else { return nil }
         let changelog = log.trimmingCharacters(in: .whitespacesAndNewlines)
         let urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
         return UpdateAnnouncement(visible: visible, updateNumber: number, changelog: changelog, urlString: urlString)
     }

     // Minimal CSV row splitter supporting quoted fields with commas and double-quotes escapes.
     private func splitCSVRow(_ row: String) -> [String] {
         var result: [String] = []
         var current = ""
         var inQuotes = false
         var i = row.startIndex
         while i < row.endIndex {
             let ch = row[i]
             if ch == "\"" {
                 if inQuotes, row.index(after: i) < row.endIndex, row[row.index(after: i)] == "\"" {
                     // Escaped quote
                     current.append("\"")
                     i = row.index(after: i)
                 } else {
                     inQuotes.toggle()
                 }
             } else if ch == "," && !inQuotes {
                 result.append(current)
                 current = ""
             } else {
                 current.append(ch)
             }
             i = row.index(after: i)
         }
         result.append(current)
         return result
     }
 }

 // MARK: - Persistence and Store

 final class UserScheduleStore: ObservableObject {
     private static let defaults: UserDefaults = {
         let suiteName = "dev.roomate.prefs"
         return UserDefaults(suiteName: suiteName) ?? .standard
     }()

     @Published var assignments: [Level: ClassAssignment] = [:] {
         didSet { save() }
     }
     @Published var specialColors: [SpecialBlock: CodableColor] = [:] {
         didSet { save() }
     }
     @Published var appearance: AppearancePreference = .system {
         didSet { save() }
     }

     // New: card color style preference
     @Published var cardColorStyle: CardColorStyle = .colors {
         didSet { save() }
     }

     @Published var canvasDomain: String = "afs.instructure.com" {
         didSet { save() }
     }
     @Published var canvasToken: String = "" {
         didSet { save() }
     }

     @Published private(set) var canvasTodos: [CanvasTodoItem] = []
     @Published private(set) var isFetchingTodos: Bool = false
     @Published private(set) var fetchError: String?

     @Published private(set) var courses: [CanvasCourse] = []
     @Published private(set) var gradesByCourse: [Int: GradeSummary] = [:]
     @Published private(set) var isFetchingGrades: Bool = false
     @Published private(set) var gradesError: String?

     // Local completion for Canvas todos
     @Published var completedTodoIDs: Set<String> = [] {
         didSet { save() }
     }

     // Notifications (macOS)
     @Published var notificationsEnabled: Bool = true {
         didSet { save() }
     }
     @Published private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

     // New: per-event notification preferences
     @Published var notifyClassStartingSoon: Bool = true {
         didSet { save() }
     }
     @Published var notifyClassEndingSoon: Bool = false {
         didSet { save() }
     }

     // Update announcements
     @Published var pendingAnnouncement: UpdateAnnouncement? {
         didSet { /* presentation driven by binding */ }
     }

     // Transient telemetry capture for "Test Connection"
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
     // New keys for per-event notifications
     private let notifyClassStartingSoonKey = "NotifyClassStartingSoon"
     private let notifyClassEndingSoonKey = "NotifyClassEndingSoon"

     // Update announcement keys
     private let lastShownUpdateNumberKey = "LastShownUpdateNumber"
     private let updateFeedURLString = "https://docs.google.com/spreadsheets/d/e/2PACX-1vQzOVA2twWoSkiRYwAdAjjkT7pOBD1GdngOTx9BrsTklmLa1ddsMnS48o1S4yPnETcaf2ah3UJs_GLr/pub?gid=60316779&single=true&output=csv"

     private let api = CanvasAPI()
     private let updateFeed = UpdateFeed()

     // Telemetry: ensure we only signal once per app launch
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

     // Completion helpers
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

     // Resolve a color for a Canvas course name by matching to saved class titles or level names.
     func colorForCanvasCourseName(_ courseName: String?) -> Color {
         guard let name = courseName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
             return .accentColor
         }
         let lower = name.lowercased()

         // 1) Exact/contains match against user-provided ClassAssignment titles
         for (level, assignment) in assignments {
             let title = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
             if !title.isEmpty && (lower == title || lower.contains(title) || title.contains(lower)) {
                 return assignment.color.swiftUIColor
             }
             // Also match against Level display name e.g. "Level 3"
             let levelName = level.displayName.lowercased()
             if lower == levelName || lower.contains(levelName) || levelName.contains(lower) {
                 return assignment.color.swiftUIColor
             }
         }

         // 2) If no custom assignment for a level yet, try raw Level display names, using defaultColor
         for level in Level.allCases {
             let levelName = level.displayName.lowercased()
             if lower == levelName || lower.contains(levelName) || levelName.contains(lower) {
                 return level.defaultColor
             }
         }

         // 3) Fallback
         return .accentColor
     }

     // MARK: - Telemetry

     private func sendCanvasUsageOnceIfNeeded() {
         guard !didSignalCanvasUsageThisLaunch else { return }
         guard !canvasDomain.isEmpty, !canvasToken.isEmpty else { return }
         didSignalCanvasUsageThisLaunch = true
         TelemetryDeck.signal("UsedCanvasAPI")
     }

     // Helper to send telemetry with string parameters
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
         // Telemetry: first use of Canvas API this launch
         sendCanvasUsageOnceIfNeeded()

         isFetchingTodos = true
         fetchError = nil
         // default unset
         lastTodosHTTPStatus = nil
         do {
             let items = try await api.fetchTodos(domain: canvasDomain, token: canvasToken)
             self.canvasTodos = items
             // Consider success as HTTP 200 for telemetry purposes
             self.lastTodosHTTPStatus = 200
             // Optionally prune completed IDs that are no longer present
             let currentIDs = Set(items.map { $0.id })
             completedTodoIDs = completedTodoIDs.intersection(currentIDs)
         } catch {
             self.fetchError = (error as NSError).localizedDescription
             self.canvasTodos = []
             // Capture status from NSError.code if available
             let ns = error as NSError
             if ns.domain == "CanvasAPI" {
                 self.lastTodosHTTPStatus = ns.code
             }
         }
         isFetchingTodos = false
     }

     @MainActor
     func refreshCanvasCoursesAndGrades() async {
         // Telemetry: first use of Canvas API this launch
         sendCanvasUsageOnceIfNeeded()

         isFetchingGrades = true
         gradesError = nil
         // default unset
         lastCoursesHTTPStatus = nil
         do {
             let fetchedCourses = try await api.fetchCourses(domain: canvasDomain, token: canvasToken)
             self.courses = fetchedCourses
             // Consider success as HTTP 200 for telemetry purposes
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
             // Capture status from NSError.code if available
             let ns = error as NSError
             if ns.domain == "CanvasAPI" {
                 self.lastCoursesHTTPStatus = ns.code
             }
         }
         isFetchingGrades = false
     }

     // MARK: - Update Announcements

     @MainActor
     func refreshUpdateAnnouncement() async {
         guard let url = URL(string: updateFeedURLString) else { return }
         do {
             let rows = try await updateFeed.fetch(from: url)
             // Consider only visible rows
             let visible = rows.filter { $0.visible }
             guard !visible.isEmpty else {
                 self.pendingAnnouncement = nil
                 return
             }
             // Choose the "latest" by semantic version or numeric compare; fallback to first
             let latest = visible.sorted(by: { compareVersions($0.updateNumber, $1.updateNumber) == .orderedDescending }).first ?? visible.first!
             // Always show the latest visible announcement
             self.pendingAnnouncement = latest
         } catch {
             // Silently ignore errors; you could surface in Settings if desired
         }
     }

     // Persist that an announcement was shown/acknowledged
     @MainActor
     func markAnnouncementShown(_ updateNumber: String) {
         let d = Self.defaults
         d.set(updateNumber, forKey: lastShownUpdateNumberKey)
         d.synchronize()
         self.pendingAnnouncement = nil
     }

     // Version comparison supporting semantic versions like "1.2.3" and numeric strings like "42".
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
         // If equal numerically but strings differ (e.g., metadata), fall back to lexical
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
             let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
             await refreshNotificationStatus()
             if !granted {
                 // Optional: handle denied state
             }
         } catch {
             // Optional: handle error
         }
         #endif
     }

     @MainActor
     func openSystemNotificationSettings() {
         #if canImport(AppKit)
         // Open System Settings > Notifications pane
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
             // Optional: handle error
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
         // Save completed to‑dos
         do {
             let data = try JSONEncoder().encode(Array(completedTodoIDs))
             d.set(data, forKey: completedTodosKey)
         } catch {
             print("Failed to save completed IDs: \(error)")
         }
         // Save notifications pref
         d.set(notificationsEnabled, forKey: notificationsEnabledKey)
         // Save per-event notification prefs
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
         // Load completed to‑dos
         if let data = d.data(forKey: completedTodosKey),
            let array = try? JSONDecoder().decode([String].self, from: data) {
             self.completedTodoIDs = Set(array)
         }
         // Load notifications pref
         if d.object(forKey: notificationsEnabledKey) != nil {
             self.notificationsEnabled = d.bool(forKey: notificationsEnabledKey)
         }
         // Load per-event notification prefs (defaults: start = true, end = false)
         if d.object(forKey: notifyClassStartingSoonKey) != nil {
             self.notifyClassStartingSoon = d.bool(forKey: notifyClassStartingSoonKey)
         }
         if d.object(forKey: notifyClassEndingSoonKey) != nil {
             self.notifyClassEndingSoon = d.bool(forKey: notifyClassEndingSoonKey)
         }
     }
 }

 // MARK: - Views

 struct ContentView: View {
     @StateObject private var store = UserScheduleStore()

     @State private var selectedDay: Weekday = {
         let calendar = Calendar.current
         let weekday = calendar.component(.weekday, from: Date())
         switch weekday {
         case 2: return .monday
         case 3: return .tuesday
         case 4: return .wednesday
         case 5: return .thursday
         case 6: return .friday
         default: return .monday
         }
     }()

     var body: some View {
         NavigationStack {
             TabView {
                 NavigationStack {
                     VStack(spacing: 0) {
                         Picker("Day", selection: $selectedDay) {
                             ForEach(Weekday.allCases) { day in
                                 Text(day.title).tag(day)
                             }
                         }
                         .pickerStyle(.segmented)
                         .tint(.blue)
                         .padding([.top, .horizontal])

                         // Inline update announcement section moved below the Day picker
                         if let announcement = store.pendingAnnouncement {
                             UpdateAnnouncementSection(announcement: announcement)
                                 .padding(.horizontal, 16)
                                 .padding(.top, 10)
                         }

                         DayScheduleView(
                             day: selectedDay,
                             blocks: BellSchedule.weekly[selectedDay] ?? [],
                             store: store
                         )
                         .padding(.top, 8)
                     }
                     .navigationTitle("RooMate")
                 }
                 .tabItem { Label("Schedule", systemImage: "calendar") }

                 NavigationStack {
                     HomeworkView(store: store)
                         .navigationTitle("Homework")
                 }
                 .tabItem { Label("Homework", systemImage: "checklist") }

                 NavigationStack {
                     SettingsView(store: store)
                         .navigationTitle("Settings")
                 }
                 .tabItem { Label("Settings", systemImage: "gearshape") }
             }
             .background(BackgroundView().ignoresSafeArea())
         }
         // Removed the .sheet popup; updates now show inline.
         .task {
             await store.refreshUpdateAnnouncement()
         }
         .preferredColorScheme(store.appearance.colorScheme)
         .frame(minWidth: 600, minHeight: 680)
     }
 }

 struct DayScheduleView: View {
     let day: Weekday
     let blocks: [BellBlock]
     @ObservedObject var store: UserScheduleStore

     // Timer-driven "now"
     @State private var now: Date = Date()
     private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

     // A concrete interval for a BellBlock on the given weekday date
     private struct DatedBlock: Identifiable {
         let id = UUID()
         let original: BellBlock
         let startDate: Date
         let endDate: Date
     }

     var body: some View {
         ScrollView {
             VStack(alignment: .leading, spacing: 16) {
                 Spacer().frame(height: 4)

                 // Current/Next header
                 if let currentInfo = currentBlockInfo(on: now) {
                     CurrentBlockHeader(
                         title: currentInfo.title,
                         subtitle: currentInfo.subtitle,
                         color: currentInfo.color,
                         progress: currentInfo.progress,
                         remainingText: currentInfo.remainingText,
                         nextTitle: currentInfo.nextTitle,
                         nextStartText: currentInfo.nextStartText,
                         nextColor: currentInfo.nextColor,
                         style: store.cardColorStyle,
                         isCountdownMode: false
                     )
                     .padding(.horizontal)
                 } else if let countdown = nextCountdownInfo(on: now) {
                     // No current class: show countdown to next class and its details
                     CurrentBlockHeader(
                         title: countdown.headerTitle,
                         subtitle: countdown.headerSubtitle,
                         color: countdown.headerColor,
                         progress: countdown.progress,
                         remainingText: countdown.remainingText, // Starts in …
                         nextTitle: countdown.nextTitle,
                         nextStartText: countdown.nextStartText,
                         nextColor: countdown.nextColor,
                         style: store.cardColorStyle,
                         isCountdownMode: true
                     )
                     .padding(.horizontal)
                 }

                 Text("\(day.title)’s Schedule")
                     .font(.largeTitle)
                     .fontWeight(.bold)
                     .padding(.horizontal)

                 ForEach(blocks) { block in
                     switch block.kind {
                     case .level(let level):
                         let assignment = store.assignment(for: level)
                         ClassCardView(
                            title: assignment.title,
                            teacher: assignment.teacher.isEmpty ? nil : assignment.teacher,
                            room: assignment.room.isEmpty ? nil : assignment.room,
                            timeRange: formattedRange(start: block.start, end: block.end),
                            color: assignment.color.swiftUIColor,
                            style: store.cardColorStyle
                         )
                         .padding(.horizontal)

                     case .special(let special):
                         ClassCardView(
                            title: special.title,
                            teacher: nil,
                            room: nil,
                            timeRange: formattedRange(start: block.start, end: block.end),
                            color: store.color(for: special),
                            style: store.cardColorStyle
                         )
                         .padding(.horizontal)
                     }
                 }

                 Spacer(minLength: 12)
             }
             .padding(.vertical, 16)
         }
         .modifier(SafeAreaTopPadding(4))
         .onReceive(timer) { now = $0 }
     }

     // Build concrete dates for the schedule for the chosen weekday (relative to the current week)
     private func datedBlocks(for reference: Date) -> [DatedBlock] {
         let cal = Calendar.current
         // Map Weekday to weekday component (1=Sun ... 7=Sat); we use 2..6 for Mon..Fri
         let targetWeekday: Int = {
             switch day {
             case .monday: 2
             case .tuesday: 3
             case .wednesday: 4
             case .thursday: 5
             case .friday: 6
             }
         }()

         // Find the next occurrence of the selected weekday (including today if it matches)
         let startOfDay = cal.startOfDay(for: reference)
         let todayWeekday = cal.component(.weekday, from: startOfDay)
         let dayOffset: Int = {
             var delta = targetWeekday - todayWeekday
             if delta < 0 { delta += 7 } // move to next week if already passed
             return delta
         }()
         let weekdayDate = cal.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay

         return blocks.compactMap { block in
             var startComps = cal.dateComponents([.year, .month, .day], from: weekdayDate)
             startComps.hour = block.start.hour
             startComps.minute = block.start.minute
             startComps.second = 0

             var endComps = cal.dateComponents([.year, .month, .day], from: weekdayDate)
             endComps.hour = block.end.hour
             endComps.minute = block.end.minute
             endComps.second = 0

             guard let s = cal.date(from: startComps), let e = cal.date(from: endComps) else { return nil }
             return DatedBlock(original: block, startDate: s, endDate: e)
         }.sorted(by: { $0.startDate < $1.startDate })
     }

     private func blockTitleColorSubtitle(for block: BellBlock) -> (title: String, color: Color, subtitle: String) {
         switch block.kind {
         case .level(let level):
             let a = store.assignment(for: level)
             let subtitle = [a.teacher, a.room].filter { !$0.isEmpty }.joined(separator: " • ")
             return (a.title, a.color.swiftUIColor, subtitle)
         case .special(let sp):
             return (sp.title, store.color(for: sp), "")
         }
     }

     private func currentBlockInfo(on reference: Date) -> (title: String, subtitle: String, color: Color, progress: Double, remainingText: String, nextTitle: String?, nextStartText: String?, nextColor: Color?)? {
         let list = datedBlocks(for: reference)
         guard !list.isEmpty else { return nil }

         // Find current and next
         var current: DatedBlock?
         var next: DatedBlock?
         for (idx, item) in list.enumerated() {
             if reference >= item.startDate && reference < item.endDate {
                 current = item
                 if idx + 1 < list.count { next = list[idx + 1] }
                 break
             }
             if reference < item.startDate {
                 // Not started yet; next is this one; no current
                 current = nil
                 next = item
                 break
             }
         }

         guard let current else { return nil }

         let total = current.endDate.timeIntervalSince(current.startDate)
         let elapsed = reference.timeIntervalSince(current.startDate)
         let remaining = max(0, current.endDate.timeIntervalSince(reference))
         let progress = max(0, min(1, elapsed / max(1, total)))

         let (title, color, subtitle) = blockTitleColorSubtitle(for: current.original)

         let remainingText = "Ends in " + formatDuration(remaining)

         var nextTitle: String?
         var nextStartText: String?
         var nextColor: Color?
         if let next {
             let (ntitle, ncolor, _) = blockTitleColorSubtitle(for: next.original)
             nextTitle = ntitle
             nextColor = ncolor
             nextStartText = "Starts at " + timeString(next.startDate)
         }

         return (title, subtitle, color, progress, remainingText, nextTitle, nextStartText, nextColor)
     }

     // When there is no current class: compute countdown and progress to the next class.
     private func nextCountdownInfo(on reference: Date) -> (headerTitle: String, headerSubtitle: String, headerColor: Color, progress: Double, remainingText: String, nextTitle: String, nextStartText: String, nextColor: Color)? {
         let list = datedBlocks(for: reference)
         guard !list.isEmpty else { return nil }

         // Find the first future block, and also the last block that ended before now (to anchor progress)
         var future: DatedBlock?
         var previousAnchorTime: Date?
         for (idx, item) in list.enumerated() {
             if reference < item.startDate {
                 future = item
                 // Anchor is the end of the previous block if any; otherwise start of day for that schedule date
                 if idx > 0 {
                     previousAnchorTime = list[idx - 1].endDate
                 } else {
                     previousAnchorTime = Calendar.current.startOfDay(for: item.startDate)
                 }
                 break
             }
         }

         guard let next = future, let anchor = previousAnchorTime else {
             // If all blocks are in the past, show nothing (or could show "No more classes today")
             return nil
         }

         // Remaining time until next starts
         let remaining = max(0, next.startDate.timeIntervalSince(reference))
         // Progress from anchor -> next.startDate
         let totalGap = max(1, next.startDate.timeIntervalSince(anchor))
         let elapsedGap = max(0, reference.timeIntervalSince(anchor))
         let progress = max(0, min(1, elapsedGap / totalGap))

         let (ntitle, ncolor, _) = blockTitleColorSubtitle(for: next.original)

         return (
             headerTitle: "No class right now",
             headerSubtitle: "Starts soon",
             headerColor: .secondary,
             progress: progress,
             remainingText: "Starts in " + formatDuration(remaining),
             nextTitle: ntitle,
             nextStartText: "Starts at " + timeString(next.startDate),
             nextColor: ncolor
         )
     }

     private func timeString(_ date: Date) -> String {
         let fmt = DateFormatter()
         fmt.locale = Locale(identifier: "en_US_POSIX")
         fmt.dateFormat = "h:mm a"
         return fmt.string(from: date)
     }

     private func formatDuration(_ interval: TimeInterval) -> String {
         let minutes = Int(interval) / 60
         let seconds = Int(interval) % 60
         if minutes >= 60 {
             let hours = minutes / 60
             let remMin = minutes % 60
             if remMin == 0 {
                 return "\(hours)h"
             } else {
                 return "\(hours)h \(remMin)m"
             }
         } else if minutes > 0 {
             if seconds == 0 {
                 return "\(minutes)m"
             } else {
                 return "\(minutes)m \(seconds)s"
             }
         } else {
             return "\(seconds)s"
         }
     }

     private func formattedRange(start: DateComponents, end: DateComponents) -> String {
         func format(_ comps: DateComponents) -> String {
             var comps = comps
             comps.second = 0
             let cal = Calendar.current
             guard let date = cal.date(from: comps) else { return "—" }
             let fmt = DateFormatter()
             fmt.locale = Locale(identifier: "en_US_POSIX")
             fmt.dateFormat = "h:mm a"
             return fmt.string(from: date)
         }
         return "\(format(start)) – \(format(end))"
     }
 }

 struct ClassCardView: View {
     let title: String
     let teacher: String?
     let room: String?
     let timeRange: String
     let color: Color
     let style: CardColorStyle

     // Soft color gradient based on a single color
     private var softGradient: LinearGradient {
         let c = color
         return LinearGradient(
             colors: [
                 c.opacity(0.22),
                 c.opacity(0.12)
             ],
             startPoint: .topLeading,
             endPoint: .bottomTrailing
         )
     }

     private var softStrokeGradient: LinearGradient {
         LinearGradient(
             colors: [color.opacity(0.7), color.opacity(0.2)],
             startPoint: .topLeading,
             endPoint: .bottomTrailing
         )
     }

     var body: some View {
         HStack(alignment: .center, spacing: 16) {
             RoundedRectangle(cornerRadius: 6)
                 .fill(LinearGradient(
                     colors: [color.opacity(0.7), color.opacity(0.35)],
                     startPoint: .top,
                     endPoint: .bottom
                 ))
                 .frame(width: 8)

             VStack(alignment: .leading, spacing: 6) {
                 HStack(alignment: .firstTextBaseline) {
                     Text(title)
                         .font(.title3)
                         .fontWeight(.semibold)
                     Spacer()
                     Label(timeRange, systemImage: "clock")
                         .font(.subheadline)
                         .modifier(SecondaryForeground())
                         .labelStyle(.titleAndIcon)
                 }

                 HStack(spacing: 12) {
                     if let teacher, !teacher.isEmpty {
                         Label(teacher, systemImage: "person.fill")
                     }
                     if let room, !room.isEmpty {
                         Label(room, systemImage: "mappin.and.ellipse")
                     }
                 }
                 .font(.subheadline)
                 .modifier(SecondaryForeground())
             }
             .padding(.vertical, 10)
         }
         .padding(12)
         .background(backgroundForStyle)
         .overlay(strokeForStyle)
         .overlay(glowForStyle)
         .overlay(
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .strokeBorder(.quaternary, lineWidth: 0.6)
         )
         .accessibilityElement(children: .ignore)
         .accessibilityLabel("\(title), \(timeRange)\(teacher != nil ? ", with \(teacher!)" : "")\(room != nil ? ", in \(room!)" : "")")
     }

     @ViewBuilder
     private var backgroundForStyle: some View {
         switch style {
         case .none:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .fill(CompatibleBackgroundSecondary())
                 .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
         case .subtle:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .fill(CompatibleBackgroundSecondary())
                 .shadow(color: color.opacity(0.12), radius: 10, x: 0, y: 0)
         case .colors:
             ZStack {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .fill(color.opacity(0.12)) // slightly reduced
                     .blur(radius: 10) // reduced blur
                     .scaleEffect(1.01)
                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                     .fill(softGradient)
                     .shadow(color: color.opacity(0.18), radius: 8, x: 0, y: 0) // reduced shadow
             }
         }
     }

     @ViewBuilder
     private var strokeForStyle: some View {
         switch style {
         case .none:
             EmptyView()
         case .subtle:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .stroke(softStrokeGradient, lineWidth: 1.2)
         case .colors:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .stroke(softStrokeGradient, lineWidth: 1.4) // slightly thinner
         }
     }

     @ViewBuilder
     private var glowForStyle: some View {
         switch style {
         case .none:
             EmptyView()
         case .subtle:
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke(color.opacity(0.10), lineWidth: 4)
                 .blur(radius: 7)
         case .colors:
             // Almost no glow
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke(color.opacity(0.06), lineWidth: 2)
                 .blur(radius: 4)
         }
     }
 }

 // MARK: - Current Block Header

 private struct CurrentBlockHeader: View {
     let title: String
     let subtitle: String
     let color: Color
     let progress: Double
     let remainingText: String
     let nextTitle: String?
     let nextStartText: String?
     let nextColor: Color?
     let style: CardColorStyle
     let isCountdownMode: Bool

     var body: some View {
         VStack(alignment: .leading, spacing: 12) {
             // Now/countdown block
             VStack(spacing: 10) {
                 HStack(spacing: 12) {
                     RoundedRectangle(cornerRadius: 6)
                         .fill(accentFill)
                         .frame(width: 8, height: 40)
                         .shadow(color: accentShadowColor, radius: accentShadowRadius, x: 0, y: 0)
                     VStack(alignment: .leading, spacing: 4) {
                         HStack {
                             Label(isCountdownMode ? "Idle" : "Now", systemImage: isCountdownMode ? "pause.circle" : "clock")
                                 .font(.caption)
                                 .modifier(SecondaryForeground())
                             Spacer()
                         }
                         Text(title)
                             .font(.title3.bold())
                         if !subtitle.isEmpty {
                             Text(subtitle)
                                 .font(.subheadline)
                                 .modifier(SecondaryForeground())
                         }
                     }
                 }

                 ProgressView(value: progress)
                     .tint(progressTint)
                     .animation(.linear(duration: 0.2), value: progress)

                 HStack {
                     if !remainingText.isEmpty {
                         Label(remainingText, systemImage: isCountdownMode ? "clock.badge.checkmark" : "hourglass")
                     } else {
                         Text("—")
                     }
                     Spacer()
                 }
                 .font(.footnote)
                 .modifier(SecondaryForeground())
             }
             .padding(12)
             .background(nowBackground)
             .overlay(nowStroke)
             .overlay(nowGlow)
             .overlay(
                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                     .strokeBorder(.quaternary, lineWidth: 0.6)
             )

             // Next up card
             if let nextTitle, let nextStartText {
                 NextBlockCard(
                     title: nextTitle,
                     startText: nextStartText,
                     color: nextColor ?? .accentColor,
                     style: style
                 )
             }
         }
     }

     // MARK: - Style-dependent pieces

     private var isNeutral: Bool { style == .none || isCountdownMode }

     private var accentFill: some ShapeStyle {
         if isNeutral {
             return LinearGradient(colors: [Color.secondary.opacity(0.5), Color.secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom)
         } else {
             return LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom)
         }
     }

     private var accentShadowColor: Color {
         if isNeutral { return Color.clear }
         return color.opacity(style == .colors ? 0.25 : 0.35)
     }

     private var accentShadowRadius: CGFloat {
         if isNeutral { return 0 }
         return style == .colors ? 6 : 8
     }

     private var progressTint: Color {
         isNeutral ? .accentColor : color
     }

     @ViewBuilder
     private var nowBackground: some View {
         switch style {
         case .none:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .fill(CompatibleBackgroundSecondary())
         case .subtle:
             ZStack {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .fill((isNeutral ? Color.secondary : color).opacity(0.12))
                     .blur(radius: 10)
                     .scaleEffect(1.01)

                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                     .fill(LinearGradient(
                         colors: [(isNeutral ? Color.secondary : color).opacity(0.16), (isNeutral ? Color.secondary : color).opacity(0.06)],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing
                     ))
                     .shadow(color: (isNeutral ? Color.secondary : color).opacity(0.2), radius: 9, x: 0, y: 0)
             }
         case .colors:
             ZStack {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .fill((isNeutral ? Color.secondary : color).opacity(0.10))
                     .blur(radius: 8)
                     .scaleEffect(1.005)

                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                     .fill(LinearGradient(
                         colors: [(isNeutral ? Color.secondary : color).opacity(0.14), (isNeutral ? Color.secondary : color).opacity(0.06)],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing
                     ))
                     .shadow(color: (isNeutral ? Color.secondary : color).opacity(0.16), radius: 7, x: 0, y: 0)
             }
         }
     }

     @ViewBuilder
     private var nowStroke: some View {
         switch style {
         case .none:
             EmptyView()
         case .subtle:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .stroke(LinearGradient(
                     colors: [(isNeutral ? Color.secondary : color).opacity(0.6), (isNeutral ? Color.secondary : color).opacity(0.18)],
                     startPoint: .topLeading,
                     endPoint: .bottomTrailing
                 ), lineWidth: 1.6)
         case .colors:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .stroke(LinearGradient(
                     colors: [(isNeutral ? Color.secondary : color).opacity(0.5), (isNeutral ? Color.secondary : color).opacity(0.16)],
                     startPoint: .topLeading,
                     endPoint: .bottomTrailing
                 ), lineWidth: 1.2)
         }
     }

     @ViewBuilder
     private var nowGlow: some View {
         switch style {
         case .none:
             EmptyView()
         case .subtle:
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke((isNeutral ? Color.secondary : color).opacity(0.10), lineWidth: 4)
                 .blur(radius: 7)
         case .colors:
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke((isNeutral ? Color.secondary : color).opacity(0.05), lineWidth: 2)
                 .blur(radius: 3)
         }
     }
 }

 private struct NextBlockCard: View {
     let title: String
     let startText: String
     let color: Color
     let style: CardColorStyle

     var body: some View {
         HStack(spacing: 12) {
             RoundedRectangle(cornerRadius: 6)
                 .fill(accentFill)
                 .frame(width: 8, height: 34)
                 .shadow(color: accentShadowColor, radius: accentShadowRadius, x: 0, y: 0)

             VStack(alignment: .leading, spacing: 4) {
                 HStack {
                     Label("Next up", systemImage: "arrow.right")
                         .font(.caption)
                         .modifier(SecondaryForeground())
                     Spacer()
                 }
                 HStack {
                     Text(title)
                         .font(.subheadline.weight(.semibold))
                     Spacer()
                     Label(startText, systemImage: "calendar")
                         .font(.footnote)
                         .modifier(SecondaryForeground())
                 }
             }
         }
         .padding(10)
         .background(background)
         .overlay(stroke)
         .overlay(glow)
         .overlay(
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .strokeBorder(.quaternary, lineWidth: 0.6)
         )
     }

     private var isNeutral: Bool { style == .none }

     private var accentFill: some ShapeStyle {
         if isNeutral {
             return LinearGradient(colors: [Color.secondary.opacity(0.5), Color.secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom)
         } else {
             return LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom)
         }
     }

     private var accentShadowColor: Color {
         if isNeutral { return Color.clear }
         return color.opacity(style == .colors ? 0.20 : 0.30)
     }

     private var accentShadowRadius: CGFloat {
         if isNeutral { return 0 }
         return style == .colors ? 5 : 7
     }

     @ViewBuilder
     private var background: some View {
         switch style {
         case .none:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .fill(CompatibleBackgroundSecondary())
         case .subtle:
             ZStack {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .fill(color.opacity(0.10))
                     .blur(radius: 8)
                     .scaleEffect(1.01)

                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                     .fill(LinearGradient(
                         colors: [color.opacity(0.14), color.opacity(0.06)],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing
                     ))
                     .shadow(color: color.opacity(0.18), radius: 8, x: 0, y: 0)
             }
         case .colors:
             ZStack {
                 RoundedRectangle(cornerRadius: 16, style: .continuous)
                     .fill(color.opacity(0.08))
                     .blur(radius: 6)
                     .scaleEffect(1.005)

                 RoundedRectangle(cornerRadius: 12, style: .continuous)
                     .fill(LinearGradient(
                         colors: [color.opacity(0.12), color.opacity(0.05)],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing
                     ))
                     .shadow(color: color.opacity(0.14), radius: 6, x: 0, y: 0)
             }
         }
     }

     @ViewBuilder
     private var stroke: some View {
         switch style {
         case .none:
             EmptyView()
         case .subtle:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .stroke(LinearGradient(
                     colors: [color.opacity(0.5), color.opacity(0.16)],
                     startPoint: .topLeading,
                     endPoint: .bottomTrailing
                 ), lineWidth: 1.4)
         case .colors:
             RoundedRectangle(cornerRadius: 12, style: .continuous)
                 .stroke(LinearGradient(
                     colors: [color.opacity(0.45), color.opacity(0.14)],
                     startPoint: .topLeading,
                     endPoint: .bottomTrailing
                 ), lineWidth: 1.0)
         }
     }

     @ViewBuilder
     private var glow: some View {
         switch style {
         case .none:
             EmptyView()
         case .subtle:
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke(color.opacity(0.08), lineWidth: 3.5)
                 .blur(radius: 6)
         case .colors:
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .stroke(color.opacity(0.04), lineWidth: 1.8)
                 .blur(radius: 3)
         }
     }
 }

 // MARK: - Homework Views (Canvas-backed)

 struct HomeworkView: View {
     @ObservedObject var store: UserScheduleStore

     private var completion: (done: Int, total: Int, percent: Double) {
         let total = store.canvasTodos.count
         guard total > 0 else { return (0, 0, 0) }
         let done = store.canvasTodos.reduce(0) { $0 + (store.isTodoCompleted($1.id) ? 1 : 0) }
         return (done, total, Double(done) / Double(total))
     }

     // Ordered list of colors matching the current to‑dos
     private var segments: [Color] {
         store.canvasTodos.map { store.colorForCanvasCourseName($0.contextName) }
     }

     var body: some View {
         VStack(spacing: 0) {
             HStack {
                 Button {
                     Task {
                         async let t1: Void = store.refreshCanvasTodos()
                         async let t2: Void = store.refreshCanvasCoursesAndGrades()
                         _ = await (t1, t2)

                         // Telemetry emission after both calls complete
                         emitTelemetryForTestConnection()
                     }
                 } label: {
                     Label("Refresh", systemImage: "arrow.clockwise")
                 }
                 .keyboardShortcut("r", modifiers: [.command])

                 Spacer()

                 if store.isFetchingTodos || store.isFetchingGrades {
                     ProgressView().controlSize(.small)
                 }

                 if let error = store.fetchError ?? store.gradesError {
                     Label(error, systemImage: "exclamationmark.triangle.fill")
                         .modifier(SecondaryForeground())
                         .font(.footnote)
                 }
             }
             .padding([.top, .horizontal])

             // Progress header (uses Canvas to‑dos)
             HomeworkProgressHeader(done: completion.done, total: completion.total, percent: completion.percent, segments: segments)
                 .padding(.horizontal)
                 .padding(.top, 8)

             List {
                 // Grades section
                 Section {
                     if store.canvasToken.isEmpty {
                         CompatibleUnavailableView(
                             title: "Enter Canvas API Token",
                             systemImage: "key.fill",
                             description: "Add your Canvas domain and API token in Settings to load your grades."
                         )
                         .modifier(HideListSeparatorIfAvailable())
                     } else if store.courses.isEmpty && store.isFetchingGrades {
                         HStack {
                             ProgressView()
                             Text("Loading grades…")
                                 .modifier(SecondaryForeground())
                         }
                     } else if store.courses.isEmpty {
                         CompatibleUnavailableView(
                             title: "No Courses",
                             systemImage: "book.closed",
                             description: "We couldn’t find any active courses."
                         )
                         .modifier(HideListSeparatorIfAvailable())
                     } else {
                         ForEach(store.courses) { course in
                             GradesRow(course: course, summary: store.gradesByCourse[course.id])
                                 .contentShape(Rectangle())
                                 .onTapGesture {
                                     openCourse(course: course, domain: store.canvasDomain)
                                 }
                         }
                     }
                 } header: {
                     Label("Grades", systemImage: "chart.bar.fill")
                 }

                 // To‑Do section
                 Section {
                     if store.canvasToken.isEmpty {
                         CompatibleUnavailableView(
                             title: "Enter Canvas API Token",
                             systemImage: "key.fill",
                             description: "Add your Canvas domain and API token in Settings to load your to‑do items."
                         )
                         .modifier(HideListSeparatorIfAvailable())
                     } else if store.canvasTodos.isEmpty {
                         if store.isFetchingTodos {
                             HStack {
                                 ProgressView()
                                 Text("Loading to‑dos…")
                                     .modifier(SecondaryForeground())
                             }
                         } else {
                             CompatibleUnavailableView(
                                 title: "No To‑Do Items",
                                 systemImage: "checkmark.circle",
                                 description: "You're all caught up!"
                             )
                             .modifier(HideListSeparatorIfAvailable())
                         }
                     } else {
                         ForEach(store.canvasTodos) { todo in
                             let color = store.colorForCanvasCourseName(todo.contextName)

                             CanvasTodoRow(
                                 todo: todo,
                                 accentColor: color,
                                 completed: store.isTodoCompleted(todo.id),
                                 onToggleCompleted: {
                                     store.toggleTodoCompleted(todo.id)
                                 },
                                 onOpen: {
                                     open(todo: todo, domain: store.canvasDomain)
                                 }
                             )
                             .contentShape(Rectangle())

                             // Small derived-state badge to verify UI updates
                             HStack {
                                 Text(store.isTodoCompleted(todo.id) ? "✓ Completed" : "○ Incomplete")
                                     .font(.caption)
                                     .modifier(SecondaryForeground())
                                 Spacer()
                             }
                         }
                         // If UI still doesn't refresh, uncomment the next line as a test:
                         // .id(store.completedTodoIDs)
                     }
                 } header: {
                     Label("To‑Do", systemImage: "checklist")
                 }
             }
             .listStyle(.inset)
         }
         .task {
             if !store.canvasToken.isEmpty {
                 async let t1: Void = store.refreshCanvasTodos()
                 async let t2: Void = store.refreshCanvasCoursesAndGrades()
                 _ = await (t1, t2)
             }
         }
     }

     private func emitTelemetryForTestConnection() {
         // Evaluate statuses captured by the store
         let todosStatus = store.lastTodosHTTPStatus
         let coursesStatus = store.lastCoursesHTTPStatus

         // Helper closures to send signals with string parameters
         func sendUnauthorized(endpoint: String, status: Int) {
             TelemetryDeck.signal("CanvasConnectionUnauthorized", parameters: [
                 "endpoint": endpoint,
                 "status": "\(status)"
             ])
         }
         func sendCoursesServerError(status: Int) {
             TelemetryDeck.signal("CanvasCoursesServerError", parameters: [
                 "endpoint": store.lastCoursesEndpoint,
                 "status": "\(status)"
             ])
         }
         func sendGenericFailure(endpoint: String, status: Int) {
             TelemetryDeck.signal("CanvasConnectionFailed", parameters: [
                 "endpoint": endpoint,
                 "status": "\(status)"
             ])
         }

         // If both succeeded (treat 200 as success), send one success signal without parameters
         if let ts = todosStatus, let cs = coursesStatus,
            (200..<300).contains(ts), (200..<300).contains(cs) {
             TelemetryDeck.signal("CanvasConnectionSuccess")
             return
         }

         // Emit failures per endpoint for visibility
         if let ts = todosStatus, !(200..<300).contains(ts) {
             if ts == 401 {
                 sendUnauthorized(endpoint: store.lastTodosEndpoint, status: ts)
             } else {
                 sendGenericFailure(endpoint: store.lastTodosEndpoint, status: ts)
             }
         }

         if let cs = coursesStatus, !(200..<300).contains(cs) {
             if cs == 401 {
                 sendUnauthorized(endpoint: store.lastCoursesEndpoint, status: cs)
             } else if (500..<600).contains(cs) {
                 sendCoursesServerError(status: cs)
             } else {
                 sendGenericFailure(endpoint: store.lastCoursesEndpoint, status: cs)
             }
         }
     }

     private func open(todo: CanvasTodoItem, domain: String) {
         let urlString = todo.assignment?.htmlURL ?? todo.htmlURL
         guard let urlString, let url = URL(string: urlString) ?? URL(string: "https://\(domain)") else { return }
         #if canImport(AppKit)
         NSWorkspace.shared.open(url)
         #elseif canImport(UIKit)
         UIApplication.shared.open(url)
         #endif
     }

     private func openCourse(course: CanvasCourse, domain: String) {
         let urlString = course.htmlURL ?? "https://\(domain)/courses/\(course.id)"
         guard let url = URL(string: urlString) else { return }
         #if canImport(AppKit)
         NSWorkspace.shared.open(url)
         #elseif canImport(UIKit)
         UIApplication.shared.open(url)
         #endif
     }
 }

 // Segmented, color-coded header like the screenshot
 private struct HomeworkProgressHeader: View {
     let done: Int
     let total: Int
     let percent: Double
     let segments: [Color]

     private var percentText: String {
         guard total > 0 else { return "0%" }
         return String(format: "%.0f%%", percent * 100)
     }

     var body: some View {
         VStack(alignment: .leading, spacing: 8) {
             HStack {
                 Text(percentText)
                     .font(.title3.bold())
                 Spacer()
                 Text("\(done)/\(total) complete")
                     .font(.subheadline.weight(.semibold))
                     .modifier(SecondaryForeground())
             }

             SegmentedProgressBar(percent: percent, segments: segments)
                 .frame(height: 16)
         }
         .padding(.vertical, 6)
     }
 }

 private struct SegmentedProgressBar: View {
     let percent: Double // 0...1
     let segments: [Color]

     var body: some View {
         GeometryReader { geo in
             let width = geo.size.width
             let clipWidth = max(0, min(1, percent)) * width

             ZStack(alignment: .leading) {
                 // Track
                 RoundedRectangle(cornerRadius: 10, style: .continuous)
                     .fill(Color.secondary.opacity(0.25))

                 // Colored segments (equal widths), masked by completion clip
                 HStack(spacing: 0) {
                     ForEach(segments.indices, id: \.self) { idx in
                         segments[idx]
                             .frame(width: width / CGFloat(max(1, segments.count)))
                     }
                 }
                 .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: clipWidth, height: geo.size.height)))
                 .mask(
                     RoundedRectangle(cornerRadius: 10, style: .continuous)
                 )
             }
         }
     }
 }

 struct CanvasTodoRow: View {
     let todo: CanvasTodoItem
     let accentColor: Color
     let completed: Bool
     let onToggleCompleted: () -> Void
     let onOpen: () -> Void

     private var title: String {
         todo.assignment?.name ?? "Untitled"
     }

     private var course: String {
         todo.contextName ?? "Course"
     }

     private var dueText: String {
         guard let iso = todo.assignment?.dueAt, let date = ISO8601DateFormatter().date(from: iso) else {
             return "No due date"
         }
         let cal = Calendar.current
         if cal.isDateInToday(date) { return "Due Today" }
         if cal.isDateInTomorrow(date) { return "Due Tomorrow" }
         let fmt = DateFormatter()
         fmt.dateStyle = .medium
         fmt.timeStyle = .short
         return "Due " + fmt.string(from: date)
     }

     var body: some View {
         HStack(spacing: 12) {
             RoundedRectangle(cornerRadius: 6)
                 .fill(CompatibleGradient(accentColor))
                 .frame(width: 6)

             // Make the main content a button to open the item
             Button(action: onOpen) {
                 VStack(alignment: .leading, spacing: 4) {
                     HStack(spacing: 8) {
                         Text(title)
                             .font(.headline)
                             .strikethrough(completed, color: .secondary)
                             .opacity(completed ? 0.55 : 1.0)
                         Spacer()
                         Label(dueText, systemImage: "calendar")
                             .font(.subheadline)
                             .modifier(SecondaryForeground())
                     }

                     HStack(spacing: 10) {
                         Label(course, systemImage: "book.closed")
                             .font(.subheadline)
                             .modifier(SecondaryForeground())
                     }
                 }
                 .padding(.vertical, 8)
                 .contentShape(Rectangle())
             }
             .buttonStyle(.plain)

             // Trailing completion button remains separate and fully tappable/clickable
             Button(action: onToggleCompleted) {
                 ZStack {
                     Circle()
                         .strokeBorder(completed ? Color.green : Color.secondary.opacity(0.4), lineWidth: 2)
                         .frame(width: 22, height: 22)
                     if completed {
                         Circle()
                             .fill(Color.green)
                             .frame(width: 12, height: 12)
                     }
                 }
                 .padding(.horizontal, 4) // slightly larger tap area
                 .contentShape(Rectangle()) // declare hit area
             }
             .buttonStyle(.plain)
             .tint(.blue)
             .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
         }
     }
 }

 struct GradesRow: View {
     let course: CanvasCourse
     let summary: GradeSummary?

     var body: some View {
         HStack(spacing: 12) {
             RoundedRectangle(cornerRadius: 6)
                 .fill(CompatibleGradient(.accentColor))
                 .frame(width: 6)

             VStack(alignment: .leading, spacing: 4) {
                 HStack {
                     Text(course.name)
                         .font(.headline)
                     Spacer()
                     if let summary {
                         Label(summary.displayCurrent, systemImage: "chart.bar")
                             .font(.subheadline)
                             .modifier(SecondaryForeground())
                     } else {
                         Text("No grade yet")
                             .font(.subheadline)
                             .modifier(SecondaryForeground())
                     }
                 }

                 if let code = course.courseCode, !code.isEmpty {
                     Text(code)
                         .font(.subheadline)
                         .modifier(SecondaryForeground())
                 }
             }
             .padding(.vertical, 8)
         }
     }
 }

 // MARK: - Settings

 struct SettingsView: View {
     @ObservedObject var store: UserScheduleStore

     @State private var isClassesExpanded: Bool = true
     @State private var showToken: Bool = false
     @State private var testResult: String?
     @State private var showTokenHelp: Bool = false

     // New: collapsible flags
     @State private var isCustomizationExpanded: Bool = true
     @State private var isNotificationsExpanded: Bool = true

     private var editableLevels: [Level] {
         [.level1, .level2, .level3, .level4, .level5, .level6, .level7, .music]
     }

     private var notificationStatusText: String {
         #if canImport(UserNotifications)
         switch store.notificationAuthStatus {
         case .notDetermined: return "Not Determined"
         case .denied: return "Denied"
         case .authorized: return "Authorized"
         case .provisional: return "Provisional"
         case .ephemeral: return "Ephemeral"
         @unknown default: return "Unknown"
         }
         #else
         return "Unavailable"
         #endif
     }

     // About helpers
     private var appName: String {
         let dict = Bundle.main.infoDictionary
         return dict?["CFBundleDisplayName"] as? String
             ?? dict?["CFBundleName"] as? String
             ?? "App"
     }
     private var appVersion: String {
         let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
         let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
         return b.isEmpty ? v : "\(v) (\(b))"
     }

     // Configure your feedback details here
     private let feedbackEmail = "29makaio@abingtonfriends.net" // TODO: replace
     private let websiteURL = URL(string: "https://roomateafs.net") // optional

     var body: some View {
         ScrollView {
             VStack(alignment: .leading, spacing: 16) {
                 Spacer().frame(height: 4)

                 // Customization collapsible header
                 Button {
                     withAnimation(.snappy) { isCustomizationExpanded.toggle() }
                 } label: {
                     HStack(spacing: 10) {
                         Image(systemName: "chevron.right")
                             .rotationEffect(.degrees(isCustomizationExpanded ? 90 : 0))
                             .modifier(SecondaryForeground())
                             .animation(.snappy, value: isCustomizationExpanded)
                         Image(systemName: "paintbrush.pointed")
                             .foregroundStyle(.secondary)
                         Text("Customization")
                             .font(.title2.bold())
                         Spacer()
                     }
                     .contentShape(Rectangle())
                     .padding(.horizontal, 4)
                     .padding(.vertical, 8)
                 }
                 .buttonStyle(.plain)
                 .accessibilityElement(children: .combine)
                 .accessibilityLabel("Customization")
                 .accessibilityAddTraits(.isButton)
                 .accessibilityValue(isCustomizationExpanded ? "Expanded" : "Collapsed")

                 if isCustomizationExpanded {
                     VStack(alignment: .leading, spacing: 12) {
                         VStack(alignment: .leading, spacing: 8) {
                             Text("Appearance")
                                 .font(.headline)
                             Text("Choose light, dark, or follow the system.")
                                 .font(.footnote)
                                 .modifier(SecondaryForeground())

                             Picker("Appearance", selection: $store.appearance) {
                                 ForEach(AppearancePreference.allCases) { option in
                                     Label(option.title, systemImage: option.systemImage)
                                         .tag(option)
                                 }
                             }
                             .pickerStyle(.segmented)
                             .tint(.blue)
                             .accessibilityLabel("Appearance")
                         }

                         Divider().opacity(0.2)

                         VStack(alignment: .leading, spacing: 8) {
                             Text("Class Card Colors")
                                 .font(.headline)
                             Text("Pick how colorful class cards should look.")
                                 .font(.footnote)
                                 .modifier(SecondaryForeground())

                             Picker("Class Card Colors", selection: $store.cardColorStyle) {
                                 ForEach(CardColorStyle.allCases) { style in
                                     Label(style.title, systemImage: style.systemImage).tag(style)
                                 }
                             }
                             .pickerStyle(.segmented)
                             .tint(.blue)
                             .accessibilityLabel("Class Card Colors")
                         }
                     }
                     .padding(12)
                     .background(
                         RoundedRectangle(cornerRadius: 12, style: .continuous)
                             .fill(CompatibleBackgroundSecondary())
                     )
                     .overlay(
                         RoundedRectangle(cornerRadius: 12, style: .continuous)
                             .strokeBorder(.quaternary, lineWidth: 0.8)
                     )
                     .transition(.opacity.combined(with: .move(edge: .top)))
                 }

                 // Notifications (macOS) collapsible
                 #if canImport(AppKit)
                 Button {
                     withAnimation(.snappy) { isNotificationsExpanded.toggle() }
                 } label: {
                     HStack(spacing: 10) {
                         Image(systemName: "chevron.right")
                             .rotationEffect(.degrees(isNotificationsExpanded ? 90 : 0))
                             .modifier(SecondaryForeground())
                             .animation(.snappy, value: isNotificationsExpanded)
                         Image(systemName: "bell.badge.fill")
                             .foregroundStyle(.secondary)
                         Text("Notifications")
                             .font(.title2.bold())
                         Spacer()
                     }
                     .contentShape(Rectangle())
                     .padding(.horizontal, 4)
                     .padding(.vertical, 8)
                 }
                 .buttonStyle(.plain)
                 .tint(.blue)
                 .accessibilityElement(children: .combine)
                 .accessibilityLabel("Notifications")
                 .accessibilityAddTraits(.isButton)
                 .accessibilityValue(isNotificationsExpanded ? "Expanded" : "Collapsed")

                 if isNotificationsExpanded {
                     VStack(alignment: .leading, spacing: 12) {
                         Toggle(isOn: $store.notificationsEnabled) {
                             Text("Enable notifications")
                         }
                         .toggleStyle(.switch)
                         .tint(.blue)
                         HStack {
                             Label("Status: \(notificationStatusText)", systemImage: "info.circle")
                                 .modifier(SecondaryForeground())
                             Spacer()
                             Button {
                                 Task { @MainActor in await store.refreshNotificationStatus() }
                             } label: {
                                 Label("Refresh", systemImage: "arrow.clockwise")
                             }
                         }

                         // Per-event toggles
                         VStack(alignment: .leading, spacing: 8) {
                             Text("Class Alerts")
                                 .font(.headline)
                                 .tint(.blue)

                             Toggle(isOn: $store.notifyClassStartingSoon) {
                                 Label("Notify when a class is starting soon", systemImage: "bell.and.waveform.fill")
                             }
                             .disabled(!store.notificationsEnabled)
                             .tint(.blue)

                             Toggle(isOn: $store.notifyClassEndingSoon) {
                                 Label("Notify when a class is ending soon", systemImage: "bell.circle.fill")
                             }
                             .disabled(!store.notificationsEnabled)
                             .tint(.blue)

                             Text("These settings control which class alerts we schedule. You can adjust timing and permissions in System Settings.")
                                 .font(.footnote)
                                 .modifier(SecondaryForeground())
                         }

                         HStack(spacing: 10) {
                             Button {
                                 Task { @MainActor in await store.requestNotificationPermission() }
                             } label: {
                                 Label("Request Permission", systemImage: "bell.badge")
                             }

                             Button {
                                 store.openSystemNotificationSettings()
                             } label: {
                                 Label("Open System Settings", systemImage: "gearshape")
                             }

                             Button {
                                 Task { @MainActor in await store.sendTestNotification() }
                             } label: {
                                 Label("Send Test", systemImage: "paperplane.fill")
                             }
                             .disabled(!(store.notificationAuthStatus == .authorized || store.notificationAuthStatus == .provisional))
                         }
                     }
                     .padding(12)
                     .background(
                         RoundedRectangle(cornerRadius: 12, style: .continuous)
                             .fill(CompatibleBackgroundSecondary())
                     )
                     .overlay(
                         RoundedRectangle(cornerRadius: 12, style: .continuous)
                             .strokeBorder(.quaternary, lineWidth: 0.8)
                     )
                     .transition(.opacity.combined(with: .move(edge: .top)))
                 }
                 #endif

                 // Canvas token section
                 VStack(alignment: .leading, spacing: 12) {
                     Text("Canvas Key (For Homework And Grades) (Optional)")
                         .font(.title2.bold())

                     HStack {
                         Text("Domain")
                             .frame(width: 80, alignment: .leading)
                         TextField("afs.instructure.com", text: $store.canvasDomain)
                             .textFieldStyle(.roundedBorder)
                             #if canImport(UIKit)
                             .textContentType(.URL)
                             .autocorrectionDisabled()
                             .textInputAutocapitalization(.never)
                             #else
                             .autocorrectionDisabled()
                             .modifier(MacURLContentTypeIfAvailable())
                             #endif
                     }

                     HStack(alignment: .center, spacing: 8) {
                         Text("API Token")
                             .frame(width: 80, alignment: .leading)

                         if showToken {
                             TextField("Paste token", text: $store.canvasToken)
                                 .textFieldStyle(.roundedBorder)
                                 .textContentType(.password)
                                 .autocorrectionDisabled()
                             #if canImport(UIKit)
                                 .textInputAutocapitalization(.never)
                             #endif
                         } else {
                             SecureField("Paste token", text: $store.canvasToken)
                                 .textFieldStyle(.roundedBorder)
                                 .textContentType(.password)
                         }

                         Button { showToken.toggle() } label: {
                             Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                         }
                         .help(showToken ? "Hide Token" : "Show Token")

                         Button { showTokenHelp = true } label: {
                             Image(systemName: "questionmark.circle")
                         }
                         .help("How to get your Canvas API token")
                         .popover(isPresented: $showTokenHelp, arrowEdge: .top) {
                             TokenHelpView(domain: store.canvasDomain, isPresented: $showTokenHelp)
                                 .frame(minWidth: 320)
                                 .padding()
                         }

                         Button(role: .destructive) {
                             Task { @MainActor in store.clearCanvasToken() }
                         } label: {
                             Image(systemName: "trash")
                         }
                         .help("Clear saved API token")
                     }

                     HStack {
                         Button {
                             Task {
                                 async let t1: Void = store.refreshCanvasTodos()
                                 async let t2: Void = store.refreshCanvasCoursesAndGrades()
                                 _ = await (t1, t2)

                                 // Telemetry emission after both calls complete
                                 emitTelemetryForTestConnection()

                                 if let err = store.fetchError ?? store.gradesError {
                                     testResult = "Failed: \(err)"
                                 } else {
                                     testResult = "Success: \(store.canvasTodos.count) todos, \(store.courses.count) courses"
                                 }
                             }
                         } label: {
                             Label("Test Connection", systemImage: "wifi")
                         }

                         if store.isFetchingTodos || store.isFetchingGrades {
                             ProgressView().controlSize(.small)
                         }

                         if let testResult {
                             Text(testResult)
                                 .font(.footnote)
                                 .modifier(SecondaryForeground())
                         }
                     }
                 }
                 .padding(12)
                 .background(
                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                         .fill(CompatibleBackgroundSecondary())
                 )
                 .overlay(
                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                         .strokeBorder(.quaternary, lineWidth: 0.8)
                 )

                 // Updates section
                 VStack(alignment: .leading, spacing: 10) {
                     Text("Updates")
                         .font(.title2.bold())

                     Text("Click Check For Updates To Check For New Features Or Bug Fixes.")
                         .font(.footnote)
                         .modifier(SecondaryForeground())

                     HStack(spacing: 10) {
                         Button {
                             Task { @MainActor in await store.refreshUpdateAnnouncement() }
                         } label: {
                             Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                         }

                         if let pending = store.pendingAnnouncement {
                             Text("Pending: \(pending.updateNumber)")
                                 .font(.footnote)
                                 .modifier(SecondaryForeground())
                         } else {
                             Text("No pending announcements")
                                 .font(.footnote)
                                 .modifier(SecondaryForeground())
                         }
                     }
                 }
                 .padding(12)
                 .background(
                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                         .fill(CompatibleBackgroundSecondary())
                 )
                 .overlay(
                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                         .strokeBorder(.quaternary, lineWidth: 0.8)
                 )
                 .frame(maxWidth: .infinity, alignment: .leading)
                 .padding(.horizontal, 0)
                 
                 Button {
                     withAnimation(.snappy) { isClassesExpanded.toggle() }
                 } label: {
                     HStack(spacing: 10) {
                         Image(systemName: "chevron.right")
                             .rotationEffect(.degrees(isClassesExpanded ? 90 : 0))
                             .modifier(SecondaryForeground())
                             .animation(.snappy, value: isClassesExpanded)
                         Text("Your Classes")
                             .font(.title2.bold())
                         Spacer()
                     }
                     .contentShape(Rectangle())
                     .padding(.horizontal, 4)
                     .padding(.vertical, 8)
                 }
                 .buttonStyle(.plain)
                 .tint(.blue)
                 .accessibilityElement(children: .combine)
                 .accessibilityLabel("Your Classes")
                 .accessibilityAddTraits(.isButton)
                 .accessibilityValue(isClassesExpanded ? "Expanded" : "Collapsed")

                 if isClassesExpanded {
                     VStack(alignment: .leading, spacing: 12) {
                         ForEach(editableLevels, id: \.self) { level in
                             LevelEditorRow(level: level, assignment: store.binding(for: level))
                                 .padding(12)
                                 .background(
                                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                                         .fill(CompatibleBackgroundSecondary())
                                 )
                                 .overlay(
                                     RoundedRectangle(cornerRadius: 12, style: .continuous)
                                         .strokeBorder(.quaternary, lineWidth: 0.8)
                                 )
                         }
                     }
                     .transition(.opacity.combined(with: .move(edge: .top)))

                     VStack(alignment: .leading, spacing: 12) {
                         Text("Special Blocks")
                             .font(.title2.bold())

                         SpecialColorRow(title: SpecialBlock.lunch.title, systemImage: SpecialBlock.lunch.systemImage, color: store.colorBinding(for: .lunch))
                         SpecialColorRow(title: SpecialBlock.officeHours.title, systemImage: SpecialBlock.officeHours.systemImage, color: store.colorBinding(for: .officeHours))
                         SpecialColorRow(title: SpecialBlock.worship.title, systemImage: SpecialBlock.worship.systemImage, color: store.colorBinding(for: .worship))
                         SpecialColorRow(title: SpecialBlock.consciousCommunities.title, systemImage: SpecialBlock.consciousCommunities.systemImage, color: store.colorBinding(for: .consciousCommunities))
                         SpecialColorRow(title: SpecialBlock.advisory.title, systemImage: SpecialBlock.advisory.systemImage, color: store.colorBinding(for: .advisory))
                         SpecialColorRow(title: SpecialBlock.assembly.title, systemImage: SpecialBlock.assembly.systemImage, color: store.colorBinding(for: .assembly))
                     }
                     .padding(12)
                     .background(
                         RoundedRectangle(cornerRadius: 12, style: .continuous)
                             .fill(CompatibleBackgroundSecondary())
                     )
                     .overlay(
                         RoundedRectangle(cornerRadius: 12, style: .continuous)
                             .strokeBorder(.quaternary, lineWidth: 0.8)
                     )
                     .transition(.opacity.combined(with: .move(edge: .top)))
                 }

                 // About footer centered at the bottom
                 VStack(spacing: 6) {
                     Text("\(appName) — Version \(appVersion)")
                         .font(.footnote.weight(.semibold))
                         .multilineTextAlignment(.center)
                     Text("RooMate helps you track your schedule, homework, and grades with a clean, customizable interface.")
                         .font(.footnote)
                         .multilineTextAlignment(.center)
                         .modifier(SecondaryForeground())
                 }
                 .frame(maxWidth: .infinity)
                 .padding(.top, 24)
                 .padding(.bottom, 8)

                 Spacer(minLength: 12)
             }
             .padding(.horizontal, 16)
             .padding(.vertical, 16)
         }
         .modifier(SafeAreaTopPadding(6))
         .task {
             await store.refreshNotificationStatus()
         }
     }

     private func emitTelemetryForTestConnection() {
         let todosStatus = store.lastTodosHTTPStatus
         let coursesStatus = store.lastCoursesHTTPStatus

         // Success: both 2xx
         if let ts = todosStatus, let cs = coursesStatus,
            (200..<300).contains(ts), (200..<300).contains(cs) {
             TelemetryDeck.signal("CanvasConnectionSuccess")
             return
         }

         // Unauthorized (401) and other failures per endpoint
         if let ts = todosStatus, !(200..<300).contains(ts) {
             if ts == 401 {
                 TelemetryDeck.signal("CanvasConnectionUnauthorized", parameters: [
                     "endpoint": store.lastTodosEndpoint,
                     "status": "\(ts)"
                 ])
             } else {
                 TelemetryDeck.signal("CanvasConnectionFailed", parameters: [
                     "endpoint": store.lastTodosEndpoint,
                     "status": "\(ts)"
                 ])
             }
         }

         if let cs = coursesStatus, !(200..<300).contains(cs) {
             if cs == 401 {
                 TelemetryDeck.signal("CanvasConnectionUnauthorized", parameters: [
                     "endpoint": store.lastCoursesEndpoint,
                     "status": "\(cs)"
                 ])
             } else if (500..<600).contains(cs) {
                 TelemetryDeck.signal("CanvasCoursesServerError", parameters: [
                     "endpoint": store.lastCoursesEndpoint,
                     "status": "\(cs)"
                 ])
             } else {
                 TelemetryDeck.signal("CanvasConnectionFailed", parameters: [
                     "endpoint": store.lastCoursesEndpoint,
                     "status": "\(cs)"
                 ])
             }
         }
     }

     // MARK: - About helpers
     private func openMail(to address: String, subject: String, body: String) {
         let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
         let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
         let urlString = "mailto:\(address)?subject=\(subjectEncoded)&body=\(bodyEncoded)"
         guard let url = URL(string: urlString) else { return }
         #if canImport(AppKit)
         NSWorkspace.shared.open(url)
         #elseif canImport(UIKit)
         UIApplication.shared.open(url)
         #endif
     }

     private func defaultFeedbackBody() -> String {
         #if canImport(AppKit)
         let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
         #else
         let osVersion = UIDevice.current.systemVersion
         #endif
         return """

         Please write your feedback above this line.

         —
         App: \(appName)
         Version: \(appVersion)
         OS: \(osVersion)
         """
     }
 }

 struct LevelEditorRow: View {
     let level: Level
     @Binding var assignment: ClassAssignment

     var body: some View {
         VStack(alignment: .leading, spacing: 8) {
             Text(level.displayName)
                 .font(.headline)

             TextField("Class title", text: $assignment.title)
                 .textFieldStyle(.roundedBorder)

             HStack {
                 TextField("Teacher", text: $assignment.teacher)
                     .textFieldStyle(.roundedBorder)

                 TextField("Room", text: $assignment.room)
                     .textFieldStyle(.roundedBorder)
                     .frame(maxWidth: 180)
             }

             ColorPicker("Color", selection: Binding(
                 get: { assignment.color.swiftUIColor },
                 set: { assignment.color = CodableColor($0) }
             ))
         }
     }
 }

 struct SpecialColorRow: View {
     let title: String
     let systemImage: String
     @Binding var color: Color

     var body: some View {
         HStack(spacing: 12) {
             Label(title, systemImage: systemImage)
                 .font(.headline)
             Spacer()
             ColorPicker("", selection: $color)
                 .labelsHidden()
                 .frame(maxWidth: 220)
         }
         .padding(.vertical, 4)
     }
 }

 struct ColorSwatch: View {
     let color: Color
     var body: some View {
         RoundedRectangle(cornerRadius: 6)
             .fill(CompatibleGradient(color))
             .frame(width: 24, height: 16)
             .overlay(
                 RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 0.5)
             )
     }
 }

 // MARK: - Update Announcement View (inline section variant)

 private struct UpdateAnnouncementSection: View {
     let announcement: UpdateAnnouncement

     var body: some View {
         VStack(alignment: .leading, spacing: 10) {
             HStack(spacing: 10) {
                 Image(systemName: "sparkles")
                     .font(.title3)
                     .foregroundColor(.orange)
                 Text("RooMate \(announcement.updateNumber) Is Available!")
                     .font(.title3.bold())
                 Spacer()
             }

             if !announcement.changelog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                 Text(announcement.changelog)
                     .font(.body)
                     .lineLimit(6)
                     .frame(maxWidth: .infinity, alignment: .leading)
             } else {
                 Text("No details provided.")
                     .font(.body)
                     .modifier(SecondaryForeground())
             }

             HStack(spacing: 10) {
                 if let url = announcement.url {
                     Button {
                         #if canImport(AppKit)
                         NSWorkspace.shared.open(url)
                         #elseif canImport(UIKit)
                         UIApplication.shared.open(url)
                         #endif
                         // Intentionally keep visible after download per your request.
                     } label: {
                         Label("Download", systemImage: "square.and.arrow.down")
                     }
                     .buttonStyle(.borderedProminent)
                     .tint(.blue)
                 } else {
                     Text("No download link provided.")
                         .font(.footnote)
                         .modifier(SecondaryForeground())
                 }
                 Spacer()
             }
         }
         .padding(14)
         .background(
             ZStack {
                 // Subtle attention-grabbing background
                 RoundedRectangle(cornerRadius: 14, style: .continuous)
                     .fill(LinearGradient(
                         colors: [Color.orange.opacity(0.14), Color.orange.opacity(0.06)],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing
                     ))
                 RoundedRectangle(cornerRadius: 14, style: .continuous)
                     .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.2)
             }
         )
         .overlay(
             RoundedRectangle(cornerRadius: 14, style: .continuous)
                 .strokeBorder(.quaternary, lineWidth: 0.8)
         )
         .accessibilityElement(children: .combine)
         .accessibilityLabel("RooMate \(announcement.updateNumber) is available. \(announcement.changelog)")
     }
 }

 // MARK: - Background

 struct BackgroundView: View {
     var body: some View {
         #if canImport(UIKit)
         Color(UIColor.systemBackground)
         #elseif canImport(AppKit)
         Color(nsColor: NSColor.windowBackgroundColor)
         #else
         Color.white
         #endif
     }
 }

 // MARK: - Token Help View

 struct TokenHelpView: View {
     let domain: String
     @Binding var isPresented: Bool

     private var domainURL: URL? {
         URL(string: "https://\(domain)")
     }

     var body: some View {
         VStack(alignment: .leading, spacing: 12) {
             HStack {
                 Label("Get your Canvas API Token", systemImage: "questionmark.circle.fill")
                     .font(.headline)
                 Spacer()
                 Button {
                     isPresented = false
                 } label: {
                     Image(systemName: "xmark.circle.fill")
                         .modifier(SecondaryForeground())
                 }
                 .buttonStyle(.plain)
                 .accessibilityLabel("Close")
             }

             Text("Steps")
                 .font(.subheadline.weight(.semibold))
                 .modifier(SecondaryForeground())

             VStack(alignment: .leading, spacing: 8) {
                 Text("1. Open Canvas in a web browser and sign in.")
                 Text("2. Go to Account > Settings.")
                 Text("3. Scroll to the Approved Integrations or New Access Token section.")
                 Text("4. Create a new token, give it a purpose, make the expiry date the maximum (120 days) and copy the token value.")
                 Text("5. Paste the token here. Keep it secret.")
                 Text("! Make sure to write down your token, you won't be able to get it again.")
             }
             .font(.callout)

             if let url = domainURL {
                 Button {
                     #if canImport(AppKit)
                     NSWorkspace.shared.open(url)
                     #elseif canImport(UIKit)
                     UIApplication.shared.open(url)
                     #endif
                 } label: {
                     Label("Open \(domain)", systemImage: "safari")
                 }
                 .buttonStyle(.borderedProminent)
                 .tint(.blue)
                 .padding(.top, 4)
             }

             Text("Note: You can revoke this token anytime from Canvas settings.")
                 .font(.footnote)
                 .modifier(SecondaryForeground())
                 .padding(.top, 6)
         }
         .padding()
     }
 }

 // MARK: - Compatibility Helpers

 private struct SafeAreaTopPadding: ViewModifier {
     let value: CGFloat
     init(_ value: CGFloat) { self.value = value }
     func body(content: Content) -> some View {
         if #available(macOS 14.0, iOS 16.0, *) {
             content.safeAreaPadding(.top, value)
         } else {
             content.padding(.top, value)
         }
     }
 }

 private struct HideListSeparatorIfAvailable: ViewModifier {
     func body(content: Content) -> some View {
         if #available(macOS 13.0, iOS 15.0, *) {
             content.listRowSeparator(.hidden)
         } else {
             content
         }
     }
 }

 private struct SecondaryForeground: ViewModifier {
     func body(content: Content) -> some View {
         if #available(macOS 14.0, iOS 15.0, *) {
             content.foregroundStyle(.secondary)
         } else {
             content.foregroundColor(.secondary)
         }
     }
 }

 // Make this available across platforms without outer @available to avoid limiting usage sites.
 private struct CompatibleGradient: ShapeStyle {
     let color: Color
     init(_ color: Color) { self.color = color }

     func _apply(to shape: inout _ShapeStyle_Shape) {
         // Color.gradient is available on iOS 15+, macOS 12+
         if #available(iOS 15.0, macOS 12.0, *) {
             color.gradient._apply(to: &shape)
         } else {
             LinearGradient(
                 gradient: Gradient(colors: [color.opacity(0.9), color]),
                 startPoint: .top,
                 endPoint: .bottom
             )._apply(to: &shape)
         }
     }
 }

 private struct CompatibleBackgroundSecondary: ShapeStyle {
     func _apply(to shape: inout _ShapeStyle_Shape) {
         if #available(macOS 14.0, iOS 17.0, *) {
             Color.secondary.opacity(0.15)._apply(to: &shape)
         } else {
             #if canImport(AppKit)
             Color(nsColor: NSColor.windowBackgroundColor).opacity(0.6)._apply(to: &shape)
             #else
             Color(white: 0.95)._apply(to: &shape)
             #endif
         }
     }
 }

 // macOS-only helper to apply .textContentType(.URL) when available
 private struct MacURLContentTypeIfAvailable: ViewModifier {
     func body(content: Content) -> some View {
         #if canImport(AppKit)
         if #available(macOS 14.0, *) {
             content.textContentType(.URL)
         } else {
             content
         }
         #else
         content
         #endif
     }
 }

 private struct CompatibleUnavailableView: View {
     let title: String
     let systemImage: String
     let description: String

     var body: some View {
         if #available(macOS 14.0, iOS 17.0, *) {
             ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
         } else {
             HStack(spacing: 12) {
                 Image(systemName: systemImage)
                     .font(.title2)
                 VStack(alignment: .leading, spacing: 4) {
                     Text(title)
                         .font(.headline)
                     Text(description)
                         .font(.subheadline)
                         .modifier(SecondaryForeground())
                 }
                 Spacer()
             }
             .padding(.vertical, 8)
         }
     }
 }

 #Preview {
     ContentView()
 }
*/
