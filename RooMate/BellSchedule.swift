import SwiftUI
import Foundation

struct BellSchedule {
    static let weekly: [Weekday: [BellBlock]] = [
        .monday: [
            special(.assembly, "8:00 AM", "8:10 AM"),
            level(.level1, "8:15 AM", "9:02 AM"),
            level(.level7, "9:05 AM", "10:02 AM"),
            special(.officeHours, "10:05 AM", "10:22 AM"),
            level(.level4, "10:25 AM", "11:12 AM"),
            level(.level6, "11:15 AM", "12:12 PM"),
            special(.musicClubs, "12:15 PM", "12:52 PM"),
            special(.lunch, "12:55 PM", "1:27 PM"),
            level(.level3, "1:30 PM", "2:17 PM"),
            level(.level5, "2:20 PM", "3:10 PM")
        ],
        .tuesday: [
            special(.assembly, "8:00 AM", "8:10 AM"),
            level(.level7, "8:15 AM", "9:02 AM"),
            level(.level4, "9:05 AM", "10:02 AM"),
            special(.officeHours, "10:05 AM", "10:22 AM"),
            level(.music, "10:25 AM", "11:12 AM"),
            level(.level1, "11:15 AM", "12:12 PM"),
            special(.advisory, "12:15 PM", "12:52 PM"),
            special(.lunch, "12:55 PM", "1:27 PM"),
            level(.level6, "1:30 PM", "2:17 PM"),
            level(.level2, "2:20 PM", "3:10 PM")
        ],
        .wednesday: [
            level(.level6, "8:00 AM", "8:52 AM"),
            level(.level2, "8:55 AM", "9:52 AM"),
            special(.officeHours, "9:55 AM", "10:12 AM"),
            level(.level5, "10:15 AM", "11:02 AM"),
            level(.level3, "11:05 AM", "11:52 AM"),
            special(.worship, "11:55 AM", "12:30 PM"),
            special(.lunchAndClubs, "12:30 PM", "1:30 PM"),
            level(.level4, "1:30 PM", "2:17 PM"),
            level(.level7, "2:20 PM", "3:10 PM")
        ],
        .thursday: [
            special(.assembly, "8:00 AM", "8:10 AM"),
            level(.level3, "8:15 AM", "9:02 AM"),
            level(.level5, "9:05 AM", "10:02 AM"),
            special(.officeHours, "10:05 AM", "10:22 AM"),
            level(.music, "10:25 AM", "11:12 AM"),
            level(.level1, "11:15 AM", "12:12 PM"),
            special(.consciousCommunities, "12:15 PM", "12:52 PM"),
            special(.lunch, "12:55 PM", "1:27 PM"),
            level(.level2, "1:30 PM", "2:17 PM"),
            level(.level6, "2:20 PM", "3:10 PM")
        ],
        .friday: [
            level(.music, "8:00 AM", "8:57 AM"),
            level(.level3, "9:00 AM", "9:57 AM"),
            level(.level5, "10:00 AM", "10:47 AM"),
            special(.officeHours, "10:50 AM", "11:02 AM"),
            level(.level2, "11:05 AM", "11:52 AM"),
            level(.level4, "11:55 AM", "12:42 PM"),
            special(.lunch, "12:45 PM", "1:27 PM"),
            level(.level7, "1:30 PM", "2:17 PM"),
            level(.level1, "2:20 PM", "3:10 PM")
        ]
    ]

    private static func time(_ string: String) -> DateComponents {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        guard let date = formatter.date(from: string) else {
            return DateComponents(hour: 0, minute: 0)
        }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return comps
    }

    private static func level(_ level: Level, _ start: String, _ end: String) -> BellBlock {
        BellBlock(kind: .level(level), start: time(start), end: time(end))
    }

    private static func special(_ kind: SpecialBlock, _ start: String, _ end: String) -> BellBlock {
        BellBlock(kind: .special(kind), start: time(start), end: time(end))
    }
}
