import SwiftUI
import Combine

struct DashboardView: View {
    @ObservedObject var store: UserScheduleStore

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Determine today's weekday
    private var todayWeekday: Weekday {
        let cal = Calendar.current
        switch cal.component(.weekday, from: Date()) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .monday
        }
    }

    private var isWeekend: Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7 // Sunday or Saturday
    }

    private var isAfterSchool: Bool {
        let blocks = todayBlocks
        guard !blocks.isEmpty, let lastBlock = blocks.last else { return false }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        
        var endComps = cal.dateComponents([.year, .month, .day], from: startOfDay)
        endComps.hour = lastBlock.end.hour
        endComps.minute = lastBlock.end.minute
        endComps.second = 0
        
        guard let schoolEndTime = cal.date(from: endComps) else { return false }
        return now >= schoolEndTime
    }

    private var nextSchoolDay: Weekday {
        if isWeekend {
            return .monday
        }
        
        if isAfterSchool {
            // After school on a weekday, next school day is tomorrow
            switch todayWeekday {
            case .monday: return .tuesday
            case .tuesday: return .wednesday
            case .wednesday: return .thursday
            case .thursday: return .friday
            case .friday: return .monday
            }
        }
        
        return todayWeekday
    }

    // Today’s blocks come from the weekly bell schedule
    private var todayBlocks: [BellBlock] {
        BellSchedule.weekly[todayWeekday] ?? []
    }

    // Lightweight copy of DayScheduleView’s date mapping for “today”
    private struct DatedBlock: Identifiable {
        let id = UUID()
        let original: BellBlock
        let startDate: Date
        let endDate: Date
    }

    private func datedBlocks(for reference: Date) -> [DatedBlock] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: reference)

        let result: [DatedBlock] = todayBlocks.compactMap { (block: BellBlock) -> DatedBlock? in
            var startComps = cal.dateComponents([.year, .month, .day], from: startOfDay)
            startComps.hour = block.start.hour
            startComps.minute = block.start.minute
            startComps.second = 0

            var endComps = cal.dateComponents([.year, .month, .day], from: startOfDay)
            endComps.hour = block.end.hour
            endComps.minute = block.end.minute
            endComps.second = 0

            guard let s = cal.date(from: startComps), let e = cal.date(from: endComps) else { return nil }
            return DatedBlock(original: block, startDate: s, endDate: e)
        }.sorted(by: { $0.startDate < $1.startDate })

        // debug logging removed
        return result
    }

    private func blockTitleColorSubtitle(for block: BellBlock) -> (title: String, color: Color, subtitle: String, level: Level?, specialLabel: String?) {
        switch block.kind {
        case .level(let level):
            let a = store.assignment(for: level)
            // For Music Block, check for special block replacements and color
            let title = level == .music ? (store.displayMusicTitle(on: todayWeekday) ?? a.displayTitle(for: level, on: todayWeekday)) : a.displayTitle(for: level, on: todayWeekday)
            let color = level == .music ? store.color(for: .musicClubs) : a.displayColor(on: todayWeekday)
            // Don't show subtitle for Music Block (it's a special block and doesn't need description)
            let subtitle = level == .music ? "" : a.displaySubtitle(on: todayWeekday)
            return (title, color, subtitle, level, nil)
        case .special(let sp):
            // Use the user-customizable color and display methods for special blocks
            return (store.displayTitle(for: sp, on: todayWeekday), store.color(for: sp), "", nil, sp.title)
        }
    }

    // Tolerance to avoid flicker at exact boundaries
    private let boundaryTolerance: TimeInterval = 1.0

    private func currentHeaderInfo(on reference: Date) -> (title: String, subtitle: String, color: Color, progress: Double, remainingText: String, nextTitle: String?, nextStartText: String?, nextColor: Color?, nextLevel: Level?, nextSpecialLabel: String?, isCountdownMode: Bool)? {
        let list = datedBlocks(for: reference)
        guard !list.isEmpty else {
            #if DEBUG
            print("[Dashboard] No blocks for header at", timeString(reference))
            #endif
            return nil
        }

        // Apply a small epsilon so that times exactly on the boundary are stable
        let ref = reference.addingTimeInterval(0) // keep as-is but use tolerance below

        // Find current or next
        var current: DatedBlock?
        var next: DatedBlock?

        for (idx, item) in list.enumerated() {
            // Inclusive start, exclusive end, but allow a small tolerance
            if (ref >= item.startDate.addingTimeInterval(-boundaryTolerance)) && (ref < item.endDate.addingTimeInterval(boundaryTolerance)) {
                current = item
                if idx + 1 < list.count { next = list[idx + 1] }
                break
            }
            if ref < item.startDate.addingTimeInterval(boundaryTolerance) {
                current = nil
                next = item
                break
            }
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "h:mm a"

        if let current {
            let total: TimeInterval = max(1.0, current.endDate.timeIntervalSince(current.startDate))
            let elapsed: TimeInterval = max(0.0, ref.timeIntervalSince(current.startDate))
            let remaining: TimeInterval = max(0.0, current.endDate.timeIntervalSince(ref))
            let progress = max(0.0, min(1.0, elapsed / total))

            let (title, color, subtitle, _, _) = blockTitleColorSubtitle(for: current.original)
            let remainingText = "Ends in " + formatDuration(remaining)

            var nextTitleStr: String?
            var nextStartText: String?
            var nextColor: Color?
            var nextLevel: Level?
            var nextSpecialLabel: String?
            if let next {
                let (ntitle, ncolor, _, nlevel, nspecialLabel) = blockTitleColorSubtitle(for: next.original)
                nextTitleStr = ntitle
                nextColor = ncolor
                nextLevel = nlevel
                nextSpecialLabel = nspecialLabel
                nextStartText = "Starts at " + df.string(from: next.startDate)
            }

            return (title, subtitle, color, progress, remainingText, nextTitleStr, nextStartText, nextColor, nextLevel, nextSpecialLabel, false)
        }

        if let next {
            // Countdown mode to next
            let list = datedBlocks(for: ref)
            var anchor: Date = Calendar.current.startOfDay(for: next.startDate)
            if let idx = list.firstIndex(where: { $0.id == next.id }), idx > 0 {
                anchor = list[idx - 1].endDate
            }

            let remaining: TimeInterval = max(0.0, next.startDate.timeIntervalSince(ref))
            let totalGap: TimeInterval = max(1.0, next.startDate.timeIntervalSince(anchor))
            let elapsedGap: TimeInterval = max(0.0, ref.timeIntervalSince(anchor))
            let progress = max(0.0, min(1.0, elapsedGap / totalGap))

            let (ntitle, ncolor, _, nlevel, nspecialLabel) = blockTitleColorSubtitle(for: next.original)

            return ("No class right now", "Starts soon", .secondary, progress, "Starts in " + formatDuration(remaining), ntitle, "Starts at " + df.string(from: next.startDate), ncolor, nlevel, nspecialLabel, true)
        }

        // debug logging removed
        return nil
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remMin = minutes % 60
            return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
        } else if minutes > 0 {
            return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    var body: some View {
        if isWeekend {
            weekendView
        } else if isAfterSchool {
            afterSchoolView
        } else {
            weekdayView
        }
    }

    private var weekdayView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // Premium header
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("Today")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Your Schedule")
                        .font(DesignTokens.Typography.headline2)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                // Current block section
                if let info = currentHeaderInfo(on: now) {
                    CurrentBlockHeader(
                        title: info.title,
                        subtitle: info.subtitle,
                        color: info.color,
                        progress: info.progress,
                        remainingText: info.remainingText,
                        nextTitle: info.nextTitle,
                        nextStartText: info.nextStartText,
                        nextColor: info.nextColor,
                        nextLevel: info.nextLevel,
                        nextSpecialLabel: info.nextSpecialLabel,
                        style: store.cardColorStyle,
                        isCountdownMode: info.isCountdownMode
                    )
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    .id(info.title + (info.isCountdownMode ? "-countdown" : ""))
                    .animation(DesignTokens.Animation.smooth, value: info.title)
                }

                // Quick stats
                HStack(spacing: DesignTokens.Spacing.md) {
                    StatCard(
                                label: "Classes Left",
                                value: "\(classesLeftCount)",
                        systemImage: "book.fill",
                        color: DesignTokens.Colors.primary
                    )
                    
                    StatCard(
                        label: "Free Time Left",
                        value: calculateFreeTimeLeft(),
                        systemImage: "hourglass",
                        color: DesignTokens.Colors.success
                    )
                    
                    StatCard(
                        label: "Day Progress",
                        value: "\(Int(dayProgress * 100))%",
                        systemImage: "chart.bar.fill",
                        color: DesignTokens.Colors.accent
                    )
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .animation(DesignTokens.Animation.smooth, value: classesLeftCount)

                // Today's schedule preview
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("Today's Classes")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                    
                    VStack(spacing: DesignTokens.Spacing.sm) {
                        ForEach(actualClassesOnly) { block in
                            // Find the dated version of this block for today so we can tell if it's already happened
                            let dated = datedBlocks(for: now).first(where: { $0.original.kind == block.kind })
                            let isPast = dated.map { now >= $0.endDate } ?? false

                            SchedulePreviewRow(
                                block: block,
                                store: store,
                                weekday: todayWeekday,
                                time: formatBlockTime(block: block),
                                isPast: isPast
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .animation(DesignTokens.Animation.smooth, value: actualClassesOnly.count)
                }

                Spacer(minLength: DesignTokens.Spacing.lg)
            }
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
        .onReceive(timer) {
            now = $0
        }
    }

    private var weekendView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // Weekend header
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("Weekend")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Time Off")
                        .font(DesignTokens.Typography.headline2)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)

                // Weekend message
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: "sun.max.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("Enjoy your weekend!")
                                .font(DesignTokens.Typography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            
                            Text("You've earned a break")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                .padding(DesignTokens.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(Color.orange.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .stroke(Color.orange.opacity(0.20), lineWidth: 1.2)
                )
                .padding(.horizontal, DesignTokens.Spacing.lg)

                // Next school day preview
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("Next School Day")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                    
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text(nextSchoolDay.title)
                            .font(DesignTokens.Typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                        
                        // Next day stats
                        HStack(spacing: DesignTokens.Spacing.md) {
                            StatCard(
                                label: "Classes",
                                value: "\(nextDayClassesCount)",
                                systemImage: "book.fill",
                                color: DesignTokens.Colors.primary
                            )
                            
                            StatCard(
                                label: "Free Time",
                                value: calculateFreeTimeForDay(nextSchoolDay),
                                systemImage: "hourglass",
                                color: DesignTokens.Colors.success
                            )
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            ForEach(nextDayActualClassesOnly) { block in
                                    SchedulePreviewRow(
                                            block: block,
                                            store: store,
                                            weekday: nextSchoolDay,
                                            time: formatBlockTime(block: block),
                                            isPast: false
                                        )
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.lg)
            }
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
    }

    private var afterSchoolView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                // After-school header (similar to weekend card but different text)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: "clock.fill")
                            .font(.title2)
                            .foregroundStyle(DesignTokens.Colors.accent)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("After School")
                                .font(DesignTokens.Typography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text("School's over for today — here's what's next")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
                .padding(DesignTokens.Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(DesignTokens.Colors.accent.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .stroke(DesignTokens.Colors.accent.opacity(0.20), lineWidth: 1.2)
                )
                .padding(.horizontal, DesignTokens.Spacing.lg)

                // Next school day preview
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("Next School Day")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                    
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text(nextSchoolDay.title)
                            .font(DesignTokens.Typography.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                        
                        // Next day stats
                        HStack(spacing: DesignTokens.Spacing.md) {
                            StatCard(
                                label: "Classes",
                                value: "\(nextDayClassesCount)",
                                systemImage: "book.fill",
                                color: DesignTokens.Colors.primary
                            )
                            
                            StatCard(
                                label: "Free Time",
                                value: calculateFreeTimeForDay(nextSchoolDay),
                                systemImage: "hourglass",
                                color: DesignTokens.Colors.success
                            )
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                        
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            ForEach(nextDayActualClassesOnly) { block in
                                SchedulePreviewRow(
                                    block: block,
                                    store: store,
                                    weekday: nextSchoolDay,
                                    time: formatBlockTime(block: block),
                                    isPast: false
                                )
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.lg)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.lg)
            }
            .padding(.vertical, DesignTokens.Spacing.lg)
        }
    }

    private var dayProgress: Double {
        let blocks = todayBlocks
        guard !blocks.isEmpty else { return 0.0 }
        
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        
        // Get the first block's start time
        guard let firstBlock = blocks.first else { return 0.0 }
        var startComps = cal.dateComponents([.year, .month, .day], from: startOfDay)
        startComps.hour = firstBlock.start.hour
        startComps.minute = firstBlock.start.minute
        startComps.second = 0
        
        // Get the last block's end time
        guard let lastBlock = blocks.last else { return 0.0 }
        var endComps = cal.dateComponents([.year, .month, .day], from: startOfDay)
        endComps.hour = lastBlock.end.hour
        endComps.minute = lastBlock.end.minute
        endComps.second = 0
        
        guard let progressStart = cal.date(from: startComps),
              let progressEnd = cal.date(from: endComps) else { return 0.0 }
        
        let totalSeconds = progressEnd.timeIntervalSince(progressStart)
        let elapsedSeconds = now.timeIntervalSince(progressStart)
        
        return min(1.0, max(0.0, elapsedSeconds / totalSeconds))
    }

    private var classesTodayCount: Int {
        actualClassesOnly.count
    }

    private var classesLeftCount: Int {
        let datedBlocks = datedBlocks(for: now)
        return actualClassesOnly.filter { block in
            // Find the dated block that matches this block
            if let datedBlock = datedBlocks.first(where: { $0.original.kind == block.kind }) {
                return now < datedBlock.endDate
            }
            return true
        }.count
    }

    private var actualClassesOnly: [BellBlock] {
        todayBlocks.filter { block in
            switch block.kind {
            case .level(let level):
                let assignment = store.assignment(for: level)
                return !assignment.displayIsFree(on: todayWeekday)
            case .special(let sp):
                // Exclude lunch, advisory, assembly, office hours, worship, and similar non-class blocks
                switch sp {
                case .lunch, .lunchAndClubs, .assembly, .officeHours, .advisory, .worship:
                    return false
                default:
                    // Check if it's marked as free
                    return !(store.specialFree[sp] ?? false)
                }
            }
        }
    }

    private var nextDayActualClassesOnly: [BellBlock] {
        let nextDayBlocks = BellSchedule.weekly[nextSchoolDay] ?? []
        return nextDayBlocks.filter { block in
            switch block.kind {
            case .level(let level):
                let assignment = store.assignment(for: level)
                return !assignment.displayIsFree(on: nextSchoolDay)
            case .special(let sp):
                // Exclude lunch, advisory, assembly, office hours, worship, and similar non-class blocks
                switch sp {
                case .lunch, .lunchAndClubs, .assembly, .officeHours, .advisory, .worship:
                    return false
                default:
                    // Check if it's marked as free
                    return !(store.specialFree[sp] ?? false)
                }
            }
        }
    }

    private var nextDayClassesCount: Int {
        nextDayActualClassesOnly.count
    }

    private func calculateFreeTimeForDay(_ weekday: Weekday) -> String {
         let total: TimeInterval = 8 * 3600 // 8 hours
         let dayBlocks = BellSchedule.weekly[weekday] ?? []
         let used = dayBlocks.reduce(0) { acc, block in
             // Only count blocks that are NOT free
             var isFreeBlock = false
             if case .level(let level) = block.kind, store.assignment(for: level).displayIsFree(on: weekday) {
                 isFreeBlock = true
             }
             if case .special(let sp) = block.kind, store.specialFree[sp] == true {
                 isFreeBlock = true
             }
             
             // If it's not free, count its duration as used time
             guard !isFreeBlock else { return acc }
             
             let start = Calendar.current.date(
                 bySettingHour: block.start.hour ?? 0,
                 minute: block.start.minute ?? 0,
                 second: 0,
                 of: Date()
             ) ?? Date()
             let end = Calendar.current.date(
                 bySettingHour: block.end.hour ?? 0,
                 minute: block.end.minute ?? 0,
                 second: 0,
                 of: Date()
             ) ?? Date()
             return acc + max(0, end.timeIntervalSince(start))
         }
         let free = max(0, total - used)
         let totalSeconds = Int(round(free))
         let hours = totalSeconds / 3600
         let minutes = (totalSeconds % 3600) / 60
         let seconds = totalSeconds % 60

         if hours > 0 {
             if minutes > 0 {
                 return "\(hours)h \(minutes)m"
             } else {
                 return "\(hours)h"
             }
         } else if minutes > 0 {
             return "\(minutes)m"
         } else if seconds > 0 {
             return "\(seconds)s"
         } else {
             return "—"
         }
     }

    private func calculateFreeTime() -> String {
         let used = todayBlocks.reduce(0) { acc, block in
             // Only count blocks that are NOT free
             var isFreeBlock = false
             if case .level(let level) = block.kind, store.assignment(for: level).displayIsFree(on: todayWeekday) {
                 isFreeBlock = true
             }
             if case .special(let sp) = block.kind, store.specialFree[sp] == true {
                 isFreeBlock = true
             }
             
             // If it's not free, count its duration as used time
             guard !isFreeBlock else { return acc }
             
             let start = Calendar.current.date(
                 bySettingHour: block.start.hour ?? 0,
                 minute: block.start.minute ?? 0,
                 second: 0,
                 of: Date()
             ) ?? Date()
             let end = Calendar.current.date(
                 bySettingHour: block.end.hour ?? 0,
                 minute: block.end.minute ?? 0,
                 second: 0,
                 of: Date()
             ) ?? Date()
             return acc + max(0, end.timeIntervalSince(start))
         }
         
         let total: TimeInterval = 8 * 3600 // 8 hours
         let free = max(0, total - used)
         // Show free time with minute precision (e.g. "1h 23m" or "45m")
         let totalSeconds = Int(round(free))
         let hours = totalSeconds / 3600
         let minutes = (totalSeconds % 3600) / 60
         let seconds = totalSeconds % 60

         if hours > 0 {
             if minutes > 0 {
                 return "\(hours)h \(minutes)m"
             } else {
                 return "\(hours)h"
             }
         } else if minutes > 0 {
             return "\(minutes)m"
         } else if seconds > 0 {
             return "\(seconds)s"
         } else {
             return "—"
         }
     }

    private func calculateFreeTimeLeft() -> String {
         let datedBlocks = datedBlocks(for: now)
         guard !datedBlocks.isEmpty else { return "0m" }
         
         // Calculate remaining free time from now onwards
         var remaining: TimeInterval = 0
         
         for datedBlock in datedBlocks {
             // Only count blocks that haven't finished yet
             if now < datedBlock.endDate {
                 let block = datedBlock.original
                 
                 // Determine if this is a free period/block
                 var isFreeBlock = false
                 if case .level(let level) = block.kind {
                     let assignment = store.assignment(for: level)
                     isFreeBlock = assignment.displayIsFree(on: todayWeekday)
                 } else if case .special(let sp) = block.kind {
                     // Only lunch and special free blocks count as free time
                     switch sp {
                     case .lunch, .lunchAndClubs:
                         isFreeBlock = store.specialFree[sp] ?? false
                     default:
                         isFreeBlock = store.specialFree[sp] ?? false
                     }
                 }
                 
                 if isFreeBlock {
                    // If the free block is currently in progress, add remaining time in it (end - now).
                    // If the free block hasn't started yet, add only the block's duration (end - start).
                    let blockStart = datedBlock.startDate
                    let blockEnd = datedBlock.endDate
                    if now >= blockStart {
                        // currently in the free block
                        let blockRemaining = max(0, blockEnd.timeIntervalSince(now))
                        remaining += blockRemaining
                    } else {
                        // future free block: add the full block duration, not end - now
                        let blockDuration = max(0, blockEnd.timeIntervalSince(blockStart))
                        remaining += blockDuration
                    }
                 }
             }
         }
         
         let totalSeconds = Int(round(remaining))
         let hours = totalSeconds / 3600
         let minutes = (totalSeconds % 3600) / 60
         let seconds = totalSeconds % 60

         if hours > 0 {
             if minutes > 0 {
                 return "\(hours)h \(minutes)m"
             } else {
                 return "\(hours)h"
             }
         } else if minutes > 0 {
             return "\(minutes)m"
         } else if seconds > 0 {
             return "\(seconds)s"
         } else {
             return "0m"
         }
     }

    private func formatBlockTime(block: BellBlock) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        let cal = Calendar.current
        let start = cal.date(
            bySettingHour: block.start.hour ?? 0,
            minute: block.start.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date()
        return fmt.string(from: start)
    }

    // MARK: - Debug helpers

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "MMM d, h:mm:ss a"
        return fmt.string(from: date)
    }

    private func dayString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd (EEE)"
        return fmt.string(from: date)
    }

    private func timeRange(_ start: DateComponents, _ end: DateComponents) -> String {
        func fmt(_ comps: DateComponents) -> String {
            var comps = comps; comps.second = 0
            let cal = Calendar.current
            guard let d = cal.date(from: comps) else { return "—" }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "h:mm a"
            return f.string(from: d)
        }
        return "\(fmt(start))–\(fmt(end))"
    }

     private func debugTitle(for block: BellBlock) -> String {
         // Use the same mapping as the header so debug logs match the UI
         let (title, _, _, _, _) = blockTitleColorSubtitle(for: block)
         return title
     }
}

// MARK: - Dashboard Components

struct StatCard: View {
     let label: String
     let value: String
     let systemImage: String
     let color: Color
     
     var body: some View {
         VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
             HStack(spacing: DesignTokens.Spacing.sm) {
                 Image(systemName: systemImage)
                     .font(.title2)
                     .foregroundStyle(color)
                 
                 Spacer()
             }
             
             Text(value)
                 .font(DesignTokens.Typography.headline3)
                 .fontWeight(.bold)
                 .foregroundStyle(.primary)
             
             Text(label)
                 .font(DesignTokens.Typography.caption)
                 .foregroundStyle(.secondary)
         }
         .frame(maxWidth: .infinity, alignment: .leading)
         .padding(DesignTokens.Spacing.lg)
         .background(
             RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                 .fill(color.opacity(0.10))
         )
         .overlay(
             RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                 .stroke(color.opacity(0.20), lineWidth: 1.2)
         )
         .designShadow(DesignTokens.Shadows.subtle)
     }
 }

