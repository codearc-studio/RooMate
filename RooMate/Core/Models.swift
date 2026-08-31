import Foundation
import SwiftUI

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

/// Kept for decoding preferences written by RooMate 5/6. New versions migrate
/// this three-way setting into `RooMateTheme` on first launch.
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

enum RooMateTheme: String, CaseIterable, Identifiable, Codable, Equatable {
  case system
  case rooLight
  case sunrise
  case courtyard
  case rooDark
  case midnight
  case oled

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .rooLight: "Roo Light"
    case .sunrise: "Sunrise"
    case .courtyard: "Courtyard"
    case .rooDark: "Roo Dark"
    case .midnight: "Midnight"
    case .oled: "OLED Black"
    }
  }

  var subtitle: String {
    switch self {
    case .system: "Matches your Mac"
    case .rooLight: "Warm and familiar"
    case .sunrise: "Soft peach and cream"
    case .courtyard: "Calm paper and sage"
    case .rooDark: "The classic dark look"
    case .midnight: "Deep blue study hours"
    case .oled: "True black, minimal glow"
    }
  }

  var systemImage: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .rooLight: "sun.max.fill"
    case .sunrise: "sunrise.fill"
    case .courtyard: "leaf.fill"
    case .rooDark: "moon.fill"
    case .midnight: "moon.stars.fill"
    case .oled: "circle.inset.filled"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .rooLight, .sunrise, .courtyard: .light
    case .rooDark, .midnight, .oled: .dark
    }
  }

  var isDark: Bool {
    switch self {
    case .rooDark, .midnight, .oled: true
    case .system, .rooLight, .sunrise, .courtyard: false
    }
  }

  var appearanceLabel: String {
    switch self {
    case .system: "Automatic"
    case .rooLight, .sunrise, .courtyard: "Light"
    case .rooDark, .midnight, .oled: "Dark"
    }
  }

  var longDescription: String {
    switch self {
    case .system: "Moves between Roo Light and Roo Dark with your Mac's appearance."
    case .rooLight: "A warm, neutral canvas designed for a clear school day."
    case .sunrise: "Soft cream and peach tones with a little early-morning energy."
    case .courtyard: "Quiet paper whites and sage accents for an easy, focused feel."
    case .rooDark: "RooMate's familiar charcoal look with warm, colorful accents."
    case .midnight: "Deep navy surfaces made for late study sessions."
    case .oled: "True black surfaces with restrained glow and crisp text contrast."
    }
  }
}

// MARK: - Models

enum Level: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
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
    case .music: "Music Block"
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
    case .music: .cyan
    }
  }
}

enum SpecialBlock: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
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

enum BlockKind: Codable, Hashable, Sendable {
  case level(Level)
  case special(SpecialBlock)
  /// A school-wide/custom block supplied by the official remote special-schedule feed.
  /// The associated value is the literal title RooMate should display.
  case custom(String)

  enum CodingKeys: String, CodingKey { case type, value }
  enum KindType: String, Codable { case level, special, custom }

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
    case .custom:
      let value = try container.decode(String.self, forKey: .value)
      self = .custom(value)
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
    case .custom(let title):
      try container.encode(KindType.custom, forKey: .type)
      try container.encode(title, forKey: .value)
    }
  }
}

enum BellBlockTimelineType: String, Codable, Hashable, Sendable {
  case block
  case extra
  case marker

  var isPrimary: Bool { self == .block }
}

struct BellBlock: Identifiable, Hashable, Sendable {
  let id: UUID
  let kind: BlockKind
  let start: DateComponents
  let end: DateComponents
  /// Official remote schedules can override the normal block title without changing
  /// how personalized Level mapping works.
  let titleOverride: String?
  /// Optional schedule-specific note shown as secondary text.
  let detail: String?
  /// Main timeline block, overlapping extra, or one-time marker.
  let timelineType: BellBlockTimelineType

  init(
    id: UUID = UUID(),
    kind: BlockKind,
    start: DateComponents,
    end: DateComponents,
    titleOverride: String? = nil,
    detail: String? = nil,
    timelineType: BellBlockTimelineType = .block
  ) {
    self.id = id
    self.kind = kind
    self.start = start
    self.end = end
    self.titleOverride = titleOverride
    self.detail = detail
    self.timelineType = timelineType
  }

  var isPrimaryTimelineBlock: Bool { timelineType.isPrimary }
  var isMarker: Bool { timelineType == .marker }
  var isExtra: Bool { timelineType == .extra }
}

/// Resolves the status of a same-day bell schedule without treating point-in-time
/// markers as active blocks. Future markers remain eligible for `nextItemID`, which
/// prevents marker-based special schedules from appearing complete too early.
struct BellScheduleStatus: Equatable, Sendable {
  let currentItemID: UUID?
  let nextItemID: UUID?

