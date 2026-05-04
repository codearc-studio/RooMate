import Foundation

struct UpdateAnnouncement: Identifiable, Equatable, Codable {
    let id: String
    let visible: Bool
    let updateNumber: String
    let changelog: String
    let url: URL?

    init(visible: Bool, updateNumber: String, changelog: String, urlString: String?) {
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
    func fetch(from url: URL) async throws -> [UpdateAnnouncement] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parseCSV(text: text)
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