struct SchedulePreviewRow: View {
     let block: BellBlock
     @ObservedObject var store: UserScheduleStore
     let weekday: Weekday
     let time: String
     let isPast: Bool
     
      private var blockInfo: (title: String, color: Color, subtitle: String, level: Level?, isFree: Bool) {
          switch block.kind {
          case .level(let level):
              let a = store.assignment(for: level)
              // For Music Block, check for special block replacements and color
              let title = level == .music ? (store.displayMusicTitle(on: weekday) ?? a.displayTitle(for: level, on: weekday)) : a.displayTitle(for: level, on: weekday)
              let color = level == .music ? store.color(for: .musicClubs) : a.displayColor(on: weekday)
              // Don't show subtitle for Music Block (it's a special block and doesn't need description)
              let subtitle = level == .music ? "" : a.displaySubtitle(on: weekday)
              return (title, color, subtitle, level, a.displayIsFree(on: weekday))
          case .special(let sp):
              return (store.displayTitle(for: sp, on: weekday), store.color(for: sp), "", nil, false)
          }
      }
     
     var body: some View {
         HStack(spacing: DesignTokens.Spacing.md) {
             RoundedRectangle(cornerRadius: 6)
                 .fill(isPast ? Color.secondary.opacity(0.6) : blockInfo.color.opacity(0.6))
                 .frame(width: 5, height: 48)
             
             VStack(alignment: .leading, spacing: 2) {
                 HStack(spacing: 6) {
                     Text(blockInfo.title)
                         .font(DesignTokens.Typography.body)
                         .fontWeight(.medium)
                         .foregroundStyle(isPast ? .secondary : .primary)
                     
                     if let level = blockInfo.level, !blockInfo.isFree {
                         Text(level.displayName)
                             .font(DesignTokens.Typography.caption)
                             .foregroundStyle(.secondary)
                     }
                 }
                 
                 if !blockInfo.subtitle.isEmpty {
                     Text(blockInfo.subtitle)
                         .font(DesignTokens.Typography.caption)
                         .foregroundStyle(.secondary)
                 }
             }
             .frame(maxHeight: .infinity, alignment: .center)
             
             Spacer()
             
             Text(time)
                 .font(DesignTokens.Typography.caption)
                 .foregroundStyle(.secondary)
                 .opacity(isPast ? 0.8 : 1.0)
         }
         .padding(DesignTokens.Spacing.md)
         .background(
             RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                 .fill(blockInfo.color.opacity(isPast ? 0.03 : 0.06))
         )
         .overlay(
             RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                 .stroke(blockInfo.color.opacity(isPast ? 0.06 : 0.12), lineWidth: 1)
         )
         .designShadow(DesignTokens.Shadows.subtle)
      }
  }
