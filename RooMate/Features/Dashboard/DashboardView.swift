import Combine
import SwiftUI

struct DashboardView: View {
  @ObservedObject var store: UserScheduleStore
  @ObservedObject var sportsStore: SportsStore
  @ObservedObject var eventsStore: EventsStore
  @ObservedObject var menuStore: MenuStore

  @Environment(\.openURL) private var openURL
  @AppStorage("RooMateSportsGameReminders")
  private var savedGameIDsRaw = ""

  var onOpenSchedule: () -> Void = {}
  var onOpenDining: () -> Void = {}
  var onOpenSports: () -> Void = {}
  var onOpenClubs: () -> Void = {}
  var onOpenEvents: () -> Void = {}
  var onOpenPacTrack: () -> Void = {}
  var onOpenScheduleFocus: () -> Void = {}
  var onSearch: () -> Void = {}

  @State private var now = Date()
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  // MARK: - Schedule model used by Today

  fileprivate struct DatedBlock: Identifiable {
    let block: BellBlock
    let startDate: Date
    let endDate: Date
    let title: String
    let subtitle: String
    let color: Color
    let symbol: String
    let isFree: Bool

    var id: UUID { block.id }
  }

  private struct HeroInfo {
    let title: String
    let subtitle: String
    let color: Color
    let symbol: String
    let progress: Double
    let remaining: TimeInterval
    let endTime: String?
    let isBetweenBlocks: Bool
    let nextTitle: String?
    let nextSubtitle: String?
    let nextColor: Color?
    let nextSymbol: String?
    let nextStartTime: String?
  }

  private enum ContextualActionKind: String {
    case dining
    case clubs
    case sports
    case focus
    case events
    case schedule
  }

