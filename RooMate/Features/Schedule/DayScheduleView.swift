import Combine
import SwiftUI

struct DayScheduleView: View {
  let day: Weekday
  let blocks: [BellBlock]
  @ObservedObject var store: UserScheduleStore
  @Environment(\.colorScheme) private var colorScheme

  @State private var now: Date = Date()
  @State private var didAutoScrollToCurrentClass = false
  @State private var cachedDayDated: [DatedBlock] = []
  private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

  private struct DatedBlock: Identifiable {
    let id: UUID
    let original: BellBlock
    let startDate: Date
    let endDate: Date
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(day.title)
              .font(DesignTokens.Typography.headline2)
              .foregroundStyle(.primary)

            Text("Your Schedule")
              .font(DesignTokens.Typography.subheadline)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, DesignTokens.Spacing.lg)

          let selectedIsToday = isSelectedDayToday()
          let dayDated = cachedDayDated
          let timeline = selectedIsToday ? scheduleTimeline(for: now) : nil
          let indexedBlocks = Array(dayDated.enumerated())

          // Show the current / countdown header when viewing today's schedule
          if selectedIsToday {
            let currentInfo = currentBlockInfo(on: now)
            let countdownInfo = currentInfo == nil ? nextCountdownInfo(on: now) : nil

            if let info = currentInfo {
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
                isCountdownMode: false
              )
              .padding(.horizontal, DesignTokens.Spacing.lg)
              .id(now)
            } else if let info = countdownInfo {
              CurrentBlockHeader(
                title: info.headerTitle,
                subtitle: info.headerSubtitle,
                color: info.headerColor,
                progress: info.progress,
                remainingText: info.remainingText,
                nextTitle: info.nextTitle,
                nextStartText: info.nextStartText,
                nextColor: info.nextColor,
                nextLevel: nil,
                nextSpecialLabel: info.nextSpecialLabel,
                style: store.cardColorStyle,
                isCountdownMode: true
              )
              .padding(.horizontal, DesignTokens.Spacing.lg)
              .id(now)
            }
          }

          ForEach(indexedBlocks, id: \.element.id) { index, datedBlock in
            let presentation = store.schedulePresentation(for: datedBlock.original, on: day)
            let isPast = selectedIsToday && now >= datedBlock.endDate
            let inlineStatus: ClassCardView.InlineStatus? = {
              guard selectedIsToday else { return nil }
              if timeline?.currentIndex == index,
                let remainingText = timeline?.currentRemainingText,
                let progress = timeline?.currentProgress
              {
                return .current(progress: progress, remainingText: remainingText)
              }
              if timeline?.nextIndex == index, let nextStartText = timeline?.nextStartText {
                return .upNext(startText: nextStartText)
              }
              return nil
            }()

            switch datedBlock.original.kind {
            case .level(let level):
              ClassCardView(
                title: presentation.title,
                teacher: presentation.teacher,
                room: presentation.room,
                timeRange: formattedRange(for: datedBlock.original),
                color: presentation.color,
                systemImage: presentation.systemImage,
                style: store.cardColorStyle,
                duration: formattedDuration(for: datedBlock.original),
                level: level,
                specialLabel: nil,
                isFree: presentation.isFree,
                inlineStatus: inlineStatus,
                isPast: isPast
              )
              .padding(.horizontal, DesignTokens.Spacing.lg)
              .id(datedBlock.id)

            case .special(let special):
              ClassCardView(
                title: presentation.title,
                teacher: presentation.teacher,
                room: presentation.room,
                timeRange: formattedRange(for: datedBlock.original),
                color: presentation.color,
                systemImage: presentation.systemImage,
                style: store.cardColorStyle,
                duration: formattedDuration(for: datedBlock.original),
                level: nil,
                specialLabel: datedBlock.original.isExtra
                  ? "Extra"
                  : (datedBlock.original.isMarker ? "Marker" : specialBlockLabel(for: special)),
                isFree: presentation.isFree,
                inlineStatus: inlineStatus,
                isPast: isPast
              )
              .padding(.horizontal, DesignTokens.Spacing.lg)
              .id(datedBlock.id)

            case .custom:
              ClassCardView(
                title: presentation.title,
                teacher: presentation.teacher,
                room: presentation.room,
                timeRange: formattedRange(for: datedBlock.original),
                color: presentation.color,
                systemImage: presentation.systemImage,
                style: store.cardColorStyle,
                duration: formattedDuration(for: datedBlock.original),
                level: nil,
                specialLabel: datedBlock.original.isExtra
                  ? "Extra" : (datedBlock.original.isMarker ? "Marker" : "Special Schedule"),
                isFree: false,
                inlineStatus: inlineStatus,
                isPast: isPast
              )
              .padding(.horizontal, DesignTokens.Spacing.lg)
              .id(datedBlock.id)
            }
          }

          Spacer(minLength: DesignTokens.Spacing.lg)
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
      }
      .modifier(SafeAreaTopPadding(4))
      .onReceive(timer) { newTime in
        now = newTime
        updateCache()
      }
      .onAppear {
        updateCache()
        scheduleAutoScrollIfNeeded(using: proxy)
      }
      .onChange(of: day) { _, _ in
        didAutoScrollToCurrentClass = false
        updateCache()
        scheduleAutoScrollIfNeeded(using: proxy)
      }
      .onChange(of: blocks.count) { _, _ in
        updateCache()
        scheduleAutoScrollIfNeeded(using: proxy)
      }
    }
  }

  private func updateCache() {
    cachedDayDated = datedBlocks(for: now)
  }

  private func scheduleAutoScrollIfNeeded(using proxy: ScrollViewProxy) {
    guard !didAutoScrollToCurrentClass, isSelectedDayToday() else { return }
    guard let targetID = currentBlockScrollTargetID(for: now) else { return }

    didAutoScrollToCurrentClass = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      withAnimation(DesignTokens.Animation.smooth) {
        proxy.scrollTo(targetID, anchor: .center)
      }
    }
  }

  private func currentBlockScrollTargetID(for reference: Date) -> UUID? {
    let list = cachedDayDated
    let timeline = scheduleTimeline(for: reference)
    // Prefer current block, fall back to next block
    if let currentIndex = timeline.currentIndex, list.indices.contains(currentIndex) {
      return list[currentIndex].id
    }
    if let nextIndex = timeline.nextIndex, list.indices.contains(nextIndex) {
      return list[nextIndex].id
    }
    return nil
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

      var endComps = startComps
      endComps.hour = block.end.hour
      endComps.minute = block.end.minute

      guard let s = cal.date(from: startComps), let e = cal.date(from: endComps) else { return nil }
      return DatedBlock(id: block.id, original: block, startDate: s, endDate: e)
    }.sorted { $0.startDate < $1.startDate }
  }

  private func isSelectedDayToday() -> Bool {
    let calendar = Calendar.current
    switch calendar.component(.weekday, from: Date()) {
    case 2: return day == .monday
    case 3: return day == .tuesday
    case 4: return day == .wednesday
    case 5: return day == .thursday
    case 6: return day == .friday
    default: return false
    }
  }

  private struct ScheduleTimeline {
    let currentIndex: Int?
    let nextIndex: Int?
    let currentProgress: Double?
    let currentRemainingText: String?
    let nextStartText: String?
  }

  private func scheduleTimeline(for reference: Date) -> ScheduleTimeline {
    let list = cachedDayDated
    guard !list.isEmpty else {
      return ScheduleTimeline(
        currentIndex: nil, nextIndex: nil, currentProgress: nil, currentRemainingText: nil,
        nextStartText: nil)
    }

    var currentIndex: Int?
    var nextIndex: Int?

    for (idx, item) in list.enumerated() {
      guard !item.original.isMarker else { continue }
      if reference >= item.startDate && reference < item.endDate {
        currentIndex = idx
        nextIndex = list.indices.dropFirst(idx + 1).first(where: {
          list[$0].startDate > reference
        })
        break
      } else if reference < item.startDate {
        nextIndex = idx
        break
      }
    }

    let currentProgress: Double?
    let currentRemainingText: String?
    if let currentIndex = currentIndex {
      let current = list[currentIndex]
      let total = max(1, current.endDate.timeIntervalSince(current.startDate))
      let elapsed = max(0, reference.timeIntervalSince(current.startDate))
      currentProgress = max(0, min(1, elapsed / total))
      let remaining = max(0, current.endDate.timeIntervalSince(reference))
      currentRemainingText = "Ends in " + formatDuration(remaining)
    } else {
      currentProgress = nil
      currentRemainingText = nil
    }

    let nextStartText: String?
    if let nextIndex = nextIndex {
      let remaining = max(0, list[nextIndex].startDate.timeIntervalSince(reference))
      let minutes = Int(remaining) / 60
      nextStartText = "Starts in \(minutes) min"
    } else {
      nextStartText = nil
    }

    return ScheduleTimeline(
      currentIndex: currentIndex,
      nextIndex: nextIndex,
      currentProgress: currentProgress,
      currentRemainingText: currentRemainingText,
      nextStartText: nextStartText
    )
  }

  private func blockTitleColorSubtitle(for block: BellBlock) -> (
    title: String, color: Color, subtitle: String, level: Level?, specialLabel: String?
  ) {
    let presentation = store.schedulePresentation(for: block, on: day)

    switch block.kind {
    case .level(let level):
      return (presentation.title, presentation.color, presentation.subtitle, level, nil)
    case .special(let special):
      return (
        presentation.title, presentation.color, presentation.subtitle, nil,
        specialBlockLabel(for: special)
      )
    case .custom:
      return (
        presentation.title, presentation.color, presentation.subtitle, nil, "Special Schedule"
      )
    }
  }

  private func specialBlockLabel(for block: SpecialBlock) -> String {
    switch block {
    case .assembly: "Assembly"
    case .officeHours: "Office Hours"
    case .advisory: "Advisory"
    case .worship: "Meeting For Worship"
    case .consciousCommunities: "Conscious Communities"
    case .lunch: "Lunch"
    case .lunchAndClubs: "Lunch & Clubs"
    case .musicClubs: "Music Block + Clubs"
    }
  }

  private func currentBlockInfo(on reference: Date) -> (
    title: String, subtitle: String, color: Color, progress: Double, remainingText: String,
    nextTitle: String?, nextStartText: String?, nextColor: Color?, nextLevel: Level?,
    nextSpecialLabel: String?
  )? {
    let list = cachedDayDated
    guard !list.isEmpty else { return nil }

    var current: DatedBlock?
    var next: DatedBlock?
    for (idx, item) in list.enumerated() {
      guard !item.original.isMarker else { continue }
      if reference >= item.startDate && reference < item.endDate {
        current = item
        if let nextIndex = list.indices.dropFirst(idx + 1).first(where: {
          list[$0].startDate > reference
        }) {
          next = list[nextIndex]
        }
        break
      }
    }

    guard let current = current else { return nil }

    let total = current.endDate.timeIntervalSince(current.startDate)
    let elapsed = reference.timeIntervalSince(current.startDate)
    let remaining = max(0, current.endDate.timeIntervalSince(reference))
    let progress = max(0, min(1, elapsed / max(1, total)))

    let (title, color, subtitle, _, _) = blockTitleColorSubtitle(for: current.original)
    let remainingText = "Ends in " + formatDuration(remaining)

    var nextTitle: String?
    var nextStartText: String?
    var nextColor: Color?
    var nextLevel: Level?
    var nextSpecialLabel: String?
    if let next = next {
      let (ntitle, ncolor, _, nlevel, nspecialLabel) = blockTitleColorSubtitle(for: next.original)
      nextTitle = ntitle
      nextColor = ncolor
      nextLevel = nlevel
      nextSpecialLabel = nspecialLabel
      nextStartText = "Starts at " + timeString(next.startDate)
    }

    return (
      title, subtitle, color, progress, remainingText, nextTitle, nextStartText, nextColor,
      nextLevel, nextSpecialLabel
    )
  }

  private func nextCountdownInfo(on reference: Date) -> (
    headerTitle: String, headerSubtitle: String, headerColor: Color, progress: Double,
    remainingText: String, nextTitle: String, nextStartText: String, nextColor: Color,
    nextSpecialLabel: String?
  )? {
    let list = cachedDayDated
    guard !list.isEmpty else { return nil }

    var future: DatedBlock?
    var previousAnchorTime: Date?
    for (idx, item) in list.enumerated() {
      if reference < item.startDate {
        future = item
        let previousIndex = list.indices.prefix(idx).reversed().first
        previousAnchorTime =
          previousIndex.map { list[$0].endDate } ?? Calendar.current.startOfDay(for: item.startDate)
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

    let (ntitle, ncolor, _, _, nspecialLabel) = blockTitleColorSubtitle(for: next.original)

    return (
      headerTitle: "Nothing scheduled right now",
      headerSubtitle: next.original.isMarker ? "Next event" : "Starts soon",
      headerColor: .secondary,
      progress: progress,
      remainingText: (next.original.isMarker ? "Happens in " : "Starts in ")
        + formatDuration(remaining),
      nextTitle: ntitle,
      nextStartText: (next.original.isMarker ? "At " : "Starts at ")
        + timeString(next.startDate),
      nextColor: ncolor,
      nextSpecialLabel: nspecialLabel
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

  private func formattedRange(for block: BellBlock) -> String {
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
    if block.isMarker { return format(block.start) }
    return "\(format(block.start)) – \(format(block.end))"
  }

  private func formattedDuration(for block: BellBlock) -> String {
    if block.isMarker { return "" }
    let cal = Calendar.current
    var startComps = block.start
    var endComps = block.end
    startComps.second = 0
    endComps.second = 0

    guard let startDate = cal.date(from: startComps),
      let endDate = cal.date(from: endComps)
    else { return "—" }

    let duration = Int(endDate.timeIntervalSince(startDate))
    let hours = duration / 3600
    let minutes = (duration % 3600) / 60

    if hours > 0 && minutes > 0 {
      return "\(hours)h \(minutes)m"
    } else if hours > 0 {
      return "\(hours)h"
    } else if minutes > 0 {
      return "\(minutes)m"
    } else {
      return "—"
    }
  }
}

// Made internal so it can be used by DashboardView too
struct CurrentBlockHeader: View {
  @Environment(\.colorScheme) private var colorScheme
  let title: String
  let subtitle: String
  let color: Color
  let progress: Double
  let remainingText: String
  let nextTitle: String?
  let nextStartText: String?
  let nextColor: Color?
  let nextLevel: Level?
  let nextSpecialLabel: String?
  let style: CardColorStyle
  let isCountdownMode: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
              Image(systemName: isCountdownMode ? "pause.circle.fill" : "clock.fill")
                .font(.title3)
                .foregroundStyle(isCountdownMode ? .secondary : color)

              Text(isCountdownMode ? "Idle" : "Now")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            }

            Text(title)
              .font(DesignTokens.Typography.headline2)
              .fontWeight(.bold)
              .foregroundStyle(.primary)

            if !subtitle.isEmpty {
              Text(subtitle)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()

          VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
            if !remainingText.isEmpty {
              Label(
                remainingText,
                systemImage: isCountdownMode
                  ? "clock.badge.checkmark.fill" : "hourglass.bottomhalf.fill"
              )
              .font(DesignTokens.Typography.body)
              .fontWeight(.semibold)
              .foregroundStyle(color)
            }
          }
        }

        ProgressView(value: progress)
          .tint(progressTint)
          .animation(.linear(duration: 0.2), value: progress)
      }
      .padding(DesignTokens.Spacing.lg)
      .background(nowBackground)

      if let nextTitle, let nextStartText {
        NextBlockCard(
          title: nextTitle,
          startText: nextStartText,
          color: nextColor ?? .accentColor,
          style: style,
          level: nextLevel,
          specialLabel: nextSpecialLabel
        )
      }
    }
  }

  private var isNeutral: Bool { style == .none || isCountdownMode }

  private var accentFill: some ShapeStyle {
    if isNeutral {
      return LinearGradient(
        colors: [Color.secondary.opacity(0.5), Color.secondary.opacity(0.3)], startPoint: .top,
        endPoint: .bottom)
    } else {
      return LinearGradient(
        colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom)
    }
  }

  private var progressTint: Color {
    isNeutral ? .accentColor : color
  }

  @ViewBuilder
  private var nowBackground: some View {
    let accentColor = isNeutral ? DesignTokens.Colors.secondaryText : color

    ZStack {
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .fill(DesignTokens.Colors.surfaceElevated)

      if style != .none && !isCountdownMode {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                accentColor.opacity(colorScheme == .light ? 0.10 : 0.15),
                accentColor.opacity(colorScheme == .light ? 0.025 : 0.045),
                Color.clear,
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(
          style == .none || isCountdownMode
            ? DesignTokens.Colors.border
            : accentColor.opacity(0.20),
          lineWidth: 1
        )
    )
    .overlay(alignment: .leading) {
      if style != .none && !isCountdownMode {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(accentColor)
          .frame(width: 4)
          .padding(.vertical, 14)
          .padding(.leading, 2)
      }
    }
    .designShadow(DesignTokens.Shadows.small)
  }
}

