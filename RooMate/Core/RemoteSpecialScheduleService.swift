import Foundation

// MARK: - Official remote special schedules

struct RemoteSpecialScheduleItem: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let order: Int
  let start: DateComponents
  let end: DateComponents?
  let kind: BlockKind
  let titleOverride: String?
  let detail: String?
  let timelineType: BellBlockTimelineType

  init(
    id: UUID = UUID(),
    order: Int,
    start: DateComponents,
    end: DateComponents?,
    kind: BlockKind,
    titleOverride: String? = nil,
    detail: String? = nil,
    timelineType: BellBlockTimelineType = .block
  ) {
    self.id = id
    self.order = order
    self.start = start
    self.end = end
    self.kind = kind
    self.titleOverride = titleOverride
    self.detail = detail
    self.timelineType = timelineType
  }

  func bellBlock() -> BellBlock {
    BellBlock(
      id: id,
      kind: kind,
      start: start,
      // Markers are points in time. Using the same start/end keeps existing
      // schedule math safe while `timelineType` tells the UI to render one time.
      end: end ?? start,
      titleOverride: titleOverride,
      detail: detail,
      timelineType: timelineType
    )
  }
}

struct RemoteSpecialScheduleDay: Identifiable, Codable, Hashable, Sendable {
  var id: String { dateKey }

  let dateKey: String
  let title: String
  let note: String
  let isSchoolClosed: Bool
  let tabName: String?
  let items: [RemoteSpecialScheduleItem]

  var displayTitle: String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? (isSchoolClosed ? "School Closed" : "Special Schedule") : trimmed
  }
}

struct RemoteSpecialScheduleFeed: Codable, Hashable, Sendable {
  let refreshedAt: Date
  let days: [RemoteSpecialScheduleDay]

  static let empty = RemoteSpecialScheduleFeed(refreshedAt: .distantPast, days: [])
}

enum RemoteSpecialScheduleServiceError: LocalizedError {
  case invalidURL
  case badHTTPStatus(Int)
  case unreadableIndex
  case missingIndexColumn(String)
  case invalidDayTab(String)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      "The special-schedule feed URL is invalid."
    case .badHTTPStatus(let status):
      "The special-schedule feed returned HTTP \(status)."
    case .unreadableIndex:
      "RooMate couldn't read the Special Schedules INDEX tab."
    case .missingIndexColumn(let name):
      "The Special Schedules INDEX is missing the \(name) column."
    case .invalidDayTab(let tab):
      "RooMate couldn't read the special-schedule tab \(tab)."
    }
  }
}

enum RemoteSpecialScheduleService {
  static let spreadsheetID = "1awDZ4D7C-OOsnqGLZgHn48Fl8jgGyGBNDtL5EcSwndw"
  static let indexTabName = "INDEX"
  private static let readerVersion = "index-fixed-columns-v3"

  private static let cacheKey = "OfficialSpecialScheduleFeedCacheV1"
  private static var defaults: UserDefaults {
    UserDefaults(suiteName: "dev.roomate.prefs") ?? .standard
  }

  private actor RefreshCoordinator {
    var inFlight: Task<RemoteSpecialScheduleFeed, Error>?

    func run(previous: RemoteSpecialScheduleFeed) async throws -> RemoteSpecialScheduleFeed {
      if let inFlight {
        return try await inFlight.value
      }

      let task = Task {
        try await RemoteSpecialScheduleService.performRefresh(previous: previous)
      }
      inFlight = task
      defer { inFlight = nil }
      return try await task.value
    }
  }

  private static let refreshCoordinator = RefreshCoordinator()

  nonisolated private static func debugLog(_ message: String) {
    #if DEBUG
      print("[SpecialSchedules] \(message)")
    #endif
  }

