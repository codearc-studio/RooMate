import Combine
import Foundation

struct ClubDirectoryEntry: Identifiable, Hashable, Codable {
  let name: String
  let category: String
  let description: String
  let instagram: String
  let website: String
  let iconName: String
  let colorHex: String
  let featured: Bool

  var id: String {
    name
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
  }

  var instagramURL: URL? {
    let value = instagram.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
      return URL(string: value)
    }

    let handle = value.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
    guard !handle.isEmpty else { return nil }
    return URL(string: "https://www.instagram.com/\(handle)")
  }

  var websiteURL: URL? {
    let value = website.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
      return URL(string: value)
    }

    return URL(string: "https://\(value)")
  }
}

@MainActor
final class ClubDirectoryStore: ObservableObject {
  @Published private(set) var clubs: [ClubDirectoryEntry] = []
  @Published private(set) var isLoading = false
  @Published private(set) var lastError: String?
  @Published private(set) var lastUpdated: Date?
  @Published private(set) var isShowingSavedData = false

  /// Once the shared Google Sheet is created, put its spreadsheet ID here.
  /// The rows can then change at any time without an app update.
  private static let bundledSpreadsheetID = "1n9IBnrvBbnP_wCMP7iCC8dldGmyNyOFYbEKad4iMX2A"
  private static let sheetName = "CLUBS"
  private static let overrideDefaultsKey = "RooMateClubDirectorySpreadsheetID"
  private var refreshGeneration = 0

  init() {
    if let cached = PersistentRemoteCache.load([ClubDirectoryEntry].self, named: "clubs") {
      clubs = cached.value
      lastUpdated = cached.refreshedAt
      isShowingSavedData = !cached.value.isEmpty
    }
  }

  var isConfigured: Bool {
    !Self.spreadsheetID.isEmpty
  }

  func refresh() async {
    refreshGeneration += 1
    let generation = refreshGeneration

    guard isConfigured else {
      clubs = []
      lastError = nil
      isLoading = false
      return
    }

    isLoading = true
    lastError = nil

    do {
      let csv = try await Self.fetchCSV(
        spreadsheetID: Self.spreadsheetID,
        sheetName: Self.sheetName
      )
      let parsed = try Self.parseDirectory(csv)
      guard !parsed.isEmpty else { throw DirectoryError.emptyFeed }
      guard generation == refreshGeneration else { return }

      clubs = parsed.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
      let refreshedAt = Date()
      lastUpdated = refreshedAt
      isShowingSavedData = false
      try? PersistentRemoteCache.save(clubs, refreshedAt: refreshedAt, named: "clubs")
      RemoteDataHealthStore.shared.recordSuccess(.clubs, refreshedAt: refreshedAt)
      isLoading = false
      #if DEBUG
        print("[ClubDirectory] Loaded \(clubs.count) published clubs.")
      #endif
    } catch is CancellationError {
      guard generation == refreshGeneration else { return }
      isLoading = false
    } catch {
      guard generation == refreshGeneration else { return }
      lastError = error.localizedDescription
      isShowingSavedData = !clubs.isEmpty
      RemoteDataHealthStore.shared.recordFailure(
        .clubs,
        error: error,
        usingSavedData: isShowingSavedData,
        lastUpdated: lastUpdated
      )
      isLoading = false
      #if DEBUG
        print("[ClubDirectory] Refresh failed: \(error.localizedDescription)")
      #endif
    }
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
    sheetName: String
  ) async throws -> String {
    guard !spreadsheetID.isEmpty else { throw DirectoryError.notConfigured }

    guard
      var components = URLComponents(
        string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/gviz/tq"
      )
    else {
      throw DirectoryError.invalidURL
    }
    components.queryItems = [
      URLQueryItem(name: "tqx", value: "out:csv"),
      URLQueryItem(name: "sheet", value: sheetName),
      URLQueryItem(name: "tq", value: "select A,B,C,D,E,F,G,H,I"),
      URLQueryItem(name: "headers", value: "1"),
    ]

    guard let url = components.url else { throw DirectoryError.invalidURL }

    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw DirectoryError.badResponse
    }

