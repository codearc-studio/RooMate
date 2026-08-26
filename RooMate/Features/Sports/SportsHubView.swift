import SwiftUI

private enum SportsHubSection: String, CaseIterable, Identifiable {
  case overview
  case games

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "Overview"
    case .games: "Games"
    }
  }

  var icon: String {
    switch self {
    case .overview: "square.grid.2x2.fill"
    case .games: "calendar"
    }
  }
}

struct SportsHubView: View {
  @ObservedObject var store: SportsStore
  @ObservedObject private var navigation = RooMateNavigationCoordinator.shared

  @State private var selectedDate = Date()
  @State private var range: SportsRangeFilter = .week
  @State private var searchText = ""
  @State private var selectedSport = "All Sports"

  @State private var showFilters = false
  @State private var showSportPicker = false

  @State private var showHomeGames = true
  @State private var showAwayGames = true
  @State private var showChangedGames = true

  @State private var selectedGame: SportsGame?
  @State private var selectedSection: SportsHubSection = .overview
  @State private var showCalendar = false

  @AppStorage("RooMateSportsGameReminders")
  private var savedGameIDsRaw = ""

  private let calendar = Calendar.current
  private let athleticsColor = DesignTokens.Colors.athletics

  var body: some View {
    sportsDashboard
      .background { BackgroundView() }
      .onAppear {
        if store.liveGames.isEmpty {
          store.refresh()
        }
        handleNavigationRequest()
      }
      .onChange(of: navigation.request) { _, _ in handleNavigationRequest() }
      .onChange(of: store.liveGames) { _, _ in handleNavigationRequest() }
      .sheet(item: $selectedGame) { game in
        SportsFeedGameDetailSheet(
          game: game,
          store: store,
          hasReminder: savedGameIDs.contains(game.id),
          onToggleReminder: { toggleGameReminder(game) }
        )
        .onAppear { TelemetryTracker.trackSportsGameViewed() }
      }
  }

  private func handleNavigationRequest() {
    guard let request = navigation.request else { return }
    switch request.destination {
    case .sportsGame(let id):
      guard let game = store.liveGames.first(where: { $0.id == id }) else { return }
      selectedSection = .games
      if let date = game.date { selectedDate = date }
      selectedGame = game
      navigation.consume(request)
    default:
      break
    }
  }

  private var sportsDashboard: some View {
    VStack(spacing: 16) {
      sportsHeader
      hubNavigation

      Group {
        switch selectedSection {
        case .overview:
          sportsOverviewWorkspace
            .transition(.opacity)

        case .games:
          VStack(spacing: 12) {
            scopeBar

            Group {
              if showCalendar {
                sportsCalendarWorkspace
                  .transition(.opacity.combined(with: .move(edge: .trailing)))
              } else {
                sportsAgendaWorkspace
                  .transition(.opacity)
              }
            }
            .animation(DesignTokens.Animation.navigation, value: showCalendar)
          }
          .transition(.opacity)

        }
      }
      .animation(DesignTokens.Animation.navigation, value: selectedSection)
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 16)
  }

  // MARK: - Hub overview

  private var sportsOverviewWorkspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        overviewMetricStrip

        HStack(alignment: .top, spacing: 16) {
          overviewUpcomingCard
            .frame(maxWidth: .infinity)

          VStack(spacing: 14) {
            teamsMaintenanceCard
            updatesCard
          }
          .frame(width: 330)
        }

