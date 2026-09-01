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
      with:
        "BEGIN:VEVENT\nDTSTART;TZID=America/New_York:20260826T090000\nSUMMARY:Opening Assembly\nLOCATION:Meetinghouse\nEND:VEVENT\nEND:VCALENDAR"
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

  func testAnnouncementParserUsesProductionWorkbookContract() throws {
    let csv = """
      ID,Title,Message,Priority,Icon,Start Date,End Date,Link,Dismissible,Minimum Version,Status
      welcome,Welcome,"Hello, RooMate!",success,sparkles,8/26/2026,9/1/2026,https://example.com,TRUE,6.0,Published
      draft,Draft Notice,This should stay hidden,warning,exclamationmark.triangle.fill,,,,TRUE,6.0,Draft
      """

    let announcements = try RemoteAnnouncementService.parseAnnouncements(csv)
    XCTAssertEqual(announcements.count, 1)
    XCTAssertEqual(announcements.first?.id, "welcome")
    XCTAssertEqual(announcements.first?.title, "Welcome")
    XCTAssertEqual(announcements.first?.message, "Hello, RooMate!")
    XCTAssertEqual(announcements.first?.level, .success)
    XCTAssertEqual(announcements.first?.icon, "sparkles")
    XCTAssertEqual(announcements.first?.linkURL?.absoluteString, "https://example.com")
    XCTAssertEqual(announcements.first?.dismissible, true)
    XCTAssertEqual(announcements.first?.minVersion, "6.0")
    XCTAssertNotNil(announcements.first?.startDate)
    XCTAssertNotNil(announcements.first?.endDate)
  }

  func testAnnouncementParserAcceptsIntentionalHeaderOnlyFeed() throws {
    let csv =
      "ID,Title,Message,Priority,Icon,Start Date,End Date,Link,Dismissible,Minimum Version,Status\n"
    XCTAssertTrue(try RemoteAnnouncementService.parseAnnouncements(csv).isEmpty)
  }

  func testAnnouncementParserRejectsUnrelatedGoogleResponse() {
    XCTAssertThrowsError(
      try RemoteAnnouncementService.parseAnnouncements(
        "Error,Requested entity was not found\n"
      )
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

  func testWeeklyScheduleMatchesPublishedLevelOrder() {
    let expected: [Weekday: [BlockKind]] = [
      .monday: [
        .special(.assembly), .level(.level2), .level(.level5), .special(.officeHours),
        .level(.level6), .level(.level3), .special(.musicClubs), .special(.lunch),
        .level(.level7), .level(.level4),
      ],
      .tuesday: [
        .special(.assembly), .level(.level3), .level(.level1), .special(.officeHours),
        .level(.music), .level(.level2), .special(.advisory), .special(.lunch),
        .level(.level5), .level(.level6),
      ],
      .wednesday: [
        .level(.level5), .level(.level6), .special(.officeHours), .level(.level4),
        .level(.level7), .special(.worship), .special(.lunchAndClubs), .level(.level1),
        .level(.level3),
      ],
      .thursday: [
        .special(.assembly), .level(.level7), .level(.level4), .special(.officeHours),
        .level(.music), .level(.level2), .special(.consciousCommunities), .special(.lunch),
        .level(.level3), .level(.level1),
      ],
      .friday: [
        .level(.music), .level(.level7), .level(.level4), .special(.officeHours),
        .level(.level1), .level(.level5), .special(.lunch), .level(.level6),
        .level(.level2),
      ],
    ]

    for weekday in Weekday.allCases {
      XCTAssertEqual(
        BellSchedule.weekly[weekday]?.map(\.kind),
        expected[weekday],
        "Published block order changed for \(weekday.title)"
      )
    }
  }

  func testMondayFirstClassBoundariesUseHalfOpenIntervals() throws {
    let monday = try XCTUnwrap(BellSchedule.weekly[.monday])
    let firstClass = try XCTUnwrap(
      monday.first(where: {
        if case .level(.level2) = $0.kind { return true }
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

  func testFutureMarkerKeepsSpecialSchoolDayActive() throws {
    let earlierMarker = RemoteSpecialScheduleItem(
      order: 3,
      start: DateComponents(hour: 10, minute: 30),
      end: nil,
      kind: .custom("Seniors Depart for Retreat"),
      titleOverride: "Seniors Depart for Retreat",
      timelineType: .marker
    ).bellBlock()
    let endMarker = RemoteSpecialScheduleItem(
      order: 4,
      start: DateComponents(hour: 15, minute: 10),
      end: nil,
      kind: .custom("School Day Ends"),
      titleOverride: "School Day Ends",
      detail: "Athletics begin afterward",
      timelineType: .marker
    ).bellBlock()

    let status = BellScheduleStatus.resolve(
      blocks: [earlierMarker, endMarker],
      at: DateComponents(hour: 10, minute: 58)
    )

    XCTAssertNil(status.currentItemID, "Markers are not duration blocks")
    XCTAssertEqual(status.nextItemID, endMarker.id, "The 3:10 marker keeps the day active")
    XCTAssertEqual(endMarker.end, endMarker.start, "A marker stays instantaneous")
  }

  func testThemeCollectionBalancesLightAndDarkChoices() {
    let customThemes = RooMateTheme.allCases.filter { $0 != .system }
    XCTAssertEqual(customThemes.filter { !$0.isDark }.count, 3)
    XCTAssertEqual(customThemes.filter(\.isDark).count, 3)
    XCTAssertEqual(Set(customThemes.map(\.title)).count, customThemes.count)
  }

  func testOLEDThemeUsesTrueBlackCanvasAndLayeredSurfaces() {
    let palette = DesignTokens.Colors.palette(for: .oled)
    XCTAssertEqual(palette.background, 0x000000)
    XCTAssertNotEqual(palette.surface, palette.background)
    XCTAssertNotEqual(palette.surfaceElevated, palette.surface)
  }

  func testThemeTextAndFeatureColorsMeetContrastTargets() {
    for theme in RooMateTheme.allCases where theme != .system {
      let palette = DesignTokens.Colors.palette(for: theme)
      let surfaces: [(String, UInt32)] = [
        ("canvas", palette.background),
        ("sidebar", palette.sidebar),
        ("surface", palette.surface),
        ("elevated surface", palette.surfaceElevated),
      ]
      let textColors: [(String, UInt32)] = [
        ("primary text", palette.primaryText),
        ("secondary text", palette.secondaryText),
        ("subtle text", palette.subtleText),
      ]

      for (textName, foreground) in textColors {
        for (surfaceName, background) in surfaces {
          XCTAssertGreaterThanOrEqual(
            contrastRatio(foreground, background),
            4.5,
            "\(theme.title) \(textName) on \(surfaceName)"
          )
        }
      }

      let featureColors: [(String, UInt32)] = [
        ("Today", palette.today), ("Schedule", palette.schedule),
        ("PacTrack", palette.pacTrack), ("Dining", palette.dining),
        ("Athletics", palette.athletics), ("Events", palette.events),
        ("Links", palette.links), ("Settings", palette.settings),
        ("Success", palette.success), ("Warning", palette.warning),
        ("Destructive", palette.destructive), ("Info", palette.info),
      ]
      for (name, foreground) in featureColors {
        XCTAssertGreaterThanOrEqual(
          contrastRatio(foreground, palette.surface),
          4.5,
          "\(theme.title) \(name) on a card surface"
        )
      }
    }
  }

  private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05)
      / (min(firstLuminance, secondLuminance) + 0.05)
  }

  private func relativeLuminance(_ hex: UInt32) -> Double {
    let components = [
      Double((hex >> 16) & 0xFF) / 255,
      Double((hex >> 8) & 0xFF) / 255,
      Double(hex & 0xFF) / 255,
    ].map { component in
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * components[0] + 0.7152 * components[1] + 0.0722 * components[2]
  }
}
