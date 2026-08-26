import SwiftUI

struct RooMateSearchSheet: View {
  @ObservedObject var sportsStore: SportsStore
  @ObservedObject var eventsStore: EventsStore
  @ObservedObject var menuStore: MenuStore
  @ObservedObject private var scheduleStore = UserScheduleStore.shared
  @ObservedObject private var navigation = RooMateNavigationCoordinator.shared
  let onNavigate: (ContentView.Tab) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var selectedResultID: String?
  @FocusState private var searchFocused: Bool

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var tabMatches: [ContentView.Tab] {
    guard !trimmedQuery.isEmpty else { return [] }
    let q = trimmedQuery.lowercased()
    return ContentView.Tab.allCases.filter {
      $0.displayTitle.lowercased().contains(q) || $0.title.lowercased().contains(q)
    }.sorted { searchScore($0.displayTitle) < searchScore($1.displayTitle) }
  }

  private var classMatches: [ClassSearchMatch] {
    guard !trimmedQuery.isEmpty else { return [] }
    let q = trimmedQuery.lowercased()

    return scheduleStore.assignments.compactMap { level, assignment in
      let searchable = [
        assignment.title,
        assignment.teacher,
        assignment.room,
        level.displayName,
      ]
      .joined(separator: " ")
      .lowercased()

      guard searchable.contains(q) else { return nil }
      return ClassSearchMatch(level: level, assignment: assignment)
    }
    .sorted { $0.level.rawValue < $1.level.rawValue }
    .prefix(6)
    .map { $0 }
  }

  private var clubMatches: [Club] {
    guard !trimmedQuery.isEmpty else { return [] }
    let q = trimmedQuery.lowercased()

    return scheduleStore.clubs.filter { club in
      [club.name, club.room, club.otherDaysNote]
        .joined(separator: " ")
        .lowercased()
        .contains(q)
    }
    .prefix(6)
    .map { $0 }
  }

  private var eventMatches: [CalendarEvent] {
    guard !trimmedQuery.isEmpty else { return [] }
    let q = trimmedQuery.lowercased()
    return eventsStore.events.filter {
      $0.title.lowercased().contains(q) || ($0.location?.lowercased().contains(q) ?? false)
    }
    .sorted { $0.startDate < $1.startDate }
    .prefix(6)
    .map { $0 }
  }

  private var sportsMatches: [SportsGame] {
    guard !trimmedQuery.isEmpty else { return [] }
    let q = trimmedQuery.lowercased()
    return sportsStore.liveGames.filter {
      $0.team.lowercased().contains(q) || $0.opponent.lowercased().contains(q)
        || $0.location.lowercased().contains(q)
    }
    .prefix(6)
    .map { $0 }
  }

  private var menuMatches: [MenuRecipe] {
    guard !trimmedQuery.isEmpty else { return [] }
    let q = trimmedQuery.lowercased()
    let recipes = menuStore.currentMenu?.stations.flatMap(\.recipes) ?? []
    return recipes.filter {
      $0.name.lowercased().contains(q) || $0.stationName.lowercased().contains(q)
    }
    .prefix(6)
    .map { $0 }
  }

  private var settingsMatches: [SettingsSearchMatch] {
    guard !trimmedQuery.isEmpty else { return [] }
    return SettingsSearchMatch.all.filter { match in
      ([match.title] + match.keywords).contains { $0.lowercased().contains(trimmedQuery.lowercased()) }
    }
    .sorted { searchScore($0.title) < searchScore($1.title) }
  }

  private var hasResults: Bool {
    !tabMatches.isEmpty || !classMatches.isEmpty || !clubMatches.isEmpty
      || !eventMatches.isEmpty || !sportsMatches.isEmpty || !menuMatches.isEmpty
      || !settingsMatches.isEmpty
  }