  private struct ContextualActionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let kind: ContextualActionKind
  }

  private struct ClubMeetingContext {
    let club: Club
    let startDate: Date
    let endDate: Date

    var isCurrent: Bool {
      let reference = Date()
      return reference >= startDate && reference < endDate
    }
  }

  private var todayWeekday: Weekday? {
    store.scheduleWeekday(for: now)
  }

  private var todayBlocks: [BellBlock] {
    store.bellBlocks(for: now)
  }

  private var todaySpecialSchedule: RemoteSpecialScheduleDay? {
    store.remoteSpecialScheduleDay(on: now)
  }

  private func date(on reference: Date, components: DateComponents) -> Date? {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: reference)
    var result = calendar.dateComponents([.year, .month, .day], from: day)
    result.hour = components.hour
    result.minute = components.minute
    result.second = 0
    return calendar.date(from: result)
  }

  private func presentation(for block: BellBlock, weekday: Weekday) -> (
    String, String, Color, String, Bool
  ) {
    let presentation = store.schedulePresentation(for: block, on: weekday)
    return (
      presentation.title,
      presentation.subtitle,
      presentation.color,
      presentation.systemImage,
      presentation.isFree
    )
  }

  private var datedBlocks: [DatedBlock] {
    guard let weekday = todayWeekday else { return [] }

    return todayBlocks.compactMap { block in
      guard let start = date(on: now, components: block.start),
        let end = date(on: now, components: block.end)
      else { return nil }

      let info = presentation(for: block, weekday: weekday)
      return DatedBlock(
        block: block,
        startDate: start,
        endDate: end,
        title: info.0,
        subtitle: info.1,
        color: info.2,
        symbol: info.3,
        isFree: info.4
      )
    }
    .sorted { $0.startDate < $1.startDate }
  }

  private var primaryDatedBlocks: [DatedBlock] {
    datedBlocks.filter { $0.block.isPrimaryTimelineBlock }
  }

  private var classBlocks: [DatedBlock] {
    primaryDatedBlocks.filter { item in
      switch item.block.kind {
      case .level:
        return !item.isFree
      case .special(let special):
        switch special {
        case .lunch, .lunchAndClubs, .assembly, .officeHours, .advisory, .worship:
          return false
        default:
          return !item.isFree
        }
      case .custom:
        return false
      }
    }
  }

  private var freeBlockCount: Int {
    datedBlocks.filter(\.isFree).count
  }

  private var currentBlock: DatedBlock? {
    primaryDatedBlocks.first { now >= $0.startDate && now < $0.endDate }
  }

  private var nextBlock: DatedBlock? {
    primaryDatedBlocks.first { now < $0.startDate }
  }

  private func shortTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
  }

  private var heroInfo: HeroInfo? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"

    if let current = currentBlock {
      let total = max(1, current.endDate.timeIntervalSince(current.startDate))
      let elapsed = max(0, now.timeIntervalSince(current.startDate))
      let next = primaryDatedBlocks.first { $0.startDate >= current.endDate }

      return HeroInfo(
        title: current.title,
        subtitle: current.subtitle,
        color: current.color,
        symbol: current.symbol,
        progress: min(1, max(0, elapsed / total)),
        remaining: max(0, current.endDate.timeIntervalSince(now)),
        endTime: formatter.string(from: current.endDate),
        isBetweenBlocks: false,
        nextTitle: next?.title,
        nextSubtitle: next?.subtitle,
        nextColor: next?.color,
        nextSymbol: next?.symbol,
        nextStartTime: next.map { formatter.string(from: $0.startDate) }
      )
    }

    if let next = nextBlock {
      let previousEnd =
        primaryDatedBlocks.last(where: { $0.endDate <= now })?.endDate
        ?? Calendar.current.startOfDay(for: now)
      let totalGap = max(1, next.startDate.timeIntervalSince(previousEnd))
      let elapsed = max(0, now.timeIntervalSince(previousEnd))

      return HeroInfo(
        title: "Free time",
        subtitle: "Nothing scheduled right now",
        color: DesignTokens.Colors.today,
        symbol: "cup.and.saucer.fill",
        progress: min(1, max(0, elapsed / totalGap)),
        remaining: max(0, next.startDate.timeIntervalSince(now)),
        endTime: nil,
        isBetweenBlocks: true,
        nextTitle: next.title,
        nextSubtitle: next.subtitle,
        nextColor: next.color,
        nextSymbol: next.symbol,
        nextStartTime: formatter.string(from: next.startDate)
      )
    }

    return nil
  }

  private var completedClassCount: Int {
    classBlocks.filter { now >= $0.endDate }.count
  }

  private var currentClassCount: Int {
    guard let currentBlock else { return 0 }
    return classBlocks.contains(where: { $0.id == currentBlock.id }) ? 1 : 0
  }

  private var upcomingClassCount: Int {
    max(0, classBlocks.count - completedClassCount - currentClassCount)
  }

  private var dayProgress: Double {
    guard let first = primaryDatedBlocks.first, let last = primaryDatedBlocks.last else { return 0 }
    let duration = max(1, last.endDate.timeIntervalSince(first.startDate))
    return min(1, max(0, now.timeIntervalSince(first.startDate) / duration))
  }

  // MARK: - External feature previews

  private var upcomingEvents: [CalendarEvent] {
    eventsStore.events
      .filter { $0.startDate >= Calendar.current.date(byAdding: .hour, value: -2, to: now) ?? now }
      .sorted { $0.startDate < $1.startDate }
      .prefix(4)
      .map { $0 }
  }

  private var lunchRecipes: [MenuRecipe] {
    menuStore.visibleStations
      .flatMap(\.recipes)
      .reduce(into: [MenuRecipe]()) { result, recipe in
        if !result.contains(where: { $0.name.caseInsensitiveCompare(recipe.name) == .orderedSame })
        {
          result.append(recipe)
        }
      }
      .prefix(3)
      .map { $0 }
  }

  private var upcomingGames: [SportsGame] {
    let startOfToday = Calendar.current.startOfDay(for: now)
    return sportsStore.liveGames
      .filter { game in
        guard let gameDate = game.date else { return false }
        return gameDate >= startOfToday && game.status != .eliminated
      }
      .sorted { lhs, rhs in
        (lhs.date ?? .distantFuture) < (rhs.date ?? .distantFuture)
      }
      .prefix(3)
      .map { $0 }
  }

  private var rooPacSelectedPlans: [(RooPACActivityType, RooPACPlan)] {
    RooPACActivityType.officialCases.compactMap { activity in
      let plan = store.rooPacPlans[activity] ?? RooPACPlan()
      return plan.isSelected ? (activity, plan) : nil
    }
  }

  private var rooPacMinimumCredits: Int {
    rooPacSelectedPlans.reduce(0) { total, item in
      let activity = item.0
      let plan = item.1
      if let exact = plan.overrideCredits { return total + exact }
      return total + activity.minCredits
    }
  }

  private var rooPacRequirement: Int {
    store.rooPACCurrentGrade.requirement
  }

  private var rooPacProgress: Double {
    guard rooPacRequirement > 0 else { return 0 }
    return min(1, Double(rooPacMinimumCredits) / Double(rooPacRequirement))
  }

  private func isLunchBlock(_ item: DatedBlock?) -> Bool {
    guard let item else { return false }

    switch item.block.kind {
    case .special(let special):
      switch special {
      case .lunch, .lunchAndClubs:
        return true
      default:
        return false
      }
    default:
      return false
    }
  }

  private var savedGameIDs: Set<String> {
    Set(savedGameIDsRaw.split(separator: "\n").map(String.init))
  }

  private var hasFocusContext: Bool {
    guard let currentBlock else { return false }
    return classBlocks.contains(where: { $0.id == currentBlock.id })
  }

  private var contextualEvent: CalendarEvent? {
    let cutoff = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now
    return upcomingEvents.first { event in
      event.startDate >= now && event.startDate <= cutoff
    }
  }

  private func combinedGameDate(_ game: SportsGame) -> Date? {
    guard let day = game.date else { return nil }

    let time = game.time.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !time.isEmpty else {
      return Calendar.current.startOfDay(for: day)
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .current

    for format in ["h:mm a", "h:mma", "hh:mm a", "H:mm", "HH:mm"] {
      formatter.dateFormat = format
      if let parsed = formatter.date(from: time) {
        var calendar = Calendar.current
        calendar.timeZone = formatter.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: parsed)
        return calendar.date(
          bySettingHour: components.hour ?? 0,
          minute: components.minute ?? 0,
          second: 0,
          of: day
        )
      }
    }

    return Calendar.current.startOfDay(for: day)
  }

  private func gameIsContextuallyRelevant(_ game: SportsGame) -> Bool {
    guard let date = game.date,
      Calendar.current.isDate(date, inSameDayAs: now)
    else {
      return false
    }

    let rawTime = game.time.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawTime.isEmpty, let moment = combinedGameDate(game) else {
      return true
    }

    let earliest = Calendar.current.date(byAdding: .hour, value: -3, to: now) ?? now
    let latest = Calendar.current.date(byAdding: .hour, value: 8, to: now) ?? now
    return moment >= earliest && moment <= latest
  }

  private var contextualReminderGame: SportsGame? {
    sportsStore.liveGames
      .filter { savedGameIDs.contains($0.id) }
      .filter { $0.status != .cancelled && $0.status != .eliminated }
      .filter(gameIsContextuallyRelevant)
      .sorted {
        (combinedGameDate($0) ?? .distantFuture) < (combinedGameDate($1) ?? .distantFuture)
      }
      .first
  }

  private func dateForMeetingTime(_ time: Date) -> Date? {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.hour, .minute], from: time)
    return date(on: now, components: components)
  }

  private var contextualAdditionalClubMeeting: ClubMeetingContext? {
    let weekday = Calendar.current.component(.weekday, from: now)
    let upcomingCutoff = Calendar.current.date(byAdding: .minute, value: 90, to: now) ?? now

    let meetings: [ClubMeetingContext] = store.clubs.flatMap { club in
      club.otherMeetings.compactMap { meeting in
        guard meeting.weekday == weekday,
          let start = dateForMeetingTime(meeting.startTime),
          let end = dateForMeetingTime(meeting.endTime),
          end > start
        else {
          return nil
        }

        let isCurrent = now >= start && now < end
        let isSoon = start > now && start <= upcomingCutoff
        guard isCurrent || isSoon else { return nil }

        return ClubMeetingContext(
          club: club,
          startDate: start,
          endDate: end
        )
      }
    }

    return meetings.sorted { lhs, rhs in
      let lhsCurrent = now >= lhs.startDate && now < lhs.endDate
      let rhsCurrent = now >= rhs.startDate && now < rhs.endDate
      if lhsCurrent != rhsCurrent { return lhsCurrent }
      return lhs.startDate < rhs.startDate
    }
    .first
  }

  private var contextualBellClub: (title: String, subtitle: String)? {
    guard let weekday = todayWeekday else { return nil }

    if let currentBlock {
      let presentation = store.schedulePresentation(
        for: currentBlock.block,
        on: weekday
      )
      if presentation.isClub {
        return (
          presentation.title,
          "Meeting now"
        )
      }
    }

    if let nextBlock {
      let presentation = store.schedulePresentation(
        for: nextBlock.block,
        on: weekday
      )
      let secondsUntil = nextBlock.startDate.timeIntervalSince(now)
      if presentation.isClub, secondsUntil >= 0, secondsUntil <= 90 * 60 {
        return (
          presentation.title,
          "Coming up at \(shortTime(nextBlock.startDate))"
        )
      }
    }

    return nil
  }

  private var contextualLunchSubtitle: String {
    if isLunchBlock(currentBlock) {
      return "Lunch is happening now"
    }
    return "Lunch is up next"
  }

  private var contextualActions: [ContextualActionItem] {
    var actions: [ContextualActionItem] = []

    if isLunchBlock(currentBlock) || isLunchBlock(nextBlock) {
      actions.append(
        ContextualActionItem(
          id: "lunch",
          title: "Today’s Menu",
          subtitle: contextualLunchSubtitle,
          systemImage: "fork.knife",
          color: DesignTokens.Colors.dining,
          kind: .dining
        )
      )
    }

    if let club = contextualBellClub {
      actions.append(
        ContextualActionItem(
          id: "bell-club",
          title: "My Clubs",
          subtitle: "\(club.title) • \(club.subtitle)",
          systemImage: "person.3.fill",
          color: DesignTokens.Colors.events,
          kind: .clubs
        )
      )
    } else if let meeting = contextualAdditionalClubMeeting {
      let isCurrent = now >= meeting.startDate && now < meeting.endDate
      actions.append(
        ContextualActionItem(
          id: "extra-club",
          title: isCurrent ? "Club Meeting" : "Club Soon",
          subtitle: isCurrent
            ? "\(meeting.club.name) is meeting now"
            : "\(meeting.club.name) • \(shortTime(meeting.startDate))",
          systemImage: meeting.club.displayIconName,
          color: meeting.club.displayColor,
          kind: .clubs
        )
      )
    }

    if let game = contextualReminderGame {
      let gameTime = game.time.trimmingCharacters(in: .whitespacesAndNewlines)
      actions.append(
        ContextualActionItem(
          id: "saved-game",
          title: "Game Reminder",
          subtitle: gameTime.isEmpty
            ? game.team
            : "\(game.team) • \(gameTime)",
          systemImage: "bell.fill",
          color: DesignTokens.Colors.athletics,
          kind: .sports
        )
      )
    }

    if hasFocusContext {
      actions.append(
        ContextualActionItem(
          id: "focus",
          title: "Focus",
          subtitle: "Stay with your current class",
          systemImage: "rectangle.center.inset.filled",
          color: DesignTokens.Colors.today,
          kind: .focus
        )
      )
    }

    if let event = contextualEvent {
      actions.append(
        ContextualActionItem(
          id: "event-\(event.id)",
          title: "Upcoming Event",
          subtitle: event.title,
          systemImage: "calendar.circle",
          color: DesignTokens.Colors.events,
          kind: .events
        )
      )
    }

    if actions.isEmpty,
      let nextBlock,
      nextBlock.startDate.timeIntervalSince(now) >= 0,
      nextBlock.startDate.timeIntervalSince(now) <= 30 * 60
    {
      actions.append(
        ContextualActionItem(
          id: "up-next",
          title: "Up Next",
          subtitle: "\(nextBlock.title) • \(shortTime(nextBlock.startDate))",
          systemImage: nextBlock.symbol,
          color: nextBlock.color,
          kind: .schedule
        )
      )
    }

    if actions.isEmpty {
      actions.append(
        ContextualActionItem(
          id: "schedule",
          title: "Schedule",
          subtitle: "See the rest of your day",
          systemImage: "calendar",
          color: DesignTokens.Colors.schedule,
          kind: .schedule
        )
      )
    }

    return Array(actions.prefix(3))
  }

  private var hasMeaningfulContextualActions: Bool {
    contextualActions.first?.id != "schedule"
  }

  private func performContextualAction(_ kind: ContextualActionKind) {
    switch kind {
    case .dining: onOpenDining()
    case .clubs: onOpenClubs()
    case .sports: onOpenSports()
    case .focus: onOpenScheduleFocus()
    case .events: onOpenEvents()
    case .schedule: onOpenSchedule()
    }
  }

  // MARK: - Body

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
        topBar

        if !store.activeAnnouncements(at: now).isEmpty {
          announcementsSection
        } else if store.announcementError != nil {
          announcementUnavailableNotice
        }

        if let specialDay = todaySpecialSchedule {
          specialScheduleNoticeCard(specialDay)
        }

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            currentClassHero
              .frame(maxWidth: .infinity)
            dayOverviewCard
              .frame(width: 350)
          }

          VStack(spacing: DesignTokens.Spacing.lg) {
            currentClassHero
            dayOverviewCard
          }
        }

        quickActionsCard

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            scheduleTimelineCard
              .frame(maxWidth: .infinity)
            upcomingEventsCard
              .frame(width: 350)
          }

          VStack(spacing: DesignTokens.Spacing.lg) {
            scheduleTimelineCard
            upcomingEventsCard
          }
        }

        LazyVGrid(
          columns: [
            GridItem(.adaptive(minimum: 240, maximum: 360), spacing: DesignTokens.Spacing.md)
          ],
          alignment: .leading,
          spacing: DesignTokens.Spacing.md
        ) {
          lunchCard
          sportsCard
          eventPreviewCard
          pacTrackCard
        }
      }
      .padding(DesignTokens.Spacing.xl)
    }
    .background { BackgroundView() }
    .onReceive(timer) { now = $0 }
    .task {
      if eventsStore.events.isEmpty && !eventsStore.isLoading {
        eventsStore.refresh()
      }
      if menuStore.currentMenu == nil && !menuStore.isLoading {
        menuStore.refresh()
      }
    }
  }

  // MARK: - Announcements

  private var announcementsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(store.activeAnnouncements(at: now).prefix(3))) { announcement in
        announcementCard(announcement)
      }

      RemoteDataStatusLabel(
        lastUpdated: store.announcementsLastUpdated,
        usingSavedData: store.announcementsUsingSavedData
      )
      .padding(.leading, 2)
    }
  }

  private var announcementUnavailableNotice: some View {
    HStack(spacing: 10) {
      Image(systemName: "wifi.exclamationmark")
        .foregroundStyle(DesignTokens.Colors.warning)

      VStack(alignment: .leading, spacing: 2) {
        Text("Announcements couldn’t be updated")
          .font(.system(size: 11.5, weight: .semibold))
        Text("RooMate will keep trying in the background.")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      Button("Retry") {
        Task { await store.refreshAnnouncements(force: true) }
      }
      .buttonStyle(.borderless)
      .disabled(store.announcementsRefreshing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
      DesignTokens.Colors.surface.opacity(0.72),
      in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
    )
  }

  private func announcementCard(_ announcement: RooMateAnnouncement) -> some View {
    let tint = announcementTint(announcement.level)

    return HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(tint.opacity(0.13))
        Image(
          systemName: announcement.icon.isEmpty
            ? announcementIcon(announcement.level)
            : announcement.icon
        )
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(tint)
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 7) {
          Text("FROM ROOMATE")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(tint)

          if announcement.level != .info {
            Text(announcement.level == .warning ? "IMPORTANT" : "NOTICE")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(tint)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(tint.opacity(0.10), in: Capsule())
          }
        }

        Text(announcement.title)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(announcement.message)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)

        if let url = announcement.linkURL {
          Button {
            TelemetryTracker.trackAnnouncementLinkOpened(level: announcement.level.rawValue)
            openURL(url)
          } label: {
            HStack(spacing: 5) {
              Text(announcement.linkLabel.isEmpty ? "Learn More" : announcement.linkLabel)
              Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.top, 2)
        }
      }

      Spacer(minLength: 8)

      if announcement.dismissible {
        Button {
          withAnimation(DesignTokens.Animation.quick) {
            store.dismissAnnouncement(announcement)
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Dismiss announcement")
      }
    }
    .padding(14)
    .background(
      tint.opacity(0.055),
      in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
        .strokeBorder(tint.opacity(0.18), lineWidth: 1)
    }
  }

  private func announcementTint(_ level: RooMateAnnouncementLevel) -> Color {
    switch level {
    case .info: DesignTokens.Colors.info
    case .success: DesignTokens.Colors.success
    case .important: DesignTokens.Colors.primary
    case .warning: DesignTokens.Colors.warning
    }
  }

  private func announcementIcon(_ level: RooMateAnnouncementLevel) -> String {
    switch level {
    case .info: "megaphone.fill"
    case .success: "checkmark.circle.fill"
    case .important: "bell.badge.fill"
    case .warning: "exclamationmark.triangle.fill"
    }
  }

  // MARK: - Header

  private var topBar: some View {
    HStack(spacing: DesignTokens.Spacing.md) {
      HStack(spacing: DesignTokens.Spacing.md) {
        Image(systemName: greetingSymbol)
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.today)
          .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 2) {
          Text(greeting)
            .font(DesignTokens.Typography.pageTitle)
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(dateHeaderText)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }

      Spacer()

      RooGlassEffectGroup(spacing: 8) {
        HStack(spacing: DesignTokens.Spacing.sm) {
          Button(action: onOpenSchedule) {
            HStack(spacing: 7) {
              Image(systemName: "calendar")
              Text("Schedule")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 11)

          Button(action: onSearch) {
            HStack(spacing: 8) {
              Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              Text("Search RooMate")
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              Text("⌘K")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.subtleText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                  DesignTokens.Colors.selection,
                  in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .frame(minWidth: 190, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 11)
        }
      }
    }
  }

  private var greeting: String {
    let base: String
    switch Calendar.current.component(.hour, from: now) {
    case 5..<12: base = "Good morning"
    case 12..<17: base = "Good afternoon"
    case 17..<22: base = "Good evening"
    default: base = "Welcome back"
    }
    guard store.profileGreetingEnabled, let firstName = store.profileFirstName, !firstName.isEmpty
    else { return base }
    return "\(base), \(firstName)"
  }

  private var greetingSymbol: String {
    switch Calendar.current.component(.hour, from: now) {
    case 6..<18: return "sun.max"
    default: return "moon.stars"
    }
  }

  private var dateHeaderText: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: now)
  }

  // MARK: - Current class hero

  @ViewBuilder
  private func specialScheduleNoticeCard(_ day: RemoteSpecialScheduleDay) -> some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(DesignTokens.Colors.schedule.opacity(0.12))
        Image(systemName: day.isSchoolClosed ? "calendar.badge.minus" : "calendar.badge.clock")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.schedule)
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 3) {
        Text(day.isSchoolClosed ? "OFFICIAL SCHOOL CLOSURE" : "OFFICIAL SPECIAL SCHEDULE")
          .font(.system(size: 9, weight: .bold))
          .tracking(0.7)
          .foregroundStyle(DesignTokens.Colors.schedule)
        Text(day.displayTitle)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
        if !day.note.isEmpty {
          Text(day.note)
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
    }
    .padding(14)
    .rooGlass(cornerRadius: DesignTokens.Radius.md)
  }

  @ViewBuilder
  private var currentClassHero: some View {
    if let info = heroInfo {
      HStack(spacing: DesignTokens.Spacing.xl) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
          HStack(spacing: DesignTokens.Spacing.md) {
            ZStack {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(info.color.opacity(0.12))
              Image(systemName: info.symbol)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(info.color)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 5) {
              Text(info.isBetweenBlocks ? "RIGHT NOW" : "CURRENT CLASS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(
                  info.isBetweenBlocks ? DesignTokens.Colors.secondaryText : info.color)

              Text(info.title)
                .font(DesignTokens.Typography.heroTitle)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .lineLimit(1)

              if !info.subtitle.isEmpty {
                Text(info.subtitle)
                  .font(DesignTokens.Typography.subheadline)
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(1)
              }
            }
          }

          HStack(spacing: DesignTokens.Spacing.lg) {
            CountdownRing(
              progress: info.progress,
              color: info.isBetweenBlocks ? DesignTokens.Colors.today : info.color,
              remaining: info.remaining,
              isUntilNext: info.isBetweenBlocks
            )

            VStack(alignment: .leading, spacing: 3) {
              Text(info.isBetweenBlocks ? "Next block starts in" : "Period ends at")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              Text(info.isBetweenBlocks ? shortDuration(info.remaining) : (info.endTime ?? "—"))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.Colors.primaryText)

              if !info.isBetweenBlocks {
                Text("\(Int((info.progress * 100).rounded()))% complete")
                  .font(.system(size: 10, weight: .semibold, design: .rounded))
                  .foregroundStyle(info.color)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let nextTitle = info.nextTitle {
          Rectangle()
            .fill(DesignTokens.Colors.border)
            .frame(width: 1, height: 120)

          VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("UP NEXT")
              .font(.system(size: 11, weight: .semibold))
              .tracking(0.8)
              .foregroundStyle(info.nextColor ?? DesignTokens.Colors.secondaryText)

            HStack(spacing: DesignTokens.Spacing.md) {
              ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .fill((info.nextColor ?? DesignTokens.Colors.schedule).opacity(0.11))
                Image(systemName: info.nextSymbol ?? "calendar")
                  .font(.system(size: 17, weight: .semibold))
                  .foregroundStyle(info.nextColor ?? DesignTokens.Colors.schedule)
              }
              .frame(width: 44, height: 44)

              VStack(alignment: .leading, spacing: 3) {
                Text(nextTitle)
                  .font(.system(size: 18, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.primaryText)
                  .lineLimit(2)
                  .fixedSize(horizontal: false, vertical: true)
                  .layoutPriority(1)
                if let subtitle = info.nextSubtitle, !subtitle.isEmpty {
                  Text(subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if let start = info.nextStartTime {
                  Text(start)
                    .font(DesignTokens.Typography.metadata)
                    .foregroundStyle(info.nextColor ?? DesignTokens.Colors.schedule)
                }
              }
            }

            if isLunchBlock(nextBlock) {
              Button(action: onOpenDining) {
                HStack {
                  Label("View Today’s Menu", systemImage: "fork.knife")
                  Spacer()
                  Image(systemName: "arrow.right")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.dining)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
                .background(
                  DesignTokens.Colors.dining.opacity(0.10),
                  in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
              }
              .buttonStyle(.plain)
            } else {
              Button(action: onOpenSchedule) {
                HStack {
                  Text("View Full Schedule")
                  Spacer()
                  Image(systemName: "arrow.right")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
                .background(
                  DesignTokens.Colors.selection,
                  in: RoundedRectangle(cornerRadius: 9, style: .continuous))
              }
              .buttonStyle(.plain)
            }
          }
          .frame(minWidth: 255, idealWidth: 280, maxWidth: 300, alignment: .leading)
        }
      }
      .padding(DesignTokens.Spacing.xl)
      .frame(minHeight: 220)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: true)
    } else {
      noSchoolHero
    }
  }

  private var noSchoolHero: some View {
    HStack(spacing: DesignTokens.Spacing.lg) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(DesignTokens.Colors.today.opacity(0.12))
        Image(systemName: todayWeekday == nil ? "sun.max.fill" : "checkmark.circle.fill")
          .font(.system(size: 27))
          .foregroundStyle(DesignTokens.Colors.today)
      }
      .frame(width: 62, height: 62)

      VStack(alignment: .leading, spacing: 4) {
        let closedDay = todaySpecialSchedule?.isSchoolClosed == true
        Text(closedDay || todayWeekday == nil ? "NO SCHOOL TODAY" : "SCHOOL DAY COMPLETE")
          .font(.system(size: 11, weight: .semibold))
          .tracking(0.8)
          .foregroundStyle(DesignTokens.Colors.today)
        Text(
          closedDay
            ? (todaySpecialSchedule?.displayTitle ?? "School Closed")
            : (todayWeekday == nil ? "Enjoy the weekend" : "You're done for today")
        )
        .font(DesignTokens.Typography.heroTitle)
        let closedDayNote = todaySpecialSchedule.flatMap { schedule -> String? in
          let trimmed = schedule.note.trimmingCharacters(in: .whitespacesAndNewlines)
          return trimmed.isEmpty ? nil : trimmed
        }
        Text(
          closedDay
            ? (closedDayNote ?? "There are no classes scheduled today.")
            : (todayWeekday == nil
              ? "Your school-day tools are still here when you need them."
              : "Check what's coming up next or plan ahead for tomorrow.")
        )
        .font(DesignTokens.Typography.subheadline)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      Spacer()
    }
    .padding(DesignTokens.Spacing.xl)
    .frame(minHeight: 180)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: true)
  }

  // MARK: - Day overview

  private var dayOverviewProgressTitle: String {
    guard let first = primaryDatedBlocks.first,
      let last = primaryDatedBlocks.last
    else {
      return "School day"
    }

    if now < first.startDate {
      return "School starts soon"
    }

    if now >= last.endDate {
      return "School day complete"
    }

    return "School day progress"
  }

  private var dayOverviewProgressSubtitle: String {
    guard let first = primaryDatedBlocks.first,
      let last = primaryDatedBlocks.last
    else {
      return "No schedule available"
    }

    if now < first.startDate {
      return
        "Your first block starts at \(first.startDate.formatted(date: .omitted, time: .shortened))"
    }

    if now >= last.endDate {
      return "You're done for the day"
    }

    if let currentBlock {
      return "\(currentBlock.title) is happening now"
    }

    return "Between blocks"
  }

  private func overviewCountPill(
    value: Int,
    label: String
  ) -> some View {
    HStack(spacing: 4) {
      Text("\(value)")
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(DesignTokens.Colors.primaryText)

      Text(label)
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
    }
    .padding(.horizontal, 8)
    .frame(height: 24)
    .background(
      DesignTokens.Colors.hover.opacity(0.30),
      in: Capsule()
    )
    .overlay {
      Capsule()
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  private var dayOverviewCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        SectionLabel("DAY OVERVIEW")

        Spacer()

        Text("\(classBlocks.count) classes")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 9)
          .frame(height: 24)
          .background(DesignTokens.Colors.selection, in: Capsule())
      }

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(dayOverviewProgressTitle)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(dayOverviewProgressSubtitle)
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Text("\(Int((dayProgress * 100).rounded()))%")
            .font(
              .system(
                size: 20,
                weight: .semibold,
                design: .rounded
              )
            )
            .foregroundStyle(DesignTokens.Colors.today)
            .contentTransition(.numericText())
        }

        DayProgressBar(
          progress: dayProgress,
          color: DesignTokens.Colors.today
        )
        .frame(height: 8)

        HStack(spacing: 7) {
          overviewCountPill(
            value: completedClassCount,
            label: "done"
          )

          overviewCountPill(
            value: upcomingClassCount,
            label: "up next"
          )

          if freeBlockCount > 0 {
            overviewCountPill(
              value: freeBlockCount,
              label: "free"
            )
          }

          Spacer()
        }
      }

      HStack(spacing: 8) {
        Circle()
          .fill(dayOverviewStatusColor)
          .frame(width: 7, height: 7)

        Text(dayOverviewStatusText)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)

        Spacer(minLength: 6)

        Button(action: onOpenSchedule) {
          HStack(spacing: 5) {
            Text("Schedule")
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .semibold))
          }
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .fixedSize(horizontal: true, vertical: false)
          .contentShape(Rectangle())
          .background(DesignTokens.Colors.selection, in: Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(3)
      }
      .padding(.top, 1)
    }
    .padding(DesignTokens.Spacing.lg)
    .frame(minHeight: 220)
    .rooGlass(cornerRadius: DesignTokens.Radius.lg)
  }

  private var dayOverviewStatusText: String {
    if currentClassCount > 0 {
      return "You're in the middle of the school day"
    }
    if upcomingClassCount > 0 {
      return upcomingClassCount == 1
        ? "1 class left today" : "\(upcomingClassCount) classes left today"
    }
    if completedClassCount > 0 {
      return "School day complete"
    }
    return todayWeekday == nil ? "No school today" : "Ready for the day"
  }

  private var dayOverviewStatusColor: Color {
    if currentClassCount > 0 { return DesignTokens.Colors.pacTrack }
    if upcomingClassCount > 0 { return DesignTokens.Colors.today }
    if completedClassCount > 0 { return DesignTokens.Colors.athletics }
    return DesignTokens.Colors.schedule
  }

  // MARK: - Contextual actions

  private var quickActionsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        SectionLabel("CONTEXTUAL ACTIONS")

        Spacer()

        Text(
          hasMeaningfulContextualActions ? "Based on what’s happening now" : "Your day at a glance"
        )
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.subtleText)
      }

      HStack(spacing: 10) {
        ForEach(contextualActions) { item in
          contextualActionButton(
            title: item.title,
            subtitle: item.subtitle,
            systemImage: item.systemImage,
            color: item.color
          ) {
            performContextualAction(item.kind)
          }
        }
      }
    }
    .padding(16)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func contextualActionButton(
    title: String,
    subtitle: String,
    systemImage: String,
    color: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(color.opacity(0.12))

          Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)

          Text(subtitle)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
        .layoutPriority(1)

        Spacer(minLength: 4)

        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .rooInteractiveGlass(cornerRadius: 12)
  }

  // MARK: - Schedule timeline

  private var scheduleTimelineCard: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
      HStack {
        SectionLabel("TODAY'S SCHEDULE")
        Spacer()
        if !classBlocks.isEmpty {
          Text("\(classBlocks.count) classes")
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }

      if classBlocks.isEmpty {
        EmptyPreviewState(
          symbol: "calendar",
          text: todayWeekday == nil ? "No classes today" : "No classes configured"
        )
        .frame(minHeight: 180)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(classBlocks.enumerated()), id: \.element.id) { index, item in
            ScheduleTimelineRow(
              item: item,
              isCurrent: currentBlock?.id == item.id,
              isPast: now >= item.endDate,
              remainingText: currentBlock?.id == item.id
                ? shortDuration(item.endDate.timeIntervalSince(now)) + " remaining" : nil,
              showTopLine: index > 0,
              showBottomLine: index < classBlocks.count - 1
            )
          }
        }
      }
    }
    .padding(DesignTokens.Spacing.lg)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: - Upcoming events

  private var upcomingEventsCard: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
      SectionLabel("UPCOMING EVENTS")

      if eventsStore.isLoading && upcomingEvents.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 150)
      } else if upcomingEvents.isEmpty {
        EmptyPreviewState(symbol: "calendar.badge.clock", text: "No upcoming events")
          .frame(minHeight: 150)
      } else {
        VStack(spacing: 6) {
          ForEach(upcomingEvents.prefix(3)) { event in
            EventPreviewRow(event: event)
          }
        }
      }

      Spacer(minLength: 0)

      Button(action: onOpenEvents) {
        Text("View All Events")
          .font(.system(size: 12, weight: .medium))
          .frame(maxWidth: .infinity)
          .frame(height: 32)
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .background(
            DesignTokens.Colors.selection, in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(DesignTokens.Spacing.lg)
    .frame(minHeight: 300)
    .rooGlass(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: - Bottom feature cards

  private var lunchCard: some View {
    FeaturePreviewCard(
      title: "TODAY'S LUNCH",
      accent: DesignTokens.Colors.dining,
      actionTitle: "View Menu",
      action: onOpenDining
    ) {
      if menuStore.isLoading && lunchRecipes.isEmpty {
        ProgressView().frame(maxWidth: .infinity, minHeight: 140)
      } else if lunchRecipes.isEmpty {
        EmptyPreviewState(symbol: "fork.knife", text: "Lunch menu isn't available yet")
          .frame(minHeight: 140)
      } else {
        VStack(spacing: 8) {
          ForEach(lunchRecipes) { recipe in
            HStack(spacing: 10) {
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(DesignTokens.Colors.dining.opacity(0.11))
                Image(systemName: recipe.lifestyleTags.isEmpty ? "fork.knife" : "leaf.fill")
                  .foregroundStyle(DesignTokens.Colors.dining)
              }
              .frame(width: 36, height: 36)

              VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                  .font(.system(size: 13, weight: .semibold))
                  .lineLimit(1)
                Text(recipe.stationName)
                  .font(.caption)
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(1)
              }
              Spacer()
            }
          }
        }
      }
    }
  }

  private var sportsCard: some View {
    FeaturePreviewCard(
      title: "SPORTS",
      accent: DesignTokens.Colors.athletics,
      actionTitle: "View All",
      action: onOpenSports
    ) {
      if sportsStore.isLoading && upcomingGames.isEmpty {
        ProgressView().frame(maxWidth: .infinity, minHeight: 140)
      } else if upcomingGames.isEmpty {
        EmptyPreviewState(symbol: "sportscourt", text: "No upcoming games found")
          .frame(minHeight: 140)
      } else {
        VStack(spacing: 8) {
          ForEach(upcomingGames.prefix(2)) { game in
            SportsPreviewRow(game: game)
          }
        }
      }
    }
  }

  private var eventPreviewCard: some View {
    FeaturePreviewCard(
      title: "EVENTS",
      accent: DesignTokens.Colors.events,
      actionTitle: "View Calendar",
      action: onOpenEvents
    ) {
      if upcomingEvents.isEmpty {
        EmptyPreviewState(symbol: "calendar", text: "Nothing coming up yet")
          .frame(minHeight: 140)
      } else {
        VStack(spacing: 8) {
          ForEach(upcomingEvents.prefix(2)) { event in
            EventPreviewRow(event: event, compact: true)
          }
        }
      }
    }
  }

  private var pacTrackCard: some View {
    FeaturePreviewCard(
      title: "PACTRACK",
      accent: DesignTokens.Colors.pacTrack,
      actionTitle: "View Details",
      action: onOpenPacTrack
    ) {
      HStack(spacing: DesignTokens.Spacing.lg) {
        ZStack {
          Circle()
            .stroke(DesignTokens.Colors.selection, lineWidth: 7)
          Circle()
            .trim(from: 0, to: CGFloat(rooPacProgress))
            .stroke(
              DesignTokens.Colors.athletics, style: StrokeStyle(lineWidth: 7, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
          VStack(spacing: 0) {
            Text("\(Int(rooPacProgress * 100))%")
              .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(rooPacMinimumCredits >= rooPacRequirement ? "On track" : "Planned")
              .font(.caption2)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }
        .frame(width: 96, height: 96)

        VStack(alignment: .leading, spacing: 10) {
          PacTrackMetric(
            symbol: "checkmark", color: DesignTokens.Colors.athletics, title: "Planned",
            value: "\(rooPacMinimumCredits)")
          PacTrackMetric(
            symbol: "flag.fill", color: DesignTokens.Colors.pacTrack, title: "Required",
            value: "\(rooPacRequirement)")
          PacTrackMetric(
            symbol: "list.bullet", color: DesignTokens.Colors.today, title: "Activities",
            value: "\(rooPacSelectedPlans.count)")
        }
      }
      .frame(maxWidth: .infinity, minHeight: 140)
    }
  }

  // MARK: - Formatting

  private func shortDuration(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval.rounded()))
    let minutes = seconds / 60
    if minutes >= 60 {
      let hours = minutes / 60
      let remainder = minutes % 60
      return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
    if minutes > 0 { return "\(minutes) min" }
    return "<1 min"
  }
}

// MARK: - Today components

private struct SectionLabel: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 11, weight: .semibold))
      .tracking(0.7)
      .foregroundStyle(DesignTokens.Colors.secondaryText)
  }
}

