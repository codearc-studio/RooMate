import Foundation

/// Parses iCalendar (.ics) calendar events.
///
/// School calendar feeds can mix UTC timestamps, explicit `TZID` timestamps, and
/// date-only all-day events. RooMate normalizes them using the school's local
/// timezone so an event does not jump to the previous/next day just because
/// the Mac or feed represented the timestamp differently.
struct ICSParser {
  private static let schoolTimeZone =
    TimeZone(identifier: "America/New_York") ?? .current

  private struct ICSProperty {
    let key: String
    let parameters: [String: String]
    let value: String
  }

  static func parseEvents(from data: Data) -> [CalendarEvent] {
    guard let content = String(data: data, encoding: .utf8) else {
      return []
    }
    return parseEvents(from: content)
  }

  static func parseEvents(from icsContent: String) -> [CalendarEvent] {
    var events: [CalendarEvent] = []
    var currentEvent: [String] = []
    var inEvent = false

    for line in unfoldedLines(from: icsContent) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      switch trimmed {
      case "BEGIN:VEVENT":
        inEvent = true
        currentEvent = []
      case "END:VEVENT":
        if inEvent, let event = parseEvent(from: currentEvent) {
          events.append(event)
        }
        inEvent = false
        currentEvent = []
      default:
        if inEvent {
          currentEvent.append(line)
        }
      }
    }

    var seen = Set<String>()
    return events
      .filter { event in
        let key = "\(event.startDate.timeIntervalSince1970)|\(event.title)|\(event.location ?? "")"
        return seen.insert(key).inserted
      }
      .sorted { $0.startDate < $1.startDate }
  }

  /// RFC 5545 allows a long property to continue on the next line when that
  /// line begins with a space or tab. Unfold before parsing properties.
  private static func unfoldedLines(from content: String) -> [String] {
    let normalized =
      content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    var result: [String] = []

    for rawLine in normalized.components(separatedBy: "\n") {
      if rawLine.hasPrefix(" ") || rawLine.hasPrefix("\t"),
        !result.isEmpty
      {
        result[result.count - 1] += String(rawLine.dropFirst())
      } else {
        result.append(rawLine)
      }
    }

    return result
  }

  private static func parseEvent(from lines: [String]) -> CalendarEvent? {
    var title: String?
    var startDate: Date?
    var endDate: Date?
    var location: String?

    for line in lines {
      guard let property = parseProperty(line) else { continue }

      switch property.key {
      case "SUMMARY":
        title = decodeICSText(property.value)
      case "DTSTART":
        startDate = parseICSDate(
          property.value,
          parameters: property.parameters
        )
      case "DTEND":
        endDate = parseICSDate(
          property.value,
          parameters: property.parameters
        )
      case "LOCATION":
        location = decodeICSText(property.value)
      default:
        break
      }
    }

    guard let title, let startDate else {
      return nil
    }

    return CalendarEvent(
      title: title,
      startDate: startDate,
      endDate: endDate,
      location: location
    )
  }

  private static func parseProperty(_ line: String) -> ICSProperty? {
    guard let colon = line.firstIndex(of: ":") else {
      return nil
    }

    let left = String(line[..<colon])
    let value = String(line[line.index(after: colon)...])
    let pieces = left.components(separatedBy: ";")
    guard let rawKey = pieces.first else { return nil }

    var parameters: [String: String] = [:]

    for parameter in pieces.dropFirst() {
      guard let equals = parameter.firstIndex(of: "=") else { continue }

      let name = String(parameter[..<equals]).uppercased()
      var parameterValue = String(parameter[parameter.index(after: equals)...])

      if parameterValue.hasPrefix("\""),
        parameterValue.hasSuffix("\""),
        parameterValue.count >= 2
      {
        parameterValue.removeFirst()
        parameterValue.removeLast()
      }

      parameters[name] = parameterValue
    }

    return ICSProperty(
      key: rawKey.uppercased(),
      parameters: parameters,
      value: value
    )
  }

  /// Parses:
  /// - UTC date-times (`...Z`)
  /// - date-times with `TZID=...`
  /// - floating date-times (treated as school-local time)
  /// - date-only all-day events (school-local midnight)
  private static func parseICSDate(
    _ rawValue: String,
    parameters: [String: String]
  ) -> Date? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let isDateOnly =
      parameters["VALUE"]?.uppercased() == "DATE" || !value.contains("T")

    if isDateOnly {
      return dateFormatter(
        format: "yyyyMMdd",
        timeZone: schoolTimeZone
      ).date(from: String(value.prefix(8)))
    }

    let isUTC = value.hasSuffix("Z")
    let cleanValue = isUTC ? String(value.dropLast()) : value

    let resolvedTimeZone: TimeZone = {
      if isUTC {
        return TimeZone(secondsFromGMT: 0) ?? schoolTimeZone
      }

      if let tzid = parameters["TZID"],
        let zone = timeZone(forTZID: tzid)
      {
        return zone
      }

      return schoolTimeZone
    }()

    for format in [
      "yyyyMMdd'T'HHmmss",
      "yyyyMMdd'T'HHmm",
    ] {
      if let date = dateFormatter(
        format: format,
        timeZone: resolvedTimeZone
      ).date(from: cleanValue) {
        return date
      }
    }

    return nil
  }

  private static func timeZone(forTZID rawTZID: String) -> TimeZone? {
    if let exact = TimeZone(identifier: rawTZID) {
      return exact
    }

    let components = rawTZID.split(separator: "/")
    if components.count >= 2 {
      let candidate = components.suffix(2).joined(separator: "/")
      if let zone = TimeZone(identifier: candidate) {
        return zone
      }
    }

    if rawTZID.uppercased().contains("EASTERN") {
      return TimeZone(identifier: "America/New_York")
    }

    return nil
  }

  private static func dateFormatter(
    format: String,
    timeZone: TimeZone
  ) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    return formatter
  }

  private static func decodeICSText(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\\,", with: ",")
      .replacingOccurrences(of: "\\;", with: ";")
      .replacingOccurrences(of: "\\\\", with: "\\")
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\N", with: "\n")
  }
}
