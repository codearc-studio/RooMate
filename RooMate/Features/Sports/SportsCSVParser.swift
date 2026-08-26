import Foundation

enum SportsCSVParser {
  private static let dateFormats: [String] = [
    "M/d/yyyy",
    "M/d/yy",
    "MMM d, yyyy",
    "MMMM d, yyyy",
    "yyyy-MM-dd",
  ]

  private static let dateFormatters: [DateFormatter] = dateFormats.map { format in
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    return formatter
  }

  // Scanner-based CSV parser that preserves commas inside quoted fields.
  static func parseCSV(_ data: Data, assumingUTF8: Bool = true) -> [[String]] {
    let str: String
    if assumingUTF8, let s = String(data: data, encoding: .utf8) {
      str = s
    } else if let s = String(data: data, encoding: .ascii) {
      str = s
    } else {
      str = String(data: data, encoding: .utf8) ?? ""
    }

    var rows: [[String]] = []
    var currentField = ""
    var currentRow: [String] = []
    var inQuotes = false
    var index = str.startIndex

    func flushRow() {
      currentRow.append(currentField)
      let hasContent = currentRow.contains {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      if hasContent {
        rows.append(currentRow)
      }
      currentRow = []
      currentField = ""
    }

    while index < str.endIndex {
      let character = str[index]

      switch character {
      case "\"":
        let nextIndex = str.index(after: index)
        if inQuotes, nextIndex < str.endIndex, str[nextIndex] == "\"" {
          currentField.append("\"")
          index = nextIndex
        } else {
          inQuotes.toggle()
        }

      case "," where !inQuotes:
        currentRow.append(currentField)
        currentField = ""

      case "\n" where !inQuotes:
        flushRow()

      case "\r" where !inQuotes:
        let nextIndex = str.index(after: index)
        if nextIndex < str.endIndex, str[nextIndex] == "\n" {
          index = nextIndex
        }
        flushRow()

      default:
        currentField.append(character)
      }

      index = str.index(after: index)
    }

    if inQuotes == false || !currentField.isEmpty || !currentRow.isEmpty {
      currentRow.append(currentField)
      let hasContent = currentRow.contains {
        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      if hasContent {
        rows.append(currentRow)
      }
    }

    return rows
  }

  private static func clean(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\u{feff}", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func parseDate(_ rawValue: String) -> Date? {
    let trimmed = clean(rawValue)
    guard !trimmed.isEmpty else { return nil }

    for formatter in dateFormatters {
      if let date = formatter.date(from: trimmed) {
        return date
      }
    }

    return nil
  }

  private static func value(at index: Int, in row: [String]) -> String {
    guard index >= 0, index < row.count else { return "" }
    return clean(row[index])
  }

  private static func shouldIgnoreRow(_ row: [String]) -> Bool {
    let first = value(at: 0, in: row)
    if first.isEmpty { return true }

    let lower = first.lowercased()
    if lower == "date" { return true }
    if lower.hasPrefix("last update") { return true }

    return false
  }

  static func hasExpectedHeader(in data: Data) -> Bool {
    guard let header = parseCSV(data).first else { return false }
    let normalized = header.map { clean($0).lowercased() }
    guard normalized.indices.contains(2) else { return false }
    return normalized[0] == "date" && normalized[2] == "team"
  }

  static func parseSportsGames(from data: Data) -> [SportsGame] {
    let rows = parseCSV(data)
    var games: [SportsGame] = []
    var seenIDs = Set<String>()

    for row in rows {
      guard row.count >= 1 else { continue }
      guard !shouldIgnoreRow(row) else { continue }

      let rawDate = value(at: 0, in: row)
      guard !rawDate.isEmpty else { continue }

      guard let parsedDate = parseDate(rawDate) else { continue }
      let team = value(at: 2, in: row)
      guard !team.isEmpty else { continue }

      let game = SportsGame(
        rawDateString: rawDate,
        date: parsedDate,
        day: value(at: 1, in: row),
        team: team,
        opponent: value(at: 3, in: row),
        location: value(at: 4, in: row),
        time: value(at: 5, in: row),
        dismiss: value(at: 6, in: row),
        return: value(at: 7, in: row),
        notesRaw: value(at: 8, in: row)
      )
      if seenIDs.insert(game.id).inserted {
        games.append(game)
      }
    }

    return games
  }
}