    guard let text = String(data: data, encoding: .utf8) else {
      throw DirectoryError.invalidText
    }
    return text
  }

  nonisolated private static func parseDirectory(_ csv: String) throws -> [ClubDirectoryEntry] {
    let responsePrefix =
      csv
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .prefix(512)
      .lowercased()
    if responsePrefix.hasPrefix("<!doctype")
      || responsePrefix.hasPrefix("<html")
      || (responsePrefix.contains("google.visualization") && responsePrefix.contains("error"))
    {
      throw DirectoryError.badResponse
    }

    let rows = parseCSV(csv)
      .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      }

    guard let header = rows.first else { return [] }

    let normalizedHeader = header.map(normalized)
    func column(_ names: [String]) -> Int? {
      normalizedHeader.firstIndex { value in names.contains(value) }
    }

    func resolvedColumn(_ aliases: [String], fallback: Int) -> Int {
      column(aliases) ?? fallback
    }

    // Google Visualization occasionally returns generic/derived headers
    // even when a Sheet is visually correct. RooMate owns a stable A:I
    // contract, so fall back to those positions rather than dropping the
    // whole directory when header inference changes.
    let nameColumn = resolvedColumn(["name", "club", "clubname"], fallback: 0)
    let categoryColumn = resolvedColumn(["category", "type"], fallback: 1)
    let descriptionColumn = resolvedColumn(["description", "about", "summary"], fallback: 2)
    let instagramColumn = resolvedColumn(["instagram", "ig"], fallback: 3)
    let websiteColumn = resolvedColumn(["website", "url", "link"], fallback: 4)
    let iconColumn = resolvedColumn(["icon", "symbol", "sfsymbol"], fallback: 5)
    let colorColumn = resolvedColumn(["colorhex", "color", "hex"], fallback: 6)
    let featuredColumn = resolvedColumn(["featured", "feature"], fallback: 7)
    let publishedColumn = resolvedColumn(["published", "active", "visible"], fallback: 8)

    func value(_ row: [String], _ index: Int?) -> String {
      guard let index, row.indices.contains(index) else { return "" }
      return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var entries: [ClubDirectoryEntry] = []
    var seen = Set<String>()

    for row in rows.dropFirst() {
      let name = value(row, nameColumn)
      guard !name.isEmpty else { continue }

      let published = parseBool(value(row, publishedColumn)) ?? false
      guard published else { continue }

      let key = normalized(name)
      guard seen.insert(key).inserted else { continue }

      entries.append(
        ClubDirectoryEntry(
          name: name,
          category: value(row, categoryColumn),
          description: value(row, descriptionColumn),
          instagram: value(row, instagramColumn),
          website: value(row, websiteColumn),
          iconName: value(row, iconColumn).isEmpty ? "person.3.fill" : value(row, iconColumn),
          colorHex: value(row, colorColumn),
          featured: parseBool(value(row, featuredColumn)) ?? false
        )
      )
    }

    return entries
  }

  nonisolated private static func parseBool(_ text: String) -> Bool? {
    switch normalized(text) {
    case "true", "yes", "y", "1": true
    case "false", "no", "n", "0": false
    default: nil
    }
  }

  nonisolated private static func normalized(_ text: String) -> String {
    text
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
        if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
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

  private enum DirectoryError: LocalizedError {
    case notConfigured
    case invalidURL
    case badResponse
    case invalidText
    case emptyFeed

    var errorDescription: String? {
      switch self {
      case .notConfigured: "The club directory source has not been configured."
      case .invalidURL: "RooMate could not build the club directory URL."
      case .badResponse: "The club directory did not return a valid response."
      case .invalidText: "RooMate could not read the club directory data."
      case .emptyFeed: "The club directory did not contain any published clubs."
      }
    }
  }
}
