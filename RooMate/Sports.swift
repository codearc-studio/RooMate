import Foundation
import SwiftUI

// Model representing a single sports game/event parsed from CSV
struct SportsGame: Identifiable, Hashable {
    enum Status: String, Codable {
        case scheduled
        case cancelled
        case rescheduled
        case conditional
        case eliminated
    }

    let id = UUID()
    let rawDateString: String
    let date: Date?
    let day: String
    let team: String
    let opponent: String
    let location: String // A or H or other
    let time: String
    let dismiss: String
    let `return`: String
    let notesRaw: String

    var notesFormatted: String { SportsHelpers.formatNotes(notesRaw) }

    var status: Status {
        SportsHelpers.inferStatus(from: notesRaw)
    }

    init(rawDateString: String = "", date: Date? = nil, day: String = "", team: String = "", opponent: String = "", location: String = "", time: String = "", dismiss: String = "", `return`: String = "", notesRaw: String = "") {
        self.rawDateString = rawDateString
        self.date = date
        self.day = day
        self.team = team
        self.opponent = opponent
        self.location = location
        self.time = time
        self.dismiss = dismiss
        self.`return` = `return`
        self.notesRaw = notesRaw
    }
}

/// Helpers used for parsing and formatting sports CSV data
enum SportsHelpers {
    static func formatNotes(_ notes: String) -> String {
        // Trim whitespace and newlines
        var s = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Replace internal newlines with spaces
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: "\r", with: " ")
        // Collapse multiple spaces
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        guard !s.isEmpty else { return "" }
        // Lowercase everything then uppercase first character only
        let lower = s.lowercased()
        let first = lower.prefix(1).uppercased()
        let rest = lower.dropFirst()
        return first + rest
    }

    static func inferStatus(from notes: String) -> SportsGame.Status {
        let lower = notes.lowercased()
        if lower.contains("canceled") || lower.contains("cancelled") { return .cancelled }
        if lower.contains("rescheduled") { return .rescheduled }
        if lower.contains("if win") || lower.contains("tentative") { return .conditional }
        if lower.contains("did not advance") { return .eliminated }
        return .scheduled
    }
}