  static func resolve(blocks: [BellBlock], at time: DateComponents) -> BellScheduleStatus {
    let referenceMinutes = minutes(time)
    let ordered = blocks.sorted { lhs, rhs in
      let lhsStart = minutes(lhs.start)
      let rhsStart = minutes(rhs.start)
      if lhsStart != rhsStart { return lhsStart < rhsStart }
      if lhs.isPrimaryTimelineBlock != rhs.isPrimaryTimelineBlock {
        return lhs.isPrimaryTimelineBlock
      }
      return lhs.id.uuidString < rhs.id.uuidString
    }

    let active = ordered.filter { block in
      !block.isMarker
        && referenceMinutes >= minutes(block.start)
        && referenceMinutes < minutes(block.end)
    }
    let current = active.first(where: \.isPrimaryTimelineBlock) ?? active.first
    let next = ordered.first { minutes($0.start) > referenceMinutes }

    return BellScheduleStatus(currentItemID: current?.id, nextItemID: next?.id)
  }

  private static func minutes(_ components: DateComponents) -> Int {
    (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }
}

enum ClubIconOption: String, CaseIterable, Identifiable, Codable, Hashable {
  case group = "person.3.fill"
  case service = "heart.fill"
  case discussion = "bubble.left.and.text.bubble.right.fill"
  case academic = "book.closed.fill"
  case writing = "pencil.and.outline"
  case stem = "atom"
  case technology = "laptopcomputer"
  case engineering = "gearshape.2.fill"
  case art = "paintpalette.fill"
  case music = "music.note"
  case theater = "theatermasks.fill"
  case photography = "camera.fill"
  case environment = "leaf.fill"
  case culture = "globe.americas.fill"
  case games = "gamecontroller.fill"
  case athletics = "figure.run"
  case leadership = "star.fill"
  case media = "newspaper.fill"

  var id: String { rawValue }
  var systemImage: String { rawValue }

  var title: String {
    switch self {
    case .group: "General"
    case .service: "Service"
    case .discussion: "Discussion"
    case .academic: "Academic"
    case .writing: "Writing"
    case .stem: "STEM"
    case .technology: "Technology"
    case .engineering: "Engineering"
    case .art: "Art"
    case .music: "Music"
    case .theater: "Theater"
    case .photography: "Photography"
    case .environment: "Environment"
    case .culture: "Culture"
    case .games: "Games"
    case .athletics: "Athletics"
    case .leadership: "Leadership"
    case .media: "Media"
    }
  }
}

struct Club: Identifiable, Hashable, Codable {
  struct OtherMeeting: Identifiable, Hashable, Codable {
    let id: UUID
    var weekday: Int
    var startTime: Date
    var endTime: Date

    init(
      id: UUID = UUID(),
      weekday: Int = 2,
      startTime: Date = Date(),
      endTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    ) {
      self.id = id
      self.weekday = weekday
      self.startTime = startTime
      self.endTime = endTime
    }
  }

  /// A club can take over any exact bell-schedule block on a particular
  /// weekday. This is separate from the two built-in club-period toggles so
  /// existing RooMate data keeps working while still allowing arbitrary
  /// Level/special-block assignment.
  struct BlockMeeting: Identifiable, Hashable, Codable {
    let id: UUID
    var weekday: Int
    var block: BlockKind

    init(
      id: UUID = UUID(),
      weekday: Int = Weekday.monday.calendarWeekdayIndex,
      block: BlockKind = .level(.level1)
    ) {
      self.id = id
      self.weekday = weekday
      self.block = block
    }
  }

  let id: UUID
  var name: String
  var room: String
  var color: CodableColor
  var iconName: String
  var meetsMondayClub: Bool
  var meetsWednesdayClub: Bool
  var blockMeetings: [BlockMeeting]
  var otherDaysNote: String
  var otherMeetings: [OtherMeeting]

  init(
    id: UUID = UUID(),
    name: String = "",
    room: String = "",
    color: CodableColor = CodableColor(.purple),
    iconName: String = ClubIconOption.group.systemImage,
    meetsMondayClub: Bool = false,
    meetsWednesdayClub: Bool = false,
    blockMeetings: [BlockMeeting] = [],
    otherDaysNote: String = "",
    otherMeetings: [OtherMeeting] = []
  ) {
    self.id = id
    self.name = name
    self.room = room
    self.color = color
    self.iconName = iconName
    self.meetsMondayClub = meetsMondayClub
    self.meetsWednesdayClub = meetsWednesdayClub
    self.blockMeetings = blockMeetings
    self.otherDaysNote = otherDaysNote
    self.otherMeetings = otherMeetings
  }

  var displayColor: Color { color.swiftUIColor }

