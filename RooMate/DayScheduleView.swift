import SwiftUI

struct DayScheduleView: View {
    let day: Weekday
    let blocks: [BellBlock]
    @ObservedObject var store: UserScheduleStore

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct DatedBlock: Identifiable {
        let id = UUID()
        let original: BellBlock
        let startDate: Date
        let endDate: Date
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: 4)

                if let currentInfo = currentBlockInfo(on: now) {
                    CurrentBlockHeader(
                        title: currentInfo.title,
                        subtitle: currentInfo.subtitle,
                        color: currentInfo.color,
                        progress: currentInfo.progress,
                        remainingText: currentInfo.remainingText,
                        nextTitle: currentInfo.nextTitle,
                        nextStartText: currentInfo.nextStartText,
                        nextColor: currentInfo.nextColor,
                        style: store.cardColorStyle,
                        isCountdownMode: false
                    )
                    .padding(.horizontal)
                } else if let countdown = nextCountdownInfo(on: now) {
                    CurrentBlockHeader(
                        title: countdown.headerTitle,
                        subtitle: countdown.headerSubtitle,
                        color: countdown.headerColor,
                        progress: countdown.progress,
                        remainingText: countdown.remainingText,
                        nextTitle: countdown.nextTitle,
                        nextStartText: countdown.nextStartText,
                        nextColor: countdown.nextColor,
                        style: store.cardColorStyle,
                        isCountdownMode: true
                    )
                    .padding(.horizontal)
                }

