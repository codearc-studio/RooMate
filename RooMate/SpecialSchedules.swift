import SwiftUI
import Foundation

struct SpecialSchedule: Identifiable, Hashable {
    let id: UUID
    let title: String
    let notes: String
    let applicableDays: Set<Weekday>
    let blocks: [BellBlock]

    init(id: UUID = UUID(),
         title: String,
         notes: String = "",
         applicableDays: Set<Weekday>,
         blocks: [BellBlock]) {
        self.id = id
        self.title = title
        self.notes = notes
        self.applicableDays = applicableDays
        self.blocks = blocks
    }
}

enum SpecialSchedules {

    // Helper to create BellBlock times from strings
    private static func time(_ string: String) -> DateComponents {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        guard let date = formatter.date(from: string) else {
            return DateComponents(hour: 0, minute: 0)
        }
        let cal = Calendar.current
        return cal.dateComponents([.hour, .minute], from: date)
    }

    private static func level(_ level: Level, _ start: String, _ end: String) -> BellBlock {
        BellBlock(kind: .level(level), start: time(start), end: time(end))
    }

    private static func special(_ kind: SpecialBlock, _ start: String, _ end: String) -> BellBlock {
        BellBlock(kind: .special(kind), start: time(start), end: time(end))
    }

    // Example special schedules (read-only for now)
    static let all: [SpecialSchedule] = [
        SpecialSchedule(
            title: "Assembly Day (Shortened)",
            notes: "Shortened periods with extended Assembly.",
            applicableDays: [.monday, .tuesday, .thursday],
            blocks: [
                special(.assembly, "8:00 AM", "8:25 AM"),
                level(.level1, "8:28 AM", "9:05 AM"),
                level(.level7, "9:08 AM", "9:45 AM"),
                special(.officeHours, "9:48 AM", "10:05 AM"),
                level(.level4, "10:08 AM", "10:45 AM"),
                level(.level6, "10:48 AM", "11:25 AM"),
                special(.lunch, "11:28 AM", "12:05 PM"),
                level(.level3, "12:08 PM", "12:45 PM"),
                level(.level5, "12:48 PM", "1:25 PM"),
                special(.advisory, "1:28 PM", "2:00 PM")
            ]
        ),
        SpecialSchedule(
            title: "Late Start",
            notes: "Classes begin at 9:30 AM.",
            applicableDays: [.wednesday],
            blocks: [
                level(.level6, "9:30 AM", "10:12 AM"),
                level(.level2, "10:15 AM", "10:57 AM"),
                special(.officeHours, "11:00 AM", "11:15 AM"),
                level(.level5, "11:18 AM", "12:00 PM"),
                special(.lunch, "12:03 PM", "12:40 PM"),
                level(.level3, "12:43 PM", "1:25 PM"),
                level(.level4, "1:28 PM", "2:10 PM"),
                level(.level7, "2:13 PM", "3:00 PM")
            ]
        ),
        SpecialSchedule(
            title: "Half Day",
            notes: "Dismissal at 12:30 PM.",
            applicableDays: [.friday],
            blocks: [
                level(.music, "8:00 AM", "8:40 AM"),
                level(.level3, "8:43 AM", "9:23 AM"),
                level(.level5, "9:26 AM", "10:06 AM"),
                special(.officeHours, "10:09 AM", "10:20 AM"),
                level(.level2, "10:23 AM", "11:03 AM"),
                level(.level4, "11:06 AM", "11:46 AM"),
                special(.lunch, "11:46 AM", "12:30 PM")
            ]
        )
    ]

    static func forDay(_ day: Weekday) -> [SpecialSchedule] {
        all.filter { $0.applicableDays.contains(day) }
    }
}

// MARK: - Small helpers for formatting preview text

extension SpecialSchedule {
    func timeSummary() -> String {
        guard let first = blocks.first, let last = blocks.last else { return "—" }

        func format(_ comps: DateComponents) -> String {
            var comps = comps
            comps.second = 0
            let cal = Calendar.current
            guard let date = cal.date(from: comps) else { return "—" }
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: date)
        }

        return "\(format(first.start)) – \(format(last.end))"
    }

    func firstBlockTitle(using store: UserScheduleStore) -> (title: String, color: Color)? {
        guard let first = blocks.first else { return nil }
        switch first.kind {
        case .level(let level):
            let a = store.assignment(for: level)
            return (a.title, a.color.swiftUIColor)
        case .special(let sp):
            return (sp.title, store.color(for: sp))
        }
    }
}
