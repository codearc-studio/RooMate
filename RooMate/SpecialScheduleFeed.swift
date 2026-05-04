import Foundation

struct DatedSpecialSchedule: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let title: String
    let url: URL
    let blocks: [BellBlock]
}

actor SpecialScheduleFeed {

    // Public entry: fetch everything from the index sheet URL.
    func fetchAll(from indexURL: URL) async throws -> [DatedSpecialSchedule] {
        let rows = try await fetchIndex(from: indexURL)
        var results: [DatedSpecialSchedule] = []
        results.reserveCapacity(rows.count)

        try await withThrowingTaskGroup(of: DatedSpecialSchedule?.self) { group in
            for row in rows {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        let blocks = try await self.fetchBlocks(from: row.csvURL)
                        return DatedSpecialSchedule(date: row.date, title: row.title, url: row.csvURL, blocks: blocks)
                    } catch {
                        #if DEBUG
                        print("[SpecialScheduleFeed] Failed blocks for \(row.title) at \(row.csvURL): \(error)")
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

    // MARK: - Index sheet parsing (Date, Event, CSV URL)

    private struct IndexRow {
        let date: Date
        let title: String
        let csvURL: URL
    }

    private let indexSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private func fetchIndex(from url: URL) async throws -> [IndexRow] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/csv, text/plain; q=0.8, */*; q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await indexSession.data(for: req)
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

        func index(of name: String) -> Int? {
            header.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        let dateIdx = index(of: "Date")
        let titleIdx = index(of: "Event")
        let urlIdx = index(of: "CSV URL")

        var rows: [IndexRow] = []
        rows.reserveCapacity(max(0, lines.count - 1))

        for row in lines.dropFirst() {
            let cols = splitCSVRow(row)
            if let di = dateIdx, let ti = titleIdx, let ui = urlIdx, cols.count > max(di, max(ti, ui)) {
                let dateString = cols[di].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = cols[ti].trimmingCharacters(in: .whitespacesAndNewlines)
                let urlString = cols[ui].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dateString.isEmpty, !title.isEmpty, let url = URL(string: urlString) else { continue }
                if let date = parseIndexDate(dateString) {
                    rows.append(IndexRow(date: date, title: title, csvURL: url))
                }
            } else if cols.count >= 3 {
                // Fallback by position
                let dateString = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
                let urlString = cols[2].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !dateString.isEmpty, !title.isEmpty, let url = URL(string: urlString) else { continue }
                if let date = parseIndexDate(dateString) {
                    rows.append(IndexRow(date: date, title: title, csvURL: url))
                }
            }
        }
        return rows
    }

    private func parseIndexDate(_ s: String) -> Date? {
        // Support common sheet formats: M/D/YYYY, M/D/YY, MMM D, YYYY
        let fmts = ["M/d/yyyy", "M/d/yy", "MMM d, yyyy", "MMMM d, yyyy", "yyyy-MM-dd"]
        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = f
            if let d = df.date(from: s) {
                return d
            }
        }
        return nil
    }

    // MARK: - Per-event CSV parsing (Start Time, End Time, Block)

    private let blocksSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func fetchBlocks(from url: URL) async throws -> [BellBlock] {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("text/csv, text/plain; q=0.8, */*; q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await blocksSession.data(for: req)
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

        func index(of name: String) -> Int? {
            header.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        }

        let startIdx = index(of: "Start Time")
        let endIdx = index(of: "End Time")
        let blockIdx = index(of: "Block")

        var blocks: [BellBlock] = []
        blocks.reserveCapacity(max(0, lines.count - 1))

        for row in lines.dropFirst() {
            let cols = splitCSVRow(row)

            let sVal: String?
            let eVal: String?
            let bVal: String?

            if let si = startIdx, let ei = endIdx, let bi = blockIdx, cols.count > max(si, max(ei, bi)) {
                sVal = cols[si]
                eVal = cols[ei]
                bVal = cols[bi]
            } else if cols.count >= 3 {
                sVal = cols[0]
                eVal = cols[1]
                bVal = cols[2]
            } else {
                continue
            }

            let startStr = (sVal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let endStr = (eVal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let blockStr = (bVal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !startStr.isEmpty, !endStr.isEmpty, !blockStr.isEmpty else { continue }
            guard let kind = mapBlockKind(blockStr) else {
                #if DEBUG
                print("[SpecialScheduleFeed] Unknown block '\(blockStr)'")
                #endif
                continue
            }
            guard let startComps = parseTime(startStr), let endComps = parseTime(endStr) else {
                #if DEBUG
                print("[SpecialScheduleFeed] Time parse failed: \(startStr) - \(endStr)")
                #endif
                continue
            }

            blocks.append(BellBlock(kind: kind, start: startComps, end: endComps))
        }

        // Ensure chronological order just in case
        return blocks.sorted { (a, b) in
            let ah = a.start.hour ?? 0, am = a.start.minute ?? 0
            let bh = b.start.hour ?? 0, bm = b.start.minute ?? 0
            return (ah, am) < (bh, bm)
        }
    }

    // Accept several time formats commonly seen in sheets.
    private func parseTime(_ s: String) -> DateComponents? {
        let candidates = [
            "h:mm a", "h:mma", "hh:mm a", "hh:mma",
            "H:mm", "HH:mm",
            "h a", "ha"
        ]
        for f in candidates {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if let date = df.date(from: s) {
                let cal = Calendar.current
                return cal.dateComponents([.hour, .minute], from: date)
            }
        }
        return nil
    }

    // Map “Block” strings to Level or SpecialBlock.
    private func mapBlockKind(_ raw: String) -> BlockKind? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // Levels – allow variations like "level 1", "l1", "1"
        if let level = parseLevel(from: lower) {
            return .level(level)
        }

        // Specials – normalize a few synonyms
        switch lower {
        case "assembly":
            return .special(.assembly)
        case "office hours", "officehours":
            return .special(.officeHours)
        case "advisory":
            return .special(.advisory)
        case "worship", "meeting for worship", "meetingforworship":
            return .special(.worship)
        case "conscious communities", "conscious-communities", "consciouscommunities":
            return .special(.consciousCommunities)
        case "lunch":
            return .special(.lunch)
        case "lunch & clubs", "lunch and clubs", "lunchandclubs":
            return .special(.lunchAndClubs)
        case "music block + clubs", "music block and clubs", "musicblock+clubs", "musicblockandclubs", "music clubs":
            return .special(.musicClubs)
        default:
            return nil
        }
    }

    private func parseLevel(from lower: String) -> Level? {
        // Try exact "music"
        if lower == "music" || lower == "music block" || lower == "musicblock" {
            return .music
        }

        // Extract a trailing digit for "level X", "lX", or just "X"
        // e.g., "level 1", "l1", "1"
        if lower.hasPrefix("level ") || lower.hasPrefix("level") {
            if let num = numberSuffix(in: lower) { return levelFrom(num) }
        }
        if lower.hasPrefix("l") {
            if let num = numberSuffix(in: lower) { return levelFrom(num) }
        }
        if let num = Int(lower) {
            return levelFrom(num)
        }
        return nil
    }

    private func numberSuffix(in s: String) -> Int? {
        let digits = s.compactMap { $0.isNumber ? Int(String($0)) : nil }
        guard let first = digits.first else { return nil }
        return first
    }

    private func levelFrom(_ n: Int) -> Level? {
        switch n {
        case 1: return .level1
        case 2: return .level2
        case 3: return .level3
        case 4: return .level4
        case 5: return .level5
        case 6: return .level6
        case 7: return .level7
        default: return nil
        }
    }

    // RFC4180-ish CSV row splitter handling quotes and commas
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
}