  private var resultIDs: [String] {
    tabMatches.map { "tab:\($0.title)" }
      + classMatches.map { "class:\($0.level.rawValue)" }
      + clubMatches.map { "club:\($0.id.uuidString)" }
      + eventMatches.map { "event:\(RooMateStableKey.event($0))" }
      + sportsMatches.map { "game:\($0.id)" }
      + menuMatches.map { "menu:\(menuStore.selectedDate?.id ?? "unknown"):\($0.id)" }
      + settingsMatches.map { "settings:\($0.section)" }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        TextField("Search RooMate", text: $query)
          .textFieldStyle(.plain)
          .font(.system(size: 16, weight: .medium))
          .focused($searchFocused)

        if !query.isEmpty {
          Button {
            query = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(DesignTokens.Colors.subtleText)
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
      .frame(height: 54)

      Divider().opacity(0.45)

      if trimmedQuery.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 28))
            .foregroundStyle(DesignTokens.Colors.subtleText)
          Text("Search your RooMate")
            .font(.system(size: 15, weight: .semibold))
          Text("Find pages, classes, clubs, events, games, and dining items.")
            .font(.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if !hasResults {
        VStack(spacing: 10) {
          Image(systemName: "questionmark.circle")
            .font(.system(size: 26))
            .foregroundStyle(DesignTokens.Colors.subtleText)
          Text("No results for “\(trimmedQuery)”")
            .font(.system(size: 14, weight: .semibold))
          Text("Try another class, club, event, game, or page name.")
            .font(.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if !tabMatches.isEmpty {
              SearchSection(title: "PAGES") {
                ForEach(tabMatches, id: \.self) { tab in
                  let resultID = "tab:\(tab.title)"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: tab.systemImage,
                    color: tab.featureColor,
                    title: tab.displayTitle,
                    subtitle: "Open \(tab.displayTitle)"
                  ) {
                    activate(resultID, tab: tab)
                  }
                }
              }
            }

            if !classMatches.isEmpty {
              SearchSection(title: "CLASSES") {
                ForEach(classMatches) { match in
                  let resultID = "class:\(match.level.rawValue)"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: match.assignment.iconName.isEmpty
                      ? "book.closed.fill" : match.assignment.iconName,
                    color: match.assignment.color.swiftUIColor,
                    title: match.assignment.title.isEmpty
                      ? match.level.displayName : match.assignment.title,
                    subtitle: classSubtitle(match)
                  ) {
                    activate(
                      resultID,
                      tab: .schedule,
                      destination: .scheduleClass(match.level)
                    )
                  }
                }
              }
            }

            if !clubMatches.isEmpty {
              SearchSection(title: "MY CLUBS") {
                ForEach(clubMatches) { club in
                  let resultID = "club:\(club.id.uuidString)"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: club.displayIconName,
                    color: club.displayColor,
                    title: club.name,
                    subtitle: club.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      ? "My Club"
                      : club.room
                  ) {
                    activate(resultID, tab: .clubs, destination: .club(club.id))
                  }
                }
              }
            }

            if !eventMatches.isEmpty {
              SearchSection(title: "EVENTS") {
                ForEach(eventMatches) { event in
                  let resultID = "event:\(RooMateStableKey.event(event))"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: "calendar",
                    color: DesignTokens.Colors.events,
                    title: event.title,
                    subtitle: eventSubtitle(event)
                  ) {
                    activate(
                      resultID,
                      tab: .events,
                      destination: .event(RooMateStableKey.event(event))
                    )
                  }
                }
              }
            }

            if !sportsMatches.isEmpty {
              SearchSection(title: "SPORTS") {
                ForEach(sportsMatches) { game in
                  let resultID = "game:\(game.id)"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: "sportscourt.fill",
                    color: DesignTokens.Colors.athletics,
                    title: game.team,
                    subtitle: game.opponent.isEmpty
                      ? game.rawDateString : "vs. \(game.opponent) • \(game.rawDateString)"
                  ) {
                    activate(resultID, tab: .athletics, destination: .sportsGame(game.id))
                  }
                }
              }
            }