  var displayIconName: String {
    ClubIconOption(rawValue: iconName)?.systemImage ?? ClubIconOption.group.systemImage
  }

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case room
    case color
    case iconName
    case meetsMondayClub
    case meetsWednesdayClub
    case blockMeetings
    case otherDaysNote
    case otherMeetings
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    self.room = try container.decodeIfPresent(String.self, forKey: .room) ?? ""
    self.color =
      try container.decodeIfPresent(CodableColor.self, forKey: .color) ?? CodableColor(.purple)
    self.iconName =
      try container.decodeIfPresent(String.self, forKey: .iconName)
      ?? ClubIconOption.group.systemImage
    self.meetsMondayClub =
      try container.decodeIfPresent(Bool.self, forKey: .meetsMondayClub) ?? false
    self.meetsWednesdayClub =
      try container.decodeIfPresent(Bool.self, forKey: .meetsWednesdayClub) ?? false
    self.blockMeetings =
      try container.decodeIfPresent([BlockMeeting].self, forKey: .blockMeetings) ?? []
    self.otherDaysNote = try container.decodeIfPresent(String.self, forKey: .otherDaysNote) ?? ""
    self.otherMeetings =
      try container.decodeIfPresent([OtherMeeting].self, forKey: .otherMeetings) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(room, forKey: .room)
    try container.encode(color, forKey: .color)
    try container.encode(iconName, forKey: .iconName)
    try container.encode(meetsMondayClub, forKey: .meetsMondayClub)
    try container.encode(meetsWednesdayClub, forKey: .meetsWednesdayClub)
    try container.encode(blockMeetings, forKey: .blockMeetings)
    try container.encode(otherDaysNote, forKey: .otherDaysNote)
    try container.encode(otherMeetings, forKey: .otherMeetings)
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
      let ns =
        NSColor(color)
        .usingColorSpace(.sRGB) ?? NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
      self.r = Double(ns.redComponent)
      self.g = Double(ns.greenComponent)
      self.b = Double(ns.blueComponent)
      self.a = Double(ns.alphaComponent)
    #elseif canImport(UIKit)
      let ui = UIColor(color)
      var rr: CGFloat = 1
      var gg: CGFloat = 1
      var bb: CGFloat = 1
      var aa: CGFloat = 1
      if ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) {
        self.r = Double(rr)
        self.g = Double(gg)
        self.b = Double(bb)
        self.a = Double(aa)
      } else {
        self.r = 1
        self.g = 1
        self.b = 1
        self.a = 1
      }
    #else
      self.r = 1
      self.g = 1
      self.b = 1
      self.a = 1
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

enum ClassIconOption: String, CaseIterable, Identifiable, Codable, Hashable {
  case general = "book.closed.fill"
  case reading = "text.book.closed.fill"
  case writing = "pencil.and.outline"
  case math = "function"
  case science = "flask.fill"
  case history = "building.columns.fill"
  case world = "globe.americas.fill"
  case language = "character.book.closed.fill"
  case art = "paintpalette.fill"
  case music = "music.note"
  case theater = "theatermasks.fill"
  case technology = "laptopcomputer"
  case engineering = "gearshape.2.fill"
  case health = "heart.fill"
  case physicalEducation = "figure.run"
  case discussion = "bubble.left.and.text.bubble.right.fill"
  case photography = "camera.fill"
  case environment = "leaf.fill"
  case data = "chart.bar.fill"
  case graduation = "graduationcap.fill"

  var id: String { rawValue }
  var systemImage: String { rawValue }

  var title: String {
    switch self {
    case .general: "General"
    case .reading: "Reading"
    case .writing: "Writing"
    case .math: "Math"
    case .science: "Science"
    case .history: "History"
    case .world: "World"
    case .language: "Language"
    case .art: "Art"
    case .music: "Music"
    case .theater: "Theater"
    case .technology: "Technology"
    case .engineering: "Engineering"
    case .health: "Health"
    case .physicalEducation: "PE"
    case .discussion: "Discussion"
    case .photography: "Photo"
    case .environment: "Environment"
    case .data: "Data"
    case .graduation: "College"
    }
  }

  static func defaultOption(for level: Level) -> ClassIconOption {
    switch level {
    case .music:
      return .music
    default:
      return .general
    }
  }
}

struct ClassAssignment: Codable, Hashable {
  var title: String
  var teacher: String
  var room: String
  var color: CodableColor
  var iconName: String
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

    init(
      title: String, teacher: String, room: String, isFree: Bool = false, daysNotFree: Set<Int> = []
    ) {
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
      iconName: ClassIconOption.defaultOption(for: level).systemImage,
      isFree: level == .music,
      musicDaysNotFree: [],
      meetsEveryDay: true,
      daysNotMeeting: [],
      replacementClass: nil
    )
  }

  enum CodingKeys: String, CodingKey {
    case title, teacher, room, color, iconName, isFree, musicDaysNotFree, meetsEveryDay,
      daysNotMeeting, replacementClass
  }