                Text("\(day.title)’s Schedule")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal)

                ForEach(blocks) { block in
                    switch block.kind {
                    case .level(let level):
                        let assignment = store.assignment(for: level)
                        ClassCardView(
                           title: assignment.title,
                           teacher: assignment.teacher.isEmpty ? nil : assignment.teacher,
                           room: assignment.room.isEmpty ? nil : assignment.room,
                           timeRange: formattedRange(start: block.start, end: block.end),
                           color: assignment.color.swiftUIColor,
                           style: store.cardColorStyle
                        )
                        .padding(.horizontal)

                    case .special(let special):
                        ClassCardView(
                           title: special.title,
                           teacher: nil,
                           room: nil,
                           timeRange: formattedRange(start: block.start, end: block.end),
                           color: store.color(for: special),
                           style: store.cardColorStyle
                        )
                        .padding(.horizontal)
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(.vertical, 16)
        }
        .modifier(SafeAreaTopPadding(4))
        .onReceive(timer) { now = $0 }
    }

    private func datedBlocks(for reference: Date) -> [DatedBlock] {
        let cal = Calendar.current
        let targetWeekday: Int = {
            switch day {
            case .monday: 2
            case .tuesday: 3
            case .wednesday: 4
            case .thursday: 5
            case .friday: 6
            }
        }()

        let startOfDay = cal.startOfDay(for: reference)
        let todayWeekday = cal.component(.weekday, from: startOfDay)
        let dayOffset: Int = {
            var delta = targetWeekday - todayWeekday
            if delta < 0 { delta += 7 }
            return delta
        }()
        let weekdayDate = cal.date(byAdding: .day, value: dayOffset, to: startOfDay) ?? startOfDay

        return blocks.compactMap { block in
            var startComps = cal.dateComponents([.year, .month, .day], from: weekdayDate)
            startComps.hour = block.start.hour
            startComps.minute = block.start.minute
            startComps.second = 0

            var endComps = cal.dateComponents([.year, .month, .day], from: weekdayDate)
            endComps.hour = block.end.hour
            endComps.minute = block.end.minute
            endComps.second = 0

            guard let s = cal.date(from: startComps), let e = cal.date(from: endComps) else { return nil }
            return DatedBlock(original: block, startDate: s, endDate: e)
        }.sorted(by: { $0.startDate < $1.startDate })
    }

    private func blockTitleColorSubtitle(for block: BellBlock) -> (title: String, color: Color, subtitle: String) {
        switch block.kind {
        case .level(let level):
            let a = store.assignment(for: level)
            let subtitle = [a.teacher, a.room].filter { !$0.isEmpty }.joined(separator: " • ")
            return (a.title, a.color.swiftUIColor, subtitle)
        case .special(let sp):
            return (sp.title, store.color(for: sp), "")
        }
    }

    private func currentBlockInfo(on reference: Date) -> (title: String, subtitle: String, color: Color, progress: Double, remainingText: String, nextTitle: String?, nextStartText: String?, nextColor: Color?)? {
        let list = datedBlocks(for: reference)
        guard !list.isEmpty else { return nil }

        var current: DatedBlock?
        var next: DatedBlock?
        for (idx, item) in list.enumerated() {
            if reference >= item.startDate && reference < item.endDate {
                current = item
                if idx + 1 < list.count { next = list[idx + 1] }
                break
            }
            if reference < item.startDate {
                current = nil
                next = item
                break
            }
        }

        guard let current else { return nil }

        let total = current.endDate.timeIntervalSince(current.startDate)
        let elapsed = reference.timeIntervalSince(current.startDate)
        let remaining = max(0, current.endDate.timeIntervalSince(reference))
        let progress = max(0, min(1, elapsed / max(1, total)))

        let (title, color, subtitle) = blockTitleColorSubtitle(for: current.original)
        let remainingText = "Ends in " + formatDuration(remaining)

        var nextTitle: String?
        var nextStartText: String?
        var nextColor: Color?
        if let next {
            let (ntitle, ncolor, _) = blockTitleColorSubtitle(for: next.original)
            nextTitle = ntitle
            nextColor = ncolor
            nextStartText = "Starts at " + timeString(next.startDate)
        }

        return (title, subtitle, color, progress, remainingText, nextTitle, nextStartText, nextColor)
    }

    private func nextCountdownInfo(on reference: Date) -> (headerTitle: String, headerSubtitle: String, headerColor: Color, progress: Double, remainingText: String, nextTitle: String, nextStartText: String, nextColor: Color)? {
        let list = datedBlocks(for: reference)
        guard !list.isEmpty else { return nil }

        var future: DatedBlock?
        var previousAnchorTime: Date?
        for (idx, item) in list.enumerated() {
            if reference < item.startDate {
                future = item
                if idx > 0 {
                    previousAnchorTime = list[idx - 1].endDate
                } else {
                    previousAnchorTime = Calendar.current.startOfDay(for: item.startDate)
                }
                break
            }
        }

        guard let next = future, let anchor = previousAnchorTime else {
            return nil
        }

        let remaining = max(0, next.startDate.timeIntervalSince(reference))
        let totalGap = max(1, next.startDate.timeIntervalSince(anchor))
        let elapsedGap = max(0, reference.timeIntervalSince(anchor))
        let progress = max(0, min(1, elapsedGap / totalGap))

        let (ntitle, ncolor, _) = blockTitleColorSubtitle(for: next.original)

        return (
            headerTitle: "No class right now",
            headerSubtitle: "Starts soon",
            headerColor: .secondary,
            progress: progress,
            remainingText: "Starts in " + formatDuration(remaining),
            nextTitle: ntitle,
            nextStartText: "Starts at " + timeString(next.startDate),
            nextColor: ncolor
        )
    }

    private func timeString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
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

    private func formattedRange(start: DateComponents, end: DateComponents) -> String {
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
        return "\(format(start)) – \(format(end))"
    }
}