private struct CountdownRing: View {
  let progress: Double
  let color: Color
  let remaining: TimeInterval
  let isUntilNext: Bool

  var body: some View {
    ZStack {
      Circle()
        .stroke(DesignTokens.Colors.selection, lineWidth: 6)
      Circle()
        .trim(from: 0, to: CGFloat(max(0.02, min(1, progress))))
        .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        .rotationEffect(.degrees(-90))

      VStack(spacing: -1) {
        Text(remainingValue)
          .font(.system(size: 27, weight: .semibold, design: .rounded))
        Text(remainingUnit)
          .font(.caption2)
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        if isUntilNext {
          Text("until next")
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
      }
    }
    .frame(width: 94, height: 94)
  }

  private var remainingValue: String {
    let minutes = max(0, Int(remaining) / 60)
    if minutes >= 60 { return "\(minutes / 60)h" }
    return "\(max(1, minutes))"
  }

  private var remainingUnit: String {
    Int(remaining) / 60 >= 60 ? "remaining" : "min"
  }
}

private struct OverviewLegendRow: View {
  let color: Color
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(text)
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .lineLimit(1)
    }
  }
}

private struct DayProgressBar: View {
  let progress: Double
  let color: Color

  private var clampedProgress: CGFloat {
    CGFloat(min(1, max(0, progress)))
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(DesignTokens.Colors.selection)

        Capsule()
          .fill(color)
          .frame(
            width: max(
              clampedProgress > 0 ? 8 : 0,
              proxy.size.width * clampedProgress
            )
          )
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("School day progress")
    .accessibilityValue(
      "\(Int((progress * 100).rounded())) percent"
    )
  }
}

