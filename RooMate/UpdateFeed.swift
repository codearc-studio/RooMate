import Foundation

struct UpdateAnnouncement: Identifiable, Equatable, Codable {
    let id: String
    let visible: Bool
    let updateNumber: String
    let changelog: String
    let url: URL?

    nonisolated init(visible: Bool, updateNumber: String, changelog: String, urlString: String?) {
        self.visible = visible
        self.updateNumber = updateNumber
        self.changelog = changelog
        if let s = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            self.url = URL(string: s)
        } else {
            self.url = nil
        }
        self.id = updateNumber
    }
}

actor UpdateFeed {

    // Dedicated URLSession tuned for this CSV fetch.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Keep connection count modest; we only fetch one resource here.
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    func fetch(from url: URL) async throws -> [UpdateAnnouncement] {
        // One retry on transient failures.
        let maxAttempts = 2
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                // Hint the content type we expect; Google’s published CSV responds fine to this.
                req.setValue("text/csv, text/plain; q=0.8, */*; q=0.5", forHTTPHeaderField: "Accept")

                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                // Treat 5xx as transient; 4xx as final.
                if !(200..<300).contains(http.statusCode) {
                    if (500..<600).contains(http.statusCode), attempt < maxAttempts {
                        try await Task.sleep(nanoseconds: 750_000_000) // 0.75s backoff
                        continue
                    }
                    throw URLError(.badServerResponse)
                }

                guard let text = String(data: data, encoding: .utf8) else { return [] }
                let parsed = parseCSV(text: text)
                #if DEBUG
                print("UpdateFeed: parsed \(parsed.count) announcements")
                #endif
                return parsed
            } catch {
                lastError = error
                // Retry on transient URL errors.
                if let urlError = error as? URLError, isTransient(urlError.code), attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 750_000_000) // 0.75s backoff
                    continue
                }
                break
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func isTransient(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func parseCSV(text: String) -> [UpdateAnnouncement] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else { return [] }

        let header = splitCSVRow(lines[0])
        func index(of name: String) -> Int? {
            header.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        }
        guard
            let visIdx = index(of: "Visibility"),
            let numIdx = index(of: "Update Number"),
            let logIdx = index(of: "Changelog"),
            let urlIdx = index(of: "URL")
        else {
            return lines.dropFirst().compactMap { row in
                let cols = splitCSVRow(row)
                guard cols.count >= 4 else { return nil }
                return makeAnnouncement(cols[0], cols[1], cols[2], cols[3])
            }
        }

        return lines.dropFirst().compactMap { row in
            let cols = splitCSVRow(row)
            guard cols.count > max(visIdx, numIdx, logIdx, urlIdx) else { return nil }
            return makeAnnouncement(cols[visIdx], cols[numIdx], cols[logIdx], cols[urlIdx])
        }
    }

    private func makeAnnouncement(_ vis: String, _ num: String, _ log: String, _ url: String) -> UpdateAnnouncement? {
        let v = vis.trimmingCharacters(in: .whitespacesAndNewlines)
        // Accept exactly "Visible" (case-insensitive); this is your current sheet content.
        let visible = v.caseInsensitiveCompare("Visible") == .orderedSame
        let number = num.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else { return nil }
        let changelog = log.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpdateAnnouncement(visible: visible, updateNumber: number, changelog: changelog, urlString: urlString)
    }

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
