import Foundation

enum RooMateAnnouncementLevel: String, Hashable, Sendable, Codable {
  case info
  case success
  case important
  case warning

  nonisolated var priority: Int {
    switch self {
    case .info: 0
    case .success: 1
    case .important: 2
    case .warning: 3
    }
  }
}

private enum AnnouncementCSVEndpoint: CaseIterable, Sendable {
  // The Visualization endpoint is intentionally first because it reliably
  // targets a worksheet by name. Google's /export CSV endpoint primarily
  // targets worksheets by gid and may ignore a `sheet=` name parameter.
  case visualization
  case directExport

  var debugName: String {
    switch self {
    case .directExport: "direct CSV export"
    case .visualization: "Visualization CSV"
    }
  }
}

struct RooMateAnnouncement: Identifiable, Hashable, Sendable, Codable {
  let id: String
  let title: String
  let message: String
  let level: RooMateAnnouncementLevel
  let icon: String
  let startDate: Date?
  let endDate: Date?
  let linkLabel: String
  let linkURL: URL?
  let dismissible: Bool
  let minVersion: String

  func isActive(at reference: Date, appVersion: String) -> Bool {
    if let startDate, reference < startDate { return false }
    if let endDate, reference > endDate { return false }
    if !minVersion.isEmpty,
      RemoteAnnouncementService.compareVersions(appVersion, minVersion) == .orderedAscending
    {
      return false
    }
    return true
  }
}

@MainActor
enum RemoteAnnouncementService {
  /// RooMate's announcement feed is managed in its own Google Sheet.
  /// The expected tab is `Announcements`; Documentation and Settings tabs may
  /// coexist in the workbook and are intentionally ignored by the app.
  private static let bundledSpreadsheetID = "1ZuKZs5-Zu7ksUl6Rz_e5NSL3AX4Ct4d0unte6SAgswc"
  private static let sheetName = "Announcements"
  private static let overrideDefaultsKey = "RooMateAnnouncementSpreadsheetID"

  static var isConfigured: Bool {
    !spreadsheetID.isEmpty
  }

  static func fetchAnnouncements() async throws -> [RooMateAnnouncement] {
    let spreadsheetID = Self.spreadsheetID
    let sheetName = Self.sheetName
    guard !spreadsheetID.isEmpty else { return [] }

    var lastError: Error?
    var validEmptyFeed: [RooMateAnnouncement]?

    for endpoint in AnnouncementCSVEndpoint.allCases {
      do {
        let csv = try await fetchCSV(
          spreadsheetID: spreadsheetID,
          sheetName: sheetName,
          endpoint: endpoint
        )
        let announcements = try parseAnnouncements(
          csv,
          requireFullContract: endpoint == .directExport
        )

        #if DEBUG
          print(
            "[Announcements] Loaded \(announcements.count) published row\(announcements.count == 1 ? "" : "s") via \(endpoint.debugName)."
          )
        #endif

        // A valid but empty feed is meaningful, but do not stop after the
        // first endpoint. This prevents a misleading empty response from the
        // generic /export endpoint from masking a populated Announcements tab.
        if announcements.isEmpty {
          validEmptyFeed = announcements
          continue
        }

        return announcements
      } catch {
        lastError = error
        #if DEBUG
          print("[Announcements] \(endpoint.debugName) failed: \(error.localizedDescription)")
        #endif
      }
    }

    if let validEmptyFeed {
      return validEmptyFeed
    }

    throw lastError ?? AnnouncementError.badResponse
  }

  private static var spreadsheetID: String {
    let override =
      UserDefaults.standard
      .string(forKey: overrideDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if !override.isEmpty { return override }
    return bundledSpreadsheetID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  nonisolated private static func fetchCSV(
    spreadsheetID: String,
    sheetName: String,
    endpoint: AnnouncementCSVEndpoint
  ) async throws -> String {
    let components: URLComponents?

    switch endpoint {
    case .directExport:
      var export = URLComponents(
        string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export"
      )
      export?.queryItems = [
        URLQueryItem(name: "format", value: "csv"),
        URLQueryItem(name: "sheet", value: sheetName),
      ]
      components = export

    case .visualization:
      var visualization = URLComponents(
        string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/gviz/tq"
      )
      visualization?.queryItems = [
        URLQueryItem(name: "tqx", value: "out:csv"),
        URLQueryItem(name: "sheet", value: sheetName),
        URLQueryItem(name: "headers", value: "1"),
        URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970))),
      ]
      components = visualization
    }