private struct ScheduleTimelineRow: View {
  let item: DashboardView.DatedBlock
  let isCurrent: Bool
  let isPast: Bool
  let remainingText: String?
  let showTopLine: Bool
  let showBottomLine: Bool

  var body: some View {
    HStack(spacing: 12) {
      Text(timeText)
        .font(.system(size: 12, weight: isCurrent ? .semibold : .medium, design: .rounded))
        .foregroundStyle(
          isCurrent ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText
        )
        .frame(width: 68, alignment: .trailing)

      ZStack {
        if showTopLine {
          Rectangle()
            .fill(DesignTokens.Colors.borderStrong)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .offset(y: -22)
        }
        if showBottomLine {
          Rectangle()
            .fill(DesignTokens.Colors.borderStrong)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .offset(y: 22)
        }

        Circle()
          .fill(isPast ? DesignTokens.Colors.subtleText : item.color)
          .frame(width: isCurrent ? 13 : 10, height: isCurrent ? 13 : 10)
          .overlay {
            if isCurrent {
              Circle().stroke(item.color.opacity(0.30), lineWidth: 5)
            }
          }
      }
      .frame(width: 18, height: 48)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
          .foregroundStyle(
            isPast ? DesignTokens.Colors.secondaryText : DesignTokens.Colors.primaryText
          )
          .lineLimit(1)
        if !item.subtitle.isEmpty {
          Text(item.subtitle)
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
      }

      Spacer()

      if let remainingText {
        Text(remainingText)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(item.color)
      }
    }
    .padding(.horizontal, isCurrent ? 10 : 0)
    .frame(minHeight: 52)
    .background {
      if isCurrent {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(item.color.opacity(0.08))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .stroke(item.color.opacity(0.16), lineWidth: 1)
          }
      }
    }
  }

  private var timeText: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: item.startDate)
  }
}

