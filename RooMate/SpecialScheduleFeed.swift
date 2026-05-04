import Foundation

// MARK: - Dated Special Schedule

struct DatedSpecialSchedule: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let title: String
    let url: URL
    let blocks: [BellBlock]
}

// MARK: - Feed

actor SpecialScheduleFeed {

    // Index sheet: Date, Event, CSV URL
    struct IndexRow: Hashable {
        let date: Date
        let title: String
        let url: URL
    }

    // Dedicated URLSession for these CSV fetches
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    // Public: fetch all dated specials from the index URL
    func fetchAll(from indexURL: URL) async throws -> [DatedSpecialSchedule] {
        let rows = try await fetchIndex(from: indexURL)

        var results: [DatedSpecialSchedule] = []
        results.reserveCapacity(rows.count)

        try await withThrowingTaskGroup(of: DatedSpecialSchedule?.self) { group in
            for row in rows {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let blocks = try await self.fetchBlocks(from: row.url)
                        return DatedSpecialSchedule(date: row.date, title: row.title, url: row.url, blocks: blocks)
                    } catch {
                        #if DEBUG
                        print("[SpecialScheduleFeed] Failed blocks for \(row.title) @ \(row.url): \(error)")
                        #endif
                        return nil
                    }
                }
            }
            for try await item in group {
                if let item { results.append(item) }
            }
        }

        // Sort by date ascending
        results.sort { $0.date < $1.date }
        return results
    }

    // MARK: Index CSV parsing (Date, Event, CSV URL)

    func fetchIndex(from url: URL) async throws -> [IndexRow] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/csv, text/plain; q=0.8, */*; q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parseIndexCSV(text: text)
    }

    private func parseIndexCSV(text: String) -> [IndexRow] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }

        let header = splitCSVRow(lines[0])
        func idx(_ name: String) -> Int? {
            header.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }
        }
        let dateIdx = idx("Date")
        let eventIdx = idx("Event") ?? idx("Name")
        let urlIdx = idx("CSV URL") ?? idx("URL")

        let dateParser = makeDateParser()

        return lines.dropFirst().compactMap { row in
            let cols = splitCSVRow(row)
            guard
                let di = dateIdx, di < cols.count,
                let ei = eventIdx, ei < cols.count,
                let ui = urlIdx, ui < cols.count
            else { return nil }

            let dateString = cols[di].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = cols[ei].trimmingCharacters(in: .whitespacesAndNewlines)
            let urlString = cols[ui].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !dateString.isEmpty, !title.isEmpty, let url = URL(string: urlString) else { return nil }
            guard let date = dateParser(dateString) else {
                #if DEBUG
                print("[SpecialScheduleFeed] Unparseable date: \(dateString)")
                #endif
                return nil
            }
            return IndexRow(date: date, title: title, url: url)
        }
    }

    // MARK: Per-event CSV parsing (Start Time, End Time, Block)

    func fetchBlocks(from url: URL) async throws -> [BellBlock] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/csv, text/plain; q=0.8, */*; q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parseBlocksCSV(text: text)
    }

    private func parseBlocksCSV(text: String) -> [BellBlock] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }

        let header = splitCSVRow(lines[0])
        func idx(_ name: String) -> Int? {
            header.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame }
        }
        let startIdx = idx("Start Time") ?? idx("Start")
        let endIdx = idx("End Time") ?? idx("End")
        let blockIdx = idx("Block") ?? idx("Title") ?? idx("Kind")

        guard let si = startIdx, let ei = endIdx, let bi = blockIdx else { return [] }

        let parseTime = makeTimeParser()

        var blocks: [BellBlock] = []
        blocks.reserveCapacity(lines.count - 1)

        for row in lines.dropFirst() {
            let cols = splitCSVRow(row)
            guard cols.count > max(si, max(ei, bi)) else { continue }

            let startRaw = cols[si].trimmingCharacters(in: .whitespacesAndNewlines)
            let endRaw = cols[ei].trimmingCharacters(in: .whitespacesAndNewlines)
            let titleRaw = cols[bi].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !startRaw.isEmpty, !endRaw.isEmpty, !titleRaw.isEmpty else { continue }
            guard let start = parseTime(startRaw), let end = parseTime(endRaw) else {
                #if DEBUG
                print("[SpecialScheduleFeed] Bad times: \(startRaw) - \(endRaw)")
                #endif
                continue
            }

            if let kind = mapBlock(titleRaw) {
                blocks.append(BellBlock(kind: kind, start: start, end: end))
            } else {
                #if DEBUG
                print("[SpecialScheduleFeed] Unknown Block: \(titleRaw)")
                #endif
            }
        }

        // Ensure chronological order
        blocks.sort { a, b in
            (a.start.hour ?? 0, a.start.minute ?? 0) < (b.start.hour ?? 0, b.start.minute ?? 0)
        }
        return blocks
    }

    // MARK: Helpers

    private func splitCSVRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        var i = row.startIndex
        while i < row.endIndex {
            let ch = row[i]
            if ch == "\"" {
                if inQuotes, row.index(after: i) < row.endIndex, row[row.index(after: i)] == "\"" {
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

    private func makeDateParser() -> (String) -> Date? {
        // Accept common spreadsheet formats
        let fmts = [
            "M/d/yyyy", "M/d/yy",
            "MM/dd/yyyy", "MM/dd/yy",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        // Important: interpret sheet dates in the user's current time zone,
        // then normalize to local noon so same-day comparisons are stable.
        df.timeZone = TimeZone.current

        let cal = Calendar.current

        return { s in
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            for f in fmts {
                df.dateFormat = f
                if let d = df.date(from: trimmed) {
                    var comps = cal.dateComponents([.year, .month, .day], from: d)
                    comps.hour = 12; comps.minute = 0; comps.second = 0
                    return cal.date(from: comps)
                }
            }
            return nil
        }
    }

    private func makeTimeParser() -> (String) -> DateComponents? {
        // Accept a handful of time styles
        let fmts = [
            "h:mm a", "h:mma", "hh:mm a", "hh:mma",
            "H:mm", "HH:mm",
            "h a", "ha" // e.g., "8 AM"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        return { s in
            let trimmed = s.replacingOccurrences(of: ".", with: ":")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            for f in fmts {
                df.dateFormat = f
                if let date = df.date(from: trimmed) {
                    let cal = Calendar.current
                    var comps = cal.dateComponents([.hour, .minute], from: date)
                    comps.second = 0
                    return comps
                }
            }
            return nil
        }
    }

    private func mapBlock(_ raw: String) -> BlockKind? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let lower = s.lowercased()

        // Levels: accept "level 1", "l1", "1" (only if explicitly "level" or "l")
        // Prefer explicit forms; avoid mapping bare numbers that might be something else.
        if lower.hasPrefix("level ") {
            let num = lower.replacingOccurrences(of: "level ", with: "")
            return levelFromNumber(num)
        }
        if lower.hasPrefix("l") {
            let num = String(lower.dropFirst())
            return levelFromNumber(num)
        }
        if lower == "music" || lower == "music block" {
            return .level(.music)
        }

        // Specials (accept a few synonyms)
        switch lower {
        case "assembly":
            return .special(.assembly)
        case "office hours", "officehrs", "office-hrs", "office hour":
            return .special(.officeHours)
        case "advisory":
            return .special(.advisory)
        case "worship", "meeting for worship", "meeting for worship (mfw)":
            return .special(.worship)
        case "conscious communities", "cc":
            return .special(.consciousCommunities)
        case "lunch":
            return .special(.lunch)
        case "lunch & clubs", "lunch and clubs":
            return .special(.lunchAndClubs)
        case "music block + clubs", "music & clubs", "music/clubs":
            return .special(.musicClubs)
        default:
            // Try exact Level N as a last attempt: "1", "2", ... "7"
            if let kind = levelFromNumber(lower) { return kind }
            return nil
        }
    }

    private func levelFromNumber(_ raw: String) -> BlockKind? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case "1", "01": return .level(.level1)
        case "2", "02": return .level(.level2)
        case "3", "03": return .level(.level3)
        case "4", "04": return .level(.level4)
        case "5", "05": return .level(.level5)
        case "6", "06": return .level(.level6)
        case "7", "07": return .level(.level7)
        default: return nil
        }
    }
}
