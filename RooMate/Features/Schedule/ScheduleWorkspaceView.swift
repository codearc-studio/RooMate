#if os(macOS)
  import SwiftUI
  import AppKit
  import Combine

  struct ScheduleWorkspaceView: View {
    @ObservedObject var store: UserScheduleStore
    @ObservedObject var sportsStore: SportsStore
    @ObservedObject private var navigation = RooMateNavigationCoordinator.shared
    @Binding var selectedDay: Weekday
    @Binding var isFocusMode: Bool

    @AppStorage("RooMateSportsGameReminders")
    private var savedGameIDsRaw = ""

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedDate: Date = Date()
    @State private var mode: ScheduleMode = .day
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var showSpecialBlocks = true
    @State private var showFreePeriods = true
    @State private var didCopySchedule = false
    @State private var showClearSemesterPlanConfirmation = false
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let calendar = Calendar.current

    private enum ScheduleMode: String, CaseIterable, Identifiable {
      case day = "Day"
      case week = "Week"
      case special = "Special"
      // Semester Planner ships in RooMate 6. The separate Study Planner remains future work.
      case planner = "Plan"
      var id: String { rawValue }
    }

    private var visibleModes: [ScheduleMode] { [.day, .week, .special, .planner] }

    private struct ScheduleEntry: Identifiable {
      let id: UUID
      let block: BellBlock
      let title: String
      let subtitle: String
      let teacher: String?
      let room: String?
      let color: Color
      let systemImage: String
      let isFree: Bool
      let isSpecial: Bool
      let level: Level?
      let special: SpecialBlock?
      let timelineType: BellBlockTimelineType
      let startDate: Date
      let endDate: Date

      var durationMinutes: Int {
        max(0, Int(endDate.timeIntervalSince(startDate) / 60))
      }
    }

    private struct ScheduleDayContext {
      let title: String
      let message: String
      let status: String
      let systemImage: String
      let color: Color
    }

    private var selectedWeekday: Weekday? {
      weekday(for: selectedDate)
    }

    private var selectedSpecialSchedule: RemoteSpecialScheduleDay? {
      store.remoteSpecialScheduleDay(on: selectedDate)
    }

    private var selectedDayContext: ScheduleDayContext? {
      scheduleDayContext(on: selectedDate)
    }

    private var scheduleStatusTitle: String {
      if let special = selectedSpecialSchedule {
        if special.isSchoolClosed { return "School closed" }
        return special.isAwaitingSchedule ? "Special schedule pending" : "Special schedule"
      }
      if let state = store.schoolDateState(on: selectedDate) {
        switch state {
        case .breakPeriod: return "School break"
        case .beforeSchoolYear: return "School hasn’t started"
        case .afterSchoolYear: return "School year complete"
        case .inSession: break
        }
      }
      return selectedWeekday == nil ? "No school" : "Regular schedule"
    }

    private var scheduleStatusInfoValue: String {
      if let special = selectedSpecialSchedule {
        if special.isSchoolClosed { return "School closed" }
        return special.isAwaitingSchedule ? "Awaiting schedule" : "Special day"
      }
      if let state = store.schoolDateState(on: selectedDate) {
        switch state {
        case .breakPeriod(let period): return period.displayTitle
        case .beforeSchoolYear: return "Before school year"
        case .afterSchoolYear: return "School year complete"
        case .inSession: break
        }
      }
      return selectedWeekday == nil ? "No school" : "Regular day"
    }

    private var scheduleStatusColor: Color {
      if let special = selectedSpecialSchedule {
        if special.isSchoolClosed { return DesignTokens.Colors.subtleText }
        return special.isAwaitingSchedule ? DesignTokens.Colors.warning : DesignTokens.Colors.schedule
      }
      if let state = store.schoolDateState(on: selectedDate), state.suppressesRegularSchedule {
        return DesignTokens.Colors.events
      }
      return selectedWeekday == nil
        ? DesignTokens.Colors.subtleText
        : DesignTokens.Colors.athletics
    }

    private var scheduleStatusSystemImage: String {
      if let special = selectedSpecialSchedule {
        if special.isSchoolClosed { return "calendar.badge.minus" }
        return special.isAwaitingSchedule ? "hourglass" : "calendar.badge.clock"
      }
      if let state = store.schoolDateState(on: selectedDate) {
        switch state {
        case .breakPeriod: return "beach.umbrella.fill"
        case .beforeSchoolYear: return "calendar.badge.clock"
        case .afterSchoolYear: return "checkmark.circle.fill"
        case .inSession: break
        }
      }
      return selectedWeekday == nil ? "moon.zzz.fill" : "circle.fill"
    }

    private var selectedEntries: [ScheduleEntry] {
      guard let weekday = selectedWeekday else { return [] }
      return entries(for: weekday, on: selectedDate)
        .filter(matchesFilters)
    }

    private var unfilteredSelectedEntries: [ScheduleEntry] {
      guard let weekday = selectedWeekday else { return [] }
      return entries(for: weekday, on: selectedDate)
    }

    private var isViewingToday: Bool {
      calendar.isDate(selectedDate, inSameDayAs: now)
    }

    private var primarySelectedEntries: [ScheduleEntry] {
      unfilteredSelectedEntries.filter { $0.timelineType == .block }
    }

    private var currentEntry: ScheduleEntry? {
      guard isViewingToday else { return nil }
      return primarySelectedEntries.first { now >= $0.startDate && now < $0.endDate }
    }

    private var nextEntry: ScheduleEntry? {
      let reference = isViewingToday ? now : calendar.startOfDay(for: selectedDate)
      return primarySelectedEntries.first { $0.startDate > reference }
    }

    private var firstEntry: ScheduleEntry? {
      primarySelectedEntries.first
    }

    private var lastEntry: ScheduleEntry? {
      primarySelectedEntries.last
    }

    private var classEntries: [ScheduleEntry] {
      primarySelectedEntries.filter { $0.level != nil && !$0.isFree }
    }

    private var freeEntries: [ScheduleEntry] {
      unfilteredSelectedEntries.filter(\.isFree)
    }

    private var completedCount: Int {
      guard isViewingToday else { return 0 }
      return classEntries.filter { now >= $0.endDate }.count
    }

    private var currentCount: Int {
      guard isViewingToday else { return 0 }
      return classEntries.filter { now >= $0.startDate && now < $0.endDate }.count
    }

    private var upcomingCount: Int {
      if isViewingToday {
        return classEntries.filter { now < $0.startDate }.count
      }
      return classEntries.count
    }

    private var dayProgress: Double {
      guard let first = firstEntry, let last = lastEntry, isViewingToday else { return 0 }
      let duration = max(1, last.endDate.timeIntervalSince(first.startDate))
      return min(1, max(0, now.timeIntervalSince(first.startDate) / duration))
    }

    private var academicPlannerLevels: [Level] {
      Level.allCases.filter { $0 != .music }
    }

    private var plannedAcademicCount: Int {
      academicPlannerLevels.filter { level in
        let assignment = store.semesterPlanAssignment(for: level)
        let title = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return assignment.isFree || (!title.isEmpty && title != level.displayName)
      }.count
    }

    private var nextSemesterTitle: String {
      let month = calendar.component(.month, from: now)
      let year = calendar.component(.year, from: now)

      if month >= 7 {
        return "Spring \(year + 1)"
      } else {
        return "Fall \(year)"
      }
    }

    private var schedulePageTitle: String {
      switch mode {
      case .planner: return "Semester Planner"
      case .special: return "School Calendar"
      case .day, .week: return "Schedule"
      }
    }

    private var schedulePageSubtitle: String {
      switch mode {
      case .planner:
        return "Planning \(nextSemesterTitle) • separate from your current schedule"
      case .special:
        return "Official special schedules, closures, breaks, and school-year dates"
      case .day, .week:
        if let special = selectedSpecialSchedule {
          return "\(longDate(selectedDate)) • \(special.displayTitle)"
        }
        if case .breakPeriod(let period) = store.schoolDateState(on: selectedDate) {
          return "\(longDate(selectedDate)) • \(period.displayTitle)"
        }
        return longDate(selectedDate)
      }
    }

    private var savedGameIDs: Set<String> {
      Set(savedGameIDsRaw.split(separator: "\n").map(String.init))
    }

    private var reminderGamesForSelectedDate: [SportsGame] {
      reminderGames(on: selectedDate)
    }

    private func reminderGames(on date: Date) -> [SportsGame] {
      guard !savedGameIDs.isEmpty else { return [] }

      return sportsStore.liveGames
        .filter { game in
          guard savedGameIDs.contains(game.id),
            let gameDate = game.date
          else {
            return false
          }

          return calendar.isDate(gameDate, inSameDayAs: date)
        }
        .sorted {
          sportsGameMoment($0) < sportsGameMoment($1)
        }
    }

    private func sportsGameMoment(_ game: SportsGame) -> Date {
      guard let day = game.date else {
        return .distantFuture
      }

      let time = game.time
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard !time.isEmpty else {
        return calendar.startOfDay(for: day)
      }

      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")

      for format in ["h:mm a", "h:mma", "hh:mm a", "h a", "ha", "H:mm", "HH:mm"] {
        formatter.dateFormat = format

        if let parsed = formatter.date(from: time) {
          let components = calendar.dateComponents(
            [.hour, .minute],
            from: parsed
          )

          return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: day
          ) ?? day
        }
      }

      return calendar.startOfDay(for: day)
    }

    private func isAwayGame(_ game: SportsGame) -> Bool {
      let value = game.location
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      return value == "a" || value == "away"
    }

    private func sportsLocationText(_ game: SportsGame) -> String {
      let value = game.location
        .trimmingCharacters(in: .whitespacesAndNewlines)

      if value.caseInsensitiveCompare("H") == .orderedSame
        || value.caseInsensitiveCompare("Home") == .orderedSame
      {
        return "Home"
      }

      if value.caseInsensitiveCompare("A") == .orderedSame
        || value.caseInsensitiveCompare("Away") == .orderedSame
      {
        return "Away"
      }

      return value.isEmpty ? "Location TBA" : value
    }

    private func sportsOpponentText(_ game: SportsGame) -> String {
      let opponent = game.opponent
        .trimmingCharacters(in: .whitespacesAndNewlines)

      guard !opponent.isEmpty else {
        return "Opponent TBA"
      }

      return isAwayGame(game)
        ? "at \(opponent)"
        : "vs \(opponent)"
    }

    private func sportsStatusText(_ game: SportsGame) -> String? {
      switch game.status {
      case .scheduled:
        return nil
      case .cancelled:
        return "Cancelled"
      case .rescheduled:
        return "Rescheduled"
      case .conditional:
        return "Conditional"
      case .eliminated:
        return "Eliminated"
      }
    }

    private func sportsStatusColor(_ game: SportsGame) -> Color {
      switch game.status {
      case .scheduled:
        return SportIconConfiguration.teamColor(for: game.team)
      case .cancelled, .eliminated:
        return DesignTokens.Colors.destructive
      case .rescheduled, .conditional:
        return DesignTokens.Colors.warning
      }
    }

    var body: some View {
      VStack(spacing: 0) {
        scheduleHeader
          .padding(.horizontal, 24)
          .padding(.top, 22)
          .padding(.bottom, 16)
          .zIndex(10)

        if mode == .day, let special = selectedSpecialSchedule {
          officialSpecialScheduleBanner(special)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }

        Group {
          switch mode {
          case .day:
            dayWorkspace
              .transition(.opacity.combined(with: .scale(scale: 0.995)))
          case .week:
            weekWorkspace
              .transition(.opacity.combined(with: .scale(scale: 0.995)))
          case .special:
            specialSchedulesWorkspace
              .transition(.opacity.combined(with: .move(edge: .trailing)))
          case .planner:
            semesterPlannerWorkspace
              .transition(.opacity.combined(with: .move(edge: .trailing)))
          }
        }
        .id(mode)
        .animation(DesignTokens.Animation.content, value: mode)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background { BackgroundView() }
      .onReceive(timer) { now = $0 }
      .onAppear {
        syncSelectedDayFromDate()
        handleNavigationRequest()
      }
      .onChange(of: navigation.request) { _, _ in handleNavigationRequest() }
      .onChange(of: selectedDate) { _, _ in
        syncSelectedDayFromDate()
      }
      .onChange(of: selectedDay) { _, newDay in
        if selectedWeekday != newDay {
          withAnimation(DesignTokens.Animation.content) {
            selectedDate = date(for: newDay, relativeTo: selectedDate)
          }
        }
      }
      .confirmationDialog(
        "Clear your \(nextSemesterTitle) plan?",
        isPresented: $showClearSemesterPlanConfirmation,
        titleVisibility: .visible
      ) {
        Button("Clear Semester Plan", role: .destructive) {
          TelemetryTracker.trackSemesterPlannerCleared()
          withAnimation(DesignTokens.Animation.content) {
            store.clearSemesterPlan()
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This won’t change your current schedule.")
      }
    }

    private func handleNavigationRequest() {
      guard let request = navigation.request,
        case .scheduleClass(let level) = request.destination
      else { return }

      let start = calendar.startOfDay(for: Date())
      if let date = (0..<14).compactMap({ calendar.date(byAdding: .day, value: $0, to: start) })
        .first(where: { date in
          store.bellBlocks(for: date).contains { block in
            if case .level(let blockLevel) = block.kind { return blockLevel == level }
            return false
          }
        })
      {
        selectedDate = date
        mode = .day
      }
      navigation.consume(request)
    }

    private func officialSpecialScheduleBanner(_ day: RemoteSpecialScheduleDay) -> some View {
      HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DesignTokens.Colors.schedule.opacity(0.11))
          Image(systemName: day.isSchoolClosed ? "calendar.badge.minus" : "calendar.badge.clock")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)
        }
        .frame(width: 38, height: 38)

        VStack(alignment: .leading, spacing: 3) {
          Text(day.isSchoolClosed ? "OFFICIAL SCHOOL CLOSURE" : "OFFICIAL SPECIAL SCHEDULE")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(DesignTokens.Colors.schedule)
          Text(day.displayTitle)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          if day.isAwaitingSchedule {
            Text("Exact bell times haven’t been published yet. RooMate will update this day automatically when they’re available.")
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          if !day.note.isEmpty {
            Text(day.note)
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer()
      }
      .padding(12)
      .rooGlass(cornerRadius: 13)
    }

    // MARK: - Header

    private var scheduleHeader: some View {
      VStack(spacing: 12) {
        HStack(alignment: .center, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(schedulePageTitle)
              .font(DesignTokens.Typography.pageTitle)
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(schedulePageSubtitle)
              .font(.system(size: 13, weight: .regular))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          if mode == .day || mode == .week {
            RooGlassEffectGroup(spacing: 8) {
              HStack(spacing: 8) {
                Button {
                  withAnimation(.easeOut(duration: 0.16)) {
                    showFilters.toggle()
                  }
                } label: {
                  Label("Filters", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .rooInteractiveGlass(cornerRadius: 11)
                .popover(isPresented: $showFilters, arrowEdge: .top) {
                  customFiltersMenu
                    .padding(2)
                }

                HStack(spacing: 8) {
                  Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.Colors.secondaryText)

                  TextField("Search classes", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 150)

                  if !searchText.isEmpty {
                    Button {
                      searchText = ""
                    } label: {
                      Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.subtleText)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                  } else {
                    Text("⌘K")
                      .font(.system(size: 10, weight: .semibold))
                      .foregroundStyle(DesignTokens.Colors.subtleText)
                      .padding(.horizontal, 6)
                      .frame(height: 20)
                      .background(
                        DesignTokens.Colors.selection,
                        in: RoundedRectangle(cornerRadius: 5)
                      )
                  }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .rooInteractiveGlass(cornerRadius: 11)
              }
            }
          }
        }

        HStack(spacing: 12) {
          modePicker

          if mode == .planner {
            semesterPlannerToolbar
          } else if mode == .special {
            officialScheduleToolbar
          } else {
            dateNavigation

            if mode == .day {
              Button {
                withAnimation(DesignTokens.Animation.snappy) {
                  isFocusMode.toggle()
                }
              } label: {
                HStack(spacing: 7) {
                  Image(
                    systemName: isFocusMode
                      ? "rectangle.split.3x1"
                      : "rectangle.center.inset.filled"
                  )
                  .font(.system(size: 11, weight: .semibold))

                  Text(isFocusMode ? "Show Panels" : "Focus")
                    .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .rooInteractiveGlass(cornerRadius: 10)
              .help(
                isFocusMode
                  ? "Show schedule side panels"
                  : "Hide side panels and focus on the schedule"
              )
            }
          }

          Spacer()
        }
      }
    }

    private var modePicker: some View {
      HStack(spacing: 3) {
        ForEach(visibleModes) { item in
          Button {
            showFilters = false

            if item != .day {
              isFocusMode = false
            }

            if item == .planner || item == .special {
              showFilters = false
              searchText = ""
            }

            TelemetryTracker.trackScheduleModeSelected(item.rawValue.lowercased())
            withAnimation(DesignTokens.Animation.navigation) {
              mode = item
            }
          } label: {
            Text(item.rawValue)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(
                mode == item
                  ? DesignTokens.Colors.primaryText
                  : DesignTokens.Colors.secondaryText
              )
              .frame(width: item == .special ? 70 : 62, height: 34)
              .contentShape(Rectangle())
              .background {
                if mode == item {
                  RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(DesignTokens.Colors.selection)
                }
              }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(2)
      .rooGlass(cornerRadius: 11)
    }

    private var dateNavigation: some View {
      HStack(spacing: 4) {
        iconButton("chevron.left") { moveSchoolDay(by: -1) }

        Button {
          withAnimation(DesignTokens.Animation.snappy) {
            selectedDate = Date()
          }
        } label: {
          HStack(spacing: 6) {
            if !isViewingToday {
              Circle()
                .fill(DesignTokens.Colors.schedule)
                .frame(width: 5, height: 5)
            }

            Text(isViewingToday ? "Today" : navigationDateLabel(selectedDate))
              .font(.system(size: 12, weight: .semibold))
          }
          .frame(width: 86)
          .frame(height: 34)
          .padding(.horizontal, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 9)
        .help("Return to today")

        iconButton("chevron.right") { moveSchoolDay(by: 1) }
      }
    }

    private func iconButton(_ name: String, action: @escaping () -> Void) -> some View {
      Button {
        withAnimation(DesignTokens.Animation.content) {
          action()
        }
      } label: {
        Image(systemName: name)
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 34, height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .rooInteractiveGlass(cornerRadius: 9)
    }

    private var officialScheduleToolbar: some View {
      HStack(spacing: 8) {
        Button {
          refreshOfficialScheduleData()
        } label: {
          HStack(spacing: 7) {
            if store.remoteSpecialSchedulesRefreshing || store.remoteSchoolDatesRefreshing {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
            }
            Text(store.remoteSpecialSchedulesRefreshing || store.remoteSchoolDatesRefreshing ? "Refreshing" : "Refresh")
              .font(.system(size: 11.5, weight: .semibold))
          }
          .padding(.horizontal, 12)
          .frame(height: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
        .disabled(store.remoteSpecialSchedulesRefreshing || store.remoteSchoolDatesRefreshing)
        .help("Reload official school dates and special schedules")

        if let updated = latestOfficialScheduleUpdate {
          RemoteDataStatusLabel(lastUpdated: updated, usingSavedData: false)
        }
      }
    }

    private var latestOfficialScheduleUpdate: Date? {
      [store.officialSpecialSchedulesLastUpdated, store.officialSchoolDatesLastUpdated]
        .compactMap { $0 }
        .max()
    }

    private func refreshOfficialScheduleData() {
      Task {
        await store.refreshOfficialSpecialSchedules(force: true)
        await store.refreshOfficialSchoolDates(force: true)
      }
    }

    private var specialSchedulesWorkspace: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          officialScheduleHero

          if let error = store.remoteSpecialScheduleError ?? store.remoteSchoolDateError {
            HStack(alignment: .top, spacing: 10) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.warning)
              VStack(alignment: .leading, spacing: 3) {
                Text("Some school calendar data couldn’t be updated")
                  .font(.system(size: 11.5, weight: .semibold))
                Text(error)
                  .font(.system(size: 10))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer()
            }
            .padding(12)
            .background(
              DesignTokens.Colors.warning.opacity(0.08),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
          }

          schoolDatesOverviewSection
          allSpecialSchedulesSection
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
    }

    private var officialScheduleHero: some View {
      HStack(spacing: 16) {
        ZStack {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(DesignTokens.Colors.schedule.opacity(0.11))
          Image(systemName: "calendar.badge.clock")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)
        }
        .frame(width: 62, height: 62)

        VStack(alignment: .leading, spacing: 4) {
          Text("Official School Calendar")
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text("RooMate keeps special schedules and school-year dates together.")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          Text("Updates are checked automatically every two hours, and you can refresh them anytime.")
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }

        Spacer()
      }
      .padding(16)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: true)
    }

    private var schoolDatesOverviewSection: some View {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("School Dates")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
            Text("School-year boundaries and longer breaks from RooMate’s official calendar.")
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          Spacer()
        }

        if store.remoteSchoolDateFeed.periods.isEmpty {
          ContentUnavailableView(
            "No school dates available",
            systemImage: "calendar",
            description: Text("RooMate hasn’t received school-year dates yet.")
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .rooSurface(cornerRadius: DesignTokens.Radius.lg)
        } else {
          LazyVGrid(
            columns: [
              GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)
            ],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(store.remoteSchoolDateFeed.periods) { period in
              schoolDateCard(period)
            }
          }
        }
      }
    }

    private func schoolDateCard(_ period: RemoteSchoolDatePeriod) -> some View {
      let accent = period.isBreak ? DesignTokens.Colors.events : DesignTokens.Colors.schedule
      let icon = period.isBreak ? "beach.umbrella.fill" : "calendar.badge.checkmark"

      return HStack(alignment: .top, spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(accent.opacity(0.11))
          Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(accent)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 4) {
          Text(period.isBreak ? "SCHOOL BREAK" : "SCHOOL YEAR")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(accent)
          Text(period.displayTitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(schoolDateRange(period))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          if !period.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(period.message)
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.subtleText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(14)
      .frame(height: 126, alignment: .topLeading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .rooSurface(cornerRadius: 14)
    }

    private var allSpecialSchedulesSection: some View {
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Special Schedules")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
            Text("Published special days stay visible even while RooMate is waiting for the exact bell schedule.")
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          Spacer()
        }

        if store.remoteSpecialScheduleFeed.days.isEmpty {
          ContentUnavailableView(
            "No special schedules published",
            systemImage: "calendar.badge.clock",
            description: Text("Published special schedules will appear here automatically.")
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 18)
          .rooSurface(cornerRadius: DesignTokens.Radius.lg)
        } else {
          VStack(spacing: 9) {
            ForEach(store.remoteSpecialScheduleFeed.days) { day in
              specialScheduleListRow(day)
            }
          }
        }
      }
    }

    private func specialScheduleListRow(_ day: RemoteSpecialScheduleDay) -> some View {
      Button {
        if let date = RemoteSchoolDateService.date(from: day.dateKey) {
          selectedDate = date
          mode = .day
        }
      } label: {
        HStack(spacing: 13) {
          VStack(spacing: 2) {
            Text(specialScheduleMonth(day.dateKey).uppercased())
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(DesignTokens.Colors.schedule)
            Text(specialScheduleDayNumber(day.dateKey))
              .font(.system(size: 18, weight: .semibold, design: .rounded))
              .foregroundStyle(DesignTokens.Colors.primaryText)
          }
          .frame(width: 46, height: 46)
          .background(
            DesignTokens.Colors.schedule.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
          )

          VStack(alignment: .leading, spacing: 3) {
            Text(day.displayTitle)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
              .lineLimit(1)
            Text(specialScheduleLongDate(day.dateKey))
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            if !day.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text(day.note)
                .font(.system(size: 9.5))
                .foregroundStyle(DesignTokens.Colors.subtleText)
                .lineLimit(2)
            }
          }

          Spacer(minLength: 8)

          specialScheduleStatusBadge(day)

          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .rooSurface(cornerRadius: 13)
    }

    private func specialScheduleStatusBadge(_ day: RemoteSpecialScheduleDay) -> some View {
      let label: String = {
        if day.isSchoolClosed { return "Closed" }
        if day.isAwaitingSchedule { return "Awaiting schedule" }
        return "Schedule ready"
      }()
      let icon: String = {
        if day.isSchoolClosed { return "calendar.badge.minus" }
        if day.isAwaitingSchedule { return "hourglass" }
        return "checkmark.circle.fill"
      }()
      let color: Color = day.isSchoolClosed
        ? DesignTokens.Colors.secondaryText
        : (day.isAwaitingSchedule ? DesignTokens.Colors.warning : DesignTokens.Colors.schedule)

      return Label(label, systemImage: icon)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(color.opacity(0.09), in: Capsule())
    }

    private func schoolDateRange(_ period: RemoteSchoolDatePeriod) -> String {
      guard let start = RemoteSchoolDateService.date(from: period.startDateKey),
        let end = RemoteSchoolDateService.date(from: period.endDateKey)
      else { return period.startDateKey == period.endDateKey ? period.startDateKey : "\(period.startDateKey) – \(period.endDateKey)" }

      let schoolTimeZone = TimeZone(identifier: "America/New_York") ?? .current
      var schoolCalendar = Calendar(identifier: .gregorian)
      schoolCalendar.timeZone = schoolTimeZone

      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = schoolTimeZone
      formatter.dateFormat = "MMM d, yyyy"

      if schoolCalendar.isDate(start, inSameDayAs: end) {
        return formatter.string(from: start)
      }

      return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private func specialScheduleLongDate(_ key: String) -> String {
      guard let date = RemoteSchoolDateService.date(from: key) else { return key }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .current
      formatter.dateFormat = "EEEE, MMMM d, yyyy"
      return formatter.string(from: date)
    }

    private func specialScheduleMonth(_ key: String) -> String {
      guard let date = RemoteSchoolDateService.date(from: key) else { return "" }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: "America/New_York") ?? .current
      formatter.dateFormat = "MMM"
      return formatter.string(from: date)
    }

    private func specialScheduleDayNumber(_ key: String) -> String {
      guard let date = RemoteSchoolDateService.date(from: key) else { return "—" }
      return String(Calendar.current.component(.day, from: date))
    }

    private var semesterPlannerToolbar: some View {
      HStack(spacing: 8) {
        Button {
          TelemetryTracker.trackSemesterPlannerCopiedCurrentSchedule()
          withAnimation(DesignTokens.Animation.content) {
            store.copyCurrentScheduleToSemesterPlan()
          }
        } label: {
          Label("Copy Current", systemImage: "doc.on.doc")
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
        .help("Use your current classes as a starting point")

        Button {
          showClearSemesterPlanConfirmation = true
        } label: {
          Label("Clear", systemImage: "trash")
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DesignTokens.Colors.destructive)
        .rooInteractiveGlass(cornerRadius: 10)
        .disabled(store.semesterPlanAssignments.isEmpty)
      }
    }

    private var semesterPlannerWorkspace: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          semesterPlannerHero

          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Classes")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

              Text(
                "Plan each level for \(nextSemesterTitle). Nothing here changes your current schedule."
              )
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Spacer()

            Text("\(plannedAcademicCount) of 7 planned")
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.schedule)
          }

          LazyVGrid(
            columns: [
              GridItem(.flexible(), spacing: 12),
              GridItem(.flexible(), spacing: 12),
            ],
            alignment: .leading,
            spacing: 12
          ) {
            ForEach(academicPlannerLevels) { level in
              semesterPlannerClassCard(level)
            }
          }

          VStack(alignment: .leading, spacing: 9) {
            Text("Music Block")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            semesterPlannerClassCard(.music)
          }

          semesterPlannerWeekPreview

          HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
              .foregroundStyle(DesignTokens.Colors.schedule)

            Text(
              "This is a planning space only. RooMate will keep using your current classes until you choose to update them yourself."
            )
          }
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
      .scrollIndicators(.hidden)
    }

    private var semesterPlannerHero: some View {
      HStack(spacing: 16) {
        ZStack {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(DesignTokens.Colors.schedule.opacity(0.11))

          Image(systemName: "calendar.badge.plus")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)
        }
        .frame(width: 62, height: 62)

        VStack(alignment: .leading, spacing: 4) {
          Text(nextSemesterTitle)
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text("Build next semester before it starts")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          Text("Start blank or copy your current schedule, then change only what you need.")
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 4) {
          Text("\(plannedAcademicCount)/7")
            .font(.system(size: 23, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.Colors.schedule)

          Text("classes set")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }
      .padding(16)
      .background(
        DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(
            DesignTokens.Colors.schedule.opacity(0.18),
            lineWidth: 1
          )
      }
      .designShadow(DesignTokens.Shadows.medium)
    }

    private func semesterPlannerClassCard(_ level: Level) -> some View {
      let assignment = store.semesterPlanBinding(for: level)
      let accent = assignment.wrappedValue.color.swiftUIColor
      let isFree = assignment.wrappedValue.isFree

      return VStack(alignment: .leading, spacing: 11) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(accent.opacity(colorScheme == .light ? 0.10 : 0.15))

            Image(
              systemName: isFree
                ? "cup.and.saucer.fill"
                : assignment.wrappedValue.displaySystemImage(for: level)
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isFree ? DesignTokens.Colors.secondaryText : accent)
          }
          .frame(width: 39, height: 39)

          VStack(alignment: .leading, spacing: 2) {
            Text(level.displayName)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(isFree ? "Free period" : "Planned class")
              .font(.system(size: 9.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Toggle("Free", isOn: assignment.isFree)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 9.5, weight: .medium))
        }

        TextField("Class name", text: assignment.title)
          .semesterPlannerField()

        HStack(spacing: 8) {
          TextField("Teacher", text: assignment.teacher)
            .semesterPlannerField()

          TextField("Room", text: assignment.room)
            .semesterPlannerField()
            .frame(maxWidth: 150)
        }
        .disabled(isFree)
        .opacity(isFree ? 0.45 : 1)
      }
      .padding(13)
      .background(
        DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(
            isFree
              ? DesignTokens.Colors.border
              : accent.opacity(colorScheme == .light ? 0.20 : 0.28),
            lineWidth: 1
          )
      }
    }

    private var semesterPlannerWeekPreview: some View {
      VStack(alignment: .leading, spacing: 11) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Week Preview")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text("See how these classes would fit into a normal school week.")
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()
        }

        HStack(alignment: .top, spacing: 9) {
          ForEach(Weekday.allCases) { weekday in
            semesterPlannerPreviewColumn(weekday)
          }
        }
      }
      .padding(.top, 4)
    }

    private func semesterPlannerPreviewColumn(_ weekday: Weekday) -> some View {
      let blocks = (BellSchedule.weekly[weekday] ?? []).compactMap { block -> (Level, BellBlock)? in
        guard case .level(let level) = block.kind else { return nil }
        return (level, block)
      }

      return VStack(alignment: .leading, spacing: 7) {
        Text(weekday.title)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .padding(.horizontal, 2)

        ForEach(Array(blocks.enumerated()), id: \.offset) { _, value in
          let level = value.0
          let block = value.1
          let assignment = store.semesterPlanAssignment(for: level)
          let accent = assignment.color.swiftUIColor

          HStack(spacing: 6) {
            Rectangle()
              .fill(assignment.isFree ? DesignTokens.Colors.subtleText : accent)
              .frame(width: 2)
              .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
              Text(
                assignment.isFree
                  ? "Free"
                  : plannerDisplayTitle(assignment, level: level)
              )
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
              .lineLimit(1)

              Text(
                "\(plannerTimeString(block.start))–\(plannerTimeString(block.end))"
              )
              .font(.system(size: 8))
              .foregroundStyle(DesignTokens.Colors.subtleText)
              .lineLimit(1)
            }

            Spacer(minLength: 0)
          }
          .padding(.horizontal, 7)
          .frame(height: 38)
          .background(
            DesignTokens.Colors.surfaceElevated.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
          }
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .background(
        DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
    }

    private func plannerTimeString(_ components: DateComponents) -> String {
      var schoolCalendar = Calendar(identifier: .gregorian)
      schoolCalendar.timeZone =
        TimeZone(identifier: "America/New_York") ?? .current

      let reference = schoolCalendar.startOfDay(for: Date())

      guard
        let date = schoolCalendar.date(
          bySettingHour: components.hour ?? 0,
          minute: components.minute ?? 0,
          second: 0,
          of: reference
        )
      else {
        return "TBA"
      }

      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = schoolCalendar.timeZone
      formatter.dateFormat = "h:mm"
      return formatter.string(from: date)
    }

    private func plannerDisplayTitle(
      _ assignment: ClassAssignment,
      level: Level
    ) -> String {
      let trimmed = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? level.displayName : trimmed
    }

    private var customFiltersMenu: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Filters")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text("Choose what appears in your schedule")
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Button {
            withAnimation(.easeOut(duration: 0.14)) {
              showFilters = false
            }
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .frame(width: 26, height: 26)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(DesignTokens.Colors.selection, in: Circle())
        }

        Divider()
          .opacity(0.35)

        filterOptionRow(
          title: "Special blocks",
          subtitle: "Advisory, lunch, office hours, clubs, and more",
          systemImage: "sparkles",
          color: DesignTokens.Colors.pacTrack,
          isOn: $showSpecialBlocks
        )

        filterOptionRow(
          title: "Free periods",
          subtitle: "Show open blocks in your timeline",
          systemImage: "cup.and.saucer.fill",
          color: DesignTokens.Colors.athletics,
          isOn: $showFreePeriods
        )

        if !searchText.isEmpty {
          Divider()
            .opacity(0.35)

          Button {
            searchText = ""
          } label: {
            HStack(spacing: 9) {
              Image(systemName: "xmark.circle")
                .foregroundStyle(DesignTokens.Colors.schedule)

              Text("Clear class search")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

              Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(DesignTokens.Colors.selection, in: RoundedRectangle(cornerRadius: 9))
        }
      }
      .padding(14)
      .frame(width: 270)
      .rooGlass(cornerRadius: 15)
      .rooFloatingShadow()
    }

    private func filterOptionRow(
      title: String,
      subtitle: String,
      systemImage: String,
      color: Color,
      isOn: Binding<Bool>
    ) -> some View {
      Button {
        withAnimation(.easeOut(duration: 0.14)) {
          isOn.wrappedValue.toggle()
        }
      } label: {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(color.opacity(0.12))

            Image(systemName: systemImage)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(color)
          }
          .frame(width: 32, height: 32)

          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(subtitle)
              .font(.system(size: 9))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          Spacer()

          ZStack {
            Circle()
              .fill(
                isOn.wrappedValue
                  ? color
                  : DesignTokens.Colors.selection
              )
              .frame(width: 20, height: 20)

            if isOn.wrappedValue {
              Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color.accessibleForegroundColor)
            }
          }
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        DesignTokens.Colors.selection.opacity(isOn.wrappedValue ? 0.68 : 0.34),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
      )
    }

    // MARK: - Day workspace

    private var dayWorkspace: some View {
      GeometryReader { geo in
        let width = geo.size.width
        let leftWidth = min(250, max(210, width * 0.20))
        let rightWidth = min(300, max(250, width * 0.23))

        HStack(alignment: .top, spacing: 14) {
          if !isFocusMode {
            ScrollView {
              VStack(spacing: 14) {
                calendarCard
                if let context = selectedDayContext {
                  dayContextInfoCard(context)
                } else {
                  scheduleInfoCard
                  legendCard
                }
              }
            }
            .scrollIndicators(.hidden)
            .frame(width: leftWidth)
            .transition(.move(edge: .leading).combined(with: .opacity))
          }

          timelineCard
            .frame(maxWidth: .infinity, maxHeight: .infinity)

          if !isFocusMode {
            ScrollView {
              VStack(spacing: 14) {
                if let context = selectedDayContext {
                  selectedDayContextCard(context)

                  if !reminderGamesForSelectedDate.isEmpty {
                    gameRemindersCard
                  }
                } else {
                  currentClassCard
                  upNextCard

                  if !reminderGamesForSelectedDate.isEmpty {
                    gameRemindersCard
                  }

                  daySummaryCard
                }
              }
            }
            .scrollIndicators(.hidden)
            .frame(width: rightWidth)
            .transition(.move(edge: .trailing).combined(with: .opacity))
          }
        }
        .animation(DesignTokens.Animation.snappy, value: isFocusMode)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
      }
    }

    private var calendarCard: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(monthYear(selectedDate))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Spacer()

          HStack(spacing: 4) {
            calendarNavigationButton("chevron.left") {
              moveMonth(by: -1)
            }

            calendarNavigationButton("chevron.right") {
              moveMonth(by: 1)
            }
          }
        }

        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
          spacing: 5
        ) {
          ForEach(Array(customCalendarWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
            Text(symbol)
              .font(.system(size: 8, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.subtleText)
              .frame(maxWidth: .infinity)
              .frame(height: 18)
          }

          ForEach(customCalendarDates(for: selectedDate), id: \.self) { date in
            customCalendarDay(date)
          }
        }
      }
      .padding(16)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    private func calendarNavigationButton(
      _ systemImage: String,
      action: @escaping () -> Void
    ) -> some View {
      Button {
        withAnimation(DesignTokens.Animation.content) {
          action()
        }
      } label: {
        Image(systemName: systemImage)
          .font(.system(size: 9, weight: .semibold))
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(DesignTokens.Colors.selection, in: RoundedRectangle(cornerRadius: 8))
    }

    private var customCalendarWeekdaySymbols: [String] {
      ["S", "M", "T", "W", "T", "F", "S"]
    }

    private func customCalendarDates(for month: Date) -> [Date] {
      guard let monthInterval = calendar.dateInterval(of: .month, for: month),
        let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
      else {
        return []
      }

      let start = firstWeek.start

      return (0..<42).compactMap {
        calendar.date(byAdding: .day, value: $0, to: start)
      }
    }

    private func customCalendarDay(_ date: Date) -> some View {
      let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
      let isToday = calendar.isDateInToday(date)
      let isCurrentMonth = calendar.isDate(
        date,
        equalTo: selectedDate,
        toGranularity: .month
      )
      let hasSchool = store.scheduleWeekday(for: date) != nil
      let day = calendar.component(.day, from: date)

      return Button {
        withAnimation(DesignTokens.Animation.snappy) {
          selectedDate = date
        }
      } label: {
        ZStack {
          Text("\(day)")
            .font(
              .system(
                size: 9,
                weight: isSelected || isToday
                  ? .semibold
                  : .medium
              )
            )
            .foregroundStyle(
              isSelected
                ? Color.white
                : (isCurrentMonth
                  ? DesignTokens.Colors.primaryText
                  : DesignTokens.Colors.subtleText.opacity(0.45))
            )

          if hasSchool && isCurrentMonth && !isSelected {
            Circle()
              .fill(DesignTokens.Colors.schedule.opacity(0.68))
              .frame(width: 3, height: 3)
              .offset(y: 9)
          }

          if !reminderGames(on: date).isEmpty && isCurrentMonth {
            Image(systemName: "star.fill")
              .font(.system(size: 5.5, weight: .bold))
              .foregroundStyle(
                isSelected
                  ? Color.white.opacity(0.92)
                  : DesignTokens.Colors.athletics
              )
              .offset(x: 9, y: -9)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
          isSelected
            ? DesignTokens.Colors.schedule
            : Color.clear,
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
          if isToday && !isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(
                DesignTokens.Colors.schedule.opacity(0.65),
                lineWidth: 1
              )
          }
        }
        .contentShape(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
      }
      .buttonStyle(.plain)
    }

    private var scheduleInfoCard: some View {
      VStack(alignment: .leading, spacing: 12) {
        sectionLabel("ABOUT THIS DAY")

        infoRow("Schedule", value: scheduleStatusInfoValue, color: scheduleStatusColor)
        infoRow("Start Time", value: firstEntry.map { timeString($0.startDate) } ?? "—")
        infoRow("End Time", value: lastEntry.map { timeString($0.endDate) } ?? "—")
        infoRow("Classes", value: "\(classEntries.count)")
        infoRow("Free Periods", value: "\(freeEntries.count)")

        if !reminderGamesForSelectedDate.isEmpty {
          infoRow(
            "Followed Games",
            value: "\(reminderGamesForSelectedDate.count)",
            color: DesignTokens.Colors.athletics
          )
        }
      }
      .padding(16)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    private func dayContextInfoCard(_ context: ScheduleDayContext) -> some View {
      VStack(alignment: .leading, spacing: 12) {
        sectionLabel("ABOUT THIS DAY")

        infoRow("Date", value: mediumDate(selectedDate))
        infoRow("Schedule", value: context.status, color: context.color)

        Text(context.message)
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    private var legendCard: some View {
      let legend = Array(unfilteredSelectedEntries.filter { !$0.isFree }.prefix(6))

      return VStack(alignment: .leading, spacing: 11) {
        sectionLabel("LEGEND")

        if legend.isEmpty {
          Text("No classes on this day")
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        } else {
          ForEach(legend) { entry in
            HStack(spacing: 9) {
              Circle()
                .fill(entry.color)
                .frame(width: 8, height: 8)
              Text(entry.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
              Spacer()
            }
          }
        }
      }
      .padding(16)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    // MARK: - Timeline

    private var timelineCard: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            sectionLabel(selectedWeekday?.title.uppercased() ?? "NO SCHOOL")
            Text(mediumDate(selectedDate))
              .font(.system(size: 11))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          if selectedWeekday != nil || selectedSpecialSchedule != nil {
            Label(scheduleStatusTitle, systemImage: scheduleStatusSystemImage)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(scheduleStatusColor)
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)

        if selectedEntries.isEmpty {
          scheduleEmptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollViewReader { proxy in
            ScrollView {
              VStack(spacing: 0) {
                timelineBoundaryLabel(
                  "Before School", time: firstEntry.map { timeString($0.startDate) } ?? "")

                ForEach(selectedEntries) { entry in
                  timelineRow(entry)
                    .id(entry.id)
                }

                timelineBoundaryLabel(
                  "After School", time: lastEntry.map { timeString($0.endDate) } ?? "")
              }
              .padding(.horizontal, 18)
              .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
            .onAppear {
              if let currentEntry {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                  withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(currentEntry.id, anchor: .center)
                  }
                }
              }
            }
          }
        }
      }
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    @ViewBuilder
    private var scheduleEmptyState: some View {
      if let context = selectedDayContext {
        ContentUnavailableView(
          context.title,
          systemImage: context.systemImage,
          description: Text(context.message)
        )
      } else {
        ContentUnavailableView(
          "No matching blocks",
          systemImage: "magnifyingglass",
          description: Text("Try clearing your search or filters.")
        )
      }
    }

    private func schoolDateStartText(_ period: RemoteSchoolDatePeriod) -> String {
      guard let date = RemoteSchoolDateService.date(from: period.startDateKey) else {
        return period.startDateKey
      }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "EEEE, MMMM d"
      return formatter.string(from: date)
    }

    private func timelineBoundaryLabel(_ label: String, time: String) -> some View {
      HStack(spacing: 12) {
        Text(time)
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 58, alignment: .trailing)

        Circle()
          .fill(DesignTokens.Colors.subtleText.opacity(0.55))
          .frame(width: 6, height: 6)
          .frame(width: 16)

        Text(label)
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 10)
          .frame(height: 24)
          .background(DesignTokens.Colors.selection, in: Capsule())

        Spacer()
      }
      .frame(height: 34)
    }

    private func timelineRow(_ entry: ScheduleEntry) -> some View {
      let state = stateFor(entry)

      return HStack(alignment: .center, spacing: 12) {
        Text(timeString(entry.startDate))
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(
            state == .past ? DesignTokens.Colors.subtleText : DesignTokens.Colors.primaryText
          )
          .frame(width: 58, alignment: .trailing)

        ZStack {
          Rectangle()
            .fill(DesignTokens.Colors.borderStrong)
            .frame(width: 1)

          Circle()
            .fill(state == .past ? DesignTokens.Colors.subtleText : entry.color)
            .frame(width: state == .current ? 13 : 8, height: state == .current ? 13 : 8)
            .overlay {
              if state == .current {
                Circle()
                  .stroke(entry.color.opacity(0.35), lineWidth: 5)
              }
            }
        }
        .frame(width: 16, height: 82)

        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(entry.color.opacity(state == .past ? 0.05 : 0.12))
            Image(systemName: entry.systemImage)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(state == .past ? DesignTokens.Colors.subtleText : entry.color)
          }
          .frame(width: 36, height: 36)

          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
              Text(entry.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                  state == .past
                    ? DesignTokens.Colors.secondaryText : DesignTokens.Colors.primaryText
                )
                .lineLimit(1)

              if let level = entry.level {
                Text(level.displayName)
                  .font(.system(size: 9, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.subtleText)
              }

              if entry.timelineType == .extra {
                Text("EXTRA")
                  .font(.system(size: 7.5, weight: .bold))
                  .tracking(0.45)
                  .foregroundStyle(entry.color)
                  .padding(.horizontal, 6)
                  .frame(height: 18)
                  .background(entry.color.opacity(0.10), in: Capsule())
              }
            }

            if !entry.subtitle.isEmpty {
              Text(entry.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .lineLimit(1)
            }
          }

          Spacer(minLength: 8)

          VStack(alignment: .trailing, spacing: 3) {
            Text(
              entry.timelineType == .marker
                ? timeString(entry.startDate)
                : "\(timeString(entry.startDate)) – \(timeString(entry.endDate))"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            if entry.timelineType != .marker {
              Text("\(entry.durationMinutes) min")
                .font(.system(size: 9))
                .foregroundStyle(DesignTokens.Colors.subtleText)
            }
          }

          if state == .current {
            Text("NOW")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(entry.color)
              .padding(.horizontal, 7)
              .frame(height: 22)
              .background(entry.color.opacity(0.10), in: Capsule())
          }
        }
        .padding(.horizontal, 12)
        .frame(height: 70)
        .background {
          ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(DesignTokens.Colors.surfaceElevated)

            if state != .past {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(entry.color.opacity(state == .current ? 0.09 : 0.045))
            }
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
              state == .current
                ? entry.color.opacity(0.42) : entry.color.opacity(state == .past ? 0.04 : 0.12),
              lineWidth: 1
            )
        }
        .opacity(state == .past ? 0.68 : 1)
      }
      .overlay(alignment: .bottom) {
        if state == .current {
          currentTimeIndicator(entry)
            .offset(y: 6)
        }
      }
    }

    private func currentTimeIndicator(_ entry: ScheduleEntry) -> some View {
      HStack(spacing: 0) {
        Text(timeString(now))
          .font(.system(size: 9, weight: .bold, design: .rounded))
          .foregroundStyle(DesignTokens.Colors.schedule.accessibleForegroundColor)
          .padding(.horizontal, 6)
          .frame(height: 18)
          .background(DesignTokens.Colors.schedule, in: Capsule())

        Rectangle()
          .fill(DesignTokens.Colors.schedule)
          .frame(height: 1)
      }
      .padding(.leading, 47)
    }

    // MARK: - Right rail

    private var currentClassCard: some View {
      VStack(alignment: .leading, spacing: 14) {
        sectionLabel(isViewingToday ? "CURRENT CLASS" : "SELECTED DAY")

        if let current = currentEntry {
          HStack(spacing: 12) {
            iconTile(for: current, size: 44)
            VStack(alignment: .leading, spacing: 3) {
              Text(current.title)
                .font(.system(size: 20, weight: .semibold))
                .lineLimit(2)
              if !current.subtitle.isEmpty {
                Text(current.subtitle)
                  .font(.system(size: 11))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(2)
              }
            }
          }

          Divider().opacity(0.35)

          HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
              Text("ENDS IN")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              Text(remainingText(for: current))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            }
            Spacer()
            ProgressRing(progress: progress(for: current), color: current.color)
              .frame(width: 62, height: 62)
          }
        } else if let weekday = selectedWeekday {
          HStack(spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DesignTokens.Colors.schedule.opacity(0.12))
              Image(systemName: "calendar.day.timeline.left")
                .foregroundStyle(DesignTokens.Colors.schedule)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
              Text(weekday.title)
                .font(.system(size: 18, weight: .semibold))
              if !isViewingToday {
                Text(mediumDate(selectedDate))
                  .font(.system(size: 11, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }
              Text("\(classEntries.count) classes · \(freeEntries.count) free periods")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
          }

          if isViewingToday {
            Text(
              currentEntry == nil && nextEntry == nil
                ? "School is finished for today." : "You're between classes right now."
            )
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        } else {
          Label("No schedule today", systemImage: "moon.zzz")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .frame(minHeight: 190, alignment: .topLeading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: true)
    }

    private func selectedDayContextCard(_ context: ScheduleDayContext) -> some View {
      VStack(alignment: .leading, spacing: 14) {
        sectionLabel("SELECTED DAY")

        HStack(alignment: .top, spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(context.color.opacity(0.12))
            Image(systemName: context.systemImage)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(context.color)
          }
          .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 3) {
            Text(context.title)
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
              .fixedSize(horizontal: false, vertical: true)
            Text(mediumDate(selectedDate))
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }

        Text(context.message)
          .font(.system(size: 11))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(16)
      .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg, elevated: true)
    }

    private var upNextCard: some View {
      let entry = isViewingToday ? nextEntry : firstEntry

      return VStack(alignment: .leading, spacing: 12) {
        sectionLabel(isViewingToday ? "UP NEXT" : "FIRST CLASS")

        if let entry {
          HStack(spacing: 11) {
            iconTile(for: entry, size: 40)
            VStack(alignment: .leading, spacing: 3) {
              Text(entry.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
              Text(timeString(entry.startDate))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.color)
              if !entry.subtitle.isEmpty {
                Text(entry.subtitle)
                  .font(.system(size: 10))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(1)
              }
            }
            Spacer()
          }
        } else {
          Text("Nothing else scheduled")
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    private var daySummaryCard: some View {
      VStack(alignment: .leading, spacing: 13) {
        HStack {
          sectionLabel("DAY SUMMARY")
          Spacer()
          Text("\(classEntries.count) classes")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        if isViewingToday {
          ProgressView(value: dayProgress)
            .tint(DesignTokens.Colors.schedule)
        }

        summaryRow(color: DesignTokens.Colors.schedule, label: "Completed", value: completedCount)
        summaryRow(color: DesignTokens.Colors.pacTrack, label: "In Progress", value: currentCount)
        summaryRow(color: DesignTokens.Colors.today, label: "Upcoming", value: upcomingCount)
        summaryRow(
          color: DesignTokens.Colors.athletics, label: "Free Periods", value: freeEntries.count)

        Button {
          copyScheduleToClipboard()

          withAnimation(.easeOut(duration: 0.15)) {
            didCopySchedule = true
          }

          DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeOut(duration: 0.15)) {
              didCopySchedule = false
            }
          }
        } label: {
          HStack(spacing: 7) {
            Image(systemName: didCopySchedule ? "checkmark.circle.fill" : "doc.on.doc")
            Text(didCopySchedule ? "Copied" : "Copy Schedule")
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            didCopySchedule
              ? DesignTokens.Colors.athletics
              : DesignTokens.Colors.primaryText
          )
          .frame(maxWidth: .infinity)
          .frame(height: 34)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    // MARK: - Saved game reminders

    private var gameRemindersCard: some View {
      VStack(alignment: .leading, spacing: 11) {
        HStack(spacing: 8) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(DesignTokens.Colors.athletics.opacity(0.11))

            Image(systemName: "star.fill")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.athletics)
          }
          .frame(width: 28, height: 28)

          VStack(alignment: .leading, spacing: 1) {
            Text("Game Reminders")
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(
              reminderGamesForSelectedDate.count == 1
                ? "1 game"
                : "\(reminderGamesForSelectedDate.count) games"
            )
            .font(.system(size: 9.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()
        }

        ForEach(reminderGamesForSelectedDate) { game in
          gameReminderRow(game)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    private func gameReminderRow(_ game: SportsGame) -> some View {
      let accent = sportsStatusColor(game)

      return VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Circle()
            .fill(accent)
            .frame(width: 7, height: 7)

          Text(game.team)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)

          Spacer(minLength: 6)

          if let status = sportsStatusText(game) {
            Text(status.uppercased())
              .font(.system(size: 7.5, weight: .bold))
              .tracking(0.45)
              .foregroundStyle(accent)
          }
        }

        Text(sportsOpponentText(game))
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)

        HStack(spacing: 8) {
          Label(
            game.time.isEmpty ? "TBA" : game.time,
            systemImage: "clock"
          )

          Label(
            sportsLocationText(game),
            systemImage: isAwayGame(game)
              ? "arrow.up.right"
              : "house.fill"
          )
        }
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.secondaryText)

        if !game.dismiss.isEmpty || !game.return.isEmpty {
          HStack(spacing: 8) {
            if !game.dismiss.isEmpty {
              Label(
                "Dismiss \(game.dismiss)",
                systemImage: "rectangle.portrait.and.arrow.right"
              )
            }

            if !game.return.isEmpty {
              Label(
                "Return \(game.return)",
                systemImage: "arrow.uturn.left"
              )
            }
          }
          .font(.system(size: 8.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.athletics)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        DesignTokens.Colors.surfaceElevated.opacity(0.74),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(accent.opacity(0.14), lineWidth: 1)
      }
    }

    // MARK: - Week

    private var weekWorkspace: some View {
      ScrollView([.horizontal, .vertical]) {
        HStack(alignment: .top, spacing: 12) {
          ForEach(Weekday.allCases) { weekday in
            weekColumn(weekday)
              .frame(width: 220)
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
      }
      .scrollIndicators(.hidden)
    }

    private func weekColumn(_ weekday: Weekday) -> some View {
      let date = date(for: weekday, relativeTo: selectedDate)
      let items = entries(for: weekday, on: date).filter(matchesFilters)
      let athletics = reminderGames(on: date)
      let today = calendar.isDate(date, inSameDayAs: now)
      let context = scheduleDayContext(on: date)

      return VStack(alignment: .leading, spacing: 10) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(weekday.title)
              .font(.system(size: 14, weight: .semibold))
            Text(shortDate(date))
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          Spacer()
          if today {
            Text("TODAY")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(DesignTokens.Colors.schedule)
          }
        }

        if let context {
          Button {
            selectedDate = date
            mode = .day
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(context.color.opacity(0.11))
                Image(systemName: context.systemImage)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(context.color)
              }
              .frame(width: 36, height: 36)

              Text(context.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

              Text(context.message)
                .font(.system(size: 9.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .contentShape(Rectangle())
            .background(
              context.color.opacity(0.045),
              in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(context.color.opacity(0.14), lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
        } else {
          ForEach(items) { entry in
            weekScheduleEntryCard(entry, date: date)
          }
        }

        if !athletics.isEmpty {
          Divider()
            .overlay(DesignTokens.Colors.border)
            .padding(.vertical, 2)

          HStack(spacing: 6) {
            Image(systemName: "star.fill")
              .font(.system(size: 8, weight: .bold))
              .foregroundStyle(DesignTokens.Colors.athletics)

            Text("GAME REMINDERS")
              .font(.system(size: 8, weight: .bold))
              .tracking(0.55)
              .foregroundStyle(DesignTokens.Colors.secondaryText)

            Spacer()
          }

          ForEach(athletics) { game in
            weekAthleticsGameCard(game)
          }
        }
      }
      .padding(14)
      .rooSurface(cornerRadius: DesignTokens.Radius.lg)
    }

    private func weekScheduleEntryCard(_ entry: ScheduleEntry, date: Date) -> some View {
      Button {
        selectedDate = date
        mode = .day
      } label: {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Circle().fill(entry.color).frame(width: 7, height: 7)
            Text(timeString(entry.startDate))
              .font(.system(size: 9, weight: .medium, design: .rounded))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            Spacer()
            if entry.timelineType != .marker {
              Text("\(entry.durationMinutes)m")
                .font(.system(size: 8))
                .foregroundStyle(DesignTokens.Colors.subtleText)
            }
          }
          Text(entry.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(2)
          if !entry.subtitle.isEmpty {
            Text(entry.subtitle)
              .font(.system(size: 9))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .background {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(DesignTokens.Colors.surfaceElevated)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(entry.color.opacity(0.055))
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .stroke(entry.color.opacity(0.12), lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }

    private func weekAthleticsGameCard(_ game: SportsGame) -> some View {
      let accent = sportsStatusColor(game)

      return VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Circle()
            .fill(accent)
            .frame(width: 6, height: 6)

          Text(game.time.isEmpty ? "TBA" : game.time)
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          Spacer()

          Image(systemName: "star.fill")
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.athletics)
        }

        Text(game.team)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)

        Text(sportsOpponentText(game))
          .font(.system(size: 8.8))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(1)

        if !game.dismiss.isEmpty {
          Text("Dismiss \(game.dismiss)")
            .font(.system(size: 8.2, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.athletics)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        DesignTokens.Colors.surfaceElevated.opacity(0.74),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(accent.opacity(0.14), lineWidth: 1)
      }
    }

    // MARK: - Reusable UI

    private func sectionLabel(_ text: String) -> some View {
      Text(text)
        .font(.system(size: 9, weight: .bold))
        .tracking(0.8)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
    }

    private func infoRow(_ label: String, value: String, color: Color? = nil) -> some View {
      HStack {
        if let color {
          Circle().fill(color).frame(width: 7, height: 7)
        }
        Text(label)
          .font(.system(size: 11))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Spacer()
        Text(value)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.primaryText)
      }
    }

    private func summaryRow(color: Color, label: String, value: Int) -> some View {
      HStack(spacing: 9) {
        Circle().fill(color).frame(width: 7, height: 7)
        Text(label)
          .font(.system(size: 11))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Spacer()
        Text("\(value)")
          .font(.system(size: 11, weight: .semibold))
      }
    }

    private func iconTile(for entry: ScheduleEntry, size: CGFloat) -> some View {
      ZStack {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
          .fill(entry.color.opacity(0.12))
        Image(systemName: entry.systemImage)
          .font(.system(size: size * 0.34, weight: .semibold))
          .foregroundStyle(entry.color)
      }
      .frame(width: size, height: size)
    }

    private struct ProgressRing: View {
      let progress: Double
      let color: Color

      var body: some View {
        ZStack {
          Circle()
            .stroke(DesignTokens.Colors.borderStrong, lineWidth: 6)
          Circle()
            .trim(from: 0, to: min(1, max(0, progress)))
            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .rotationEffect(.degrees(-90))
        }
      }
    }

    private enum EntryState {
      case past, current, future
    }

    private func stateFor(_ entry: ScheduleEntry) -> EntryState {
      guard isViewingToday else { return .future }
      if now >= entry.endDate { return .past }
      if now >= entry.startDate && now < entry.endDate { return .current }
      return .future
    }

    // MARK: - Data mapping

    private func entries(for weekday: Weekday, on date: Date) -> [ScheduleEntry] {
      let blocks = store.bellBlocks(for: date)
      let displayWeekday = store.scheduleWeekday(for: date) ?? weekday

      var result: [ScheduleEntry] = blocks.compactMap { block in
        guard let start = concreteDate(block.start, on: date),
          let end = concreteDate(block.end, on: date)
        else { return nil }

        let presentation = store.schedulePresentation(for: block, on: displayWeekday)

        switch block.kind {
        case .level(let level):
          return ScheduleEntry(
            id: block.id,
            block: block,
            title: presentation.title,
            subtitle: presentation.subtitle,
            teacher: presentation.teacher,
            room: presentation.room,
            color: presentation.isFree ? DesignTokens.Colors.subtleText : presentation.color,
            systemImage: presentation.systemImage,
            isFree: presentation.isFree,
            isSpecial: block.timelineType != .block,
            level: level,
            special: nil,
            timelineType: block.timelineType,
            startDate: start,
            endDate: end
          )

        case .special(let special):
          return ScheduleEntry(
            id: block.id,
            block: block,
            title: presentation.title,
            subtitle: presentation.subtitle,
            teacher: presentation.teacher,
            room: presentation.room,
            color: presentation.color,
            systemImage: presentation.systemImage,
            isFree: presentation.isFree,
            isSpecial: true,
            level: nil,
            special: special,
            timelineType: block.timelineType,
            startDate: start,
            endDate: end
          )

        case .custom:
          return ScheduleEntry(
            id: block.id,
            block: block,
            title: presentation.title,
            subtitle: presentation.subtitle,
            teacher: nil,
            room: nil,
            color: presentation.color,
            systemImage: presentation.systemImage,
            isFree: false,
            isSpecial: true,
            level: nil,
            special: nil,
            timelineType: block.timelineType,
            startDate: start,
            endDate: end
          )
        }
      }

      // A closure, break, weekend, or out-of-session date should not regain a
      // school-day timeline just because a recurring club meeting exists.
      guard scheduleDayContext(on: date) == nil else {
        return result.sorted { $0.startDate < $1.startDate }
      }

      // My Clubs can have additional meetings at any clock time, including
      // after school. They are added as timeline extras instead of replacing
      // bell-schedule blocks, so an extra meeting can intentionally overlap a
      // class, lunch, or another schedule item.
      let calendarWeekday = calendar.component(.weekday, from: date)
      for club in store.clubs {
        let clubName = club.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clubName.isEmpty else { continue }

        for meeting in club.otherMeetings where meeting.weekday == calendarWeekday {
          let startComponents = calendar.dateComponents([.hour, .minute], from: meeting.startTime)
          let endComponents = calendar.dateComponents([.hour, .minute], from: meeting.endTime)

          guard let start = concreteDate(startComponents, on: date),
            let end = concreteDate(endComponents, on: date),
            end > start
          else {
            continue
          }

          let room = club.room.trimmingCharacters(in: .whitespacesAndNewlines)
          let subtitle = room.isEmpty ? "Club meeting" : "Club meeting • \(room)"
          let block = BellBlock(
            id: meeting.id,
            kind: .custom(clubName),
            start: startComponents,
            end: endComponents,
            titleOverride: clubName,
            detail: subtitle,
            timelineType: .extra
          )

          result.append(
            ScheduleEntry(
              id: meeting.id,
              block: block,
              title: clubName,
              subtitle: subtitle,
              teacher: nil,
              room: room.isEmpty ? nil : room,
              color: club.displayColor,
              systemImage: club.displayIconName,
              isFree: false,
              isSpecial: false,
              level: nil,
              special: nil,
              timelineType: .extra,
              startDate: start,
              endDate: end
            )
          )
        }
      }

      return result.sorted { lhs, rhs in
        if lhs.startDate != rhs.startDate {
          return lhs.startDate < rhs.startDate
        }

        if lhs.timelineType != rhs.timelineType {
          return lhs.timelineType == .block
        }

        return lhs.endDate < rhs.endDate
      }
    }

    private func scheduleDayContext(on date: Date) -> ScheduleDayContext? {
      if let special = store.remoteSpecialScheduleDay(on: date) {
        let note = special.note.trimmingCharacters(in: .whitespacesAndNewlines)

        if special.isSchoolClosed {
          return ScheduleDayContext(
            title: special.displayTitle,
            message: note.isEmpty
              ? "School is closed on this date. There are no classes scheduled."
              : note,
            status: "School closed",
            systemImage: "calendar.badge.minus",
            color: DesignTokens.Colors.subtleText
          )
        }

        if special.isAwaitingSchedule {
          return ScheduleDayContext(
            title: special.displayTitle,
            message: note.isEmpty
              ? "The exact bell times haven’t been published yet. RooMate will update this day automatically."
              : "\(note) Exact bell times haven’t been published yet.",
            status: "Awaiting schedule",
            systemImage: "hourglass",
            color: DesignTokens.Colors.warning
          )
        }

        // A published special schedule is authoritative even when it lands
        // inside a broader break period.
        return nil
      }

      if let state = store.schoolDateState(on: date) {
        switch state {
        case .breakPeriod(let period):
          let message = period.message.trimmingCharacters(in: .whitespacesAndNewlines)
          return ScheduleDayContext(
            title: period.displayTitle,
            message: message.isEmpty
              ? "School is on break. There are no regular classes scheduled."
              : message,
            status: "School break",
            systemImage: "beach.umbrella.fill",
            color: DesignTokens.Colors.events
          )
        case .beforeSchoolYear(let period):
          return ScheduleDayContext(
            title: "School hasn’t started yet",
            message: "The \(period.displayTitle) begins \(schoolDateStartText(period)).",
            status: "Before school year",
            systemImage: "calendar.badge.clock",
            color: DesignTokens.Colors.warning
          )
        case .afterSchoolYear:
          return ScheduleDayContext(
            title: "School year complete",
            message: "The regular school-year schedule has ended.",
            status: "School year complete",
            systemImage: "checkmark.circle.fill",
            color: DesignTokens.Colors.athletics
          )
        case .inSession:
          break
        }
      }

      if weekday(for: date) == nil {
        return ScheduleDayContext(
          title: "No school",
          message: "There is no regular school-day schedule on weekends.",
          status: "Weekend",
          systemImage: "moon.zzz.fill",
          color: DesignTokens.Colors.subtleText
        )
      }

      return nil
    }

    private func matchesFilters(_ entry: ScheduleEntry) -> Bool {
      if !showSpecialBlocks && entry.isSpecial { return false }
      if !showFreePeriods && entry.isFree { return false }

      let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !query.isEmpty else { return true }

      return [
        entry.title, entry.subtitle, entry.teacher ?? "", entry.room ?? "",
        entry.level?.displayName ?? "",
      ]
      .contains { $0.lowercased().contains(query) }
    }

    // MARK: - Date helpers

    private func weekday(for date: Date) -> Weekday? {
      switch calendar.component(.weekday, from: date) {
      case 2: .monday
      case 3: .tuesday
      case 4: .wednesday
      case 5: .thursday
      case 6: .friday
      default: nil
      }
    }

    private func syncSelectedDayFromDate() {
      if let weekday = selectedWeekday {
        selectedDay = weekday
      }
    }

    private func date(for weekday: Weekday, relativeTo reference: Date) -> Date {
      let start = calendar.startOfDay(for: reference)
      let currentWeekday = calendar.component(.weekday, from: start)
      let delta = weekday.calendarWeekdayIndex - currentWeekday
      return calendar.date(byAdding: .day, value: delta, to: start) ?? start
    }

    private func moveSchoolDay(by direction: Int) {
      var candidate = selectedDate
      repeat {
        candidate = calendar.date(byAdding: .day, value: direction, to: candidate) ?? candidate
      } while weekday(for: candidate) == nil
      selectedDate = candidate
    }

    private func moveMonth(by amount: Int) {
      selectedDate =
        calendar.date(byAdding: .month, value: amount, to: selectedDate) ?? selectedDate
    }

    private func concreteDate(_ components: DateComponents, on day: Date) -> Date? {
      var dateComponents = calendar.dateComponents([.year, .month, .day], from: day)
      dateComponents.hour = components.hour
      dateComponents.minute = components.minute
      dateComponents.second = 0
      return calendar.date(from: dateComponents)
    }

    private func progress(for entry: ScheduleEntry) -> Double {
      let duration = max(1, entry.endDate.timeIntervalSince(entry.startDate))
      return min(1, max(0, now.timeIntervalSince(entry.startDate) / duration))
    }

    private func remainingText(for entry: ScheduleEntry) -> String {
      let seconds = max(0, Int(entry.endDate.timeIntervalSince(now)))
      let minutes = seconds / 60
      if minutes >= 60 {
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
      }
      return "\(max(1, minutes))m"
    }

    private func timeString(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "h:mm a"
      return formatter.string(from: date)
    }

    private func navigationDateLabel(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "MMM d"
      return formatter.string(from: date)
    }

    private func longDate(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "EEEE, MMMM d, yyyy"
      return formatter.string(from: date)
    }

    private func mediumDate(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "MMMM d, yyyy"
      return formatter.string(from: date)
    }

    private func shortDate(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "MMM d"
      return formatter.string(from: date)
    }

    private func monthYear(_ date: Date) -> String {
      let formatter = DateFormatter()
      formatter.dateFormat = "MMMM yyyy"
      return formatter.string(from: date)
    }

    // MARK: - Clipboard

    private func copyScheduleToClipboard() {
      guard let weekday = selectedWeekday else { return }
      let lines = entries(for: weekday, on: selectedDate).map { entry in
        let detail = entry.subtitle.isEmpty ? "" : " — \(entry.subtitle)"
        return
          "\(timeString(entry.startDate))–\(timeString(entry.endDate))  \(entry.title)\(detail)"
      }

      let output = (["\(weekday.title) · \(mediumDate(selectedDate))"] + lines).joined(
        separator: "\n")
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(output, forType: .string)
    }
  }

  extension View {
    fileprivate func semesterPlannerField() -> some View {
      self
        .textFieldStyle(.plain)
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(
          DesignTokens.Colors.hover.opacity(0.26),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
        }
    }
  }

#endif