  private static var schoolCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    return calendar
  }

  static func cachedFeed() -> RemoteSpecialScheduleFeed {
    guard let data = defaults.data(forKey: cacheKey),
      let feed = try? JSONDecoder().decode(RemoteSpecialScheduleFeed.self, from: data)
    else {
      return .empty
    }
    return feed
  }

  static func saveCache(_ feed: RemoteSpecialScheduleFeed) {
    guard let data = try? JSONEncoder().encode(feed) else { return }
    defaults.set(data, forKey: cacheKey)
  }

  static func clearCache() {
    defaults.removeObject(forKey: cacheKey)
  }

  static func refresh(previous: RemoteSpecialScheduleFeed? = nil) async throws
    -> RemoteSpecialScheduleFeed
  {
    let prior = previous ?? cachedFeed()
    return try await refreshCoordinator.run(previous: prior)
  }

  private static func performRefresh(previous prior: RemoteSpecialScheduleFeed) async throws
    -> RemoteSpecialScheduleFeed
  {
    debugLog("Refreshing official schedule INDEX… [\(readerVersion)]")
    let indexData = try await fetchCSV(tab: indexTabName)
    let indexRows = parseCSV(indexData)
    let indexEntries = try parseIndex(indexRows)
    let publishedCount = indexEntries.filter(\.isPublished).count
    debugLog("INDEX parsed: \(indexEntries.count) rows, \(publishedCount) published.")

    var days: [RemoteSpecialScheduleDay] = []
    let priorByDate = Dictionary(uniqueKeysWithValues: prior.days.map { ($0.dateKey, $0) })

    for entry in indexEntries where entry.isPublished {
      if entry.isSchoolClosed {
        debugLog("\(entry.dateKey): published school-closed day.")
        days.append(
          RemoteSpecialScheduleDay(
            dateKey: entry.dateKey,
            title: entry.title,
            note: entry.note,
            isSchoolClosed: true,
            tabName: nil,
            items: []
          )
        )
        continue
      }

      guard let tab = entry.tabName, !tab.isEmpty else {
        // A published, open-school day must have a tab. Preserve a last-known-good
        // copy if one exists; otherwise skip the malformed entry instead of breaking
        // every user's normal schedule.
        if let cached = priorByDate[entry.dateKey], !cached.isSchoolClosed {
          days.append(cached)
        }
        continue
      }

      do {
        debugLog("\(entry.dateKey): loading tab ‘\(tab)’…")
        let data = try await fetchCSV(tab: tab)
        let rows = parseCSV(data)
        let parsed = try parseDayTab(
          rows,
          fallbackDateKey: entry.dateKey,
          fallbackTitle: entry.title,
          fallbackNote: entry.note,
          tabName: tab
        )
        days.append(parsed)
        debugLog("\(entry.dateKey): loaded \(parsed.items.count) timeline items from ‘\(tab)’.")
      } catch {
        debugLog("\(entry.dateKey): failed to load ‘\(tab)’ — \(error.localizedDescription)")
        // A single broken tab should never wipe out the rest of the official feed.
        if let cached = priorByDate[entry.dateKey], !cached.isSchoolClosed {
          debugLog("\(entry.dateKey): keeping cached last-known-good schedule.")
          days.append(cached)
        }
      }
    }

    let feed = RemoteSpecialScheduleFeed(
      refreshedAt: Date(),
      days: days.sorted { $0.dateKey < $1.dateKey }
    )
    saveCache(feed)
    debugLog("Refresh complete: \(feed.days.count) official days cached.")
    return feed
  }

  static func dateKey(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = schoolCalendar
    formatter.timeZone = schoolCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  // MARK: Networking

  private static func csvURL(tab: String) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "docs.google.com"
    components.path = "/spreadsheets/d/\(spreadsheetID)/gviz/tq"

    let isIndex = tab.caseInsensitiveCompare(indexTabName) == .orderedSame
    let queryItems = [
      URLQueryItem(name: "tqx", value: "out:csv"),
      URLQueryItem(name: "sheet", value: tab),
      // Explicitly select the columns RooMate owns. Google Visualization can
      // otherwise infer a mixed-type sheet in surprising ways and omit a
      // Boolean column such as INDEX column E (School Closed).
      URLQueryItem(
        name: "tq",
        value: isIndex
          ? "select A,B,C,D,E,F"
          : "select A,B,C,D,E,F,G"
      ),
      // INDEX has one real header row. Day tabs intentionally mix metadata
      // rows with the schedule table, so they are parsed as raw rows.
      URLQueryItem(name: "headers", value: isIndex ? "1" : "0"),
    ]

    components.queryItems = queryItems
    return components.url
  }

  private static func fetchCSV(tab: String) async throws -> Data {
    guard let url = csvURL(tab: tab) else {
      throw RemoteSpecialScheduleServiceError.invalidURL
    }

    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20
    request.setValue("text/csv,text/plain;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)
    if let http = response as? HTTPURLResponse {
      debugLog("Fetched tab ‘\(tab)’: HTTP \(http.statusCode), \(data.count) bytes.")
      if !(200...299).contains(http.statusCode) {
        throw RemoteSpecialScheduleServiceError.badHTTPStatus(http.statusCode)
      }
    } else {
      debugLog("Fetched tab ‘\(tab)’: non-HTTP response, \(data.count) bytes.")
    }
    return data
  }

  // MARK: INDEX

  private struct IndexEntry {
    let dateKey: String
    let title: String
    let note: String
    let isPublished: Bool
    let isSchoolClosed: Bool
    let tabName: String?
  }

  private static func parseIndex(_ rows: [[String]]) throws -> [IndexEntry] {
    // INDEX is deliberately a fixed six-column contract:
    // A Date | B Title | C Note | D Status | E School Closed | F Tab
    //
    // Do not depend on the text of Google's exported header row. The GViz CSV
    // exporter can blank/rewrite an individual label while keeping the actual
    // column data. `csvURL` explicitly selects A:F, so positions are stable.
    var result: [IndexEntry] = []

    for row in rows {
      guard let dateKey = canonicalDateKey(value(at: 0, in: row)) else {
        // This naturally skips the CSV header row and any blank/non-data rows.
        continue
      }

      let status = value(at: 3, in: row)
      let isPublished = normalized(status) == "published"
      let closed = parseBool(value(at: 4, in: row))
      let tab = clean(value(at: 5, in: row))

      result.append(
        IndexEntry(
          dateKey: dateKey,
          title: clean(value(at: 1, in: row)),
          note: clean(value(at: 2, in: row)),
          isPublished: isPublished,
          isSchoolClosed: closed,
          tabName: tab.isEmpty ? nil : tab
        )
      )
    }

    guard !result.isEmpty else {
      let preview = rows.prefix(5)
        .map { $0.map(clean).joined(separator: " | ") }
        .joined(separator: " || ")
      debugLog("INDEX contained no parseable dated rows. CSV preview: \(preview)")
      throw RemoteSpecialScheduleServiceError.unreadableIndex
    }

    return result
  }

  // MARK: Day tabs

  private static func parseDayTab(
    _ rows: [[String]],
    fallbackDateKey: String,
    fallbackTitle: String,
    fallbackNote: String,
    tabName: String
  ) throws -> RemoteSpecialScheduleDay {
    // Prefer the human-readable header row when Google returns it. The live
    // Google Visualization CSV endpoint can sometimes strip that row because
    // these sheets intentionally mix metadata text with numeric Order values,
    // so a positional fallback is also supported below.
    let scheduleHeaderIndex = rows.firstIndex(where: { row in
      let normalizedRow = row.map(normalized)
      let hasCodeColumn = normalizedRow.contains("block code") || normalizedRow.contains("level")
      let hasNameColumn = normalizedRow.contains("name override") || normalizedRow.contains("name")
      return normalizedRow.contains("order")
        && normalizedRow.contains("start")
        && normalizedRow.contains("end")
        && hasCodeColumn
        && hasNameColumn
        && normalizedRow.contains("type")
    })

    // If Google stripped the table header, find the first row that looks like
    // actual schedule data. Our sheet contract is fixed to seven columns:
    // Order | Start | End | Block Code/Level | Name Override/Name | Detail | Type.
    let firstDataRowIndex = rows.firstIndex(where: { row in
      guard row.count >= 7 else { return false }
      guard Int(clean(value(at: 0, in: row))) != nil else { return false }
      guard parseTime(value(at: 1, in: row)) != nil else { return false }
      switch normalized(value(at: 6, in: row)) {
      case "block", "extra", "marker": return true
      default: return false
      }
    })

    guard scheduleHeaderIndex != nil || firstDataRowIndex != nil else {
      let preview = rows.prefix(6)
        .map { $0.map(clean).joined(separator: " | ") }
        .joined(separator: " || ")
      debugLog("\(tabName): no readable schedule header/data rows. CSV preview: \(preview)")
      throw RemoteSpecialScheduleServiceError.invalidDayTab(tabName)
    }

    let metadataEndIndex = scheduleHeaderIndex ?? firstDataRowIndex ?? 0
    var metadata: [String: String] = [:]
    for row in rows.prefix(metadataEndIndex) where row.count >= 2 {
      let key = normalized(value(at: 0, in: row))
      guard !key.isEmpty else { continue }
      metadata[key] = clean(value(at: 1, in: row))
    }

    // INDEX is the canonical date. The Date row inside a day tab is human-facing
    // documentation and may be stale after duplicating a template tab.
    let dateKey = fallbackDateKey
    let metadataTitle = clean(metadata["title"] ?? "")
    let metadataNote = clean(metadata["note"] ?? "")
    let title = metadataTitle.isEmpty ? fallbackTitle : metadataTitle
    let note = metadataNote.isEmpty ? fallbackNote : metadataNote

    let orderColumn: Int
    let startColumn: Int
    let endColumn: Int
    let codeColumn: Int
    let nameColumn: Int
    let detailColumn: Int?
    let typeColumn: Int
    let dataStartIndex: Int

    if let scheduleHeaderIndex {
      let header = rows[scheduleHeaderIndex].map(normalized)
      func column(_ names: String...) -> Int? {
        for name in names {
          if let index = header.firstIndex(of: normalized(name)) {
            return index
          }
        }
        return nil
      }

      guard let foundOrder = column("Order"),
        let foundStart = column("Start"),
        let foundEnd = column("End"),
        let foundCode = column("Block Code", "Level"),
        let foundName = column("Name Override", "Name"),
        let foundType = column("Type")
      else {
        throw RemoteSpecialScheduleServiceError.invalidDayTab(tabName)
      }

      orderColumn = foundOrder
      startColumn = foundStart
      endColumn = foundEnd
      codeColumn = foundCode
      nameColumn = foundName
      detailColumn = column("Detail")
      typeColumn = foundType
      dataStartIndex = scheduleHeaderIndex + 1
    } else {
      // Header was removed by Google's type/header inference. Fall back to
      // the fixed day-tab column contract used by the KEY/template sheet.
      orderColumn = 0
      startColumn = 1
      endColumn = 2
      codeColumn = 3
      nameColumn = 4
      detailColumn = 5
      typeColumn = 6
      dataStartIndex = firstDataRowIndex ?? 0
      debugLog("\(tabName): Google omitted the schedule header; using positional 7-column parsing.")
    }

    var items: [RemoteSpecialScheduleItem] = []
    for row in rows.dropFirst(dataStartIndex) {
      let orderRaw = clean(value(at: orderColumn, in: row))
      let startRaw = clean(value(at: startColumn, in: row))
      let typeRaw = normalized(value(at: typeColumn, in: row))
      let codeRaw = clean(value(at: codeColumn, in: row))
      let nameRaw = clean(value(at: nameColumn, in: row))
      let detailRaw = detailColumn.map { clean(value(at: $0, in: row)) } ?? ""

      // Ignore genuinely blank rows.
      if orderRaw.isEmpty && startRaw.isEmpty && codeRaw.isEmpty && nameRaw.isEmpty
        && typeRaw.isEmpty
      {
        continue
      }

      guard let start = parseTime(startRaw) else { continue }
      let timelineType: BellBlockTimelineType
      switch typeRaw {
      case "extra": timelineType = .extra
      case "marker": timelineType = .marker
      default: timelineType = .block
      }

      let endRaw = clean(value(at: endColumn, in: row))
      let parsedEnd = endRaw.isEmpty ? nil : parseTime(endRaw)
      if timelineType != .marker, parsedEnd == nil { continue }

      let kindAndOverride = blockKind(code: codeRaw, nameOverride: nameRaw)
      guard let kind = kindAndOverride?.kind else { continue }

      let order = Int(orderRaw) ?? (items.count + 1)
      items.append(
        RemoteSpecialScheduleItem(
          order: order,
          start: start,
          end: parsedEnd,
          kind: kind,
          titleOverride: kindAndOverride?.titleOverride,
          detail: detailRaw.isEmpty ? nil : detailRaw,
          timelineType: timelineType
        )
      )
    }

    guard !items.isEmpty else {
      debugLog("\(tabName): schedule tab parsed but produced 0 usable timeline items.")
      throw RemoteSpecialScheduleServiceError.invalidDayTab(tabName)
    }

    return RemoteSpecialScheduleDay(
      dateKey: dateKey,
      title: title,
      note: note,
      isSchoolClosed: false,
      tabName: tabName,
      items: items.sorted {
        if $0.order == $1.order {
          return minutes($0.start) < minutes($1.start)
        }
        return $0.order < $1.order
      }
    )
  }

  private static func blockKind(code rawCode: String, nameOverride rawName: String) -> (
    kind: BlockKind, titleOverride: String?
  )? {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let name = clean(rawName)
    let override = name.isEmpty ? nil : name

    if let number = Int(code), (1...7).contains(number) {
      let levels: [Level] = [.level1, .level2, .level3, .level4, .level5, .level6, .level7]
      return (.level(levels[number - 1]), override)
    }

    switch code {
    case "M": return (.level(.music), override)
    case "A": return (.special(.assembly), override)
    case "L": return (.special(.lunch), override)
    case "AD": return (.special(.advisory), override)
    case "OH": return (.special(.officeHours), override)
    case "MFW": return (.special(.worship), override)
    case "CC": return (.special(.consciousCommunities), override)
    case "B": return (.custom(name.isEmpty ? "Break" : name), nil)
    case "CL": return (.custom(name.isEmpty ? "Clubs" : name), nil)
    case "":
      guard !name.isEmpty else { return nil }
      return (.custom(name), nil)
    default:
      // Unknown future codes are still safe if the sheet supplies a literal name.
      guard !name.isEmpty else { return nil }
      return (.custom(name), nil)
    }
  }

  // MARK: Parsing helpers

  private static func parseCSV(_ data: Data) -> [[String]] {
    let string = String(data: data, encoding: .utf8) ?? ""
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var index = string.startIndex

    func flushRow() {
      row.append(field)
      if row.contains(where: { !clean($0).isEmpty }) {
        rows.append(row)
      }
      row = []
      field = ""
    }

    while index < string.endIndex {
      let character = string[index]
      switch character {
      case "\"":
        let next = string.index(after: index)
        if inQuotes, next < string.endIndex, string[next] == "\"" {
          field.append("\"")
          index = next
        } else {
          inQuotes.toggle()
        }
      case "," where !inQuotes:
        row.append(field)
        field = ""
      case "\n" where !inQuotes:
        flushRow()
      case "\r" where !inQuotes:
        let next = string.index(after: index)
        if next < string.endIndex, string[next] == "\n" {
          index = next
        }
        flushRow()
      default:
        field.append(character)
      }
      index = string.index(after: index)
    }

    if !field.isEmpty || !row.isEmpty {
      flushRow()
    }
    return rows
  }

  private static func canonicalDateKey(_ raw: String) -> String? {
    let value = clean(raw)
    guard !value.isEmpty else { return nil }

    let formats = ["yyyy-MM-dd", "M/d/yyyy", "MM/dd/yyyy", "M/d/yy"]
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = schoolCalendar.timeZone
      formatter.calendar = schoolCalendar
      formatter.dateFormat = format
      if let date = formatter.date(from: value) {
        return dateKey(for: date)
      }
    }
    return nil
  }

  private static func parseTime(_ raw: String) -> DateComponents? {
    let value = clean(raw)
    guard !value.isEmpty else { return nil }

    for format in [
      "h:mm a", "h:mm:ss a", "h:mma", "h:mm:ssa", "H:mm", "HH:mm", "H:mm:ss", "HH:mm:ss",
    ] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = schoolCalendar.timeZone
      formatter.dateFormat = format
      if let date = formatter.date(from: value.uppercased()) {
        return schoolCalendar.dateComponents([.hour, .minute], from: date)
      }
    }
    return nil
  }

  private static func parseBool(_ raw: String) -> Bool {
    switch normalized(raw) {
    case "true", "yes", "y", "1": true
    default: false
    }
  }

  nonisolated private static func clean(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\u{feff}", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // Pure string normalization is safe from any actor. Keeping this nonisolated
  // also lets synchronous collection transforms such as `map(normalized)` use
  // it under Swift 6's default main-actor isolation without crossing actors.
  nonisolated private static func normalized(_ value: String) -> String {
    clean(value).lowercased()
  }

  private static func value(at index: Int, in row: [String]) -> String {
    guard row.indices.contains(index) else { return "" }
    return row[index]
  }

  private static func minutes(_ components: DateComponents) -> Int {
    (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }
}