private struct CurrentBlockHeader: View {
    let title: String
    let subtitle: String
    let color: Color
    let progress: Double
    let remainingText: String
    let nextTitle: String?
    let nextStartText: String?
    let nextColor: Color?
    let style: CardColorStyle
    let isCountdownMode: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accentFill)
                        .frame(width: 8, height: 40)
                        .shadow(color: accentShadowColor, radius: accentShadowRadius, x: 0, y: 0)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(isCountdownMode ? "Idle" : "Now", systemImage: isCountdownMode ? "pause.circle" : "clock")
                                .font(.caption)
                                .modifier(SecondaryForeground())
                            Spacer()
                        }
                        Text(title).font(.title3.bold())
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.subheadline).modifier(SecondaryForeground())
                        }
                    }
                }

                ProgressView(value: progress)
                    .tint(progressTint)
                    .animation(.linear(duration: 0.2), value: progress)

                HStack {
                    if !remainingText.isEmpty {
                        Label(remainingText, systemImage: isCountdownMode ? "clock.badge.checkmark" : "hourglass")
                    } else {
                        Text("—")
                    }
                    Spacer()
                }
                .font(.footnote)
                .modifier(SecondaryForeground())
            }
            .padding(12)
            .background(nowBackground)
            .overlay(nowStroke)
            .overlay(nowGlow)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.6)
            )

            if let nextTitle, let nextStartText {
                NextBlockCard(
                    title: nextTitle,
                    startText: nextStartText,
                    color: nextColor ?? .accentColor,
                    style: style
                )
            }
        }
    }

    private var isNeutral: Bool { style == .none || isCountdownMode }

    private var accentFill: some ShapeStyle {
        if isNeutral {
            return LinearGradient(colors: [Color.secondary.opacity(0.5), Color.secondary.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var accentShadowColor: Color {
        if isNeutral { return Color.clear }
        return color.opacity(style == .colors ? 0.25 : 0.35)
    }

    private var accentShadowRadius: CGFloat {
        if isNeutral { return 0 }
        return style == .colors ? 6 : 8
    }

    private var progressTint: Color {
        isNeutral ? .accentColor : color
    }

    @ViewBuilder
    private var nowBackground: some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CompatibleBackgroundSecondary())
        case .subtle:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((isNeutral ? Color.secondary : color).opacity(0.12))
                    .blur(radius: 10)
                    .scaleEffect(1.01)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [(isNeutral ? Color.secondary : color).opacity(0.16), (isNeutral ? Color.secondary : color).opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: (isNeutral ? Color.secondary : color).opacity(0.2), radius: 9, x: 0, y: 0)
            }
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((isNeutral ? Color.secondary : color).opacity(0.10))
                    .blur(radius: 8)
                    .scaleEffect(1.005)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [(isNeutral ? Color.secondary : color).opacity(0.14), (isNeutral ? Color.secondary : color).opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: (isNeutral ? Color.secondary : color).opacity(0.16), radius: 7, x: 0, y: 0)
            }
        }
    }

    @ViewBuilder
    private var nowStroke: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LinearGradient(
                    colors: [(isNeutral ? Color.secondary : color).opacity(0.6), (isNeutral ? Color.secondary : color).opacity(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1.6)
        case .colors:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LinearGradient(
                    colors: [(isNeutral ? Color.secondary : color).opacity(0.5), (isNeutral ? Color.secondary : color).opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private var nowGlow: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((isNeutral ? Color.secondary : color).opacity(0.10), lineWidth: 4)
                .blur(radius: 7)
        case .colors:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((isNeutral ? Color.secondary : color).opacity(0.05), lineWidth: 2)
                .blur(radius: 3)
        }
    }
}

struct ClassCardView: View {
    let title: String
    let teacher: String?
    let room: String?
    let timeRange: String
    let color: Color
    let style: CardColorStyle

    private var softGradient: LinearGradient {
        let c = color
        return LinearGradient(
            colors: [c.opacity(0.22), c.opacity(0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var softStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.7), color.opacity(0.2)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.title3).fontWeight(.semibold)
                    Spacer()
                    Label(timeRange, systemImage: "clock")
                        .font(.subheadline)
                        .modifier(SecondaryForeground())
                        .labelStyle(.titleAndIcon)
                }

                HStack(spacing: 12) {
                    if let teacher, !teacher.isEmpty {
                        Label(teacher, systemImage: "person.fill")
                    }
                    if let room, !room.isEmpty {
                        Label(room, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.subheadline)
                .modifier(SecondaryForeground())
            }
            .padding(.vertical, 10)
        }
        .padding(12)
        .background(backgroundForStyle)
        .overlay(strokeForStyle)
        .overlay(glowForStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(timeRange)\(teacher != nil ? ", with \(teacher!)" : "")\(room != nil ? ", in \(room!)" : "")")
    }

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CompatibleBackgroundSecondary())
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        case .subtle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CompatibleBackgroundSecondary())
                .shadow(color: color.opacity(0.12), radius: 10, x: 0, y: 0)
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.12))
                    .blur(radius: 10)
                    .scaleEffect(1.01)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(softGradient)
                    .shadow(color: color.opacity(0.18), radius: 8, x: 0, y: 0)
            }
        }
    }

    @ViewBuilder
    private var strokeForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(softStrokeGradient, lineWidth: 1.2)
        case .colors:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(softStrokeGradient, lineWidth: 1.4)
        }
    }

    @ViewBuilder
    private var glowForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.10), lineWidth: 4)
                .blur(radius: 7)
        case .colors:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.06), lineWidth: 2)
                .blur(radius: 4)
        }
    }
}
