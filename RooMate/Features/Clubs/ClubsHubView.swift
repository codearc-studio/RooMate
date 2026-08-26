import SwiftUI

private enum ClubsHubSection: String, CaseIterable, Identifiable {
  case overview
  case directory
  case myClubs

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "Overview"
    case .directory: "Directory"
    case .myClubs: "My Clubs"
    }
  }

  var icon: String {
    switch self {
    case .overview: "square.grid.2x2.fill"
    case .directory: "rectangle.grid.2x2.fill"
    case .myClubs: "person.3.fill"
    }
  }
}

struct ClubsHubView: View {
  @ObservedObject var store: UserScheduleStore
  @ObservedObject private var navigation = RooMateNavigationCoordinator.shared
  @StateObject private var directoryStore = ClubDirectoryStore()

  @Environment(\.openURL) private var openURL

  @State private var selectedSection: ClubsHubSection = .overview
  @State private var searchText = ""
  @State private var selectedCategory = "All Clubs"

  private let accent = DesignTokens.Colors.events

  var body: some View {
    VStack(spacing: 16) {
      hubHeader
      hubNavigation

      Group {
        switch selectedSection {
        case .overview:
          overviewWorkspace
            .transition(.opacity)
        case .directory:
          directoryWorkspace
            .transition(.opacity)
        case .myClubs:
          myClubsWorkspace
            .transition(.opacity)
        }
      }
      .animation(DesignTokens.Animation.navigation, value: selectedSection)
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 16)
    .background { BackgroundView() }
    .task {
      if directoryStore.clubs.isEmpty {
        await directoryStore.refresh()
      }
      handleNavigationRequest()
    }
    .onChange(of: navigation.request) { _, _ in handleNavigationRequest() }
  }

  private func handleNavigationRequest() {
    guard let request = navigation.request,
      case .club(let id) = request.destination,
      store.clubs.contains(where: { $0.id == id })
    else { return }
    selectedSection = .myClubs
    navigation.consume(request)
  }

  // MARK: Header