    guard let url = components?.url else {
      throw AnnouncementError.invalidURL
    }

    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 20

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse,
      (200..<300).contains(http.statusCode)
    else {
      throw AnnouncementError.badResponse
    }

    guard let text = String(data: data, encoding: .utf8) else {
      throw AnnouncementError.invalidText
    }

    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      !trimmed.localizedCaseInsensitiveContains("<html"),
      !trimmed.localizedCaseInsensitiveContains("<!doctype")
    else {
      throw AnnouncementError.badResponse
    }

    return text
  }

  nonisolated static func parseAnnouncements(
    _ csv: String,
    requireFullContract: Bool = false
  ) throws -> [RooMateAnnouncement] {
    let rows = parseCSV(csv)
      .filter { row in
        row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      }

    guard let header = rows.first else { return [] }

    let normalizedHeader = header.map(normalized)
    func column(_ aliases: [String]) -> Int? {
      normalizedHeader.firstIndex { aliases.contains($0) }
    }

    if csv.localizedCaseInsensitiveContains("unable to parse")
      || csv.localizedCaseInsensitiveContains("requested entity was not found")
      || csv.localizedCaseInsensitiveContains("google visualization api query language")
    {
      throw AnnouncementError.badResponse
    }

    guard
      column(["title", "heading", "name"]) != nil,
      column(["message", "body", "text", "description"]) != nil,
      column(["status", "published", "active", "visible"]) != nil
    else {
      throw AnnouncementError.missingRequiredColumns
    }

    if requireFullContract {
      let requiredAnnouncementColumns: [[String]] = [
        ["id", "announcementid", "key"],
        ["priority", "type", "level", "style"],
        ["dismissible", "canhide", "allowdismiss"],
        ["minimumversion", "minversion", "version"],
      ]

      guard requiredAnnouncementColumns.allSatisfy({ column($0) != nil }) else {
        throw AnnouncementError.missingRequiredColumns
      }
    }

    func resolvedColumn(_ aliases: [String], fallback: Int) -> Int {
      column(aliases) ?? fallback
    }

    // RooMate announcement workbook contract A:K:
    // ID, Title, Message, Priority, Icon, Start Date, End Date, Link,
    // Dismissible, Minimum Version, Status.
    // Header aliases make the parser tolerant of small human-readable renames.
    let idColumn = resolvedColumn(["id", "announcementid", "key"], fallback: 0)
    let titleColumn = resolvedColumn(["title", "heading", "name"], fallback: 1)
    let messageColumn = resolvedColumn(["message", "body", "text", "description"], fallback: 2)
    let typeColumn = resolvedColumn(["priority", "type", "level", "style"], fallback: 3)
    let iconColumn = column(["icon", "sfsymbol", "systemimage"])
    let startColumn = resolvedColumn(["startdate", "start", "starts", "publishat"], fallback: 5)
    let endColumn = resolvedColumn(["enddate", "end", "ends", "expires", "expiresat"], fallback: 6)
    let linkURLColumn = resolvedColumn(["link", "linkurl", "url"], fallback: 7)
    let dismissibleColumn = resolvedColumn(["dismissible", "canhide", "allowdismiss"], fallback: 8)
    let minVersionColumn = resolvedColumn(
      ["minimumversion", "minversion", "version"], fallback: 9)
    let statusColumn = resolvedColumn(["status", "published", "active", "visible"], fallback: 10)

    func value(_ row: [String], _ index: Int?) -> String {
      guard let index, row.indices.contains(index) else { return "" }
      return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var result: [RooMateAnnouncement] = []
    var seenIDs = Set<String>()

    for row in rows.dropFirst() {
      let title = value(row, titleColumn)
      let message = value(row, messageColumn)
      guard !title.isEmpty, !message.isEmpty else { continue }

      if !isPublished(value(row, statusColumn)) {
        continue
      }

      let rawID = value(row, idColumn)
      let fallbackID = normalized("\(title)-\(value(row, startColumn))")
      let id = rawID.isEmpty ? fallbackID : rawID
      guard !id.isEmpty, seenIDs.insert(id).inserted else { continue }

      let rawURL = value(row, linkURLColumn)
      let linkURL: URL?
      if rawURL.isEmpty {
        linkURL = nil
      } else if rawURL.lowercased().hasPrefix("http://")
        || rawURL.lowercased().hasPrefix("https://")
      {
        linkURL = URL(string: rawURL)
      } else {
        linkURL = URL(string: "https://\(rawURL)")
      }

      result.append(
        RooMateAnnouncement(
          id: id,
          title: title,
          message: message,
          level: parseLevel(value(row, typeColumn)),
          icon: value(row, iconColumn),
          startDate: parseDate(value(row, startColumn), isEnd: false),
          endDate: parseDate(value(row, endColumn), isEnd: true),
          linkLabel: "Learn More",
          linkURL: linkURL,
          dismissible: parseBool(value(row, dismissibleColumn)) ?? true,
          minVersion: value(row, minVersionColumn)
        )
      )
    }

    return result.sorted { lhs, rhs in
      if lhs.level.priority != rhs.level.priority {
        return lhs.level.priority > rhs.level.priority
      }
      return (lhs.startDate ?? .distantPast) > (rhs.startDate ?? .distantPast)
    }
  }

  nonisolated private static func parseLevel(_ raw: String) -> RooMateAnnouncementLevel {
    switch normalized(raw) {
    case "warning", "critical", "urgent", "alert":
      return .warning
    case "important", "priority", "notice":
      return .important
    case "success", "resolved", "update", "goodnews":
      return .success
    default:
      return .info
    }
  }

  nonisolated private static func isPublished(_ raw: String) -> Bool {
    switch normalized(raw) {
    case "published", "publish", "live", "active", "visible", "true", "yes", "y", "1":
      return true
    default:
      return false
    }
  }

  nonisolated private static func parseBool(_ raw: String) -> Bool? {
    switch normalized(raw) {
    case "true", "yes", "y", "1": true
    case "false", "no", "n", "0": false
    default: nil
    }
  }

  nonisolated private static func parseDate(_ raw: String, isEnd: Bool) -> Date? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: value) { return date }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

    let locale = Locale(identifier: "en_US_POSIX")
    let dateTimeFormats = [
      "M/d/yyyy h:mm a",
      "M/d/yyyy h:mma",
      "M/d/yyyy H:mm:ss",
      "M/d/yyyy H:mm",
      "yyyy-MM-dd HH:mm:ss",
      "yyyy-MM-dd HH:mm",
      "MMM d, yyyy h:mm a",
      "MMMM d, yyyy h:mm a",
    ]

    for format in dateTimeFormats {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = format
      if let date = formatter.date(from: value) { return date }
    }

    let dateOnlyFormats = [
      "M/d/yyyy",
      "M/d/yy",
      "yyyy-MM-dd",
      "MMM d, yyyy",
      "MMMM d, yyyy",
    ]

    for format in dateOnlyFormats {
      let formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = format
      if let parsed = formatter.date(from: value) {
        if isEnd {
          return calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: parsed
          ) ?? parsed
        }
        return calendar.startOfDay(for: parsed)
      }
    }

    return nil
  }

  nonisolated static func compareVersions(
    _ lhs: String,
    _ rhs: String
  ) -> ComparisonResult {
    let left = lhs.split(separator: ".").map {
      Int(String($0.filter { $0.isNumber })) ?? 0
    }
    let right = rhs.split(separator: ".").map {
      Int(String($0.filter { $0.isNumber })) ?? 0
    }
    let count = max(left.count, right.count)

    for index in 0..<count {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      if l < r { return .orderedAscending }
      if l > r { return .orderedDescending }
    }
    return .orderedSame
  }

  nonisolated private static func normalized(_ raw: String) -> String {
    raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
  }

  nonisolated private static func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var insideQuotes = false
    let characters = Array(text)
    var index = 0

    while index < characters.count {
      let character = characters[index]

      if character == "\"" {
        if insideQuotes,
          index + 1 < characters.count,
          characters[index + 1] == "\""
        {
          field.append("\"")
          index += 1
        } else {
          insideQuotes.toggle()
        }
      } else if character == ",", !insideQuotes {
        row.append(field)
        field = ""
      } else if character == "\n" || character == "\r", !insideQuotes {
        if character == "\r",
          index + 1 < characters.count,
          characters[index + 1] == "\n"
        {
          index += 1
        }
        row.append(field)
        rows.append(row)
        row = []
        field = ""
      } else {
        field.append(character)
      }

      index += 1
    }

    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }

    return rows
  }

  private enum AnnouncementError: LocalizedError {
    case invalidURL
    case badResponse
    case invalidText
    case missingRequiredColumns

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        "RooMate could not build the announcements URL."
      case .badResponse:
        "The announcements feed did not return a valid response."
      case .invalidText:
        "RooMate could not read the announcements feed."
      case .missingRequiredColumns:
        "The announcements sheet is missing Title or Message."
      }
    }
  }
}
