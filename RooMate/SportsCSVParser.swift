import Foundation

enum SportsCSVParser {
    // Basic robust CSV parser that supports quoted fields and commas inside quotes.
    static func parseCSV(_ data: Data, assumingUTF8: Bool = true) -> [[String]] {
        let str: String
        if assumingUTF8, let s = String(data: data, encoding: .utf8) { str = s }
        else if let s = String(data: data, encoding: .ascii) { str = s }
        else { str = String(data: data, encoding: .utf8) ?? "" }

        var rows: [[String]] = []
        var currentField = ""
        var currentRow: [String] = []
        var inQuotes = false
        let characters = Array(str)
        var i = 0
        while i < characters.count {
            let c = characters[i]
            if c == Character("\"") {
                // If quote and next is quote, it's an escaped quote
                if inQuotes && i + 1 < characters.count && characters[i + 1] == Character("\"") {
                    currentField.append("\"")
                    i += 1
                } else {
                    inQuotes.toggle()
                }
            } else if c == Character(",") && !inQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if (c == Character("\n") || c == Character("\r")) && !inQuotes {
                // handle CRLF by peeking next
                // End of row
                // Only push non-empty row separator once
                // If CR followed by LF skip the LF
                if c == Character("\r") && i + 1 < characters.count && characters[i + 1] == Character("\n") {
                    i += 1
                }
                currentRow.append(currentField)
                currentField = ""
                // Only push row if it's not an empty single-field row produced by trailing newline
                rows.append(currentRow)
                currentRow = []
            } else {
                currentField.append(c)
            }
            i += 1
        }
        // append final field/row
        if inQuotes == false {
            currentRow.append(currentField)
            if !currentRow.isEmpty { rows.append(currentRow) }
        }
        return rows
    }

    static func rowsToDictionaries(_ rows: [[String]]) -> [[String: String]] {
        guard !rows.isEmpty else { return [] }
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out: [[String: String]] = []
        for i in 1..<rows.count {
            let row = rows[i]
            // skip rows that look like metadata "Last Update:" or empty first cell
            let first = row.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if first.isEmpty { continue }
            if first.lowercased().starts(with: "last update") { continue }
            var dict: [String: String] = [:]
            for (j, colName) in header.enumerated() {
                let value = j < row.count ? row[j] : ""
                dict[colName] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            out.append(dict)
        }
        return out
    }

    static func parseSportsGames(from data: Data) -> [SportsGame] {
        let rows = parseCSV(data)
        let dicts = rowsToDictionaries(rows)
        var games: [SportsGame] = []

        // Date parsing: try multiple formats, but do not require successful parse for inclusion
        let fmts = ["M/d/yyyy", "M/d/yy", "yyyy-MM-dd", "MMMM d, yyyy"]
        let formatters: [DateFormatter] = fmts.map {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
        }

        for dict in dicts {
            // We consider a row valid only if the Date column exists and is non-empty
            guard let rawDate = dict["Date"], !rawDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            // ignore rows like "Last Update: ..."
            if rawDate.lowercased().starts(with: "last update") { continue }

            var parsedDate: Date? = nil
            for f in formatters {
                if let d = f.date(from: rawDate) { parsedDate = d; break }
            }

            let day = dict["Day"] ?? ""
            let team = dict["Team"] ?? ""
            let opponent = dict["Opponent"] ?? ""
            let location = dict["A/H"] ?? dict["A/H "] ?? ""
            let time = dict["Time"] ?? ""
            let dismiss = dict["Dismiss"] ?? ""
            let ret = dict["Return"] ?? ""
            let notes = dict["Notes"] ?? ""

            let game = SportsGame(rawDateString: rawDate, date: parsedDate, day: day, team: team, opponent: opponent, location: location, time: time, dismiss: dismiss, return: ret, notesRaw: notes)
            games.append(game)
        }
        return games
    }
}