  init(
    title: String, teacher: String, room: String, color: CodableColor,
    iconName: String = ClassIconOption.general.systemImage, isFree: Bool = false,
    musicDaysNotFree: Set<Int> = [], meetsEveryDay: Bool = true, daysNotMeeting: Set<Int> = [],
    replacementClass: ReplacementClass? = nil
  ) {
    self.title = title
    self.teacher = teacher
    self.room = room
    self.color = color
    self.iconName = iconName
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
    self.color =
      try container.decodeIfPresent(CodableColor.self, forKey: .color)
      ?? CodableColor(Color.accentColor)
    self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? ""
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

    self.replacementClass = try container.decodeIfPresent(
      ReplacementClass.self, forKey: .replacementClass)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encode(teacher, forKey: .teacher)
    try container.encode(room, forKey: .room)
    try container.encode(color, forKey: .color)
    try container.encode(iconName, forKey: .iconName)
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
    guard let weekday, !meetsEveryDay, let replacementClass,
      daysNotMeeting.contains(weekday.calendarWeekdayIndex)
    else {
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
    return [teacher, room].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " • ")
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

  func displaySystemImage(for level: Level, on weekday: Weekday? = nil) -> String {
    if let replacement = replacementClass(for: weekday) {
      return replacement.isFree ? "cup.and.saucer.fill" : "arrow.triangle.swap"
    }

    if isActuallyFree(on: weekday) {
      return "cup.and.saucer.fill"
    }

    let trimmed = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? ClassIconOption.defaultOption(for: level).systemImage : trimmed
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
    return [teacher, room].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " • ")
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

// MARK: - Special Schedule Overrides

struct SpecialScheduleOverride: Identifiable, Codable, Hashable {
  enum Template: String, CaseIterable, Identifiable, Codable, Hashable {
    case noSchool, monday, tuesday, wednesday, thursday, friday
    var id: String { rawValue }
    var title: String {
      switch self {
      case .noSchool: "No School"
      case .monday: "Monday schedule"
      case .tuesday: "Tuesday schedule"
      case .wednesday: "Wednesday schedule"
      case .thursday: "Thursday schedule"
      case .friday: "Friday schedule"
      }
    }
    var shortTitle: String {
      switch self {
      case .noSchool: "No School"
      case .monday: "Monday"
      case .tuesday: "Tuesday"
      case .wednesday: "Wednesday"
      case .thursday: "Thursday"
      case .friday: "Friday"
      }
    }
    var weekday: Weekday? {
      switch self {
      case .noSchool: nil
      case .monday: .monday
      case .tuesday: .tuesday
      case .wednesday: .wednesday
      case .thursday: .thursday
      case .friday: .friday
      }
    }
    var systemImage: String {
      self == .noSchool ? "calendar.badge.minus" : "arrow.triangle.2.circlepath"
    }
  }

  let id: UUID
  var date: Date
  var title: String
  var template: Template

  init(id: UUID = UUID(), date: Date, title: String = "", template: Template) {
    self.id = id
    self.date = date
    self.title = title
    self.template = template
  }

  var displayTitle: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? template.title : trimmed
  }
}

// MARK: - Calendar Event

struct CalendarEvent: Identifiable, Codable, Hashable {
  let id: UUID
  let title: String
  let startDate: Date
  let endDate: Date?
  let location: String?

  init(
    id: UUID = UUID(), title: String, startDate: Date, endDate: Date? = nil, location: String? = nil
  ) {
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

  /// The individual school calendar ID used by the public ICS endpoint.
  /// `allEvents` is a convenience selection that requests all four calendars.
  var calendarID: Int? {
    switch self {
    case .allEvents: nil
    case .allSchool: 7
    case .upperSchool: 6
    case .middleSchool: 5
    case .lowerSchool: 4
    }
  }

  static var individualCases: [CalendarSource] {
    [.allSchool, .upperSchool, .middleSchool, .lowerSchool]
  }

  var url: URL? {
    Self.feedURL(for: [self])
  }

  /// Builds one ICS request for any selected combination. Selecting All Events
  /// intentionally overrides the individual choices and requests everything.
  static func feedURL(for sources: Set<CalendarSource>) -> URL? {
    let normalized = sources.isEmpty ? Set([CalendarSource.allEvents]) : sources

    let requested: [CalendarSource]
    if normalized.contains(.allEvents) {
      requested = individualCases
    } else {
      requested = individualCases.filter { normalized.contains($0) }
    }

    var components = URLComponents(
      string: "https://www.abingtonfriends.net/fs/calendar-manager/events.ics"
    )
    components?.queryItems = requested.compactMap { source in
      guard let id = source.calendarID else { return nil }
      return URLQueryItem(name: "calendar_ids[]", value: String(id))
    }
    return components?.url
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