        sourceNote
      }
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  private var overviewMetricStrip: some View {
    HStack(spacing: 12) {
      overviewMetricCard(
        title: "Today",
        value: "\(overviewTodayGames.count)",
        subtitle: overviewTodayGames.count == 1 ? "game" : "games",
        icon: "sun.max.fill",
        color: athleticsColor
      )

      overviewMetricCard(
        title: "Next 7 Days",
        value: "\(overviewWeekGames.count)",
        subtitle: overviewWeekGames.count == 1 ? "game" : "games",
        icon: "calendar",
        color: DesignTokens.Colors.events
      )

      overviewMetricCard(
        title: "Home",
        value: "\(overviewWeekGames.filter { !isAwayGame($0) }.count)",
        subtitle: "next 7 days",
        icon: "house.fill",
        color: DesignTokens.Colors.athletics
      )

      overviewMetricCard(
        title: "Changes",
        value: "\(overviewWeekGames.filter { $0.status != .scheduled }.count)",
        subtitle: "next 7 days",
        icon: "exclamationmark.arrow.triangle.2.circlepath",
        color: DesignTokens.Colors.warning
      )
    }
  }

  private func overviewMetricCard(
    title: String,
    value: String,
    subtitle: String,
    icon: String,
    color: Color
  ) -> some View {
    HStack(spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(color.opacity(0.12))

        Image(systemName: icon)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(color)
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 1) {
        Text(title.uppercased())
          .font(.system(size: 8.5, weight: .bold))
          .tracking(0.5)
          .foregroundStyle(DesignTokens.Colors.subtleText)

        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(value)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(subtitle)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(13)
    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var overviewUpcomingCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          SportsSectionLabel("UPCOMING GAMES", color: athleticsColor)
          Text("What’s coming up next")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button {
          withAnimation(DesignTokens.Animation.navigation) {
            selectedSection = .games
            range = .week
            showCalendar = false
          }
        } label: {
          HStack(spacing: 5) {
            Text("All Games")
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .bold))
          }
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(athleticsColor)
          .padding(.horizontal, 10)
          .frame(height: 30)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          athleticsColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      }
      .padding(15)

      Divider().opacity(0.30)

      if store.isLoading && store.liveGames.isEmpty {
        HStack(spacing: 9) {
          ProgressView().controlSize(.small)
          Text("Loading games…")
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
      } else if overviewUpcomingGames.isEmpty {
        compactEmptyState(
          icon: "calendar.badge.checkmark",
          title: "No upcoming games",
          subtitle: "New games will appear here when they are added to the school sports schedule."
        )
        .frame(minHeight: 170)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(overviewUpcomingGames.prefix(6))) { game in
            overviewGameRow(game)

            if game.id != overviewUpcomingGames.prefix(6).last?.id {
              Divider()
                .opacity(0.24)
                .padding(.horizontal, 15)
            }
          }
        }
      }
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func overviewGameRow(_ game: SportsGame) -> some View {
    let teamColor = SportIconConfiguration.teamColor(for: game.team)

    return Button {
      selectedGame = game
    } label: {
      HStack(spacing: 12) {
        sportIconTile(for: game.team, color: teamColor)

        VStack(alignment: .leading, spacing: 3) {
          Text(game.team)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)

          Text(opponentLine(game))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .trailing, spacing: 3) {
          Text(shortGameDate(game))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(game.time.isEmpty ? "TBA" : game.time)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        if let status = statusLabel(game) {
          Text(status.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(statusColor(game))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(statusColor(game).opacity(0.10), in: Capsule())
        }

        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 11)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var teamsMaintenanceCard: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "wrench.and.screwdriver.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(athleticsColor)
        .frame(width: 30, height: 30)
        .background(athleticsColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

      VStack(alignment: .leading, spacing: 3) {
        Text("Team pages are unavailable for now")
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
        Text("They’ll return in a future update. You can still view games and set reminders.")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var overviewTodayGames: [SportsGame] {
    allDatedGames.filter { game in
      guard let date = game.date else { return false }
      return calendar.isDateInToday(date)
        && game.status != .cancelled
        && game.status != .eliminated
    }
  }

  private var overviewWeekGames: [SportsGame] {
    nextSevenDayGames.filter {
      $0.status != .cancelled && $0.status != .eliminated
    }
  }

  private var overviewUpcomingGames: [SportsGame] {
    let now = Date()
    return allDatedGames.filter { game in
      game.status != .cancelled
        && game.status != .eliminated
        && combinedDate(for: game) >= now
    }
  }

  private var sportsAgendaWorkspace: some View {
    HStack(alignment: .top, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let error = store.lastError, store.liveGames.isEmpty { errorCard(error) }
          if store.isLoading && store.liveGames.isEmpty {
            loadingCard
          } else if groupedGames.isEmpty {
            emptyState
          } else {
            ForEach(groupedGames) { group in
              SportsDaySection(
                group: group,
                store: store,
                savedGameIDs: savedGameIDs,
                onToggleReminder: toggleGameReminder,
                onSelectGame: { selectedGame = $0 }
              )
            }
          }
          sourceNote
        }
        .padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)

      ScrollView {
        VStack(spacing: 14) {
          nextUpCard
          updatesCard
          teamsMaintenanceCard
          athleticCalendarCard
        }
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .frame(width: 300)
    }
  }

  private var sportsCalendarWorkspace: some View {
    HStack(alignment: .top, spacing: 16) {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            VStack(alignment: .leading, spacing: 3) {
              Text(sportsMonthYear(selectedDate))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
              Text("Select a day to see its games")
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            Spacer()
            Text("\(filteredGames.count) game\(filteredGames.count == 1 ? "" : "s")")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(athleticsColor)
              .padding(.horizontal, 9)
              .frame(height: 26)
              .background(athleticsColor.opacity(0.10), in: Capsule())
          }
          .padding(.horizontal, 2)

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6
          ) {
            ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) { day in
              Text(day)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(DesignTokens.Colors.subtleText)
                .frame(maxWidth: .infinity)
            }
          }

          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6
          ) {
            ForEach(Array(sportsMonthGridDates.enumerated()), id: \.offset) { _, date in
              if let date { sportsCalendarDayCell(date) } else { Color.clear.frame(minHeight: 104) }
            }
          }

          sourceNote
        }
        .padding(.bottom, 8)
      }
      .scrollIndicators(.hidden)

      ScrollView { selectedSportsCalendarDayCard }
        .scrollIndicators(.hidden)
        .frame(width: 300)
    }
  }

  private func sportsCalendarDayCell(_ date: Date) -> some View {
    let games = calendarGames(on: date)
    let selected = calendar.isDate(date, inSameDayAs: selectedDate)
    let today = calendar.isDateInToday(date)

    return Button {
      withAnimation(DesignTokens.Animation.snappy) { selectedDate = date }
    } label: {
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text(String(calendar.component(.day, from: date)))
            .font(.system(size: 11.5, weight: selected ? .bold : .semibold))
            .foregroundStyle(selected ? athleticsColor : DesignTokens.Colors.primaryText)
          Spacer()
          if today {
            Text("TODAY").font(.system(size: 7.5, weight: .bold)).foregroundStyle(athleticsColor)
          }
        }
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(games.prefix(3))) { game in
            HStack(spacing: 5) {
              Circle().fill(sportsCalendarStatusColor(game)).frame(width: 5, height: 5)
              Text(game.team).font(.system(size: 8.5, weight: .medium)).foregroundStyle(
                DesignTokens.Colors.primaryText
              ).lineLimit(1)
            }
          }
          if games.count > 3 {
            Text("+\(games.count - 3) more").font(.system(size: 8, weight: .semibold))
              .foregroundStyle(athleticsColor)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(9)
      .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selected ? athleticsColor.opacity(0.10) : DesignTokens.Colors.surface,
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(
          selected || today
            ? athleticsColor.opacity(selected ? 0.34 : 0.22) : DesignTokens.Colors.border,
          lineWidth: 1)
    }
  }

  private var selectedSportsCalendarDayCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(sportsCalendarDayTitle(selectedDate))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(
            "\(selectedSportsCalendarDayGames.count) game\(selectedSportsCalendarDayGames.count == 1 ? "" : "s")"
          )
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        Spacer()
        if calendar.isDateInToday(selectedDate) {
          Image(systemName: "sportscourt.fill").foregroundStyle(athleticsColor)
        }
      }
      Divider().overlay(DesignTokens.Colors.border)
      if selectedSportsCalendarDayGames.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(
            DesignTokens.Colors.subtleText)
          Text("No games that day").font(.system(size: 11.5, weight: .semibold))
          Text("Choose another day in the calendar.").font(.system(size: 9.5)).foregroundStyle(
            DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        VStack(spacing: 8) {
          ForEach(selectedSportsCalendarDayGames) { game in
            Button {
              selectedGame = game
            } label: {
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(game.team).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(
                    DesignTokens.Colors.primaryText
                  ).lineLimit(2)
                  Spacer()
                  Circle().fill(sportsCalendarStatusColor(game)).frame(width: 7, height: 7)
                }
                Text(game.opponent.isEmpty ? "Opponent TBA" : "vs \(game.opponent)")
                  .font(.system(size: 9.5)).foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(1)
                HStack(spacing: 7) {
                  if !game.time.isEmpty { Label(game.time, systemImage: "clock") }
                  Label(
                    isAwayGame(game) ? "Away" : "Home",
                    systemImage: isAwayGame(game) ? "car.fill" : "house.fill")
                }
                .font(.system(size: 8.5))
                .foregroundStyle(DesignTokens.Colors.subtleText)
              }
              .padding(9)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
              DesignTokens.Colors.selection.opacity(0.34),
              in: RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
        }
      }
    }
    .padding(14)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: - Header

  private var sportsHeader: some View {
    HStack(alignment: .center, spacing: 16) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(athleticsColor.opacity(0.12))

          Image(systemName: "sportscourt.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(athleticsColor)
        }
        .frame(width: 46, height: 46)

        VStack(alignment: .leading, spacing: 3) {
          Text("Sports")
            .font(DesignTokens.Typography.pageTitle)
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(headerSubtitle)
            .font(.system(size: 12))
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          RemoteDataStatusLabel(
            lastUpdated: store.lastUpdated,
            usingSavedData: store.isShowingSavedData
          )
        }
      }

      Spacer()

      RooGlassEffectGroup(spacing: 8) {
        HStack(spacing: 8) {
          if selectedSection == .games {
            dateNavigation

            HStack(spacing: 8) {
              Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignTokens.Colors.secondaryText)

              TextField(
                "Search games or opponents",
                text: $searchText
              )
              .textFieldStyle(.plain)
              .font(.system(size: 12))
              .frame(width: 230)

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
              }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .rooInteractiveGlass(cornerRadius: 11)
          }

          Button {
            store.refresh()
          } label: {
            Group {
              if store.isLoading {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: "arrow.clockwise")
                  .font(.system(size: 11, weight: .semibold))
              }
            }
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 11)
          .help("Refresh sports")

          if selectedSection == .games {
            Button {
              withAnimation(.easeOut(duration: 0.15)) {
                showFilters.toggle()
                showSportPicker = false
              }
            } label: {
              Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rooInteractiveGlass(cornerRadius: 11)
            .overlay(alignment: .topTrailing) {
              if showFilters {
                sportsFiltersPanel
                  .offset(y: 46)
                  .transition(
                    .opacity.combined(
                      with: .scale(
                        scale: 0.96,
                        anchor: .topTrailing
                      )
                    )
                  )
                  .zIndex(200)
              }
            }
            .zIndex(showFilters ? 200 : 0)
          }
        }
      }
    }
    .zIndex(200)
  }

  private var headerSubtitle: String {
    switch selectedSection {
    case .overview:
      return "Games and schedule changes in one place"
    case .games:
      return longDate(selectedDate)
    }
  }

  private var hubNavigation: some View {
    HStack(spacing: 8) {
      ForEach(SportsHubSection.allCases) { section in
        Button {
          withAnimation(DesignTokens.Animation.navigation) {
            selectedSection = section
            showFilters = false
            showSportPicker = false
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: section.icon)
              .font(.system(size: 11, weight: .semibold))

            Text(section.title)
              .font(.system(size: 11.5, weight: .semibold))
          }
          .foregroundStyle(
            selectedSection == section
              ? athleticsColor
              : DesignTokens.Colors.secondaryText
          )
          .padding(.horizontal, 14)
          .frame(height: 36)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          selectedSection == section
            ? athleticsColor.opacity(0.11)
            : DesignTokens.Colors.surface,
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
              selectedSection == section
                ? athleticsColor.opacity(0.24)
                : DesignTokens.Colors.border,
              lineWidth: 1
            )
        }
      }

      Spacer()

      if selectedSection == .overview {
        Text("Updated from the school sports schedule")
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
    }
  }

  private var dateNavigation: some View {
    HStack(spacing: 4) {
      sportsIconButton("chevron.left") {
        moveReferenceDate(by: -1)
      }

      Button {
        withAnimation(DesignTokens.Animation.snappy) {
          selectedDate = Date()
        }
      } label: {
        Text(calendar.isDateInToday(selectedDate) ? "Today" : shortDate(selectedDate))
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 84, height: 38)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .rooInteractiveGlass(cornerRadius: 10)
      .help("Return to today")

      sportsIconButton("chevron.right") {
        moveReferenceDate(by: 1)
      }
    }
  }

  private func sportsIconButton(
    _ name: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: name)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 38, height: 38)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .rooInteractiveGlass(cornerRadius: 10)
  }

  // MARK: - Scope / sport controls

  private var scopeBar: some View {
    HStack(spacing: 8) {
      Button {
        withAnimation(.easeOut(duration: 0.15)) {
          showSportPicker.toggle()
          showFilters = false
        }
      } label: {
        HStack(spacing: 7) {
          SportIconConfiguration.icon(for: selectedSport)
            .font(.system(size: 11, weight: .semibold))

          Text(selectedSport)
            .font(.system(size: 11, weight: .semibold))

          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(
          selectedSport == "All Sports"
            ? athleticsColor
            : DesignTokens.Colors.primaryText
        )
        .padding(.horizontal, 13)
        .frame(height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(
            selectedSport == "All Sports"
              ? athleticsColor.opacity(0.11)
              : DesignTokens.Colors.surface
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(
            selectedSport == "All Sports"
              ? athleticsColor.opacity(0.24)
              : DesignTokens.Colors.border,
            lineWidth: 1
          )
      }
      .overlay(alignment: .topLeading) {
        if showSportPicker {
          sportPickerPanel
            .offset(y: 44)
            .transition(
              .opacity.combined(
                with: .scale(scale: 0.97, anchor: .topLeading)
              )
            )
            .zIndex(180)
        }
      }
      .zIndex(showSportPicker ? 180 : 0)

      ForEach(SportsRangeFilter.allCases) { item in
        Button {
          var transaction = Transaction()
          transaction.animation = nil
          withTransaction(transaction) {
            range = item
            showCalendar = false
          }
        } label: {
          Text(item.title)
            .font(.system(size: 11, weight: (range == item && !showCalendar) ? .semibold : .medium))
            .foregroundStyle(
              (range == item && !showCalendar)
                ? DesignTokens.Colors.primaryText
                : DesignTokens.Colors.secondaryText
            )
            .padding(.horizontal, 13)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
              (range == item && !showCalendar)
                ? DesignTokens.Colors.selection
                : DesignTokens.Colors.surface
            )
        }
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
              (range == item && !showCalendar)
                ? DesignTokens.Colors.selectionBorder
                : DesignTokens.Colors.border,
              lineWidth: 1
            )
        }
      }

      Button {
        withAnimation(DesignTokens.Animation.navigation) {
          range = .month
          showCalendar = true
          showSportPicker = false
          showFilters = false
        }
      } label: {
        Label("Calendar", systemImage: "calendar")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(showCalendar ? athleticsColor : DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 13)
          .frame(height: 36)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        showCalendar ? athleticsColor.opacity(0.10) : DesignTokens.Colors.surface,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            showCalendar ? athleticsColor.opacity(0.24) : DesignTokens.Colors.border, lineWidth: 1)
      }

      Spacer()

      if activeFilterCount > 0 {
        Text("\(activeFilterCount) filter\(activeFilterCount == 1 ? "" : "s")")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(athleticsColor)
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(athleticsColor.opacity(0.10), in: Capsule())
      }
    }
    .zIndex(180)
  }

  private var sportPickerPanel: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("Sports")
          .font(.system(size: 13, weight: .semibold))

        Spacer()

        if selectedSport != "All Sports" {
          Button("Clear") {
            selectedSport = "All Sports"
            showSportPicker = false
          }
          .buttonStyle(.plain)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(athleticsColor)
          .padding(.horizontal, 5)
          .frame(minHeight: 24)
          .contentShape(Rectangle())
        }
      }

      sportPickerRow("All Sports")

      ForEach(sportsCategories, id: \.self) { sport in
        sportPickerRow(sport)
      }
    }
    .padding(13)
    .frame(width: 230)
    .rooGlass(cornerRadius: 14)
    .rooFloatingShadow()
  }

  private func sportPickerRow(_ sport: String) -> some View {
    Button {
      selectedSport = sport
      showSportPicker = false
    } label: {
      HStack(spacing: 9) {
        SportIconConfiguration.icon(for: sport)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(
            selectedSport == sport
              ? athleticsColor
              : DesignTokens.Colors.secondaryText
          )
          .frame(width: 20)

        Text(sport)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Spacer()

        if selectedSport == sport {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(athleticsColor)
        }
      }
      .padding(.horizontal, 9)
      .frame(height: 34)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      selectedSport == sport
        ? athleticsColor.opacity(0.09)
        : DesignTokens.Colors.selection.opacity(0.35),
      in: RoundedRectangle(cornerRadius: 9, style: .continuous)
    )
  }

  // MARK: - Filters

  private var sportsFiltersPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Filters")
            .font(.system(size: 14, weight: .semibold))

          Text("Choose which games appear")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button {
          showFilters = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DesignTokens.Colors.selection, in: Circle())
      }

      Divider().opacity(0.35)

      sportsFilterRow(
        title: "Home games",
        subtitle: "Show games marked home",
        systemImage: "house.fill",
        color: athleticsColor,
        isOn: showHomeGames
      ) {
        showHomeGames.toggle()
      }

      sportsFilterRow(
        title: "Away games",
        subtitle: "Show games marked away",
        systemImage: "car.fill",
        color: DesignTokens.Colors.events,
        isOn: showAwayGames
      ) {
        showAwayGames.toggle()
      }

      sportsFilterRow(
        title: "Schedule changes",
        subtitle: "Cancelled, rescheduled, and conditional games",
        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
        color: DesignTokens.Colors.warning,
        isOn: showChangedGames
      ) {
        showChangedGames.toggle()
      }

      if activeFilterCount > 0 {
        Divider().opacity(0.35)

        Button {
          showHomeGames = true
          showAwayGames = true
          showChangedGames = true
          selectedSport = "All Sports"
          searchText = ""
        } label: {
          Text("Clear Filters")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          DesignTokens.Colors.selection,
          in: RoundedRectangle(cornerRadius: 9)
        )
      }
    }
    .padding(14)
    .frame(width: 280)
    .rooGlass(cornerRadius: 15)
    .rooFloatingShadow()
  }

  private func sportsFilterRow(
    title: String,
    subtitle: String,
    systemImage: String,
    color: Color,
    isOn: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.12))

          Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
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
            .fill(isOn ? color : DesignTokens.Colors.selection)
            .frame(width: 20, height: 20)

          if isOn {
            Image(systemName: "checkmark")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(.white)
          }
        }
      }
      .padding(.horizontal, 9)
      .frame(height: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      DesignTokens.Colors.selection.opacity(isOn ? 0.68 : 0.30),
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
  }

  // MARK: - Right rail

  private var nextUpCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      SportsSectionLabel("NEXT UP", color: athleticsColor)

      if let game = nextUpcomingGame {
        let teamColor = SportIconConfiguration.teamColor(for: game.team)

        HStack(alignment: .top, spacing: 11) {
          sportIconTile(for: game.team, color: teamColor)

          VStack(alignment: .leading, spacing: 4) {
            Text(game.team)
              .font(.system(size: 14, weight: .semibold))

            Text(opponentLine(game))
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.primaryText)
              .lineLimit(2)

            HStack(spacing: 6) {
              Text(shortGameDate(game))
              if !game.time.isEmpty {
                Text("•")
                Text(game.time)
              }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()
        }

        if let countdown = countdownText(for: game) {
          Text(countdown)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(teamColor)
        }

        Button {
          selectedGame = game
        } label: {
          HStack {
            Text("View Game")
            Spacer()
            Image(systemName: "chevron.right")
          }
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .padding(.horizontal, 11)
          .frame(height: 34)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
      } else {
        compactEmptyState(
          icon: "calendar.badge.checkmark",
          title: "No upcoming games",
          subtitle: "There isn’t another game on the school sports schedule yet."
        )
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var updatesCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SportsSectionLabel("SCHEDULE CHANGES", color: DesignTokens.Colors.warning)
        Spacer()
        Text("\(updates.count)")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      if updates.isEmpty {
        compactEmptyState(
          icon: "checkmark.circle",
          title: "No schedule changes",
          subtitle: "Cancelled, rescheduled, or noted games will appear here."
        )
      } else {
        VStack(spacing: 0) {
          ForEach(Array(updates.prefix(3))) { game in
            Button {
              selectedGame = game
            } label: {
              HStack(alignment: .top, spacing: 9) {
                Circle()
                  .fill(statusColor(game))
                  .frame(width: 7, height: 7)
                  .padding(.top, 4)

                VStack(alignment: .leading, spacing: 2) {
                  Text(game.team)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)

                  Text(updateSubtitle(game))
                    .font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .lineLimit(2)
                }

                Spacer()

                Text(shortGameDate(game))
                  .font(.system(size: 9, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.subtleText)
              }
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if game.id != updates.prefix(3).last?.id {
              Divider().opacity(0.28)
            }
          }
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var athleticCalendarCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      SportsSectionLabel("SPORTS CALENDAR", color: DesignTokens.Colors.events)

      Button {
        selectedDate = Date()
        range = .week
      } label: {
        HStack(spacing: 11) {
          ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(DesignTokens.Colors.events.opacity(0.12))

            Image(systemName: "calendar")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.events)
          }
          .frame(width: 38, height: 38)

          VStack(alignment: .leading, spacing: 3) {
            Text(nextSevenDayRangeText)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text("\(nextSevenDayGames.count) game\(nextSevenDayGames.count == 1 ? "" : "s")")
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        DesignTokens.Colors.selection.opacity(0.42),
        in: RoundedRectangle(cornerRadius: 11)
      )
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: - Main list states

  private var loadingCard: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)

      Text("Loading games…")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)

      Spacer()
    }
    .padding(16)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func errorCard(_: Error) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.Colors.warning)

      VStack(alignment: .leading, spacing: 3) {
        Text("Couldn’t load games")
          .font(.system(size: 12, weight: .semibold))

        Text("Check your connection or try again in a moment.")
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      Button("Try Again") {
        store.refresh()
      }
      .buttonStyle(.plain)
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(athleticsColor)
      .frame(minWidth: 44, minHeight: 28)
      .contentShape(Rectangle())
    }
    .padding(16)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "sportscourt")
        .font(.system(size: 24))
        .foregroundStyle(athleticsColor)

      Text("No games match this view")
        .font(.system(size: 14, weight: .semibold))

      Text("Try another date, sport, or filter.")
        .font(.system(size: 11))
        .foregroundStyle(DesignTokens.Colors.secondaryText)

      if activeFilterCount > 0 || !searchText.isEmpty || selectedSport != "All Sports" {
        Button("Clear Filters") {
          showHomeGames = true
          showAwayGames = true
          showChangedGames = true
          selectedSport = "All Sports"
          searchText = ""
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(athleticsColor)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(athleticsColor.opacity(0.10), in: Capsule())
        .contentShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 54)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var sourceNote: some View {
    HStack(alignment: .top, spacing: 7) {
      Image(systemName: "info.circle")
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      Text("Game times can change. RooMate shows the latest school sports schedule available.")
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      Spacer()
    }
    .padding(.horizontal, 6)
  }

  // MARK: - Data

  private var allDatedGames: [SportsGame] {
    store.liveGames
      .filter { $0.date != nil }
      .sorted {
        combinedDate(for: $0) < combinedDate(for: $1)
      }
  }

  private var filteredGames: [SportsGame] {
    let query =
      searchText
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    return allDatedGames.filter { game in
      guard let date = game.date else { return false }

      if !dateMatchesRange(date) {
        return false
      }

      if selectedSport != "All Sports"
        && sportName(from: game.team) != selectedSport
      {
        return false
      }

      let isAway = isAwayGame(game)
      if isAway && !showAwayGames {
        return false
      }
      if !isAway && !showHomeGames {
        return false
      }

      if !showChangedGames {
        switch game.status {
        case .scheduled:
          break
        case .cancelled, .rescheduled, .conditional, .eliminated:
          return false
        }
      }

      if !query.isEmpty {
        let searchable = [
          game.team,
          game.opponent,
          game.time,
          game.notesRaw,
          sportName(from: game.team),
          isAway ? "away" : "home",
        ]
        .joined(separator: " ")
        .lowercased()

        if !searchable.contains(query) {
          return false
        }
      }

      return true
    }
  }

  private var sportsMonthGridDates: [Date?] {
    guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else { return [] }
    let monthStart = calendar.startOfDay(for: interval.start)
    let weekday = calendar.component(.weekday, from: monthStart)
    let leading = (weekday - calendar.firstWeekday + 7) % 7
    let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
    var dates = [Date?](repeating: nil, count: leading)
    for offset in 0..<dayCount {
      dates.append(calendar.date(byAdding: .day, value: offset, to: monthStart))
    }
    while dates.count % 7 != 0 { dates.append(nil) }
    return dates
  }

  private func calendarGames(on date: Date) -> [SportsGame] {
    filteredGames.filter { game in
      guard let gameDate = game.date else { return false }
      return calendar.isDate(gameDate, inSameDayAs: date)
    }.sorted { combinedDate(for: $0) < combinedDate(for: $1) }
  }

  private var selectedSportsCalendarDayGames: [SportsGame] { calendarGames(on: selectedDate) }

  private func sportsMonthYear(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    return formatter.string(from: date)
  }

  private func sportsCalendarDayTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: date)
  }

  private func sportsCalendarStatusColor(_ game: SportsGame) -> Color {
    switch game.status {
    case .scheduled: return SportIconConfiguration.teamColor(for: game.team)
    case .cancelled: return DesignTokens.Colors.destructive
    case .rescheduled, .conditional: return DesignTokens.Colors.warning
    case .eliminated: return DesignTokens.Colors.subtleText
    }
  }

  private var groupedGames: [SportsDayGroup] {
    let grouped = Dictionary(grouping: filteredGames) { game in
      calendar.startOfDay(for: game.date ?? selectedDate)
    }

    return grouped
      .keys
      .sorted()
      .map { date in
        SportsDayGroup(
          date: date,
          games: (grouped[date] ?? []).sorted {
            combinedDate(for: $0) < combinedDate(for: $1)
          }
        )
      }
  }

  private var teamNames: [String] {
    Array(Set(store.liveGames.map(\.team).filter { !$0.isEmpty }))
      .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var sportsCategories: [String] {
    Array(Set(teamNames.map(sportName(from:))))
      .filter { !$0.isEmpty && $0 != "All Sports" }
      .sorted()
  }

  private var nextUpcomingGame: SportsGame? {
    let now = Date()

    let candidates = allDatedGames.filter { game in
      guard game.status != .cancelled, game.status != .eliminated else {
        return false
      }
      return combinedDate(for: game) >= now
    }

    return candidates.first
  }

  private var updates: [SportsGame] {
    allDatedGames
      .filter { game in
        game.status != .scheduled
          || !game.notesRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
      }
      .sorted {
        abs(combinedDate(for: $0).timeIntervalSinceNow)
          < abs(combinedDate(for: $1).timeIntervalSinceNow)
      }
  }

  private var nextSevenDayGames: [SportsGame] {
    let start = calendar.startOfDay(for: Date())
    let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start

    return allDatedGames.filter { game in
      guard let date = game.date else { return false }
      return date >= start && date < end
    }
  }

  private var nextSevenDayRangeText: String {
    let start = Date()
    let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"

    return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
  }

  private var activeFilterCount: Int {
    var count = 0
    if !showHomeGames { count += 1 }
    if !showAwayGames { count += 1 }
    if !showChangedGames { count += 1 }
    if selectedSport != "All Sports" { count += 1 }
    return count
  }

  // MARK: - Helpers

  private var savedGameIDs: Set<String> {
    Set(savedGameIDsRaw.split(separator: "\n").map(String.init))
  }

  private func toggleGameReminder(_ game: SportsGame) {
    var gameIDs = savedGameIDs
    if gameIDs.contains(game.id) {
      gameIDs.remove(game.id)
    } else {
      gameIDs.insert(game.id)
    }
    savedGameIDsRaw = gameIDs.sorted().joined(separator: "\n")
    NotificationCenter.default.post(
      name: .rooMateSportsPreferencesDidChange,
      object: nil
    )
  }

  private func dateMatchesRange(_ date: Date) -> Bool {
    switch range {
    case .today:
      return calendar.isDate(date, inSameDayAs: selectedDate)

    case .week:
      guard
        let interval = calendar.dateInterval(
          of: .weekOfYear,
          for: selectedDate
        )
      else {
        return false
      }
      return interval.contains(date)

    case .month:
      return calendar.isDate(
        date,
        equalTo: selectedDate,
        toGranularity: .month
      )
    }
  }

  private func moveReferenceDate(by amount: Int) {
    let component: Calendar.Component
    switch range {
    case .today:
      component = .day
    case .week:
      component = .weekOfYear
    case .month:
      component = .month
    }

    selectedDate =
      calendar.date(
        byAdding: component,
        value: amount,
        to: selectedDate
      ) ?? selectedDate
  }

  private func combinedDate(for game: SportsGame) -> Date {
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

    for format in ["h:mm a", "h:mma", "hh:mm a"] {
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

  private func opponentLine(_ game: SportsGame) -> String {
    if game.opponent.isEmpty {
      return "Opponent TBA"
    }
    return isAwayGame(game)
      ? "@ \(game.opponent)"
      : "vs \(game.opponent)"
  }

  private func sportName(from teamName: String) -> String {
    let value = teamName.lowercased()

    if value.contains("field hockey") { return "Field Hockey" }
    if value.contains("cross country") { return "Cross Country" }
    if value.contains("soccer") { return "Soccer" }
    if value.contains("basketball") { return "Basketball" }
    if value.contains("volleyball") { return "Volleyball" }
    if value.contains("football") { return "Football" }
    if value.contains("softball") { return "Softball" }
    if value.contains("baseball") { return "Baseball" }
    if value.contains("tennis") { return "Tennis" }
    if value.contains("golf") { return "Golf" }
    if value.contains("lacrosse") { return "Lacrosse" }
    if value.contains("swim") { return "Swimming" }
    if value.contains("wrestl") { return "Wrestling" }
    if value.contains("track") { return "Track & Field" }
    if value.contains("ultimate") || value.contains("frisbee") {
      return "Ultimate Frisbee"
    }

    return
      teamName
      .replacingOccurrences(of: "Varsity", with: "")
      .replacingOccurrences(of: "Junior Varsity", with: "")
      .replacingOccurrences(of: "JV", with: "")
      .replacingOccurrences(of: "MS", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func teamLevel(_ game: SportsGame) -> String? {
    let value = game.team.lowercased()
    if value.contains("middle school") || value.hasPrefix("ms ") {
      return "Middle School"
    }
    if value.contains("jv") || value.contains("junior varsity") {
      return "Junior Varsity"
    }
    if value.contains("varsity") {
      return "Varsity"
    }
    return nil
  }

  private func homeLocation(_ game: SportsGame) -> String? {
    // The live schedule does not publish a reliable home-venue field yet.
    // Avoid inventing a location until RooMate has a verified source.
    nil
  }

  private func statusColor(_ game: SportsGame) -> Color {
    switch game.status {
    case .scheduled:
      return SportIconConfiguration.teamColor(for: game.team)
    case .cancelled:
      return DesignTokens.Colors.destructive
    case .rescheduled:
      return DesignTokens.Colors.warning
    case .conditional:
      return DesignTokens.Colors.warning
    case .eliminated:
      return DesignTokens.Colors.subtleText
    }
  }

  private func statusLabel(_ game: SportsGame) -> String? {
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

  private func updateSubtitle(_ game: SportsGame) -> String {
    if let status = statusLabel(game) {
      if !game.notesFormatted.isEmpty {
        return "\(status) • \(game.notesFormatted)"
      }
      return status
    }

    return game.notesFormatted.isEmpty
      ? opponentLine(game)
      : game.notesFormatted
  }

  private func countdownText(for game: SportsGame) -> String? {
    let date = combinedDate(for: game)
    let seconds = date.timeIntervalSinceNow

    guard seconds > 0 else { return nil }

    let totalMinutes = Int(seconds / 60)
    let days = totalMinutes / (60 * 24)
    let hours = (totalMinutes % (60 * 24)) / 60
    let minutes = totalMinutes % 60

    if days > 0 {
      return "\(days)d \(hours)h away"
    }
    if hours > 0 {
      return "\(hours)h \(minutes)m away"
    }
    return "\(max(minutes, 1))m away"
  }

  private func longDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
  }

  private func shortDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
  }

  private func shortGameDate(_ game: SportsGame) -> String {
    guard let date = game.date else {
      return game.rawDateString
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    return formatter.string(from: date)
  }

  private func compactEmptyState(
    icon: String,
    title: String,
    subtitle: String
  ) -> some View {
    VStack(spacing: 7) {
      Image(systemName: icon)
        .font(.system(size: 17))
        .foregroundStyle(DesignTokens.Colors.subtleText)

      Text(title)
        .font(.system(size: 11, weight: .semibold))

      Text(subtitle)
        .font(.system(size: 9))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
  }

  private func sportIconTile(
    for team: String,
    color: Color
  ) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(color.opacity(0.13))

      SportIconConfiguration.icon(for: sportName(from: team))
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(color)
    }
    .frame(width: 44, height: 44)
  }
}

// MARK: - Range

private enum SportsRangeFilter: String, CaseIterable, Identifiable {
  case today
  case week
  case month

  var id: String { rawValue }

  var title: String {
    switch self {
    case .today: "Today"
    case .week: "This Week"
    case .month: "This Month"
    }
  }
}

// MARK: - Day grouping

private struct SportsDayGroup: Identifiable {
  let date: Date
  let games: [SportsGame]

  var id: Date { date }
}

private struct SportsDaySection: View {
  let group: SportsDayGroup
  @ObservedObject var store: SportsStore
  let savedGameIDs: Set<String>
  let onToggleReminder: (SportsGame) -> Void
  let onSelectGame: (SportsGame) -> Void

  private let athleticsColor = DesignTokens.Colors.athletics

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(dayHeader(group.date))
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(athleticsColor)

        Spacer()

        Text("\(group.games.count) game\(group.games.count == 1 ? "" : "s")")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 16)
      .frame(height: 44)

      Divider().opacity(0.30)

      ForEach(group.games) { game in
        SportsFeedGameRow(
          game: game,
          store: store,
          hasReminder: savedGameIDs.contains(game.id),
          onToggleReminder: { onToggleReminder(game) },
          onSelect: { onSelectGame(game) }
        )

        if game.id != group.games.last?.id {
          Divider()
            .opacity(0.24)
            .padding(.horizontal, 16)
        }
      }
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func dayHeader(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE • MMMM d"
    return formatter.string(from: date).uppercased()
  }
}

// MARK: - Game row

private struct SportsFeedGameRow: View {
  let game: SportsGame
  @ObservedObject var store: SportsStore
  let hasReminder: Bool
  let onToggleReminder: () -> Void
  let onSelect: () -> Void

  private let calendar = Calendar.current

  private var teamColor: Color {
    SportIconConfiguration.teamColor(for: game.team)
  }

  var body: some View {
    HStack(spacing: 13) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(teamColor.opacity(0.12))

        SportIconConfiguration.icon(for: sportName)
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(teamColor)
      }
      .frame(width: 46, height: 46)

      VStack(alignment: .leading, spacing: 4) {
        Text(game.team.uppercased())
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(teamColor)
          .lineLimit(1)

        Text(opponentText)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)

        HStack(spacing: 7) {
          if let level = levelText {
            Text(level)
          }

          if levelText != nil {
            Text("•")
          }

          Label(
            isAway ? "Away" : "Home",
            systemImage: isAway ? "car.fill" : "house.fill"
          )
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(
          isAway
            ? DesignTokens.Colors.secondaryText
            : teamColor
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 4) {
        Text(game.time.isEmpty ? "TBA" : game.time)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(venueText)
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(1)
      }
      .frame(width: 150, alignment: .leading)

      if let status = statusText {
        Text(status)
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(statusColor)
          .padding(.horizontal, 8)
          .frame(height: 24)
          .background(statusColor.opacity(0.10), in: Capsule())
          .frame(width: 88)
      } else {
        Color.clear
          .frame(width: 88, height: 24)
      }

      Button(action: onToggleReminder) {
        Image(systemName: hasReminder ? "bell.fill" : "bell")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(
            hasReminder
              ? teamColor
              : DesignTokens.Colors.subtleText
          )
          .frame(width: 34, height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(
        hasReminder
          ? teamColor.opacity(0.10)
          : DesignTokens.Colors.selection.opacity(0.44),
        in: RoundedRectangle(cornerRadius: 9)
      )
      .help(hasReminder ? "Remove game reminder" : "Remind me about this game")

      Button(action: onSelect) {
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 30, height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .opacity(game.status == .cancelled || game.status == .eliminated ? 0.68 : 1)
    .contentShape(Rectangle())
    .onTapGesture(perform: onSelect)
  }

  private var isAway: Bool {
    let value = game.location
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return value == "a" || value == "away"
  }

  private var opponentText: String {
    guard !game.opponent.isEmpty else {
      return "Opponent TBA"
    }

    return isAway
      ? "@ \(game.opponent)"
      : "vs \(game.opponent)"
  }

  private var venueText: String {
    if isAway {
      if !game.dismiss.isEmpty {
        return "Dismiss \(game.dismiss)"
      }
      return "Away"
    }

    return "Home"
  }

  private var levelText: String? {
    let value = game.team.lowercased()
    if value.contains("middle school") || value.hasPrefix("ms ") {
      return "Middle School"
    }
    if value.contains("jv") || value.contains("junior varsity") {
      return "Junior Varsity"
    }
    if value.contains("varsity") {
      return "Varsity"
    }
    return nil
  }

  private var sportName: String {
    let value = game.team.lowercased()

    if value.contains("field hockey") { return "Field Hockey" }
    if value.contains("cross country") { return "Cross Country" }
    if value.contains("soccer") { return "Soccer" }
    if value.contains("basketball") { return "Basketball" }
    if value.contains("volleyball") { return "Volleyball" }
    if value.contains("football") { return "Football" }
    if value.contains("softball") { return "Softball" }
    if value.contains("baseball") { return "Baseball" }
    if value.contains("tennis") { return "Tennis" }
    if value.contains("golf") { return "Golf" }
    if value.contains("lacrosse") { return "Lacrosse" }
    if value.contains("swim") { return "Swimming" }
    if value.contains("wrestl") { return "Wrestling" }
    if value.contains("track") { return "Track & Field" }
    if value.contains("ultimate") || value.contains("frisbee") {
      return "Ultimate Frisbee"
    }

    return game.team
  }

  private var statusText: String? {
    switch game.status {
    case .scheduled:
      return nil
    case .cancelled:
      return "CANCELLED"
    case .rescheduled:
      return "RESCHEDULED"
    case .conditional:
      return "CONDITIONAL"
    case .eliminated:
      return "ELIMINATED"
    }
  }

  private var statusColor: Color {
    switch game.status {
    case .scheduled:
      return teamColor
    case .cancelled:
      return DesignTokens.Colors.destructive
    case .rescheduled, .conditional:
      return DesignTokens.Colors.warning
    case .eliminated:
      return DesignTokens.Colors.subtleText
    }
  }
}

// MARK: - Detail sheet

private struct SportsFeedGameDetailSheet: View {
  let game: SportsGame
  @ObservedObject var store: SportsStore
  let hasReminder: Bool
  let onToggleReminder: () -> Void

  @Environment(\.dismiss)
  private var dismiss

  private var teamColor: Color {
    SportIconConfiguration.teamColor(for: game.team)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        HStack(spacing: 11) {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(teamColor.opacity(0.13))

            SportIconConfiguration.icon(for: sportName)
              .font(.system(size: 19, weight: .semibold))
              .foregroundStyle(teamColor)
          }
          .frame(width: 46, height: 46)

          VStack(alignment: .leading, spacing: 3) {
            Text(game.team)
              .font(.system(size: 18, weight: .semibold))

            Text(opponentText)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }

        Spacer()

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(DesignTokens.Colors.selection, in: Circle())
      }

      Divider().opacity(0.35)

      LazyVGrid(
        columns: [
          GridItem(.flexible()),
          GridItem(.flexible()),
        ],
        alignment: .leading,
        spacing: 14
      ) {
        detailMetric(
          title: "Date",
          value: fullDate,
          icon: "calendar"
        )

        detailMetric(
          title: "Time",
          value: game.time.isEmpty ? "TBA" : game.time,
          icon: "clock"
        )

        detailMetric(
          title: "Location",
          value: isAway ? "Away" : homeVenue,
          icon: isAway ? "car.fill" : "house.fill"
        )

        detailMetric(
          title: "Status",
          value: statusText,
          icon: "info.circle"
        )

        if !game.dismiss.isEmpty {
          detailMetric(
            title: "Dismissal",
            value: game.dismiss,
            icon: "figure.walk"
          )
        }

        if !game.return.isEmpty {
          detailMetric(
            title: "Return",
            value: game.return,
            icon: "arrow.uturn.backward"
          )
        }
      }

      if !game.notesFormatted.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("Notes", systemImage: "note.text")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          Text(game.notesFormatted)
            .font(.system(size: 12))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          DesignTokens.Colors.selection.opacity(0.40),
          in: RoundedRectangle(cornerRadius: 11)
        )
      }

      Button(action: onToggleReminder) {
        HStack {
          Image(systemName: hasReminder ? "bell.fill" : "bell")
          Text(hasReminder ? "Game reminder on" : "Remind me about this game")
          Spacer()
          Image(systemName: hasReminder ? "checkmark" : "plus")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(
          hasReminder
            ? teamColor
            : DesignTokens.Colors.primaryText
        )
        .padding(.horizontal, 12)
        .frame(height: 38)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .rooInteractiveGlass(cornerRadius: 10)
    }
    .padding(20)
    .frame(width: 500)
    .background(DesignTokens.Colors.background)
  }

  private func detailMetric(
    title: String,
    value: String,
    icon: String
  ) -> some View {
    HStack(alignment: .top, spacing: 9) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(teamColor)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 2) {
        Text(title.uppercased())
          .font(.system(size: 8, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.subtleText)

        Text(value)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var isAway: Bool {
    let value = game.location
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    return value == "a" || value == "away"
  }

  private var opponentText: String {
    if game.opponent.isEmpty {
      return "Opponent TBA"
    }
    return isAway
      ? "@ \(game.opponent)"
      : "vs \(game.opponent)"
  }

  private var homeVenue: String {
    // Home venue details are intentionally omitted until a verified source exists.
    "Home"
  }

  private var fullDate: String {
    guard let date = game.date else {
      return game.rawDateString
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
  }

  private var statusText: String {
    switch game.status {
    case .scheduled: "Scheduled"
    case .cancelled: "Cancelled"
    case .rescheduled: "Rescheduled"
    case .conditional: "Conditional"
    case .eliminated: "Eliminated"
    }
  }

  private var sportName: String {
    let value = game.team.lowercased()
    if value.contains("field hockey") { return "Field Hockey" }
    if value.contains("cross country") { return "Cross Country" }
    if value.contains("soccer") { return "Soccer" }
    if value.contains("basketball") { return "Basketball" }
    if value.contains("volleyball") { return "Volleyball" }
    if value.contains("football") { return "Football" }
    if value.contains("softball") { return "Softball" }
    if value.contains("baseball") { return "Baseball" }
    if value.contains("tennis") { return "Tennis" }
    if value.contains("golf") { return "Golf" }
    if value.contains("lacrosse") { return "Lacrosse" }
    if value.contains("swim") { return "Swimming" }
    if value.contains("wrestl") { return "Wrestling" }
    if value.contains("track") { return "Track & Field" }
    if value.contains("ultimate") || value.contains("frisbee") {
      return "Ultimate Frisbee"
    }
    return game.team
  }
}

private struct SportsSectionLabel: View {
  let title: String
  let color: Color

  init(_ title: String, color: Color) {
    self.title = title
    self.color = color
  }

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)

      Text(title)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .tracking(0.7)
    }
  }
}

#Preview {
  SportsHubView(store: SportsStore())
}