private struct EventPreviewRow: View {
  let event: CalendarEvent
  var compact: Bool = false

  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(eventColor.opacity(0.13))
        Image(systemName: eventSymbol)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(eventColor)
      }
      .frame(width: compact ? 36 : 40, height: compact ? 36 : 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(compact ? 1 : 2)
          .fixedSize(horizontal: false, vertical: true)
        if let location = event.location, !location.isEmpty {
          Text(location)
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        Text(dateText)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Text(timeText)
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
      .fixedSize()

    }
    .padding(.vertical, 5)
  }

  private var lowerTitle: String { event.title.lowercased() }

  private var eventSymbol: String {
    if lowerTitle.contains("concert") || lowerTitle.contains("music") { return "music.note" }
    if lowerTitle.contains("theater") || lowerTitle.contains("talent")
      || lowerTitle.contains("play")
    {
      return "theatermasks.fill"
    }
    if lowerTitle.contains("soccer") || lowerTitle.contains("game")
      || lowerTitle.contains("athletic")
    {
      return "sportscourt.fill"
    }
    if lowerTitle.contains("commencement") || lowerTitle.contains("graduation") {
      return "graduationcap.fill"
    }
    return "calendar"
  }

  private var eventColor: Color {
    if lowerTitle.contains("concert") || lowerTitle.contains("music") {
      return DesignTokens.Colors.pacTrack
    }
    if lowerTitle.contains("soccer") || lowerTitle.contains("game")
      || lowerTitle.contains("athletic")
    {
      return DesignTokens.Colors.athletics
    }
    return DesignTokens.Colors.events
  }

  private var dateText: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: event.startDate)
  }

  private var timeText: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: event.startDate)
  }
}