struct ClassCardView: View {
  enum InlineStatus {
    case current(progress: Double, remainingText: String)
    case upNext(startText: String)
  }

  let title: String
  let teacher: String?
  let room: String?
  let timeRange: String
  let color: Color
  let systemImage: String
  let style: CardColorStyle
  let duration: String?
  let level: Level?
  let specialLabel: String?
  let isFree: Bool
  let inlineStatus: InlineStatus?
  let isPast: Bool
  @Environment(\.colorScheme) private var colorScheme

  private var displayedTeacher: String? {
    teacher.flatMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }
  private var displayedRoom: String? {
    room.flatMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }
  private var displayedDuration: String? {
    duration.flatMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }
  private var displayedSpecialLabel: String? {
    specialLabel.flatMap { value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }
  private var hasDetails: Bool {
    !isFree && (displayedTeacher != nil || displayedRoom != nil || displayedDuration != nil)
  }
  private var hasLevel: Bool { level != nil }
  private var mutedOpacity: Double { isPast ? 0.56 : 1.0 }
  private var isCurrent: Bool {
    if case .current = inlineStatus { return true }
    return false
  }

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
    VStack(
      alignment: .leading, spacing: isCurrent ? DesignTokens.Spacing.lg : DesignTokens.Spacing.md
    ) {
      if let inlineStatus {
        HStack(spacing: DesignTokens.Spacing.sm) {
          switch inlineStatus {
          case .current:
            Image(systemName: "clock.fill")
              .font(.title3)
              .foregroundStyle(isPast ? .secondary : color)

            Text("Now")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          case .upNext:
            Label("Up Next", systemImage: "forward.fill")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          switch inlineStatus {
          case .current(_, let remainingText):
            Label(remainingText, systemImage: "hourglass.bottomhalf.fill")
              .font(DesignTokens.Typography.body)
              .fontWeight(.semibold)
              .foregroundStyle(isPast ? .secondary : color)
          case .upNext(let startText):
            Label(startText, systemImage: "clock.fill")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(isPast ? 0.07 : 0.14))
          Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isPast ? .secondary : color)
        }
        .frame(width: 40, height: 40)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(DesignTokens.Typography.title)
            .fontWeight(.semibold)
            .foregroundStyle(isPast ? .secondary : .primary)

          if let level = level {
            Text(level.displayName)
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          } else if let displayedSpecialLabel {
            Text(displayedSpecialLabel)
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Label(timeRange, systemImage: "clock.fill")
          .font(DesignTokens.Typography.caption)
          .foregroundStyle(isPast ? .secondary : color)
          .fontWeight(.medium)
          .labelStyle(.titleAndIcon)
      }

      if hasDetails {
        HStack(spacing: DesignTokens.Spacing.lg) {
          if let displayedTeacher {
            Label(displayedTeacher, systemImage: "person.fill")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          }
          if let displayedRoom {
            Label(displayedRoom, systemImage: "mappin.and.ellipse")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let displayedDuration {
            Label(displayedDuration, systemImage: "hourglass.bottomhalf.filled")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      if case .current(let progress, _) = inlineStatus {
        ProgressView(value: progress)
          .tint(isPast ? .secondary : color)
          .animation(.linear(duration: 0.2), value: progress)
      }
    }
    .padding(DesignTokens.Spacing.lg)
    .padding(.vertical, isCurrent ? DesignTokens.Spacing.sm : 0)
    .background(backgroundForStyle)
    .overlay(strokeForStyle)
    .overlay(alignment: .leading) {
      if style != .none {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .fill(isPast ? DesignTokens.Colors.subtleText.opacity(0.42) : color)
          .frame(width: style == .colors ? 4 : 3)
          .padding(.vertical, 12)
          .padding(.leading, 2)
      }
    }
    .overlay(glowForStyle)
    .cornerRadius(DesignTokens.Radius.md)
    // Avoid a subtle 1px hairline seam on macOS caused by scaling + blur/clip.
    // Keep the small scale effect on non-macOS targets (iOS) where it is visually helpful.
    #if os(macOS)
      .scaleEffect(1.0)
    #else
      .scaleEffect(isCurrent ? 1.01 : 1.0)
    #endif
    .opacity(mutedOpacity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDescription)
  }

  private var accessibilityDescription: String {
    var parts = [title, timeRange]
    if let displayedTeacher { parts.append("with \(displayedTeacher)") }
    if let displayedRoom { parts.append("in \(displayedRoom)") }
    return parts.joined(separator: ", ")
  }

  @ViewBuilder
  private var backgroundForStyle: some View {
    switch style {
    case .none:
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .fill(DesignTokens.Colors.surface)

    case .subtle:
      ZStack {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(DesignTokens.Colors.surface)

        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                color.opacity(colorScheme == .light ? 0.045 : 0.055),
                Color.clear,
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
      }

    case .colors:
      ZStack {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(DesignTokens.Colors.surface)

        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                color.opacity(colorScheme == .light ? 0.10 : 0.12),
                color.opacity(colorScheme == .light ? 0.03 : 0.035),
                Color.clear,
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
      }
    }
  }

  @ViewBuilder
  private var strokeForStyle: some View {
    switch style {
    case .none:
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(DesignTokens.Colors.border, lineWidth: 1)

    case .subtle:
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(color.opacity(0.11), lineWidth: 1)

    case .colors:
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(color.opacity(0.17), lineWidth: 1)
    }
  }

  @ViewBuilder
  private var glowForStyle: some View {
    if style != .none && colorScheme == .dark && isCurrent {
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .stroke(color.opacity(0.08), lineWidth: 3)
        .blur(radius: 6)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous))
    } else {
      EmptyView()
    }
  }
}
