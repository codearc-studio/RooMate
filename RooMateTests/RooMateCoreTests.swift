import XCTest
@testable import RooMate

final class RooMateCoreTests: XCTestCase {
  private func fixture(_ name: String) throws -> Data {
    let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return try Data(contentsOf: directory.appendingPathComponent("Fixtures/\(name)"))
  }

  func testVersionComparisonHandlesDisplayVersions() {
    XCTAssertEqual(RooMateVersion.compare("6.0", "6.0.0"), .orderedSame)
    XCTAssertEqual(RooMateVersion.compare("6.0.1", "6.0"), .orderedDescending)
    XCTAssertEqual(RooMateVersion.compare("6.0.2", "6.1"), .orderedAscending)
    XCTAssertEqual(RooMateVersion.compare("7.0-beta", "7.0"), .orderedSame)
  }

  func testSportsParserAcceptsExtraColumnsAndQuotedCommas() throws {
    let data = try fixture("sports-valid.csv")
    XCTAssertTrue(SportsCSVParser.hasExpectedHeader(in: data))
    let games = SportsCSVParser.parseSportsGames(from: data)
    XCTAssertEqual(games.count, 2)
    XCTAssertEqual(games.first?.notesRaw, "Bring water, uniforms")
  }

  func testSportsParserSkipsMalformedRowsAndDeduplicates() throws {
    let partial = try fixture("sports-partial.csv")
    XCTAssertEqual(SportsCSVParser.parseSportsGames(from: partial).map(\.team), ["Valid Team"])

    let original = try fixture("sports-valid.csv")
    var duplicate = original
    duplicate.append(original)
    XCTAssertEqual(SportsCSVParser.parseSportsGames(from: duplicate).count, 2)
  }

  func testSportsHeaderRejectsMalformedResponse() {
    XCTAssertFalse(SportsCSVParser.hasExpectedHeader(in: Data("<html>error</html>".utf8)))
    XCTAssertTrue(SportsCSVParser.parseSportsGames(from: Data("".utf8)).isEmpty)
  }

  func testICSParserHandlesTimedAndAllDayEvents() throws {
    let events = ICSParser.parseEvents(from: try fixture("events-valid.ics"))
    XCTAssertEqual(events.map(\.title), ["Opening Assembly", "Community Day"])
    XCTAssertEqual(events.first?.location, "Meetinghouse")
  }

  func testICSParserRejectsMalformedEventsAndDeduplicates() throws {
    XCTAssertTrue(ICSParser.parseEvents(from: "not a calendar").isEmpty)
    XCTAssertTrue(
      ICSParser.parseEvents(
        from: "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Missing date\nEND:VEVENT\nEND:VCALENDAR"
      ).isEmpty
    )

    let valid = String(decoding: try fixture("events-valid.ics"), as: UTF8.self)
    let duplicatedEvent = valid.replacingOccurrences(
      of: "END:VCALENDAR",
      with: "BEGIN:VEVENT\nDTSTART;TZID=America/New_York:20260826T090000\nSUMMARY:Opening Assembly\nLOCATION:Meetinghouse\nEND:VEVENT\nEND:VCALENDAR"
    )
    XCTAssertEqual(ICSParser.parseEvents(from: duplicatedEvent).count, 2)
  }

  @MainActor
  func testPersistentRemoteCacheRoundTripAndMalformedProtection() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RooMateCacheTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let refreshedAt = Date(timeIntervalSince1970: 1_787_667_200)
    try PersistentRemoteCache.save(
      ["one", "two"],
      refreshedAt: refreshedAt,
      named: "sample cache",
      directory: directory
    )
    let loaded = PersistentRemoteCache.load(
      [String].self,
      named: "sample cache",
      directory: directory
    )
    XCTAssertEqual(loaded?.value, ["one", "two"])
    XCTAssertEqual(loaded?.refreshedAt, refreshedAt)

    let file = directory.appendingPathComponent("sample-cache.json")
    try Data("malformed".utf8).write(to: file, options: .atomic)
    XCTAssertNil(
      PersistentRemoteCache.load([String].self, named: "sample cache", directory: directory)
    )
  }

  func testWeeklyScheduleHasOrderedNonOverlappingPrimaryBlocks() {
    XCTAssertEqual(BellSchedule.weekly.count, Weekday.allCases.count)
    for weekday in Weekday.allCases {
      let blocks = BellSchedule.weekly[weekday] ?? []
      XCTAssertFalse(blocks.isEmpty, "\(weekday.title) should have a schedule")
      for pair in zip(blocks, blocks.dropFirst()) {
        let previousEnd = (pair.0.end.hour ?? 0) * 60 + (pair.0.end.minute ?? 0)
        let nextStart = (pair.1.start.hour ?? 0) * 60 + (pair.1.start.minute ?? 0)
        XCTAssertLessThanOrEqual(previousEnd, nextStart, "Overlap on \(weekday.title)")
      }
    }
  }

  func testMondayBlockBoundariesUseHalfOpenIntervals() throws {
    let monday = try XCTUnwrap(BellSchedule.weekly[.monday])
    let firstClass = try XCTUnwrap(monday.first(where: {
      if case .level(.level1) = $0.kind { return true }
      return false
    }))
    XCTAssertEqual(firstClass.start.hour, 8)
    XCTAssertEqual(firstClass.start.minute, 15)
    XCTAssertEqual(firstClass.end.hour, 9)
    XCTAssertEqual(firstClass.end.minute, 2)

    let atStart = 8 * 60 + 15
    let atEnd = 9 * 60 + 2
    let start = (firstClass.start.hour ?? 0) * 60 + (firstClass.start.minute ?? 0)
    let end = (firstClass.end.hour ?? 0) * 60 + (firstClass.end.minute ?? 0)
    XCTAssertTrue(atStart >= start && atStart < end)
    XCTAssertFalse(atEnd >= start && atEnd < end)
  }
}