private struct SportsPreviewRow: View {
  let game: SportsGame

  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(DesignTokens.Colors.athletics.opacity(0.12))
        Image(systemName: "sportscourt.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.athletics)
      }
      .frame(width: 38, height: 38)

      VStack(alignment: .leading, spacing: 2) {
        Text(game.team)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
        Text(game.opponent.isEmpty ? "Opponent TBA" : "vs. \(game.opponent)")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(1)
        Text(detailText)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.athletics)
          .lineLimit(1)
      }
      Spacer()
    }
  }

  private var detailText: String {
    let homeAway: String
    switch game.location.uppercased() {
    case "H": homeAway = "Home"
    case "A": homeAway = "Away"
    default: homeAway = game.location
    }

    return [game.rawDateString, game.time, homeAway]
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " • ")
  }
}

private struct FeaturePreviewCard<Content: View>: View {
  let title: String
  let accent: Color
  let actionTitle: String
  let action: () -> Void
  let content: Content

  init(
    title: String,
    accent: Color,
    actionTitle: String,
    action: @escaping () -> Void,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.accent = accent
    self.actionTitle = actionTitle
    self.action = action
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
      HStack {
        HStack(spacing: 7) {
          Circle().fill(accent).frame(width: 7, height: 7)
          SectionLabel(title)
        }
        Spacer()
        Button(actionTitle, action: action)
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 8)
          .frame(height: 24)
          .background(DesignTokens.Colors.selection, in: Capsule())
          .contentShape(Capsule())
      }

      content
    }
    .padding(DesignTokens.Spacing.lg)
    .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
    .rooGlass(cornerRadius: DesignTokens.Radius.lg)
  }
}

private struct PacTrackMetric: View {
  let symbol: String
  let color: Color
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(color)
        .frame(width: 13)
      Text(title)
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      Spacer()
      Text(value)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
    }
  }
}

private struct EmptyPreviewState: View {
  let symbol: String
  let text: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 22))
        .foregroundStyle(DesignTokens.Colors.subtleText)
      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