            if !menuMatches.isEmpty {
              SearchSection(title: "DINING") {
                ForEach(menuMatches) { recipe in
                  let resultID = "menu:\(menuStore.selectedDate?.id ?? "unknown"):\(recipe.id)"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: "fork.knife",
                    color: DesignTokens.Colors.dining,
                    title: recipe.name,
                    subtitle: recipe.stationName
                  ) {
                    guard let dateID = menuStore.selectedDate?.id else { return }
                    activate(
                      resultID,
                      tab: .menu,
                      destination: .dining(dateID: dateID, recipeName: recipe.name)
                    )
                  }
                }
              }
            }

            if !settingsMatches.isEmpty {
              SearchSection(title: "SETTINGS") {
                ForEach(settingsMatches) { match in
                  let resultID = "settings:\(match.section)"
                  RooMateGlobalSearchResultRow(
                    id: resultID,
                    isSelected: selectedResultID == resultID,
                    symbol: match.symbol,
                    color: DesignTokens.Colors.primary,
                    title: match.title,
                    subtitle: "Open \(match.section) settings"
                  ) {
                    activate(
                      resultID,
                      tab: .settings,
                      destination: .settings(match.section)
                    )
                  }
                }
              }
            }
          }
          .padding(16)
        }
      }
    }
    .frame(width: 580, height: 520)
    .background(DesignTokens.Colors.background)
    .onAppear {
      searchFocused = true
      if eventsStore.events.isEmpty && !eventsStore.isLoading { eventsStore.refresh() }
      if menuStore.currentMenu == nil && !menuStore.isLoading { menuStore.refresh() }
    }
    .onChange(of: query) { _, _ in selectedResultID = resultIDs.first }
    .onChange(of: resultIDs) { _, ids in
      if selectedResultID == nil || !ids.contains(selectedResultID ?? "") {
        selectedResultID = ids.first
      }
    }
    .onMoveCommand { direction in
      switch direction {
      case .down: moveSelection(by: 1)
      case .up: moveSelection(by: -1)
      default: break
      }
    }
    .onSubmit { openSelectedResult() }
    .onExitCommand { dismiss() }
  }

  private func searchScore(_ value: String) -> Int {
    let value = value.lowercased()
    let query = trimmedQuery.lowercased()
    if value == query { return 0 }
    if value.hasPrefix(query) { return 1 }
    if value.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .contains(where: { $0.hasPrefix(query) }) { return 2 }
    return value.contains(query) ? 3 : 4
  }

  private func activate(
    _ id: String,
    tab: ContentView.Tab,
    destination: RooMateNavigationCoordinator.Destination? = nil
  ) {
    selectedResultID = id
    if let destination { navigation.navigate(to: destination) }
    onNavigate(tab)
    dismiss()
  }

  private func moveSelection(by offset: Int) {
    guard !resultIDs.isEmpty else { return }
    let current = selectedResultID.flatMap(resultIDs.firstIndex(of:)) ?? (offset > 0 ? -1 : 0)
    let next = min(max(current + offset, 0), resultIDs.count - 1)
    selectedResultID = resultIDs[next]
  }

  private func openSelectedResult() {
    guard let selectedResultID else { return }

    if let tab = tabMatches.first(where: { "tab:\($0.title)" == selectedResultID }) {
      activate(selectedResultID, tab: tab)
      return
    }
    if let match = classMatches.first(where: { "class:\($0.level.rawValue)" == selectedResultID }) {
      activate(selectedResultID, tab: .schedule, destination: .scheduleClass(match.level))
      return
    }
    if let club = clubMatches.first(where: { "club:\($0.id.uuidString)" == selectedResultID }) {
      activate(selectedResultID, tab: .clubs, destination: .club(club.id))
      return
    }
    if let event = eventMatches.first(where: {
      "event:\(RooMateStableKey.event($0))" == selectedResultID
    }) {
      activate(
        selectedResultID,
        tab: .events,
        destination: .event(RooMateStableKey.event(event))
      )
      return
    }
    if let game = sportsMatches.first(where: { "game:\($0.id)" == selectedResultID }) {
      activate(selectedResultID, tab: .athletics, destination: .sportsGame(game.id))
      return
    }
    if let recipe = menuMatches.first(where: {
      "menu:\(menuStore.selectedDate?.id ?? "unknown"):\($0.id)" == selectedResultID
    }), let dateID = menuStore.selectedDate?.id {
      activate(
        selectedResultID,
        tab: .menu,
        destination: .dining(dateID: dateID, recipeName: recipe.name)
      )
      return
    }
    if let setting = settingsMatches.first(where: {
      "settings:\($0.section)" == selectedResultID
    }) {
      activate(selectedResultID, tab: .settings, destination: .settings(setting.section))
    }
  }

  private func classSubtitle(_ match: ClassSearchMatch) -> String {
    let details = [match.level.displayName, match.assignment.teacher, match.assignment.room]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return details.joined(separator: " • ")
  }

  private func eventSubtitle(_ event: CalendarEvent) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d • h:mm a"
    let date = formatter.string(from: event.startDate)
    if let location = event.location, !location.isEmpty {
      return "\(date) • \(location)"
    }
    return date
  }
}

private struct ClassSearchMatch: Identifiable {
  let level: Level
  let assignment: ClassAssignment
  var id: Level { level }
}

private struct SettingsSearchMatch: Identifiable {
  let title: String
  let section: String
  let symbol: String
  let keywords: [String]
  var id: String { section }

  static let all: [SettingsSearchMatch] = [
    .init(title: "Appearance & menu bar", section: "General", symbol: "gearshape", keywords: ["theme", "light", "dark", "launch", "timer"]),
    .init(title: "Schedule setup", section: "Schedule", symbol: "calendar", keywords: ["classes", "blocks", "notifications"]),
    .init(title: "Dining preferences", section: "Dining", symbol: "fork.knife", keywords: ["favorites", "allergens", "menu"]),
    .init(title: "Sports game reminders", section: "Sports", symbol: "sportscourt", keywords: ["games", "reminders", "athletics"]),
    .init(title: "Event preferences", section: "Events", symbol: "calendar.circle", keywords: ["calendar", "saved", "reminders"]),
    .init(title: "PacTrack settings", section: "PacTrack", symbol: "chart.bar.xaxis", keywords: ["credits", "requirements"]),
    .init(title: "Software updates", section: "Updates", symbol: "arrow.down.circle", keywords: ["sparkle", "version", "check for updates"]),
    .init(title: "About & feedback", section: "About", symbol: "info.circle", keywords: ["report problem", "suggest feature", "diagnostics", "what's new"]),
  ]
}

private struct SearchSection<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .tracking(0.7)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      VStack(spacing: 4) { content }
    }
  }
}

private struct RooMateGlobalSearchResultRow: View {
  let id: String
  let isSelected: Bool
  let symbol: String
  let color: Color
  let title: String
  let subtitle: String
  let action: () -> Void
  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 11) {
        ZStack {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color.opacity(0.12))
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)
          Text(subtitle)
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }

        Spacer()
        Image(systemName: "arrow.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.subtleText)
      }
      .padding(.horizontal, 10)
      .frame(height: 50)
      .background(
        (isSelected || isHovering ? DesignTokens.Colors.selection : DesignTokens.Colors.surface),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .stroke(DesignTokens.Colors.border, lineWidth: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .id(id)
    .onHover { isHovering = $0 }
  }
}