  private var hubHeader: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Clubs")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(
          "Explore clubs, keep the ones you’re part of in My Clubs, and add meeting times to your schedule."
        )
        .font(.system(size: 11))
        .foregroundStyle(DesignTokens.Colors.secondaryText)

        RemoteDataStatusLabel(
          lastUpdated: directoryStore.lastUpdated,
          usingSavedData: directoryStore.isShowingSavedData
        )
      }

      Spacer()

      if directoryStore.isConfigured {
        Button {
          Task { await directoryStore.refresh() }
        } label: {
          Label(directoryStore.isLoading ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(directoryStore.isLoading)
        .background(
          DesignTokens.Colors.hover.opacity(0.38),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      }

      Button {
        addBlankClub()
      } label: {
        Label("Add to My Clubs", systemImage: "plus")
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(accent)
          .padding(.horizontal, 12)
          .frame(height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(accent.opacity(0.24), lineWidth: 1)
      }
    }
  }

  private var hubNavigation: some View {
    HStack(spacing: 7) {
      ForEach(ClubsHubSection.allCases) { section in
        let selected = selectedSection == section

        Button {
          withAnimation(DesignTokens.Animation.navigation) {
            selectedSection = section
          }
        } label: {
          HStack(spacing: 7) {
            Image(systemName: section.icon)
              .font(.system(size: 10.5, weight: .semibold))
            Text(section.title)
              .font(.system(size: 10.5, weight: .semibold))
          }
          .foregroundStyle(selected ? accent : DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 12)
          .frame(height: 34)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
          selected ? accent.opacity(0.12) : DesignTokens.Colors.hover.opacity(0.24),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
              selected ? accent.opacity(0.28) : DesignTokens.Colors.border, lineWidth: 1)
        }
      }

      Spacer()
    }
  }

  // MARK: Overview

  private var overviewWorkspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        overviewMetricStrip

        HStack(alignment: .top, spacing: 16) {
          myClubsOverviewCard
            .frame(maxWidth: .infinity)

          todayCard
            .frame(width: 330)
        }

        if !directoryStore.clubs.isEmpty {
          featuredDirectoryCard
        }
      }
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  private var overviewMetricStrip: some View {
    HStack(spacing: 12) {
      metricCard(
        title: "My Clubs",
        value: "\(store.clubs.count)",
        subtitle: store.clubs.count == 1 ? "club" : "clubs",
        icon: "person.3.fill",
        color: accent
      )

      metricCard(
        title: "Today",
        value: "\(todayClubs.count)",
        subtitle: todayClubs.count == 1 ? "club meeting" : "club meetings",
        icon: "calendar.badge.clock",
        color: DesignTokens.Colors.schedule
      )

      metricCard(
        title: "Meetings",
        value: "\(configuredMeetingCount)",
        subtitle: configuredMeetingCount == 1 ? "time set" : "times set",
        icon: "slider.horizontal.3",
        color: DesignTokens.Colors.pacTrack
      )

      metricCard(
        title: "Directory",
        value: directoryStore.isConfigured ? "\(directoryStore.clubs.count)" : "—",
        subtitle: directoryStore.isConfigured ? "clubs available" : "directory unavailable",
        icon: "rectangle.grid.2x2.fill",
        color: DesignTokens.Colors.dining
      )
    }
  }

  private func metricCard(
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

  private var myClubsOverviewCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader(
        eyebrow: "MY CLUBS",
        subtitle: "Your clubs and the meetings you’ve added",
        actionTitle: "Manage"
      ) {
        selectedSection = .myClubs
      }

      Divider().opacity(0.30)

      if store.clubs.isEmpty {
        overviewEmptyState(
          icon: "person.3",
          title: "My Clubs is empty",
          subtitle:
            "Browse Directory, add the clubs you attend, then set the meeting times that apply to you."
        )
        .frame(minHeight: 205)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(store.clubs.prefix(6))) { club in
            Button {
              selectedSection = .myClubs
            } label: {
              HStack(spacing: 11) {
                clubIcon(club)

                VStack(alignment: .leading, spacing: 2) {
                  Text(
                    club.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      ? "Untitled Club" : club.name
                  )
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.primaryText)
                  .lineLimit(1)
                  Text(clubOverviewSubtitle(club))
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                    .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                  .font(.system(size: 8.5, weight: .bold))
                  .foregroundStyle(DesignTokens.Colors.subtleText)
              }
              .padding(.horizontal, 15)
              .frame(height: 58)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if club.id != store.clubs.prefix(6).last?.id {
              Divider().padding(.leading, 66).opacity(0.28)
            }
          }
        }
      }
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var todayCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionHeader(
        eyebrow: "TODAY",
        subtitle: todayDateText,
        actionTitle: nil,
        action: nil
      )

      Divider().opacity(0.30)

      if todayClubs.isEmpty {
        overviewEmptyState(
          icon: "calendar",
          title: "No club meetings today",
          subtitle: "Meetings you add to My Clubs will show here when they match today."
        )
        .frame(minHeight: 205)
      } else {
        VStack(spacing: 0) {
          ForEach(todayClubs) { club in
            HStack(spacing: 10) {
              clubIcon(club, size: 36)
              VStack(alignment: .leading, spacing: 2) {
                Text(club.name.isEmpty ? "Untitled Club" : club.name)
                  .font(.system(size: 11.5, weight: .semibold))
                  .lineLimit(1)
                Text(clubTodaySubtitle(club))
                  .font(.system(size: 9.5))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(2)
              }
              Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
          }
        }
      }
    }
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private var featuredDirectoryCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("EXPLORE CLUBS")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(accent)
          Text("A few picks from the Club Directory")
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Button {
          selectedSection = .directory
        } label: {
          HStack(spacing: 5) {
            Text("Full Directory")
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .bold))
          }
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
      }

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 10)],
        spacing: 10
      ) {
        ForEach(featuredDirectoryEntries.prefix(6)) { entry in
          directoryClubCard(entry, compact: true)
        }
      }
    }
    .padding(15)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  // MARK: Directory

  private var directoryWorkspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        directoryToolbar

        if !directoryStore.isConfigured {
          directorySetupState
        } else if directoryStore.isLoading && directoryStore.clubs.isEmpty {
          HStack(spacing: 9) {
            ProgressView().controlSize(.small)
            Text("Loading club directory…")
              .font(.system(size: 11))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          .frame(maxWidth: .infinity, minHeight: 260)
          .rooSurface(cornerRadius: DesignTokens.Radius.lg)
        } else if let error = directoryStore.lastError, directoryStore.clubs.isEmpty {
          VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
              .font(.system(size: 24, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.warning)
            Text("Couldn’t load the club directory")
              .font(.system(size: 13, weight: .semibold))
            Text(error)
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .multilineTextAlignment(.center)
            Button("Try Again") {
              Task { await directoryStore.refresh() }
            }
            .buttonStyle(.bordered)
          }
          .frame(maxWidth: .infinity, minHeight: 260)
          .rooSurface(cornerRadius: DesignTokens.Radius.lg)
        } else if filteredDirectoryEntries.isEmpty {
          overviewEmptyState(
            icon: "magnifyingglass",
            title: directoryStore.clubs.isEmpty ? "No clubs yet" : "No clubs match your search",
            subtitle: directoryStore.clubs.isEmpty
              ? "Clubs will appear here when the Directory has something to show."
              : "Try a different search or category."
          )
          .frame(maxWidth: .infinity, minHeight: 260)
          .rooSurface(cornerRadius: DesignTokens.Radius.lg)
        } else {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 285, maximum: 390), spacing: 12)],
            spacing: 12
          ) {
            ForEach(filteredDirectoryEntries) { entry in
              directoryClubCard(entry, compact: false)
            }
          }
        }
      }
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  private var directoryToolbar: some View {
    HStack(spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        TextField("Search clubs", text: $searchText)
          .textFieldStyle(.plain)
          .font(.system(size: 11))
      }
      .padding(.horizontal, 11)
      .frame(height: 34)
      .frame(maxWidth: 360)
      .background(
        DesignTokens.Colors.hover.opacity(0.30),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }

      Picker("Category", selection: $selectedCategory) {
        ForEach(directoryCategories, id: \.self) { category in
          Text(category).tag(category)
        }
      }
      .pickerStyle(.menu)
      .frame(width: 170)

      Spacer()

      if directoryStore.isConfigured {
        Text(
          "\(filteredDirectoryEntries.count) club\(filteredDirectoryEntries.count == 1 ? "" : "s")"
        )
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
    }
  }

  private var directorySetupState: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(accent.opacity(0.12))
          Image(systemName: "tablecells")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(accent)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 3) {
          Text("Club Directory")
            .font(.system(size: 14, weight: .semibold))
          Text(
            "Browse what’s available here. My Clubs and your meeting times still work if the Directory is empty or temporarily unavailable."
          )
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }

      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(DesignTokens.Colors.success)
        Text(
          "Club details refresh automatically. Your My Clubs list and meeting times stay personal to you."
        )
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
    .rooSurface(cornerRadius: DesignTokens.Radius.lg)
  }

  private func directoryClubCard(_ entry: ClubDirectoryEntry, compact: Bool) -> some View {
    let color = directoryColor(entry.colorHex)
    let isAdded = isInMyClubs(entry)

    return VStack(alignment: .leading, spacing: compact ? 10 : 12) {
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(color.opacity(0.13))
          Image(systemName: entry.iconName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 3) {
          Text(entry.name)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(2)

          if !entry.category.isEmpty {
            Text(entry.category.uppercased())
              .font(.system(size: 8.5, weight: .bold))
              .tracking(0.5)
              .foregroundStyle(color)
              .lineLimit(1)
              .minimumScaleFactor(0.82)
          }
        }

        Spacer(minLength: 6)

      }

      if !entry.description.isEmpty {
        Text(entry.description)
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 7) {
          if let url = entry.instagramURL {
            socialButton(title: "Instagram", icon: "camera", color: color) {
              openURL(url)
            }
          }

          if let url = entry.websiteURL {
            socialButton(title: "Website", icon: "safari", color: color) {
              openURL(url)
            }
          }

          Spacer(minLength: 6)

          directoryMembershipButton(entry, isAdded: isAdded, color: color)
        }

        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 7) {
            if let url = entry.instagramURL {
              socialButton(title: "Instagram", icon: "camera", color: color) {
                openURL(url)
              }
            }

            if let url = entry.websiteURL {
              socialButton(title: "Website", icon: "safari", color: color) {
                openURL(url)
              }
            }

            Spacer(minLength: 0)
          }

          HStack {
            Spacer(minLength: 0)
            directoryMembershipButton(entry, isAdded: isAdded, color: color)
          }
        }
      }
    }
    .padding(compact ? 12 : 14)
    .frame(maxWidth: .infinity, minHeight: compact ? 122 : 155, alignment: .topLeading)
    .rooSurface(cornerRadius: 14, elevated: false, border: true)
  }

  private func directoryMembershipButton(
    _ entry: ClubDirectoryEntry,
    isAdded: Bool,
    color: Color
  ) -> some View {
    Button {
      if isAdded {
        selectedSection = .myClubs
      } else {
        addDirectoryClub(entry)
      }
    } label: {
      HStack(spacing: 5) {
        Image(systemName: isAdded ? "checkmark" : "plus")
          .font(.system(size: 8.5, weight: .bold))

        Text(isAdded ? "In My Clubs" : "Add to My Clubs")
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundStyle(color)
      .padding(.horizontal, 9)
      .frame(height: 28)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      color.opacity(0.10),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
  }

  private func socialButton(
    title: String,
    icon: String,
    color: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 9, weight: .semibold))
        Text(title)
          .font(.system(size: 9.5, weight: .semibold))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(DesignTokens.Colors.secondaryText)
      .padding(.horizontal, 8)
      .frame(height: 27)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      DesignTokens.Colors.hover.opacity(0.30),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  // MARK: My Clubs

  private var myClubsWorkspace: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        manualMeetingNotice

        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("My Clubs")
              .font(.system(size: 18, weight: .semibold))
            Text(
              "This is your personal club list. Adding a club here only changes RooMate for you; it does not create or publish a school club."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Button {
            addBlankClub()
          } label: {
            Label("Add to My Clubs", systemImage: "plus")
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(accent)
              .padding(.horizontal, 11)
              .frame(height: 31)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }

        if store.clubs.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "person.3")
              .font(.system(size: 28, weight: .medium))
              .foregroundStyle(accent)

            Text("No clubs in My Clubs yet")
              .font(.system(size: 14, weight: .semibold))

            Text(
              "Browse the directory to add a club to My Clubs, or add one manually if it isn’t listed yet. This only changes your personal RooMate setup."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .multilineTextAlignment(.center)

            HStack(spacing: 8) {
              Button("Browse Directory") {
                selectedSection = .directory
              }
              .buttonStyle(.bordered)

              Button("Add Manually") {
                addBlankClub()
              }
              .buttonStyle(.borderedProminent)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 250)
          .rooSurface(cornerRadius: DesignTokens.Radius.lg)
        } else {
          VStack(spacing: 12) {
            ForEach(store.clubs.indices, id: \.self) { index in
              let clubID = store.clubs[index].id
              ClubEditorRow(club: $store.clubs[index]) {
                withAnimation(DesignTokens.Animation.snappy) {
                  store.clubs.removeAll { $0.id == clubID }
                }
              }
            }
          }
        }
      }
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  private var manualMeetingNotice: some View {
    HStack(alignment: .top, spacing: 11) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(DesignTokens.Colors.schedule.opacity(0.11))
        Image(systemName: "calendar.badge.clock")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.schedule)
      }
      .frame(width: 38, height: 38)

      VStack(alignment: .leading, spacing: 2) {
        Text("Your meeting times")
          .font(.system(size: 12, weight: .semibold))
        Text(
          "Add the times that apply to you: Monday or Wednesday club periods, a Level or school block, or an additional after-school meeting. Additional meetings can overlap something already on your schedule."
        )
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()
    }
    .padding(13)
    .rooSurface(cornerRadius: 13, elevated: false, border: true)
  }

  // MARK: Helpers

  private func sectionHeader(
    eyebrow: String,
    subtitle: String,
    actionTitle: String?,
    action: (() -> Void)?
  ) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 3) {
        Text(eyebrow)
          .font(.system(size: 9, weight: .bold))
          .tracking(0.7)
          .foregroundStyle(accent)
        Text(subtitle)
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      if let actionTitle, let action {
        Button(action: action) {
          HStack(spacing: 5) {
            Text(actionTitle)
            Image(systemName: "chevron.right")
              .font(.system(size: 8, weight: .bold))
          }
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(15)
  }

  private func overviewEmptyState(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.subtleText)
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)
      Text(subtitle)
        .font(.system(size: 10))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private func clubIcon(_ club: Club, size: CGFloat = 40) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        .fill(club.displayColor.opacity(0.13))
      Image(systemName: club.displayIconName)
        .font(.system(size: size * 0.36, weight: .semibold))
        .foregroundStyle(club.displayColor)
    }
    .frame(width: size, height: size)
  }

  private var configuredMeetingCount: Int {
    store.clubs.reduce(0) { result, club in
      result
        + (club.meetsMondayClub ? 1 : 0)
        + (club.meetsWednesdayClub ? 1 : 0)
        + club.blockMeetings.count
        + club.otherMeetings.count
    }
  }

  private var todayClubs: [Club] {
    let weekday = Calendar.current.component(.weekday, from: Date())
    return store.clubs.filter { club in
      (weekday == 2 && club.meetsMondayClub)
        || (weekday == 4 && club.meetsWednesdayClub)
        || club.blockMeetings.contains(where: { $0.weekday == weekday })
        || club.otherMeetings.contains(where: { $0.weekday == weekday })
    }
  }

  private var todayDateText: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: Date())
  }

  private func clubOverviewSubtitle(_ club: Club) -> String {
    var parts: [String] = []
    if !club.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      parts.append(club.room)
    }

    let count =
      (club.meetsMondayClub ? 1 : 0)
      + (club.meetsWednesdayClub ? 1 : 0)
      + club.blockMeetings.count
      + club.otherMeetings.count

    parts.append(count == 0 ? "No meeting times" : "\(count) meeting rule\(count == 1 ? "" : "s")")
    return parts.joined(separator: " • ")
  }

  private func clubTodaySubtitle(_ club: Club) -> String {
    let weekday = Calendar.current.component(.weekday, from: Date())
    var parts: [String] = []

    if weekday == 2 && club.meetsMondayClub {
      parts.append("Music Block + Clubs")
    }
    if weekday == 4 && club.meetsWednesdayClub {
      parts.append("Lunch & Clubs")
    }

    let exactCount = club.blockMeetings.filter { $0.weekday == weekday }.count
    if exactCount > 0 {
      parts.append("\(exactCount) schedule block\(exactCount == 1 ? "" : "s")")
    }

    let extraCount = club.otherMeetings.filter { $0.weekday == weekday }.count
    if extraCount > 0 {
      parts.append("\(extraCount) additional meeting\(extraCount == 1 ? "" : "s")")
    }

    if !club.room.isEmpty {
      parts.append(club.room)
    }

    return parts.isEmpty ? "Club meeting" : parts.joined(separator: " • ")
  }

  private var directoryCategories: [String] {
    let categories = Set(
      directoryStore.clubs
        .map(\.category)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
    return ["All Clubs"]
      + categories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
  }

  private var filteredDirectoryEntries: [ClubDirectoryEntry] {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    return directoryStore.clubs.filter { entry in
      let categoryMatches = selectedCategory == "All Clubs" || entry.category == selectedCategory
      guard categoryMatches else { return false }
      guard !query.isEmpty else { return true }

      return entry.name.localizedCaseInsensitiveContains(query)
        || entry.category.localizedCaseInsensitiveContains(query)
        || entry.description.localizedCaseInsensitiveContains(query)
    }
  }

  private var featuredDirectoryEntries: [ClubDirectoryEntry] {
    let featured = directoryStore.clubs.filter(\.featured)
    return featured.isEmpty ? Array(directoryStore.clubs.prefix(6)) : featured
  }

  private func isInMyClubs(_ entry: ClubDirectoryEntry) -> Bool {
    store.clubs.contains {
      $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(entry.name.trimmingCharacters(in: .whitespacesAndNewlines))
        == .orderedSame
    }
  }

  private func addDirectoryClub(_ entry: ClubDirectoryEntry) {
    guard !isInMyClubs(entry) else {
      selectedSection = .myClubs
      return
    }

    let newClub = Club(
      name: entry.name,
      color: CodableColor(directoryColor(entry.colorHex)),
      iconName: entry.iconName
    )

    withAnimation(DesignTokens.Animation.snappy) {
      store.clubs.append(newClub)
      selectedSection = .myClubs
    }
  }

  private func addBlankClub() {
    withAnimation(DesignTokens.Animation.snappy) {
      store.clubs.append(Club())
      selectedSection = .myClubs
    }
  }

  private func directoryColor(_ hex: String) -> Color {
    let trimmed =
      hex
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

    guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
      return accent
    }

    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
  }
}
