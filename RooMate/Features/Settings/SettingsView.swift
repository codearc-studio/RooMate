#if os(macOS)
  import SwiftUI
  import Foundation
  import UniformTypeIdentifiers
  import Combine
  #if canImport(AppKit)
    import AppKit
  #endif
  import UserNotifications
  import ServiceManagement

  // RooMate v6 Settings
  // A native-feeling, sectioned settings workspace that keeps the app's real
  // preferences and existing editors intact while matching the rest of RooMate v6.
  struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @ObservedObject var store: UserScheduleStore
    @ObservedObject var eventsStore: EventsStore
    @ObservedObject private var navigation = RooMateNavigationCoordinator.shared
    let checkForUpdatesAction: (() -> Void)?
    let onResetCompleted: () -> Void

    init(
      store: UserScheduleStore,
      eventsStore: EventsStore,
      checkForUpdatesAction: (() -> Void)? = nil,
      onResetCompleted: @escaping () -> Void = {}
    ) {
      self.store = store
      self.eventsStore = eventsStore
      self.checkForUpdatesAction = checkForUpdatesAction
      self.onResetCompleted = onResetCompleted
    }

    @State private var selectedSection: SettingsSection = .general
    @State private var scheduleMode: ScheduleMode = .classes
    @State private var selectedLevelIndex: Int = 0
    @State private var hoveredSection: SettingsSection?
    @State private var showResetConfirmation = false
    @State private var showDiagnostics = false
    @AppStorage("RooMateFloatingTimerEnabled")
    private var floatingTimerEnabled = false

    @AppStorage("RooMateFloatingTimerClickThrough")
    private var floatingTimerClickThrough = false

    @AppStorage("RooMateFloatingTimerCompact")
    private var floatingTimerCompact = false

    @AppStorage("RooMateFloatingTimerShowNextUp")
    private var floatingTimerShowNextUp = true

    @AppStorage("RooMateMenuBarEnabled")
    private var menuBarEnabled = true

    @AppStorage("RooMateMenuBarIconOnly")
    private var menuBarIconOnly = false

    @State private var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @State private var launchAtLoginError: String?

    @State private var diningFavoriteNames: [String] =
      UserDefaults.standard.stringArray(forKey: "RooMateDiningFavoriteRecipeNames") ?? []

    @AppStorage("RooMateSportsGameReminders") private var savedGameIDsRaw = ""
    @AppStorage("RooMateEventBookmarks") private var bookmarkedEventKeysRaw = ""
    @AppStorage("RooMateNotifySavedEvents") private var notifySavedEvents = false
    @AppStorage("RooMateNotifyCalendarEvents") private var notifyCalendarEvents = false

    enum SettingsSection: String, CaseIterable, Identifiable {
      case general = "General"
      case schedule = "Schedule"
      case dining = "Dining"
      case sports = "Sports"
      case events = "Events"
      case pacTrack = "PacTrack"
      case updates = "Updates"
      case about = "About"

      var id: String { rawValue }

      var icon: String {
        switch self {
        case .general: "gearshape"
        case .schedule: "calendar"
        case .dining: "fork.knife"
        case .sports: "sportscourt"
        case .events: "calendar.circle"
        case .pacTrack: "chart.bar.xaxis"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
      }

      var tint: Color {
        switch self {
        case .general: DesignTokens.Colors.primary
        case .schedule: DesignTokens.Colors.schedule
        case .dining: DesignTokens.Colors.dining
        case .sports: DesignTokens.Colors.athletics
        case .events: DesignTokens.Colors.events
        case .pacTrack: DesignTokens.Colors.pacTrack
        case .updates: DesignTokens.Colors.info
        case .about: DesignTokens.Colors.primary
        }
      }

      var subtitle: String {
        switch self {
        case .general: "Look, reminders, and utilities"
        case .schedule: "Classes and school blocks"
        case .dining: "Dining favorites"
        case .sports: "Game reminders"
        case .events: "Calendar and saved events"
        case .pacTrack: "RooPAC plan"
        case .updates: "RooMate updates"
        case .about: "About this app"
        }
      }
    }

    enum ScheduleMode: String, CaseIterable, Identifiable {
      case classes = "Classes"
      case specialBlocks = "Special Blocks"
      var id: String { rawValue }
      var icon: String {
        switch self {
        case .classes: "text.book.closed"
        case .specialBlocks: "square.grid.2x2"
        }
      }
    }

    private var editableLevels: [Level] {
      [.level1, .level2, .level3, .level4, .level5, .level6, .level7]
    }

    private var appName: String {
      let dict = Bundle.main.infoDictionary
      return dict?["CFBundleDisplayName"] as? String ?? dict?["CFBundleName"] as? String
        ?? "RooMate"
    }

    private var shortVersion: String {
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildVersion: String {
      Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var notificationsAreActive: Bool {
      let allowed: Bool
      switch store.notificationAuthStatus {
      case .authorized, .provisional:
        allowed = true
      case .denied, .notDetermined:
        allowed = false
      @unknown default:
        allowed = false
      }
      return store.notificationsEnabled && allowed
    }

    private var launchAtLoginBinding: Binding<Bool> {
      Binding(
        get: {
          launchAtLoginStatus == .enabled
            || launchAtLoginStatus == .requiresApproval
        },
        set: { enabled in
          setLaunchAtLogin(enabled)
        }
      )
    }

    private var launchAtLoginStatusText: String {
      switch launchAtLoginStatus {
      case .enabled:
        return "RooMate will open automatically when you sign in."
      case .requiresApproval:
        return "Allow RooMate in System Settings before it can open when you log in."
      case .notRegistered:
        return "Off by default. Turn this on if you want RooMate ready as soon as you sign in."
      case .notFound:
        return "This copy of RooMate can’t open automatically when you log in."
      @unknown default:
        return "RooMate couldn’t check this setting right now."
      }
    }

    private func refreshLaunchAtLoginStatus() {
      launchAtLoginStatus = SMAppService.mainApp.status
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
      launchAtLoginError = nil
      let service = SMAppService.mainApp

      do {
        if enabled {
          if service.status == .notRegistered || service.status == .notFound {
            try service.register()
          }
        } else if service.status != .notRegistered {
          try service.unregister()
        }
      } catch {
        #if DEBUG
          print("[LaunchAtLogin] \(error.localizedDescription)")
        #endif
        launchAtLoginError = "RooMate couldn’t change this setting. Try again, or use Login Items in System Settings."
      }

      refreshLaunchAtLoginStatus()
    }

    private var notificationsEnabledBinding: Binding<Bool> {
      Binding(
        get: { notificationsAreActive },
        set: { enabled in
          Task { await store.setNotificationsEnabled(enabled) }
        }
      )
    }

    private var notifySavedEventsBinding: Binding<Bool> {
      Binding(
        get: { notifySavedEvents },
        set: { enabled in
          notifySavedEvents = enabled
          NotificationCenter.default.post(
            name: .rooMateEventPreferencesDidChange,
            object: nil
          )
        }
      )
    }

    private var notifyCalendarEventsBinding: Binding<Bool> {
      Binding(
        get: { notifyCalendarEvents },
        set: { enabled in
          notifyCalendarEvents = enabled
          NotificationCenter.default.post(
            name: .rooMateEventPreferencesDidChange,
            object: nil
          )
        }
      )
    }

    private var assignedClassCount: Int {
      editableLevels.filter { level in
        let assignment = store.assignment(for: level)
        let title = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return assignment.isFree || (!title.isEmpty && title != level.displayName)
      }.count
    }

    private var savedGameIDs: Set<String> {
      Set(savedGameIDsRaw.split(separator: "\n").map(String.init))
    }

    private var savedEventCount: Int {
      Set(bookmarkedEventKeysRaw.split(separator: "\n").map(String.init)).count
    }

    private var selectedRooPACCount: Int {
      RooPACActivityType.officialCases.reduce(0) { count, activity in
        count + ((store.rooPacPlans[activity]?.isSelected ?? false) ? 1 : 0)
      }
    }

    private var minimumPlannedRooPACs: Int {
      RooPACActivityType.officialCases.reduce(0) { total, activity in
        guard let plan = store.rooPacPlans[activity], plan.isSelected else { return total }
        return total + (plan.overrideCredits ?? activity.minCredits)
      }
    }

    private func defaultReplacement(isFree: Bool = false) -> ClassAssignment.ReplacementClass {
      ClassAssignment.ReplacementClass(title: "", teacher: "", room: "", isFree: isFree)
    }

    private func specialFreeBinding(for block: SpecialBlock, defaultValue: Bool = false) -> Binding<
      Bool
    > {
      Binding(
        get: { store.specialFree[block] ?? defaultValue },
        set: { newValue in
          store.specialFree[block] = newValue
          if !newValue && store.specialBlockReplacements[block] == nil {
            store.specialBlockReplacements[block] = defaultReplacement(isFree: false)
          }
          if newValue && store.specialBlockReplacements[block] != nil {
            store.specialBlockReplacements[block] = nil
          }
        }
      )
    }

    private func specialReplacementBinding(for block: SpecialBlock, defaultIsFree: Bool = false)
      -> Binding<ClassAssignment.ReplacementClass>
    {
      Binding(
        get: { store.specialBlockReplacements[block] ?? defaultReplacement(isFree: defaultIsFree) },
        set: { store.specialBlockReplacements[block] = $0 }
      )
    }

    private func getMusicBlockUnavailableDays() -> Set<Int> {
      var unavailable: Set<Int> = []
      for club in store.clubs {
        if club.meetsMondayClub {
          unavailable.insert(Weekday.monday.calendarWeekdayIndex)
        }

        for meeting in club.blockMeetings {
          if meeting.block == .special(.musicClubs) || meeting.block == .level(.music) {
            unavailable.insert(meeting.weekday)
          }
        }
      }
      return unavailable
    }

    private func getLunchUnavailableDays() -> Set<Int> {
      var unavailable: Set<Int> = []
      for club in store.clubs {
        if club.meetsWednesdayClub {
          unavailable.insert(Weekday.wednesday.calendarWeekdayIndex)
        }

        for meeting in club.blockMeetings
        where meeting.block == .special(.lunchAndClubs) || meeting.block == .special(.lunch) {
          unavailable.insert(meeting.weekday)
        }
      }
      return unavailable
    }

    // MARK: Body

    private func handleNavigationRequest() {
      guard let request = navigation.request,
        case .settings(let rawSection) = request.destination,
        let section = SettingsSection(rawValue: rawSection)
      else { return }
      selectedSection = section
      navigation.consume(request)
    }

    var body: some View {
      VStack(spacing: 0) {
        settingsHeader
        settingsCategoryBar

        Divider()
          .overlay(DesignTokens.Colors.border)

        ScrollView(.vertical, showsIndicators: true) {
          sectionContent
            .id(selectedSection)
            .transition(.opacity)
            .animation(
              DesignTokens.Animation.snappy,
              value: selectedSection
            )
            .frame(maxWidth: 920, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .background {
          BackgroundView()
        }
      }
      .background {
        BackgroundView()
      }
      .navigationTitle("Settings")
      .modifier(SafeAreaTopPadding(4))
      .task { await store.refreshNotificationStatus() }
      .onAppear {
        refreshLaunchAtLoginStatus()
        diningFavoriteNames =
          UserDefaults.standard.stringArray(
            forKey: "RooMateDiningFavoriteRecipeNames"
          ) ?? []
        handleNavigationRequest()
      }
      .onChange(of: navigation.request) { _, _ in handleNavigationRequest() }
      .sheet(isPresented: $showDiagnostics) { RooMateDiagnosticsView() }
      .alert("Reset RooMate?", isPresented: $showResetConfirmation) {
        Button("Cancel", role: .cancel) {}

        Button("Reset", role: .destructive) {
          withAnimation(DesignTokens.Animation.snappy) {
            store.resetToDefaults()
            floatingTimerEnabled = false
            floatingTimerClickThrough = false
            floatingTimerCompact = false
            floatingTimerShowNextUp = true
            menuBarEnabled = true
            menuBarIconOnly = false
            notifySavedEvents = false
            notifyCalendarEvents = false
            eventsStore.setSources([.allEvents])
            eventsStore.selectedGrouping = .day
            NotificationCenter.default.post(
              name: .rooMateSportsPreferencesDidChange,
              object: nil
            )
            NotificationCenter.default.post(
              name: .rooMateEventPreferencesDidChange,
              object: nil
            )
            setLaunchAtLogin(false)
            selectedSection = .general
            scheduleMode = .classes
          }

          // Route straight back to onboarding through ContentView.
          // This is intentionally a direct callback instead of a
          // NotificationCenter bridge so the Settings view cannot lose
          // the event while SwiftUI is rebuilding after the reset.
          onResetCompleted()
        }
      } message: {
        Text(
          "This resets your classes, clubs, schedule preferences, app behavior, appearance, profile, notifications, sidebar layout, and PacTrack plan. Dining favorites, sports game reminders, and saved events are kept."
        )
      }
    }

    private var settingsHeader: some View {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Settings")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text("Make RooMate work the way you do.")
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        scheduleSetupQuickButton

        Button {
          showResetConfirmation = true
        } label: {
          HStack(spacing: 7) {
            Image(systemName: "arrow.counterclockwise")
              .font(.system(size: 11, weight: .semibold))
            Text("Reset RooMate")
              .font(.system(size: 12.5, weight: .semibold))
          }
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 12)
          .frame(height: 36)
          .contentShape(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .background(
            DesignTokens.Colors.hover.opacity(0.44),
            in: RoundedRectangle(
              cornerRadius: 9,
              style: .continuous
            )
          )
          .overlay {
            RoundedRectangle(
              cornerRadius: 9,
              style: .continuous
            )
            .strokeBorder(
              DesignTokens.Colors.border,
              lineWidth: 1
            )
          }
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 26)
      .padding(.top, 18)
      .padding(.bottom, 13)
      .background(
        DesignTokens.Colors.background.opacity(
          colorScheme == .light ? 0.74 : 1
        )
      )
    }

    private var scheduleSetupQuickButton: some View {
      Button {
        withAnimation(DesignTokens.Animation.navigation) {
          selectedSection = .schedule
          scheduleMode = .classes
        }
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "calendar.badge.checkmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)

          Text("Schedule Setup")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(
              DesignTokens.Colors.primaryText
            )

          Text("\(assignedClassCount)/7")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(
              assignedClassCount == 7
                ? DesignTokens.Colors.athletics
                : DesignTokens.Colors.schedule
            )
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
              DesignTokens.Colors.schedule.opacity(0.09),
              in: Capsule()
            )

          Image(systemName: "chevron.right")
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(
              DesignTokens.Colors.subtleText
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(
          RoundedRectangle(
            cornerRadius: 9,
            style: .continuous
          )
        )
        .background(
          DesignTokens.Colors.hover.opacity(0.44),
          in: RoundedRectangle(
            cornerRadius: 9,
            style: .continuous
          )
        )
        .overlay {
          RoundedRectangle(
            cornerRadius: 9,
            style: .continuous
          )
          .strokeBorder(
            DesignTokens.Colors.schedule.opacity(0.26),
            lineWidth: 1
          )
        }
      }
      .buttonStyle(.plain)
      .help("Open Schedule Setup")
    }

    private var settingsCategoryBar: some View {
      HStack(spacing: 0) {
        ForEach(SettingsSection.allCases) { section in
          settingsCategoryButton(section)
        }
      }
      .frame(maxWidth: 920)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 22)
      .padding(.bottom, 2)
      .background(
        DesignTokens.Colors.background.opacity(
          colorScheme == .light ? 0.74 : 1
        )
      )
    }

    private func settingsCategoryButton(
      _ section: SettingsSection
    ) -> some View {
      let isSelected = selectedSection == section
      let isHovered = hoveredSection == section

      return Button {
        withAnimation(DesignTokens.Animation.snappy) {
          selectedSection = section
        }
      } label: {
        VStack(spacing: 6) {
          ZStack(alignment: .topTrailing) {
            Image(systemName: section.icon)
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(
                isSelected
                  ? section.tint
                  : DesignTokens.Colors.secondaryText
              )
              .frame(width: 30, height: 24)

            if section == .schedule && assignedClassCount < 7 {
              Circle()
                .fill(DesignTokens.Colors.schedule)
                .frame(width: 5.5, height: 5.5)
                .offset(x: 1, y: -1)
            }
          }

          Text(section.rawValue)
            .font(
              .system(
                size: 10.5,
                weight: isSelected ? .semibold : .medium
              )
            )
            .foregroundStyle(
              isSelected
                ? DesignTokens.Colors.primaryText
                : DesignTokens.Colors.secondaryText
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)

          Capsule()
            .fill(
              isSelected
                ? section.tint
                : Color.clear
            )
            .frame(height: 2.5)
            .padding(.horizontal, 11)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 61)
        .contentShape(Rectangle())
        .background(
          isHovered && !isSelected
            ? DesignTokens.Colors.hover.opacity(0.28)
            : Color.clear
        )
      }
      .buttonStyle(.plain)
      .onHover { hovering in
        hoveredSection = hovering ? section : nil
      }
      .help(section.subtitle)
    }

    @ViewBuilder
    private var sectionContent: some View {
      switch selectedSection {
      case .general:
        generalContent
      case .schedule:
        scheduleSettingsContent
      case .dining:
        diningContent
      case .sports:
        sportsContent
      case .events:
        eventsContent
      case .pacTrack:
        pacTrackContent
      case .updates:
        updatesContent
      case .about:
        aboutContent
      }
    }

    private func sectionHeading(
      _ title: String,
      subtitle: String,
      icon: String,
      tint: Color
    ) -> some View {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(subtitle)
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 34, height: 34)
          .background(
            tint.opacity(0.10),
            in: RoundedRectangle(
              cornerRadius: 10,
              style: .continuous
            )
          )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, 2)
    }

    private func settingsCard<Content: View>(
      title: String,
      subtitle: String? = nil,
      icon: String? = nil,
      tint: Color = DesignTokens.Colors.primary,
      @ViewBuilder content: () -> Content
    ) -> some View {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top, spacing: 10) {
          if let icon {
            ZStack {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.13))
              Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)
          }

          VStack(alignment: .leading, spacing: 3) {
            Text(title)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
            if let subtitle {
              Text(subtitle)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
          }
          Spacer(minLength: 0)
        }

        content()
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        DesignTokens.Colors.surface,
        in: RoundedRectangle(
          cornerRadius: 15,
          style: .continuous
        )
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: 15,
          style: .continuous
        )
        .strokeBorder(
          DesignTokens.Colors.border,
          lineWidth: 1
        )
      }
    }

    // MARK: General

    private var generalContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "General",
          subtitle: "Choose how RooMate looks, reminds you, and fits your day.",
          icon: "gearshape",
          tint: DesignTokens.Colors.primary
        )

        settingsCard(
          title: "Look & Feel",
          subtitle: "Choose the version of RooMate that feels best on your Mac.",
          icon: "paintbrush",
          tint: DesignTokens.Colors.primary
        ) {
          VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
              Text("APPEARANCE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(DesignTokens.Colors.subtleText)

              HStack(spacing: 10) {
                ForEach(AppearancePreference.allCases) { option in
                  appearanceOption(option)
                }
              }
            }

          }
        }

        settingsCard(
          title: "App Behavior",
          subtitle: "Choose when RooMate starts and what happens when you close its main window.",
          icon: "power",
          tint: DesignTokens.Colors.primary
        ) {
          VStack(alignment: .leading, spacing: 0) {
            compactToggle(
              title: "Open RooMate at login",
              subtitle: launchAtLoginStatusText,
              isOn: launchAtLoginBinding
            )

            if launchAtLoginStatus == .requiresApproval {
              Divider().overlay(DesignTokens.Colors.border)

              Button {
                SMAppService.openSystemSettingsLoginItems()
              } label: {
                HStack(spacing: 10) {
                  Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .frame(width: 20)

                  VStack(alignment: .leading, spacing: 2) {
                    Text("Allow in System Settings")
                      .font(.system(size: 12.5, weight: .semibold))
                      .foregroundStyle(DesignTokens.Colors.primaryText)
                    Text("Allow RooMate in System Settings before it can open when you log in.")
                      .font(.system(size: 10.5))
                      .foregroundStyle(DesignTokens.Colors.secondaryText)
                  }

                  Spacer()

                  Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.subtleText)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .padding(.vertical, 8)
            }

            if let launchAtLoginError {
              Divider().overlay(DesignTokens.Colors.border)

              HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.warning)
                Text(launchAtLoginError)
                  .font(.system(size: 10.5, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 11)
              .padding(.vertical, 10)
            }

            Divider().overlay(DesignTokens.Colors.border)

            HStack(alignment: .top, spacing: 11) {
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(DesignTokens.Colors.success.opacity(0.11))
                Image(systemName: "menubar.rectangle")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.success)
              }
              .frame(width: 34, height: 34)

              VStack(alignment: .leading, spacing: 3) {
                Text("Keep RooMate running when its window is closed")
                  .font(.system(size: 12.5, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.primaryText)
                Text(
                  "Closing RooMate's main window does not quit the app, so the menu bar companion and floating timer can keep working. Use ⌘Q or Quit RooMate when you want to stop it completely."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
              }

              Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 12)
          }
        }

        settingsCard(
          title: "Notifications",
          subtitle: notificationStatusText,
          icon: "bell.badge",
          tint: DesignTokens.Colors.warning
        ) {
          VStack(spacing: 0) {
            compactToggle(
              title: "Enable notifications",
              subtitle: "Master switch for every RooMate reminder below.",
              isOn: notificationsEnabledBinding
            )

            Divider().overlay(DesignTokens.Colors.border)

            TimelineView(.periodic(from: .now, by: 30)) { context in
              notificationPauseRow(reference: context.date)
            }

            settingsSubsectionLabel("SCHOOL DAY")

            compactToggle(
              title: "Class starting soon",
              subtitle: "5 minutes before a class begins.",
              isOn: $store.notifyClassStartingSoon,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Class ending soon",
              subtitle: "5 minutes before a class ends.",
              isOn: $store.notifyClassEndingSoon,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Club meetings",
              subtitle: "5 minutes before My Clubs meetings, including after-school meetings.",
              isOn: $store.notifyClubMeetings,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Special schedules & closures",
              subtitle: "A 7:15 AM heads-up on published special-schedule or no-school days.",
              isOn: $store.notifySpecialScheduleMorning,
              disabled: !notificationsAreActive
            )

            settingsSubsectionLabel("DINING, SPORTS & EVENTS")

            compactToggle(
              title: "Lunch menu reminder",
              subtitle: "15 minutes before Lunch, with a shortcut prompt to check Dining.",
              isOn: $store.notifyDiningLunch,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Selected event calendars",
              subtitle:
                "30 minutes before events in the calendars you selected; all-day events get an 8:00 AM reminder.",
              isOn: notifyCalendarEventsBinding,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Saved events",
              subtitle:
                "30 minutes before timed bookmarks; all-day saved events get an 8:00 AM reminder.",
              isOn: notifySavedEventsBinding,
              disabled: !notificationsAreActive
            )

            if store.notificationAuthStatus == .denied {
              Divider().overlay(DesignTokens.Colors.border)

              Button(action: openNotificationSystemSettings) {
                HStack(spacing: 10) {
                  Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .frame(width: 20)

                  VStack(alignment: .leading, spacing: 2) {
                    Text("Open System Settings")
                      .font(.system(size: 12.5, weight: .semibold))
                      .foregroundStyle(DesignTokens.Colors.primaryText)

                    Text("Allow RooMate notifications, then come back here.")
                      .font(.system(size: 10.5))
                      .foregroundStyle(DesignTokens.Colors.secondaryText)
                  }

                  Spacer()

                  Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.subtleText)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
                .background(
                  DesignTokens.Colors.hover.opacity(0.34),
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
                }
              }
              .buttonStyle(.plain)
              .padding(.vertical, 10)
            }
          }
        }

        settingsCard(
          title: "Menu Bar Companion",
          subtitle: "Choose whether RooMate lives in the macOS menu bar and how it appears there.",
          icon: "menubar.rectangle",
          tint: DesignTokens.Colors.schedule
        ) {
          VStack(alignment: .leading, spacing: 0) {
            compactToggle(
              title: "Show menu bar companion",
              subtitle: "Keep RooMate's current class and quick popover in the menu bar.",
              isOn: $menuBarEnabled
            )

            Divider()
              .overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Icon-only menu bar",
              subtitle: "Show only the Roo icon instead of class details when the companion is on.",
              isOn: $menuBarIconOnly
            )
          }
        }

        settingsCard(
          title: "Floating Timer",
          subtitle: "Keep your current block visible without making the timer feel busy.",
          icon: "timer",
          tint: DesignTokens.Colors.schedule
        ) {
          VStack(alignment: .leading, spacing: 0) {
            compactToggle(
              title: "Show floating timer",
              subtitle: "Keep the current block above your other windows.",
              isOn: $floatingTimerEnabled
            )

            Divider()
              .overlay(DesignTokens.Colors.border)

            VStack(alignment: .leading, spacing: 10) {
              Text("STYLE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(
                  DesignTokens.Colors.subtleText
                )

              HStack(spacing: 10) {
                floatingTimerModeOption(
                  compact: false,
                  title: "Bold",
                  subtitle: "Current class, progress, and next up."
                )

                floatingTimerModeOption(
                  compact: true,
                  title: "Compact",
                  subtitle: "Just the essentials."
                )
              }
            }
            .padding(.vertical, 13)

            Divider()
              .overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Show next up",
              subtitle: "Add the next class row in Bold mode.",
              isOn: $floatingTimerShowNextUp,
              disabled: floatingTimerCompact
            )

            Divider()
              .overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Click-through",
              subtitle:
                "Make the timer passive and slightly transparent. Right-click or double-click it to interact again.",
              isOn: $floatingTimerClickThrough
            )

            HStack(spacing: 7) {
              Image(systemName: "cursorarrow.rays")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                  DesignTokens.Colors.schedule
                )

              Text(
                "Tip: when passive, right-click or double-click the timer to turn Click-through off."
              )
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(
                DesignTokens.Colors.secondaryText
              )
            }
            .padding(.top, 10)
          }
        }

      }
    }

    private func feedbackButton(
      title: String,
      subtitle: String,
      symbol: String,
      url: String
    ) -> some View {
      Button {
        if let destination = URL(string: url) { openURL(destination) }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.info)
            .frame(width: 32, height: 32)
            .background(DesignTokens.Colors.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 12.5, weight: .semibold))
            Text(subtitle)
              .font(.system(size: 9.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(2)
          }
          Spacer(minLength: 0)
          Image(systemName: "arrow.up.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: 11))
      .overlay { RoundedRectangle(cornerRadius: 11).stroke(DesignTokens.Colors.border) }
    }

    private func floatingTimerModeOption(
      compact: Bool,
      title: String,
      subtitle: String
    ) -> some View {
      let selected = floatingTimerCompact == compact
      let accent = DesignTokens.Colors.schedule

      return Button {
        withAnimation(DesignTokens.Animation.snappy) {
          floatingTimerCompact = compact

          if compact {
            floatingTimerShowNextUp = false
          }
        }
      } label: {
        VStack(alignment: .leading, spacing: 9) {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text("ROOMATE")
                .font(.system(size: 6.5, weight: .black))
                .tracking(0.75)
                .foregroundStyle(
                  DesignTokens.Colors.secondaryText
                )

              Spacer()

              RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(
                  width: compact ? 22 : 34,
                  height: 4
                )
            }

            HStack(alignment: .firstTextBaseline) {
              Text(compact ? "Level 4" : "RIGHT NOW")
                .font(
                  .system(
                    size: compact ? 10.5 : 7,
                    weight: .bold
                  )
                )
                .foregroundStyle(
                  compact
                    ? DesignTokens.Colors.primaryText
                    : accent
                )

              Spacer()

              Text(compact ? "17m" : "17m 42s")
                .font(
                  .system(
                    size: compact ? 12 : 15,
                    weight: .black,
                    design: .rounded
                  )
                )
                .foregroundStyle(accent)
            }

            if !compact {
              Text("Level 4")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )

              Capsule()
                .fill(accent)
                .frame(height: 3)
            }
          }
          .padding(9)
          .frame(maxWidth: .infinity)
          .frame(height: 76)
          .background(
            accent.opacity(0.055),
            in: RoundedRectangle(
              cornerRadius: 12,
              style: .continuous
            )
          )
          .overlay {
            RoundedRectangle(
              cornerRadius: 12,
              style: .continuous
            )
            .strokeBorder(
              accent.opacity(0.22),
              lineWidth: 1
            )
          }

          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(title)
                .font(
                  .system(
                    size: 11.5,
                    weight: .semibold
                  )
                )
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )

              Spacer()

              if selected {
                Image(systemName: "checkmark.circle.fill")
                  .font(
                    .system(
                      size: 11,
                      weight: .semibold
                    )
                  )
                  .foregroundStyle(accent)
              }
            }

            Text(subtitle)
              .font(.system(size: 9.5))
              .foregroundStyle(
                DesignTokens.Colors.secondaryText
              )
              .lineLimit(2)
          }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          selected
            ? accent.opacity(0.075)
            : DesignTokens.Colors.hover.opacity(0.18),
          in: RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
          )
        )
        .overlay {
          RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
          )
          .strokeBorder(
            selected
              ? accent.opacity(0.34)
              : DesignTokens.Colors.border,
            lineWidth: 1
          )
        }
      }
      .buttonStyle(.plain)
    }

    private func appearanceOption(
      _ option: AppearancePreference
    ) -> some View {
      let selected = store.appearance == option

      return Button {
        withAnimation(DesignTokens.Animation.snappy) {
          store.appearance = option
        }
      } label: {
        VStack(alignment: .leading, spacing: 9) {
          appearancePreview(option)
            .frame(height: 54)

          HStack(spacing: 6) {
            Image(systemName: option.systemImage)
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundStyle(
                selected
                  ? DesignTokens.Colors.primary
                  : DesignTokens.Colors.secondaryText
              )

            Text(option.title)
              .font(.system(size: 11.5, weight: .semibold))
              .foregroundStyle(
                DesignTokens.Colors.primaryText
              )

            Spacer()

            if selected {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(
                  DesignTokens.Colors.primary
                )
            }
          }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          selected
            ? DesignTokens.Colors.primary.opacity(
              colorScheme == .light ? 0.075 : 0.11
            )
            : DesignTokens.Colors.hover.opacity(0.20),
          in: RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
          )
        )
        .overlay {
          RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
          )
          .strokeBorder(
            selected
              ? DesignTokens.Colors.primary.opacity(0.38)
              : DesignTokens.Colors.border,
            lineWidth: 1
          )
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }

    @ViewBuilder
    private func appearancePreview(
      _ option: AppearancePreference
    ) -> some View {
      let corner: CGFloat = 8

      switch option {
      case .system:
        HStack(spacing: 0) {
          ZStack {
            Color(hex: 0xF3F0EB)
            previewWindowContents(
              dark: false,
              accent: DesignTokens.Colors.schedule
            )
          }

          ZStack {
            Color(hex: 0x111316)
            previewWindowContents(
              dark: true,
              accent: DesignTokens.Colors.schedule
            )
          }
        }
        .clipShape(
          RoundedRectangle(
            cornerRadius: corner,
            style: .continuous
          )
        )

      case .light:
        ZStack {
          Color(hex: 0xF3F0EB)
          previewWindowContents(
            dark: false,
            accent: DesignTokens.Colors.schedule
          )
        }
        .clipShape(
          RoundedRectangle(
            cornerRadius: corner,
            style: .continuous
          )
        )

      case .dark:
        ZStack {
          Color(hex: 0x111316)
          previewWindowContents(
            dark: true,
            accent: DesignTokens.Colors.schedule
          )
        }
        .clipShape(
          RoundedRectangle(
            cornerRadius: corner,
            style: .continuous
          )
        )
      }
    }

    private func previewWindowContents(
      dark: Bool,
      accent: Color
    ) -> some View {
      VStack(spacing: 6) {
        HStack(spacing: 4) {
          Circle()
            .fill(accent.opacity(0.90))
            .frame(width: 5, height: 5)

          RoundedRectangle(cornerRadius: 2)
            .fill(
              dark
                ? Color.white.opacity(0.35)
                : Color.black.opacity(0.22)
            )
            .frame(width: 28, height: 4)

          Spacer()
        }

        HStack(spacing: 5) {
          RoundedRectangle(cornerRadius: 3)
            .fill(
              dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.06)
            )
            .frame(width: 17)

          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
              .fill(accent.opacity(0.24))

            RoundedRectangle(cornerRadius: 3)
              .fill(
                dark
                  ? Color.white.opacity(0.09)
                  : Color.black.opacity(0.055)
              )
          }
        }
      }
      .padding(7)
    }

    private func cardStyleOption(
      _ style: CardColorStyle
    ) -> some View {
      let selected = store.cardColorStyle == style
      let sampleColor = DesignTokens.Colors.schedule

      return Button {
        withAnimation(DesignTokens.Animation.snappy) {
          store.cardColorStyle = style
        }
      } label: {
        VStack(alignment: .leading, spacing: 9) {
          cardStylePreview(
            style,
            color: sampleColor
          )
          .frame(height: 54)

          HStack(spacing: 6) {
            Image(systemName: style.systemImage)
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundStyle(
                selected
                  ? sampleColor
                  : DesignTokens.Colors.secondaryText
              )

            Text(style.title)
              .font(.system(size: 11.5, weight: .semibold))
              .foregroundStyle(
                DesignTokens.Colors.primaryText
              )

            Spacer()

            if selected {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(sampleColor)
            }
          }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          selected
            ? sampleColor.opacity(
              colorScheme == .light ? 0.075 : 0.11
            )
            : DesignTokens.Colors.hover.opacity(0.20),
          in: RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
          )
        )
        .overlay {
          RoundedRectangle(
            cornerRadius: 12,
            style: .continuous
          )
          .strokeBorder(
            selected
              ? sampleColor.opacity(0.38)
              : DesignTokens.Colors.border,
            lineWidth: 1
          )
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }

    private func cardStylePreview(
      _ style: CardColorStyle,
      color: Color
    ) -> some View {
      let fill: Color = {
        switch style {
        case .none:
          return DesignTokens.Colors.surfaceElevated
        case .subtle:
          return color.opacity(
            colorScheme == .light ? 0.065 : 0.10
          )
        case .colors:
          return color.opacity(
            colorScheme == .light ? 0.18 : 0.24
          )
        }
      }()

      return HStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 2)
          .fill(
            style == .none
              ? DesignTokens.Colors.border
              : color
          )
          .frame(width: 4)

        VStack(alignment: .leading, spacing: 5) {
          RoundedRectangle(cornerRadius: 2)
            .fill(DesignTokens.Colors.primaryText.opacity(0.72))
            .frame(width: 54, height: 5)

          RoundedRectangle(cornerRadius: 2)
            .fill(DesignTokens.Colors.secondaryText.opacity(0.42))
            .frame(width: 38, height: 4)

          Spacer(minLength: 0)

          HStack(spacing: 4) {
            Circle()
              .fill(color)
              .frame(width: 5, height: 5)

            RoundedRectangle(cornerRadius: 2)
              .fill(DesignTokens.Colors.secondaryText.opacity(0.30))
              .frame(width: 29, height: 3)
          }
        }

        Spacer()
      }
      .padding(8)
      .background(
        fill,
        in: RoundedRectangle(
          cornerRadius: 8,
          style: .continuous
        )
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: 8,
          style: .continuous
        )
        .strokeBorder(
          style == .colors
            ? color.opacity(0.32)
            : DesignTokens.Colors.border,
          lineWidth: 1
        )
      }
    }

    private func settingsSubsectionLabel(_ title: String) -> some View {
      HStack {
        Text(title)
          .font(.system(size: 9, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(DesignTokens.Colors.subtleText)
        Spacer()
      }
      .padding(.horizontal, 11)
      .padding(.top, 13)
      .padding(.bottom, 5)
      .background(DesignTokens.Colors.hover.opacity(0.12))
    }

    private func compactToggle(
      title: String,
      subtitle: String,
      isOn: Binding<Bool>,
      disabled: Bool = false
    ) -> some View {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(
              disabled ? DesignTokens.Colors.subtleText : DesignTokens.Colors.primaryText)
          Text(subtitle)
            .font(.system(size: 11.5))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        Spacer()
        Toggle("", isOn: isOn)
          .labelsHidden()
          .toggleStyle(.switch)
          .tint(DesignTokens.Colors.pacTrack)
          .controlSize(.small)
          .disabled(disabled)
      }
      .padding(.vertical, 10)
      .opacity(disabled ? 0.55 : 1)
    }

    private func notificationPauseRow(reference: Date) -> some View {
      let isPaused = store.isNotificationPauseActive(reference: reference)

      return HStack(spacing: 10) {
        Image(systemName: isPaused ? "pause.circle.fill" : "moon.zzz.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(
            isPaused
              ? DesignTokens.Colors.warning
              : DesignTokens.Colors.secondaryText
          )
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 2) {
          Text(isPaused ? "Notifications paused" : "Pause notifications")
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          Text(
            isPaused
              ? notificationPauseSubtitle(reference: reference)
              : "Silence reminders temporarily without turning them off."
          )
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        if isPaused {
          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              store.resumeNotifications()
            }
          } label: {
            Text("Resume")
              .font(.system(size: 11, weight: .semibold))
              .padding(.horizontal, 10)
              .frame(height: 30)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(DesignTokens.Colors.schedule)
          .background(
            DesignTokens.Colors.schedule.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(
                DesignTokens.Colors.schedule.opacity(0.22),
                lineWidth: 1
              )
          }
        } else {
          Menu {
            Button {
              store.pauseNotifications(for: 60 * 60)
            } label: {
              Label("For 1 Hour", systemImage: "clock")
            }

            Button {
              store.pauseNotificationsForToday()
            } label: {
              Label("For Today", systemImage: "sunset")
            }
          } label: {
            HStack(spacing: 6) {
              Text("Pause")
                .font(.system(size: 11, weight: .semibold))

              Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
            .background(
              DesignTokens.Colors.hover.opacity(0.34),
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
            }
          }
          .menuStyle(.borderlessButton)
          .disabled(!notificationsAreActive)
          .opacity(notificationsAreActive ? 1 : 0.45)
        }
      }
      .padding(.horizontal, 11)
      .frame(minHeight: 52)
      .contentShape(Rectangle())
    }

    private func notificationPauseSubtitle(reference: Date) -> String {
      guard let pauseUntil = store.notificationPauseUntil,
        pauseUntil > reference
      else {
        return "Schedule reminders are active."
      }

      var calendar = Calendar.current
      calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current

      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = calendar.timeZone
      formatter.timeStyle = .short
      formatter.dateStyle = .none

      if calendar.isDate(pauseUntil, inSameDayAs: reference) {
        return "Resumes automatically at \(formatter.string(from: pauseUntil))."
      }

      if calendar.isDateInTomorrow(pauseUntil) {
        return "Resumes automatically tomorrow."
      }

      formatter.dateStyle = .medium
      formatter.timeStyle = .short
      return "Resumes automatically \(formatter.string(from: pauseUntil))."
    }

    private func openNotificationSystemSettings() {
      #if canImport(AppKit)
        let workspace = NSWorkspace.shared
        let notificationPaneURLs = [
          "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
          "x-apple.systempreferences:com.apple.preference.notifications",
        ]

        for value in notificationPaneURLs {
          if let url = URL(string: value), workspace.open(url) {
            return
          }
        }

        if let systemSettingsURL = workspace.urlForApplication(
          withBundleIdentifier: "com.apple.systempreferences"
        ) {
          workspace.open(systemSettingsURL)
        }
      #endif
    }

    private var notificationStatusText: String {
      switch store.notificationAuthStatus {
      case .authorized, .provisional:
        "Schedule reminders are ready."
      case .denied:
        "Notifications are off in System Settings."
      case .notDetermined:
        "Turn reminders on when you’re ready."
      @unknown default:
        "Notification status isn’t available right now."
      }
    }

    // MARK: Schedule

    private var scheduleSettingsContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "Schedule",
          subtitle: "Build the schedule RooMate uses everywhere in the app.",
          icon: "calendar",
          tint: DesignTokens.Colors.schedule
        )

        scheduleSetupHero

        specialSchedulesCard

        scheduleModeSwitcher

        Group {
          switch scheduleMode {
          case .classes:
            classesTabContent
          case .specialBlocks:
            scheduleTabContent
          }
        }
      }
    }

    private var scheduleSetupHero: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .center, spacing: 15) {
          ZStack {
            Circle()
              .fill(
                DesignTokens.Colors.schedule.opacity(0.11)
              )

            Circle()
              .stroke(
                DesignTokens.Colors.schedule.opacity(0.14),
                lineWidth: 7
              )

            Circle()
              .trim(
                from: 0,
                to: CGFloat(assignedClassCount) / 7.0
              )
              .stroke(
                DesignTokens.Colors.schedule,
                style: StrokeStyle(
                  lineWidth: 7,
                  lineCap: .round
                )
              )
              .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
              Text("\(assignedClassCount)")
                .font(
                  .system(
                    size: 20,
                    weight: .bold,
                    design: .rounded
                  )
                )
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )

              Text("/ 7")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(
                  DesignTokens.Colors.secondaryText
                )
            }
          }
          .frame(width: 72, height: 72)

          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
              Text("Your Schedule")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )

              Text("MAIN SETUP")
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.65)
                .foregroundStyle(
                  DesignTokens.Colors.schedule
                )
                .padding(.horizontal, 7)
                .frame(height: 19)
                .background(
                  DesignTokens.Colors.schedule.opacity(0.10),
                  in: Capsule()
                )
            }

            Text(
              assignedClassCount == 7
                ? "All seven Levels are set up. This schedule powers Today, notifications, the menu bar, and your floating timer."
                : "Set each Level once. RooMate uses this everywhere: Today, Schedule, reminders, the menu bar, and the floating timer."
            )
            .font(.system(size: 11.5))
            .foregroundStyle(
              DesignTokens.Colors.secondaryText
            )
            .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 0)

          if assignedClassCount < 7 {
            Text("\(7 - assignedClassCount) LEFT")
              .font(.system(size: 8, weight: .bold))
              .tracking(0.7)
              .foregroundStyle(
                DesignTokens.Colors.schedule
              )
              .padding(.horizontal, 8)
              .frame(height: 24)
              .background(
                DesignTokens.Colors.schedule.opacity(0.10),
                in: Capsule()
              )
          } else {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(
                DesignTokens.Colors.athletics
              )
          }
        }

        Divider()
          .overlay(
            DesignTokens.Colors.schedule.opacity(0.15)
          )

        HStack(spacing: 8) {
          schedulePoweredByItem(
            icon: "sun.max.fill",
            title: "Today"
          )

          schedulePoweredByItem(
            icon: "bell.fill",
            title: "Reminders"
          )

          schedulePoweredByItem(
            icon: "menubar.rectangle",
            title: "Menu Bar"
          )

          schedulePoweredByItem(
            icon: "timer",
            title: "Timer"
          )

          Spacer()
        }
      }
      .padding(18)
      .background(
        ZStack {
          RoundedRectangle(
            cornerRadius: 17,
            style: .continuous
          )
          .fill(DesignTokens.Colors.surface)

          RoundedRectangle(
            cornerRadius: 17,
            style: .continuous
          )
          .fill(
            DesignTokens.Colors.schedule.opacity(
              colorScheme == .light ? 0.035 : 0.055
            )
          )
        }
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: 17,
          style: .continuous
        )
        .strokeBorder(
          DesignTokens.Colors.schedule.opacity(0.28),
          lineWidth: 1
        )
      }
    }

    private func schedulePoweredByItem(
      icon: String,
      title: String
    ) -> some View {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 8.5, weight: .semibold))

        Text(title)
          .font(.system(size: 9.5, weight: .semibold))
      }
      .foregroundStyle(DesignTokens.Colors.schedule)
      .padding(.horizontal, 8)
      .frame(height: 25)
      .background(
        DesignTokens.Colors.schedule.opacity(0.075),
        in: Capsule()
      )
    }

    private var specialSchedulesCard: some View {
      settingsCard(
        title: "School Special Schedules",
        subtitle: "RooMate checks for school-wide schedule changes automatically.",
        icon: "calendar.badge.clock",
        tint: DesignTokens.Colors.schedule
      ) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Colors.schedule.opacity(0.10))
              Image(systemName: "cloud.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.schedule)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
              Text("Updates happen automatically")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

              Text(officialScheduleStatusText)
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Spacer()

            Button {
              Task {
                await store.refreshOfficialSpecialSchedules(force: true)
              }
            } label: {
              HStack(spacing: 6) {
                if store.remoteSpecialSchedulesRefreshing {
                  ProgressView()
                    .controlSize(.small)
                } else {
                  Image(systemName: "arrow.clockwise")
                }
                Text(store.remoteSpecialSchedulesRefreshing ? "Refreshing" : "Refresh")
              }
              .font(.system(size: 11.5, weight: .semibold))
              .padding(.horizontal, 11)
              .frame(height: 32)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.remoteSpecialSchedulesRefreshing)
            .background(
              DesignTokens.Colors.selection,
              in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
          }

          if store.remoteSpecialScheduleError != nil {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.warning)
              Text("RooMate couldn’t update special schedules. Your saved schedule is still available.")
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(
              DesignTokens.Colors.warning.opacity(0.08),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
          }

          Divider().overlay(DesignTokens.Colors.border)

          HStack(spacing: 8) {
            Label("Automatic", systemImage: "checkmark.circle.fill")
            Text("•")
            Text(
              "\(store.remoteSpecialScheduleFeed.days.count) special day\(store.remoteSpecialScheduleFeed.days.count == 1 ? "" : "s") available"
            )
            Spacer()
          }
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

          Text(
            "RooMate updates special schedules automatically. They can’t be changed here."
          )
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }

    private var officialScheduleStatusText: String {
      guard let date = store.officialSpecialSchedulesLastUpdated else {
        return "Not updated yet."
      }

      let formatter = RelativeDateTimeFormatter()
      formatter.unitsStyle = .full
      return "Last updated \(formatter.localizedString(for: date, relativeTo: Date()))."
    }

    private var scheduleModeSwitcher: some View {
      HStack(spacing: 8) {
        ForEach(ScheduleMode.allCases) { mode in
          let selected = scheduleMode == mode
          let detail: String = {
            switch mode {
            case .classes: return "7 Levels"
            case .specialBlocks: return "\(SpecialBlock.allCases.count) school blocks"
            }
          }()

          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              scheduleMode = mode
            }
          } label: {
            HStack(spacing: 11) {
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(
                    selected
                      ? DesignTokens.Colors.schedule.opacity(0.20)
                      : DesignTokens.Colors.hover.opacity(0.46))

                Image(systemName: mode.icon)
                  .font(.system(size: 14, weight: .semibold))
                  .foregroundStyle(
                    selected ? DesignTokens.Colors.schedule : DesignTokens.Colors.secondaryText)
              }
              .frame(width: 36, height: 36)

              VStack(alignment: .leading, spacing: 2) {
                Text(mode.rawValue)
                  .font(.system(size: 12.5, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.primaryText)

                Text(detail)
                  .font(.system(size: 10.5, weight: .medium))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .lineLimit(1)
              }

              Spacer(minLength: 0)

              Image(systemName: selected ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: selected ? 12 : 10, weight: .semibold))
                .foregroundStyle(
                  selected
                    ? DesignTokens.Colors.schedule : DesignTokens.Colors.secondaryText.opacity(0.55)
                )
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
            .background {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? DesignTokens.Colors.schedule.opacity(0.10) : Color.clear)
            }
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                  selected ? DesignTokens.Colors.schedule.opacity(0.44) : Color.clear, lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(5)
      .background(
        DesignTokens.Colors.schedule.opacity(
          colorScheme == .light ? 0.035 : 0.055
        ),
        in: RoundedRectangle(
          cornerRadius: 15,
          style: .continuous
        )
      )
      .overlay {
        RoundedRectangle(
          cornerRadius: 15,
          style: .continuous
        )
        .strokeBorder(
          DesignTokens.Colors.schedule.opacity(0.18),
          lineWidth: 1
        )
      }
    }

    // MARK: Dining

    private var diningContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "Dining",
          subtitle: "Manage the dining preferences RooMate actually stores today.",
          icon: "fork.knife",
          tint: DesignTokens.Colors.dining
        )

        settingsCard(
          title: "Favorite Dishes",
          subtitle: "Favorites are the dishes you starred from the Dining screen.",
          icon: "star",
          tint: DesignTokens.Colors.dining
        ) {
          if diningFavoriteNames.isEmpty {
            compactEmptyState(
              icon: "star.slash",
              title: "No dining favorites yet",
              subtitle: "Star a dish in Dining and it will appear here."
            )
          } else {
            VStack(spacing: 0) {
              ForEach(diningFavoriteNames.sorted(), id: \.self) { name in
                HStack(spacing: 10) {
                  Image(systemName: "star.fill")
                    .foregroundStyle(DesignTokens.Colors.dining)
                  Text(name)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                  Spacer()
                }
                .frame(height: 38)

                if name != diningFavoriteNames.sorted().last {
                  Divider().overlay(DesignTokens.Colors.border)
                }
              }

              Divider().overlay(DesignTokens.Colors.border)

              Button(role: .destructive) {
                diningFavoriteNames.removeAll()
                UserDefaults.standard.set([], forKey: "RooMateDiningFavoriteRecipeNames")
              } label: {
                Label("Clear Dining Favorites", systemImage: "trash")
                  .font(.system(size: 12.5, weight: .medium))
                  .frame(maxWidth: .infinity)
                  .frame(height: 34)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }

        settingsCard(
          title: "Menu Data",
          subtitle: "Dining shows the latest school menu RooMate can find.",
          icon: "arrow.triangle.2.circlepath",
          tint: DesignTokens.Colors.info
        ) {
          infoRow(
            icon: "checkmark.circle.fill", title: "No menu setup needed",
            subtitle: "Use Dining itself for dates, search, filters, and station browsing.",
            tint: DesignTokens.Colors.success)
        }
      }
    }

    // MARK: Sports

    private var sportsContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "Sports",
          subtitle: "Manage the games you asked RooMate to remind you about.",
          icon: "sportscourt",
          tint: DesignTokens.Colors.athletics
        )

        settingsCard(
          title: "Team pages",
          subtitle: "Team pages and following will return in a future update.",
          icon: "wrench.and.screwdriver.fill",
          tint: DesignTokens.Colors.athletics
        ) {
          infoRow(
            icon: "sportscourt.fill",
            title: "Games are still available",
            subtitle: "Every matchup remains in Sports, including the teams playing, date, time, location, status, and notes.",
            tint: DesignTokens.Colors.athletics
          )
          infoRow(
            icon: "arrow.clockwise",
            title: "Team tools will return later",
            subtitle: "Existing team choices are preserved privately on this Mac, but they no longer affect RooMate while the feature is being refreshed.",
            tint: DesignTokens.Colors.info
          )
        }

        settingsCard(
          title: "Saved Game Reminders",
          subtitle: savedGameIDs.isEmpty
            ? "No games are currently saved for a reminder."
            : "\(savedGameIDs.count) game reminder\(savedGameIDs.count == 1 ? "" : "s") selected.",
          icon: "bell.badge.fill",
          tint: DesignTokens.Colors.athletics
        ) {
          infoRow(
            icon: notificationsAreActive ? "bell.fill" : "bell.slash.fill",
            title: notificationsAreActive ? "Reminders are enabled" : "RooMate notifications are off",
            subtitle: notificationsAreActive
              ? "RooMate sends one local reminder an hour before each selected game with a known start time."
              : "Your selected games stay saved. Turn notifications on in General when you want reminders delivered.",
            tint: notificationsAreActive ? DesignTokens.Colors.success : DesignTokens.Colors.warning
          )

          if !savedGameIDs.isEmpty {
            Divider().overlay(DesignTokens.Colors.border)

            Button(role: .destructive) {
              savedGameIDsRaw = ""
              NotificationCenter.default.post(
                name: .rooMateSportsPreferencesDidChange,
                object: nil
              )
            } label: {
              Label("Clear Game Reminders", systemImage: "bell.slash")
                .font(.system(size: 12.5, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }

    // MARK: Events

    private var eventsContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "Events",
          subtitle: "Choose which school calendar RooMate shows and manage saved events.",
          icon: "calendar.circle",
          tint: DesignTokens.Colors.events
        )

        settingsCard(
          title: "Event Calendars",
          subtitle: eventsStore.selectedSources.contains(.allEvents)
            ? "All Events is selected, so RooMate shows every school calendar."
            : "Choose one or more calendars. All Events is the one-click everything option.",
          icon: "calendar.badge.clock",
          tint: DesignTokens.Colors.events
        ) {
          VStack(spacing: 8) {
            ForEach(CalendarSource.allCases) { source in
              let selected = eventsStore.selectedSources.contains(source)

              Button {
                eventsStore.toggleSource(source)
              } label: {
                HStack(spacing: 11) {
                  Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                      selected ? DesignTokens.Colors.events : DesignTokens.Colors.subtleText
                    )
                    .frame(width: 19)

                  VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                      .font(.system(size: 13.5, weight: .medium))
                      .foregroundStyle(DesignTokens.Colors.primaryText)

                    if source == .allEvents {
                      Text("Selects All School, Upper, Middle, and Lower School.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignTokens.Colors.secondaryText)
                    }
                  }

                  Spacer()

                  if selected {
                    Text(source == .allEvents ? "Everything" : "Shown")
                      .font(.system(size: 10.5, weight: .semibold))
                      .foregroundStyle(DesignTokens.Colors.events)
                  }
                }
                .padding(.horizontal, 11)
                .frame(minHeight: 42)
                .background {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                      selected
                        ? DesignTokens.Colors.events.opacity(0.09)
                        : DesignTokens.Colors.hover.opacity(0.28))
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }

            HStack(spacing: 7) {
              Image(systemName: "info.circle")
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              Text("Showing: \(eventsStore.selectionDetail)")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              Spacer()
            }
            .padding(.top, 3)
          }
        }

        settingsCard(
          title: "Event Reminders",
          subtitle: savedEventCount == 0
            ? "Choose selected-calendar reminders, saved-event reminders, or both."
            : "\(savedEventCount) saved event\(savedEventCount == 1 ? "" : "s") plus optional selected-calendar reminders.",
          icon: "bell.badge.fill",
          tint: DesignTokens.Colors.events
        ) {
          VStack(spacing: 0) {
            compactToggle(
              title: "Remind me about selected calendars",
              subtitle:
                "Optional reminders for every event in the calendars selected above.",
              isOn: notifyCalendarEventsBinding,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            compactToggle(
              title: "Remind me about saved events",
              subtitle:
                "30 minutes before timed bookmarks; all-day bookmarks get an 8:00 AM reminder.",
              isOn: notifySavedEventsBinding,
              disabled: !notificationsAreActive
            )

            Divider().overlay(DesignTokens.Colors.border)

            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 3) {
                Text("\(savedEventCount)")
                  .font(.system(size: 28, weight: .semibold, design: .rounded))
                  .foregroundStyle(DesignTokens.Colors.pacTrack)
                Text("saved")
                  .font(DesignTokens.Typography.caption)
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }

              Spacer()

              Button(role: .destructive) {
                bookmarkedEventKeysRaw = ""
                NotificationCenter.default.post(
                  name: .rooMateEventPreferencesDidChange,
                  object: nil
                )
              } label: {
                Label("Clear Saved Events", systemImage: "trash")
                  .font(.system(size: 12.5, weight: .medium))
                  .padding(.horizontal, 12)
                  .frame(height: 34)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .disabled(savedEventCount == 0)
            }
            .padding(.vertical, 9)
          }
        }
      }
    }

    // MARK: PacTrack

    private var pacTrackContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "PacTrack",
          subtitle: "Your grade follows Profile automatically; manage the RooPAC plan here.",
          icon: "chart.bar.xaxis",
          tint: DesignTokens.Colors.pacTrack
        )

        settingsCard(
          title: "Grade Level",
          subtitle: "RooMate updates this from the graduation year in your Profile.",
          icon: "graduationcap",
          tint: DesignTokens.Colors.pacTrack
        ) {
          HStack(spacing: 12) {
            ZStack {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DesignTokens.Colors.pacTrack.opacity(0.12))
              Image(systemName: "graduationcap.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.pacTrack)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
              Text(store.rooPACCurrentGrade.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
              if let year = store.profileGraduationYear {
                Text(
                  "Class of \(String(year)) • \(store.rooPACCurrentGrade.requirement) RooPACs required this year"
                )
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              } else {
                Text("Set a graduation year in Profile to make this automatic.")
                  .font(.system(size: 10.5))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
              }
            }

            Spacer()

            Image(
              systemName: store.profileGraduationYear == nil
                ? "exclamationmark.circle" : "checkmark.circle.fill"
            )
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(
              store.profileGraduationYear == nil
                ? DesignTokens.Colors.warning : DesignTokens.Colors.success)
          }
          .padding(12)
          .background(
            DesignTokens.Colors.hover.opacity(0.26),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(
              DesignTokens.Colors.border, lineWidth: 1)
          }

          Text(
            "Change your graduation year from Profile. RooMate will advance your grade automatically as each school year changes."
          )
          .font(.system(size: 10))
          .foregroundStyle(DesignTokens.Colors.subtleText)
        }

        settingsCard(
          title: "Current Plan",
          subtitle: "A quick summary of the same plan shown in PacTrack.",
          icon: "checklist",
          tint: DesignTokens.Colors.pacTrack
        ) {
          HStack(spacing: 18) {
            miniMetric(
              value: "\(minimumPlannedRooPACs)", label: "Planned so far",
              tint: DesignTokens.Colors.pacTrack)
            miniMetric(
              value: "\(store.rooPACCurrentGrade.requirement)", label: "Required this year",
              tint: DesignTokens.Colors.schedule)
            miniMetric(
              value: "\(selectedRooPACCount)", label: "Activities selected",
              tint: DesignTokens.Colors.athletics)
          }

          Divider().overlay(DesignTokens.Colors.border)

          Button(role: .destructive) {
            withAnimation(DesignTokens.Animation.snappy) {
              store.rooPacPlans = [:]
            }
          } label: {
            Label("Reset PacTrack Plan", systemImage: "arrow.counterclockwise")
              .font(.system(size: 12.5, weight: .medium))
              .frame(maxWidth: .infinity)
              .frame(height: 34)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(selectedRooPACCount == 0)
        }
      }
    }

    // MARK: Updates

    private var updatesContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "Updates",
          subtitle: "Check for the latest version of RooMate.",
          icon: "arrow.down.circle",
          tint: DesignTokens.Colors.info
        )

        settingsCard(
          title: "Version \(shortVersion)",
          icon: "shippingbox",
          tint: DesignTokens.Colors.info
        ) {
          HStack(spacing: 14) {
            ZStack {
              Circle()
                .fill(DesignTokens.Colors.info.opacity(0.13))
              Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.info)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
              Text("See if a newer version is available")
                .font(.system(size: 14, weight: .semibold))
              Text(
                checkForUpdatesAction == nil
                  ? "Update checking isn’t available in this copy of RooMate."
                  : "RooMate can check for a newer version and install it for you."
              )
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            }

            Spacer()
          }

          Button {
            checkForUpdatesAction?()
          } label: {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
              .font(.system(size: 13, weight: .semibold))
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .contentShape(Rectangle())
              .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                  .fill(DesignTokens.Colors.info.opacity(0.12))
              }
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity)
          .frame(height: 38)
          .contentShape(Rectangle())
          .disabled(checkForUpdatesAction == nil)
        }
      }
    }

    // MARK: About

    private var aboutContent: some View {
      VStack(alignment: .leading, spacing: 18) {
        sectionHeading(
          "About RooMate",
          subtitle: "Version, privacy, and app details.",
          icon: "info.circle",
          tint: DesignTokens.Colors.primary
        )

        settingsCard(
          title: appName,
          subtitle: "Version \(shortVersion)",
          icon: "app.badge",
          tint: DesignTokens.Colors.primary
        ) {
          HStack(spacing: 16) {
            Image("RooMark")
              .resizable()
              .scaledToFit()
              .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 5) {
              Text("RooMate")
                .font(.system(size: 24, weight: .semibold))
              Text(DesignTokens.Brand.tagline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primary)
              Text(
                DesignTokens.Brand.about
                  + " RooMate is independent and is not an official school product."
              )
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
            }
          }
        }

        settingsCard(
          title: "Your data",
          subtitle: "Your personal RooMate setup stays on this Mac.",
          icon: "lock.shield",
          tint: DesignTokens.Colors.success
        ) {
          VStack(spacing: 10) {
            infoRow(
              icon: "calendar", title: "Schedule",
              subtitle: "Your classes, clubs, special blocks, and appearance stay on this Mac.",
              tint: DesignTokens.Colors.schedule)
            infoRow(
              icon: "chart.bar.xaxis", title: "PacTrack",
              subtitle: "Your grade and RooPAC plan stay on this Mac.",
              tint: DesignTokens.Colors.pacTrack)
            infoRow(
              icon: "bookmark", title: "Saved items",
              subtitle:
                "Dining favorites, sports game reminders, and event bookmarks stay with your RooMate setup.",
              tint: DesignTokens.Colors.dining)
            infoRow(
              icon: "chart.xyaxis.line", title: "Analytics",
              subtitle:
                "RooMate measures general app use and broad loading problems with TelemetryDeck. It never sends your name, classes, club notes, RooPAC plan, searches, or other personal school information.",
              tint: DesignTokens.Colors.info)
          }
        }

        settingsCard(
          title: "What’s New",
          subtitle: "Revisit the highlights from RooMate 6.",
          icon: "sparkles",
          tint: DesignTokens.Colors.primary
        ) {
          Button {
            NotificationCenter.default.post(name: .rooMateShowWhatsNew, object: nil)
          } label: {
            Label("Show What’s New", systemImage: "sparkles")
              .font(.system(size: 12.5, weight: .semibold))
              .frame(maxWidth: .infinity)
              .frame(height: 36)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(DesignTokens.Colors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }

        settingsCard(
          title: "Feedback & Support",
          subtitle: "Report a problem or suggest an improvement.",
          icon: "bubble.left.and.bubble.right",
          tint: DesignTokens.Colors.info
        ) {
          HStack(spacing: 10) {
            feedbackButton(
              title: "Report a Problem",
              subtitle: "Open a report draft",
              symbol: "exclamationmark.bubble",
              url: "https://github.com/codearc-studio/RooMate/issues/new?labels=bug&title=RooMate%20problem%3A%20"
            )
            feedbackButton(
              title: "Suggest a Feature",
              subtitle: "Share an idea for RooMate",
              symbol: "lightbulb",
              url: "https://github.com/codearc-studio/RooMate/issues/new?labels=enhancement&title=RooMate%20idea%3A%20"
            )
          }

          Divider().overlay(DesignTokens.Colors.border)

          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Info for a bug report")
                .font(.system(size: 12.5, weight: .semibold))
              Text("See exactly what will be copied: RooMate version, macOS version, Mac type, time, and whether school data loaded.")
                .font(.system(size: 10.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("View Bug Report Info") { showDiagnostics = true }
              .buttonStyle(.bordered)
          }
        }
      }
    }

    // MARK: Right rail

    @ViewBuilder
    private var rightRail: some View {
      VStack(spacing: 14) {
        rightRailSummary
        rightRailUpdates
        rightRailStorage
      }
    }

    private var rightRailSummary: some View {
      VStack(alignment: .leading, spacing: 14) {
        Text("RooMate")
          .font(.system(size: 11.5, weight: .bold))
          .foregroundStyle(DesignTokens.Colors.pacTrack)

        HStack(spacing: 13) {
          Image("RooMark")
            .resizable()
            .scaledToFit()
            .frame(width: 46, height: 46)

          VStack(alignment: .leading, spacing: 2) {
            Text(appName)
              .font(.system(size: 18, weight: .semibold))
            Text("Version \(shortVersion)")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }

        Divider().overlay(DesignTokens.Colors.border)

        VStack(spacing: 9) {
          railStat(
            title: "Classes set up", value: "\(assignedClassCount)/7",
            tint: DesignTokens.Colors.schedule)
          railStat(title: "Clubs", value: "\(store.clubs.count)", tint: DesignTokens.Colors.dining)
          railStat(
            title: "PacTrack grade", value: store.rooPACCurrentGrade.shortTitle,
            tint: DesignTokens.Colors.pacTrack)
        }
      }
      .padding(16)
      .rooSurface(cornerRadius: 16, elevated: false, border: true)
    }

    private var rightRailUpdates: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("UPDATES")
            .font(.system(size: 10.5, weight: .bold))
            .tracking(1.0)
            .foregroundStyle(DesignTokens.Colors.info)
          Spacer()
          Image(systemName: "arrow.down.circle")
            .foregroundStyle(DesignTokens.Colors.info)
        }

        Text("Version \(shortVersion)")
          .font(.system(size: 13, weight: .semibold))

        Text(
          checkForUpdatesAction == nil
            ? "Update checking isn’t available in this copy of RooMate."
            : "RooMate can check for a newer version."
        )
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(DesignTokens.Colors.secondaryText)

        Button {
          checkForUpdatesAction?()
        } label: {
          Text("Check for Updates")
            .font(.system(size: 12.5, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .contentShape(Rectangle())
        .rooGlass(cornerRadius: 10)
        .disabled(checkForUpdatesAction == nil)
      }
      .padding(16)
      .rooSurface(cornerRadius: 16, elevated: false, border: true)
    }

    private var rightRailStorage: some View {
      VStack(alignment: .leading, spacing: 12) {
        Text("YOUR SETUP")
          .font(.system(size: 10.5, weight: .bold))
          .tracking(1.0)
          .foregroundStyle(DesignTokens.Colors.success)

        infoRow(
          icon: "star.fill", title: "\(diningFavoriteNames.count) dining favorites", subtitle: nil,
          tint: DesignTokens.Colors.dining)
        infoRow(
          icon: "bell.badge.fill", title: "\(savedGameIDs.count) sports reminders", subtitle: nil,
          tint: DesignTokens.Colors.athletics)
        infoRow(
          icon: "bookmark.fill", title: "\(savedEventCount) saved events", subtitle: nil,
          tint: DesignTokens.Colors.events)
      }
      .padding(16)
      .rooSurface(cornerRadius: 16, elevated: false, border: true)
    }

    private func railStat(title: String, value: String, tint: Color) -> some View {
      HStack {
        Circle().fill(tint).frame(width: 7, height: 7)
        Text(title)
          .font(.system(size: 11.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Spacer()
        Text(value)
          .font(.system(size: 12, weight: .semibold, design: .rounded))
      }
    }

    private func miniMetric(value: String, label: String, tint: Color) -> some View {
      VStack(alignment: .leading, spacing: 3) {
        Text(value)
          .font(.system(size: 24, weight: .semibold, design: .rounded))
          .foregroundStyle(tint)
        Text(label)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(icon: String, title: String, subtitle: String?, tint: Color) -> some View {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 22, height: 22)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 10.8))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer(minLength: 0)
      }
    }

    private func compactEmptyState(icon: String, title: String, subtitle: String) -> some View {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .frame(width: 34)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.system(size: 13.5, weight: .semibold))
          Text(subtitle)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        Spacer()
      }
      .padding(12)
      .background {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .fill(DesignTokens.Colors.hover.opacity(0.35))
      }
    }

    private var classesTabContent: some View {
      let currentLevel = editableLevels[selectedLevelIndex]

      return VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Your Classes")
              .font(.system(size: 18, weight: .semibold))
            Text(
              "Choose a Level, then describe exactly what RooMate should show when that Level appears."
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          Spacer()
          Text("\(assignedClassCount)/7 set up")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.schedule.opacity(0.10), in: Capsule())
        }

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 14) {
            levelSetupList
              .frame(width: 220)

            LevelEditorRow(level: currentLevel, assignment: store.binding(for: currentLevel))
              .frame(maxWidth: .infinity)
          }

          VStack(spacing: 14) {
            levelSetupList
            LevelEditorRow(level: currentLevel, assignment: store.binding(for: currentLevel))
          }
        }
      }
    }

    private var levelSetupList: some View {
      VStack(spacing: 5) {
        ForEach(Array(editableLevels.enumerated()), id: \.offset) { idx, level in
          let assignment = store.assignment(for: level)
          let selected = selectedLevelIndex == idx
          let hasCustomClass =
            !assignment.isFree
            && !assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && assignment.title != level.displayName
          let summary =
            assignment.isFree
            ? "Free block" : (hasCustomClass ? assignment.title : "Not set up")

          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              selectedLevelIndex = idx
            }
          } label: {
            HStack(spacing: 10) {
              ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(assignment.color.swiftUIColor.opacity(selected ? 0.22 : 0.12))

                Image(systemName: assignment.displaySystemImage(for: level))
                  .font(.system(size: 14.5, weight: .semibold))
                  .foregroundStyle(assignment.color.swiftUIColor)
              }
              .frame(width: 34, height: 34)

              VStack(alignment: .leading, spacing: 2) {
                Text(level.displayName)
                  .font(.system(size: 12.5, weight: .semibold))
                Text(summary)
                  .font(.system(size: 10.5, weight: .medium))
                  .foregroundStyle(
                    hasCustomClass || assignment.isFree
                      ? DesignTokens.Colors.secondaryText
                      : DesignTokens.Colors.secondaryText.opacity(0.65)
                  )
                  .lineLimit(1)
              }

              Spacer(minLength: 4)

              if assignment.isFree || hasCustomClass {
                Image(systemName: assignment.isFree ? "sparkles" : "checkmark.circle.fill")
                  .font(.system(size: 11.5, weight: .semibold))
                  .foregroundStyle(
                    assignment.isFree ? DesignTokens.Colors.pacTrack : DesignTokens.Colors.success)
              } else {
                Image(systemName: "chevron.right")
                  .font(.system(size: 10, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.secondaryText.opacity(0.65))
              }
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
            .background {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                  selected
                    ? DesignTokens.Colors.schedule.opacity(0.12)
                    : DesignTokens.Colors.hover.opacity(0.22))
            }
            .overlay {
              RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                  selected ? DesignTokens.Colors.schedule.opacity(0.48) : Color.clear, lineWidth: 1)
            }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(7)
      .rooSurface(cornerRadius: 15, elevated: false, border: true)
    }

    private var scheduleTabContent: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Special Blocks")
              .font(.system(size: 18, weight: .semibold))
            Text(
              "See every non-Level block in the bell schedule, adjust its color, and configure the blocks that can change for you."
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer(minLength: 8)

          Text("\(SpecialBlock.allCases.count) blocks")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.schedule.opacity(0.10), in: Capsule())
        }

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 205, maximum: 280), spacing: 10)],
          spacing: 10
        ) {
          ForEach(SpecialBlock.allCases) { block in
            specialBlockOverviewCard(block)
          }
        }

        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 9) {
            ZStack {
              RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.Colors.schedule.opacity(0.11))
              Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.schedule)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
              Text("Set up changing blocks")
                .font(.system(size: 14, weight: .semibold))
              Text("Only set up blocks that change on different days.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
          }

          consciousCommunitiesSetup
          lunchSetup
          musicBlockSetup
        }
        .padding(14)
        .rooSurface(cornerRadius: 16, elevated: false, border: true)
      }
    }

    private func specialBlockOverviewCard(_ block: SpecialBlock) -> some View {
      let days = specialBlockDays(block)
      let dayText =
        days.isEmpty
        ? "Not in current bell schedule" : days.map(shortWeekdayName).joined(separator: " • ")
      let note: String? = {
        switch block {
        case .musicClubs:
          return "Club names come from the Clubs page."
        case .lunchAndClubs:
          return "Wednesday clubs are folded into this block."
        case .lunch:
          return "Free by default unless you add a lunch conflict."
        default:
          return nil
        }
      }()

      return VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(store.color(for: block).opacity(0.14))
            Image(systemName: block.systemImage)
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(store.color(for: block))
          }
          .frame(width: 34, height: 34)

          VStack(alignment: .leading, spacing: 2) {
            Text(block.title)
              .font(.system(size: 12.5, weight: .semibold))
              .lineLimit(1)
            Text(dayText)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          Spacer(minLength: 4)

          ColorPicker(
            "Color",
            selection: store.colorBinding(for: block),
            supportsOpacity: false
          )
          .labelsHidden()
          .frame(width: 72, height: 28)
          .padding(.trailing, 7)
        }

        if let note {
          Text(note)
            .font(.system(size: 10))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(11)
      .frame(maxWidth: .infinity, minHeight: note == nil ? 60 : 78, alignment: .topLeading)
      .background(
        DesignTokens.Colors.hover.opacity(0.26),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
    }

    private var consciousCommunitiesSetup: some View {
      let isFree = specialFreeBinding(for: .consciousCommunities)
      let replacement = specialReplacementBinding(for: .consciousCommunities)

      return VStack(alignment: .leading, spacing: 11) {
        specialBehaviorHeader(
          block: .consciousCommunities,
          subtitle:
            "Choose whether this Thursday block is open time or a scheduled class/activity.",
          status: isFree.wrappedValue ? "Free time" : "Scheduled"
        )

        HStack(spacing: 8) {
          specialStateButton(
            title: "Scheduled",
            subtitle: "I have something during this block",
            icon: "calendar.badge.clock",
            selected: !isFree.wrappedValue
          ) {
            isFree.wrappedValue = false
          }

          specialStateButton(
            title: "Free time",
            subtitle: "Treat it as open time",
            icon: "sparkles",
            selected: isFree.wrappedValue
          ) {
            isFree.wrappedValue = true
          }
        }

        if !isFree.wrappedValue {
          ReplacementClassEditor(
            prompt: "What should RooMate show for this block?",
            replacement: replacement
          )
        }
      }
      .padding(12)
      .background(
        DesignTokens.Colors.hover.opacity(0.22),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
    }

    private var lunchSetup: some View {
      let actualLunchDays = specialBlockDays(.lunch)
      let replacement = specialReplacementBinding(for: .lunch)
      let busyDays = store.specialBlockReplacements[.lunch]?.daysNotFree ?? []

      return VStack(alignment: .leading, spacing: 11) {
        specialBehaviorHeader(
          block: .lunch,
          subtitle:
            "Lunch is open time by default. Select a day only if you regularly have something scheduled during lunch.",
          status: busyDays.isEmpty
            ? "Free" : "\(busyDays.count) busy day\(busyDays.count == 1 ? "" : "s")"
        )

        HStack(spacing: 7) {
          ForEach(actualLunchDays) { weekday in
            specialDayButton(
              weekday: weekday,
              selected: busyDays.contains(weekday.calendarWeekdayIndex),
              tint: DesignTokens.Colors.dining
            ) {
              toggleLunchBusyDay(weekday)
            }
          }
        }

        if !busyDays.isEmpty {
          ReplacementClassEditor(
            prompt:
              "What happens during lunch on the selected day\(busyDays.count == 1 ? "" : "s")?",
            replacement: replacement
          )
        }
      }
      .padding(12)
      .background(
        DesignTokens.Colors.hover.opacity(0.22),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
    }

    private var musicBlockSetup: some View {
      let musicDays = levelDays(.music)
      let musicAssignment = store.assignment(for: .music)
      let busyDays = musicAssignment.musicDaysNotFree
      let replacement = specialReplacementBinding(for: .musicClubs)

      return VStack(alignment: .leading, spacing: 11) {
        specialBehaviorHeader(
          block: .musicClubs,
          subtitle:
            "Your regular Music Level is free by default. Select the Level days when you actually have music or another activity.",
          status: busyDays.isEmpty
            ? "Free" : "\(busyDays.count) scheduled day\(busyDays.count == 1 ? "" : "s")"
        )

        HStack(spacing: 7) {
          ForEach(musicDays) { weekday in
            specialDayButton(
              weekday: weekday,
              selected: busyDays.contains(weekday.calendarWeekdayIndex),
              tint: DesignTokens.Colors.schedule
            ) {
              toggleMusicBusyDay(weekday)
            }
          }

          Spacer(minLength: 0)
        }

        if !busyDays.isEmpty {
          ReplacementClassEditor(
            prompt:
              "What should RooMate show on the selected Music Level day\(busyDays.count == 1 ? "" : "s")?",
            replacement: replacement
          )
        }

        if store.clubs.contains(where: \.meetsMondayClub) {
          HStack(spacing: 7) {
            Image(systemName: "person.3.fill")
              .foregroundStyle(DesignTokens.Colors.schedule)
            Text("Monday’s Music Block + Clubs is being filled from your Clubs page.")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }
      }
      .padding(12)
      .background(
        DesignTokens.Colors.hover.opacity(0.22),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
    }

    private func specialBehaviorHeader(block: SpecialBlock, subtitle: String, status: String)
      -> some View
    {
      HStack(alignment: .top, spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(store.color(for: block).opacity(0.14))
          Image(systemName: block.systemImage)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(store.color(for: block))
        }
        .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 2) {
          Text(block == .musicClubs ? "Music Block" : block.title)
            .font(.system(size: 12.5, weight: .semibold))
          Text(subtitle)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer(minLength: 8)

        Text(status)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(store.color(for: block))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(store.color(for: block).opacity(0.09), in: Capsule())
      }
    }

    private func specialStateButton(
      title: String,
      subtitle: String,
      icon: String,
      selected: Bool,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 9) {
          Image(systemName: icon)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(
              selected ? DesignTokens.Colors.schedule : DesignTokens.Colors.secondaryText
            )
            .frame(width: 22)

          VStack(alignment: .leading, spacing: 1) {
            Text(title)
              .font(.system(size: 11.5, weight: .semibold))
            Text(subtitle)
              .font(.system(size: 9.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          Spacer(minLength: 4)

          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(
              selected
                ? DesignTokens.Colors.schedule : DesignTokens.Colors.secondaryText.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .contentShape(Rectangle())
        .background(
          selected
            ? DesignTokens.Colors.schedule.opacity(0.09) : DesignTokens.Colors.hover.opacity(0.28),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
              selected ? DesignTokens.Colors.schedule.opacity(0.38) : DesignTokens.Colors.border,
              lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }

    private func specialDayButton(
      weekday: Weekday, selected: Bool, tint: Color, action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        VStack(spacing: 3) {
          Text(shortWeekdayName(weekday))
            .font(.system(size: 10.5, weight: .bold))
          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(selected ? tint : DesignTokens.Colors.secondaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .contentShape(Rectangle())
        .background(
          selected ? tint.opacity(0.10) : DesignTokens.Colors.hover.opacity(0.28),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(selected ? tint.opacity(0.38) : DesignTokens.Colors.border, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }

    private func specialBlockDays(_ block: SpecialBlock) -> [Weekday] {
      Weekday.allCases.filter { weekday in
        BellSchedule.weekly[weekday]?.contains(where: { bellBlock in
          if case .special(let special) = bellBlock.kind {
            return special == block
          }
          return false
        }) ?? false
      }
    }

    private func levelDays(_ level: Level) -> [Weekday] {
      Weekday.allCases.filter { weekday in
        BellSchedule.weekly[weekday]?.contains(where: { bellBlock in
          if case .level(let blockLevel) = bellBlock.kind {
            return blockLevel == level
          }
          return false
        }) ?? false
      }
    }

    private func shortWeekdayName(_ weekday: Weekday) -> String {
      switch weekday {
      case .monday: "Mon"
      case .tuesday: "Tue"
      case .wednesday: "Wed"
      case .thursday: "Thu"
      case .friday: "Fri"
      }
    }

    private func toggleLunchBusyDay(_ weekday: Weekday) {
      let day = weekday.calendarWeekdayIndex
      var replacement = store.specialBlockReplacements[.lunch] ?? defaultReplacement(isFree: false)
      replacement.isFree = false

      if replacement.daysNotFree.contains(day) {
        replacement.daysNotFree.remove(day)
      } else {
        replacement.daysNotFree.insert(day)
      }

      if replacement.daysNotFree.isEmpty {
        store.specialBlockReplacements[.lunch] = nil
      } else {
        store.specialBlockReplacements[.lunch] = replacement
      }
    }

    private func toggleMusicBusyDay(_ weekday: Weekday) {
      let day = weekday.calendarWeekdayIndex
      var assignment = store.assignment(for: .music)
      assignment.isFree = true

      if assignment.musicDaysNotFree.contains(day) {
        assignment.musicDaysNotFree.remove(day)
      } else {
        assignment.musicDaysNotFree.insert(day)
      }

      store.assignments[.music] = assignment
      store.specialFree[.musicClubs] = assignment.displayIsFree(on: .monday)

      if assignment.musicDaysNotFree.isEmpty {
        store.specialBlockReplacements[.musicClubs] = nil
      } else {
        var replacement =
          store.specialBlockReplacements[.musicClubs] ?? defaultReplacement(isFree: false)
        replacement.isFree = false
        replacement.daysNotFree = assignment.musicDaysNotFree
        store.specialBlockReplacements[.musicClubs] = replacement
      }
    }

  }

  // MARK: - Helper Components

  struct ScheduleCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = DesignTokens.Colors.primary
    @ViewBuilder let content: () -> Content

    var body: some View {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        HStack(spacing: DesignTokens.Spacing.sm) {
          Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(tint)

          Text(title)
            .font(DesignTokens.Typography.headline2)
        }

        Text(subtitle)
          .font(DesignTokens.Typography.subheadline)
          .foregroundStyle(.secondary)

        content()
      }
      .padding(DesignTokens.Spacing.lg)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
          .fill(compatibleBackgroundSecondary())
      )
      .designShadow(DesignTokens.Shadows.small)
    }
  }

  struct ScheduleStateBadge: View {
    let text: String
    let isFree: Bool

    var body: some View {
      Text(text)
        .font(DesignTokens.Typography.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 6)
        .background(
          Capsule(style: .continuous)
            .fill((isFree ? DesignTokens.Colors.success : DesignTokens.Colors.accent).opacity(0.14))
        )
        .foregroundStyle(isFree ? DesignTokens.Colors.success : DesignTokens.Colors.accent)
    }
  }

  struct ReplacementClassEditor: View {
    let prompt: String
    @Binding var replacement: ClassAssignment.ReplacementClass

    var body: some View {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        Text(prompt)
          .font(DesignTokens.Typography.caption)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
          TextField("Replacement class", text: $replacement.title)
            .foregroundStyle(.primary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(compatibleBackgroundSecondary())
            .cornerRadius(DesignTokens.Radius.sm)
            .overlay(
              RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                Color.secondary.opacity(0.3), lineWidth: 1))

          HStack(spacing: DesignTokens.Spacing.md) {
            TextField("Teacher", text: $replacement.teacher)
              .foregroundStyle(.primary)
              .padding(.horizontal, DesignTokens.Spacing.sm)
              .padding(.vertical, DesignTokens.Spacing.xs)
              .background(compatibleBackgroundSecondary())
              .cornerRadius(DesignTokens.Radius.sm)
              .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                  Color.secondary.opacity(0.3), lineWidth: 1))

            TextField("Room", text: $replacement.room)
              .foregroundStyle(.primary)
              .frame(maxWidth: 140)
              .padding(.horizontal, DesignTokens.Spacing.sm)
              .padding(.vertical, DesignTokens.Spacing.xs)
              .background(compatibleBackgroundSecondary())
              .cornerRadius(DesignTokens.Radius.sm)
              .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                  Color.secondary.opacity(0.3), lineWidth: 1))
          }
        }
      }
    }
  }

  struct ThemeButton: View {
    let option: AppearancePreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: DesignTokens.Spacing.xs) {
          Image(systemName: option.systemImage)
            .font(.system(size: 18))
            .frame(height: 24)

          Text(option.title)
            .font(DesignTokens.Typography.caption)
            .fontWeight(.semibold)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 70)
        .padding(DesignTokens.Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(
              isSelected
                ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.2))
                : AnyShapeStyle(compatibleBackgroundSecondary()))
        )
        .overlay(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .strokeBorder(
              isSelected ? DesignTokens.Colors.primary : Color.secondary.opacity(0.2),
              lineWidth: isSelected ? 2 : 1)
        )
        .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .primary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  struct CardStyleButton: View {
    let style: CardColorStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: DesignTokens.Spacing.xs) {
          Image(systemName: style.systemImage)
            .font(.system(size: 18))
            .frame(height: 24)

          Text(style.title)
            .font(DesignTokens.Typography.caption)
            .fontWeight(.semibold)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 70)
        .padding(DesignTokens.Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(
              isSelected
                ? AnyShapeStyle(DesignTokens.Colors.accent.opacity(0.2))
                : AnyShapeStyle(compatibleBackgroundSecondary()))
        )
        .overlay(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .strokeBorder(
              isSelected ? DesignTokens.Colors.accent : Color.secondary.opacity(0.2),
              lineWidth: isSelected ? 2 : 1)
        )
        .foregroundStyle(isSelected ? DesignTokens.Colors.accent : .primary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  struct LevelTabButton: View {
    let level: Level
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        HStack(spacing: DesignTokens.Spacing.xs) {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.body)

          Text(level.displayName)
            .font(DesignTokens.Typography.subheadline)
            .fontWeight(.medium)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .background(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(
              isSelected
                ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.15))
                : AnyShapeStyle(compatibleBackgroundSecondary()))
        )
        .overlay(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .strokeBorder(isSelected ? DesignTokens.Colors.primary : Color.clear, lineWidth: 1.5)
        )
        .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .secondary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  struct WeekdayToggleButton: View {
    let weekday: Weekday
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        VStack(spacing: DesignTokens.Spacing.xs) {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18))
            .frame(height: 24)

          Text(weekday.title)
            .font(DesignTokens.Typography.caption)
            .fontWeight(.semibold)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 70)
        .padding(DesignTokens.Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(
              isSelected
                ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.2))
                : AnyShapeStyle(compatibleBackgroundSecondary()))
        )
        .overlay(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .strokeBorder(
              isSelected ? DesignTokens.Colors.primary : Color.secondary.opacity(0.2),
              lineWidth: isSelected ? 2 : 1)
        )
        .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .primary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Special Block Replacement Component

  struct SpecialBlockReplacementRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    @Binding var replacement: ClassAssignment.ReplacementClass

    var body: some View {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        HStack(spacing: DesignTokens.Spacing.md) {
          Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(DesignTokens.Colors.primary)

          Text(title)
            .font(DesignTokens.Typography.body)

          Spacer()

          Toggle("", isOn: $isOn)
            .tint(DesignTokens.Colors.primary)
        }

        if !isOn {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Which days is it free?")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)

            let daySymbols = Calendar.current.weekdaySymbols
            let allIndices: [Int] = [2, 3, 4, 5, 6]
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
              ForEach(allIndices, id: \.self) { idx in
                let label = daySymbols[idx - 1]
                let isFree = !replacement.daysNotFree.contains(idx)

                Button {
                  withAnimation(DesignTokens.Animation.snappy) {
                    if isFree {
                      replacement.daysNotFree.insert(idx)
                    } else {
                      replacement.daysNotFree.remove(idx)
                    }
                  }
                } label: {
                  Text(label)
                    .font(DesignTokens.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                      RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(
                          isFree
                            ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.15))
                            : compatibleBackgroundSecondary())
                    )
                    .foregroundStyle(isFree ? DesignTokens.Colors.primary : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }

            Divider().opacity(0.1)

            Text("Selected days count as free time")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)

            Toggle(
              isOn: Binding(
                get: { replacement.isFree },
                set: { replacement.isFree = $0 }
              )
            ) {
              Label("This is a class/activity on other days", systemImage: "book.fill")
            }
            .tint(DesignTokens.Colors.primary)

            if replacement.isFree {
              Text("Free on other days too.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            } else {
              VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                TextField("Class name", text: $replacement.title)
                  .foregroundStyle(.primary)
                  .padding(.horizontal, DesignTokens.Spacing.sm)
                  .padding(.vertical, DesignTokens.Spacing.xs)
                  .background(compatibleBackgroundSecondary())
                  .cornerRadius(DesignTokens.Radius.sm)
                  .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                      Color.secondary.opacity(0.3), lineWidth: 1))

                HStack(spacing: DesignTokens.Spacing.md) {
                  TextField("Teacher", text: $replacement.teacher)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(compatibleBackgroundSecondary())
                    .cornerRadius(DesignTokens.Radius.sm)
                    .overlay(
                      RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                        Color.secondary.opacity(0.3), lineWidth: 1))

                  TextField("Room", text: $replacement.room)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: 140)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(compatibleBackgroundSecondary())
                    .cornerRadius(DesignTokens.Radius.sm)
                    .overlay(
                      RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                        Color.secondary.opacity(0.3), lineWidth: 1))
                }
              }
            }
          }
          .transition(.opacity)
          .animation(.easeInOut(duration: 0.22), value: isOn)
        }
      }
      .padding(DesignTokens.Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(compatibleBackgroundSecondary())
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
      )
    }
  }

  // MARK: - Special Block Toggle Component

  struct SpecialBlockToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    var showMusicDays: Bool = false
    var musicAssignment: ClassAssignment?
    var availableMusicDays: [Weekday]?
    var onMusicDayChanged: ((Weekday, Bool) -> Void)?
    var replacement: Binding<ClassAssignment.ReplacementClass>?

    var body: some View {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        HStack(spacing: DesignTokens.Spacing.md) {
          Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(DesignTokens.Colors.primary)

          Text(title)
            .font(DesignTokens.Typography.body)

          Spacer()

          Toggle("", isOn: $isOn)
            .tint(DesignTokens.Colors.primary)
        }

        if showMusicDays && isOn && musicAssignment?.isFree == true
          && !(availableMusicDays?.isEmpty ?? true)
        {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("What days do you have music?")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)

            LazyVGrid(
              columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.sm),
              ], spacing: DesignTokens.Spacing.sm
            ) {
              ForEach(availableMusicDays ?? []) { weekday in
                let isNotFree =
                  musicAssignment?.musicDaysNotFree.contains(weekday.calendarWeekdayIndex) ?? false
                Button {
                  onMusicDayChanged?(weekday, isNotFree)
                } label: {
                  Text(weekday.title)
                    .font(DesignTokens.Typography.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                      RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(
                          isNotFree
                            ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.2))
                            : AnyShapeStyle(compatibleBackgroundSecondary()))
                    )
                    .foregroundStyle(isNotFree ? DesignTokens.Colors.primary : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }
        }

        if !isOn && replacement != nil {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Which days do you have something else?")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)

            let daySymbols = Calendar.current.weekdaySymbols
            let allIndices: [Int] = [2, 3, 4, 5, 6]
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

            LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
              ForEach(allIndices, id: \.self) { idx in
                let label = daySymbols[idx - 1]
                let hasReplacement = replacement?.wrappedValue.daysNotFree.contains(idx) ?? false

                Button {
                  withAnimation(DesignTokens.Animation.snappy) {
                    if hasReplacement {
                      replacement?.wrappedValue.daysNotFree.remove(idx)
                    } else {
                      replacement?.wrappedValue.daysNotFree.insert(idx)
                    }
                  }
                } label: {
                  Text(label)
                    .font(DesignTokens.Typography.caption)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.sm)
                    .background(
                      RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous)
                        .fill(
                          hasReplacement
                            ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.15))
                            : compatibleBackgroundSecondary())
                    )
                    .foregroundStyle(hasReplacement ? DesignTokens.Colors.primary : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }

            Divider().opacity(0.1)

            Text("Free on selected days")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(.secondary)

            Toggle(
              isOn: Binding(
                get: { replacement?.wrappedValue.isFree ?? true },
                set: { replacement?.wrappedValue.isFree = $0 }
              )
            ) {
              Label("This is a class/activity on other days", systemImage: "book.fill")
            }
            .tint(DesignTokens.Colors.primary)

            if replacement?.wrappedValue.isFree == true {
              Text("Free on other days too.")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            } else {
              VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                TextField(
                  "Class name",
                  text: Binding(
                    get: { replacement?.wrappedValue.title ?? "" },
                    set: { replacement?.wrappedValue.title = $0 }
                  )
                )
                .foregroundStyle(.primary)
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(compatibleBackgroundSecondary())
                .cornerRadius(DesignTokens.Radius.sm)
                .overlay(
                  RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                    Color.secondary.opacity(0.3), lineWidth: 1))

                HStack(spacing: DesignTokens.Spacing.md) {
                  TextField(
                    "Teacher",
                    text: Binding(
                      get: { replacement?.wrappedValue.teacher ?? "" },
                      set: { replacement?.wrappedValue.teacher = $0 }
                    )
                  )
                  .foregroundStyle(.primary)
                  .padding(.horizontal, DesignTokens.Spacing.sm)
                  .padding(.vertical, DesignTokens.Spacing.xs)
                  .background(compatibleBackgroundSecondary())
                  .cornerRadius(DesignTokens.Radius.sm)
                  .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                      Color.secondary.opacity(0.3), lineWidth: 1))

                  TextField(
                    "Room",
                    text: Binding(
                      get: { replacement?.wrappedValue.room ?? "" },
                      set: { replacement?.wrappedValue.room = $0 }
                    )
                  )
                  .foregroundStyle(.primary)
                  .frame(maxWidth: 140)
                  .padding(.horizontal, DesignTokens.Spacing.sm)
                  .padding(.vertical, DesignTokens.Spacing.xs)
                  .background(compatibleBackgroundSecondary())
                  .cornerRadius(DesignTokens.Radius.sm)
                  .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(
                      Color.secondary.opacity(0.3), lineWidth: 1))
                }
              }
            }
          }
          .transition(.opacity)
          .animation(.easeInOut(duration: 0.22), value: isOn)
        }
      }
      .padding(DesignTokens.Spacing.md)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .fill(compatibleBackgroundSecondary())
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
          .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 1)
      )
    }
  }

  // MARK: - Existing Editor Components

  struct LevelEditorRow: View {
    let level: Level
    @Binding var assignment: ClassAssignment

    private var daysLevelMeets: Set<Int> {
      var days: Set<Int> = []
      let weekdayMap: [Weekday: Int] = [
        .monday: 2, .tuesday: 3, .wednesday: 4, .thursday: 5, .friday: 6,
      ]

      for (weekday, dayIndex) in weekdayMap {
        if let blocks = BellSchedule.weekly[weekday],
          blocks.contains(where: { block in
            if case .level(let blockLevel) = block.kind { return blockLevel == level }
            return false
          })
        {
          days.insert(dayIndex)
        }
      }
      return days
    }

    private var orderedMeetingDays: [Int] {
      [2, 3, 4, 5, 6].filter { daysLevelMeets.contains($0) }
    }

    private var isConfigured: Bool {
      assignment.isFree
        || (!assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && assignment.title != level.displayName)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .center, spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(assignment.color.swiftUIColor.opacity(0.16))
            Image(systemName: assignment.displaySystemImage(for: level))
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(assignment.color.swiftUIColor)
          }
          .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 2) {
            Text(level.displayName)
              .font(.system(size: 18, weight: .semibold))
            Text(
              assignment.isFree
                ? "RooMate will treat this Level as free time."
                : (isConfigured ? assignment.title : "Tell RooMate what you have for this Level.")
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(2)
          }

          Spacer(minLength: 8)

          HStack(spacing: 5) {
            Circle()
              .fill(
                isConfigured
                  ? DesignTokens.Colors.success : DesignTokens.Colors.secondaryText.opacity(0.5)
              )
              .frame(width: 6, height: 6)
            Text(isConfigured ? "Configured" : "Needs setup")
              .font(.system(size: 10.5, weight: .semibold))
          }
          .foregroundStyle(
            isConfigured ? DesignTokens.Colors.success : DesignTokens.Colors.secondaryText
          )
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(
            (isConfigured ? DesignTokens.Colors.success : DesignTokens.Colors.secondaryText)
              .opacity(0.09), in: Capsule())
        }

        VStack(alignment: .leading, spacing: 9) {
          Text("WHAT IS THIS LEVEL?")
            .font(.system(size: 10.5, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          HStack(spacing: 8) {
            scheduleChoiceButton(
              title: "Class",
              subtitle: "Show a class name, teacher, and room",
              icon: "text.book.closed.fill",
              selected: !assignment.isFree,
              tint: DesignTokens.Colors.schedule
            ) {
              assignment.isFree = false
            }

            scheduleChoiceButton(
              title: "Free",
              subtitle: "Count this Level as open time",
              icon: "sparkles",
              selected: assignment.isFree,
              tint: DesignTokens.Colors.pacTrack
            ) {
              assignment.isFree = true
            }
          }
        }

        if !assignment.isFree {
          VStack(alignment: .leading, spacing: 12) {
            Text("CLASS DETAILS")
              .font(.system(size: 10.5, weight: .bold))
              .tracking(0.7)
              .foregroundStyle(DesignTokens.Colors.secondaryText)

            scheduleField(
              label: "Class name", placeholder: "e.g. English 10", icon: "text.book.closed",
              text: $assignment.title)

            ClassIconPicker(
              selection: $assignment.iconName,
              fallback: ClassIconOption.defaultOption(for: level),
              tint: assignment.color.swiftUIColor
            )

            HStack(spacing: 10) {
              scheduleField(
                label: "Teacher", placeholder: "Teacher name", icon: "person.fill",
                text: $assignment.teacher)
              scheduleField(
                label: "Room", placeholder: "e.g. U20", icon: "door.left.hand.open",
                text: $assignment.room
              )
              .frame(maxWidth: 190)
            }
          }
          .transition(.opacity)
        }

        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 5) {
            Text("CLASS COLOR")
              .font(.system(size: 10.5, weight: .bold))
              .tracking(0.7)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text("Used across Schedule and Today.")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          ColorPicker(
            "Color",
            selection: Binding(
              get: { assignment.color.swiftUIColor },
              set: { assignment.color = CodableColor($0) }
            )
          )
          .labelsHidden()
        }
        .padding(12)
        .background(
          DesignTokens.Colors.hover.opacity(0.30),
          in: RoundedRectangle(cornerRadius: 11, style: .continuous))

        if !assignment.isFree {
          Divider().overlay(DesignTokens.Colors.border)

          VStack(alignment: .leading, spacing: 11) {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("Meeting Pattern")
                  .font(.system(size: 13.5, weight: .semibold))
                Text(
                  "Most classes meet whenever their Level appears. Change this only if yours does not."
                )
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              }
              Spacer()
            }

            HStack(spacing: 8) {
              compactScheduleChoice(
                title: "Every scheduled day", icon: "calendar.badge.checkmark",
                selected: assignment.meetsEveryDay
              ) {
                assignment.meetsEveryDay = true
              }
              compactScheduleChoice(
                title: "Choose meeting days", icon: "calendar", selected: !assignment.meetsEveryDay
              ) {
                assignment.meetsEveryDay = false
              }
            }

            if !assignment.meetsEveryDay {
              VStack(alignment: .leading, spacing: 8) {
                Text("This class meets on")
                  .font(.system(size: 11.5, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)

                HStack(spacing: 7) {
                  ForEach(orderedMeetingDays, id: \.self) { idx in
                    let title = Calendar.current.shortWeekdaySymbols[idx - 1]
                    let selected = !assignment.daysNotMeeting.contains(idx)

                    Button {
                      withAnimation(DesignTokens.Animation.snappy) {
                        if selected {
                          assignment.daysNotMeeting.insert(idx)
                        } else {
                          assignment.daysNotMeeting.remove(idx)
                        }
                      }
                    } label: {
                      Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 31)
                        .contentShape(Rectangle())
                        .background(
                          selected
                            ? DesignTokens.Colors.schedule.opacity(0.15)
                            : DesignTokens.Colors.hover.opacity(0.36),
                          in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                          RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                              selected
                                ? DesignTokens.Colors.schedule.opacity(0.42)
                                : DesignTokens.Colors.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                  }
                }

                if !assignment.daysNotMeeting.isEmpty {
                  replacementEditor
                    .padding(.top, 4)
                }
              }
              .transition(.opacity)
            }
          }
        }
      }
      .padding(16)
      .rooSurface(cornerRadius: 16, elevated: false, border: true)
      .animation(.easeInOut(duration: 0.18), value: assignment.isFree)
      .animation(.easeInOut(duration: 0.18), value: assignment.meetsEveryDay)
    }

    private var replacementEditor: some View {
      let replacementFree = Binding<Bool>(
        get: { assignment.replacementClass?.isFree ?? true },
        set: { newValue in
          var replacement =
            assignment.replacementClass
            ?? ClassAssignment.ReplacementClass(title: "", teacher: "", room: "", isFree: true)
          replacement.isFree = newValue
          assignment.replacementClass = replacement
        }
      )

      return VStack(alignment: .leading, spacing: 11) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("On the other days")
              .font(.system(size: 13, weight: .semibold))
            Text("Choose whether those Level blocks are free or contain another class/activity.")
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          Spacer()
        }

        HStack(spacing: 8) {
          compactScheduleChoice(
            title: "Free time", icon: "sparkles", selected: replacementFree.wrappedValue
          ) {
            replacementFree.wrappedValue = true
          }
          compactScheduleChoice(
            title: "Something else", icon: "arrow.triangle.swap",
            selected: !replacementFree.wrappedValue
          ) {
            replacementFree.wrappedValue = false
          }
        }

        if !replacementFree.wrappedValue {
          scheduleField(
            label: "Name",
            placeholder: "Class or activity",
            icon: "rectangle.and.pencil.and.ellipsis",
            text: Binding(
              get: { assignment.replacementClass?.title ?? "" },
              set: { value in
                var replacement =
                  assignment.replacementClass
                  ?? ClassAssignment.ReplacementClass(
                    title: "", teacher: "", room: "", isFree: false)
                replacement.title = value
                assignment.replacementClass = replacement
              }
            )
          )

          HStack(spacing: 10) {
            scheduleField(
              label: "Teacher",
              placeholder: "Teacher name",
              icon: "person.fill",
              text: Binding(
                get: { assignment.replacementClass?.teacher ?? "" },
                set: { value in
                  var replacement =
                    assignment.replacementClass
                    ?? ClassAssignment.ReplacementClass(
                      title: "", teacher: "", room: "", isFree: false)
                  replacement.teacher = value
                  assignment.replacementClass = replacement
                }
              )
            )
            scheduleField(
              label: "Room",
              placeholder: "Room",
              icon: "door.left.hand.open",
              text: Binding(
                get: { assignment.replacementClass?.room ?? "" },
                set: { value in
                  var replacement =
                    assignment.replacementClass
                    ?? ClassAssignment.ReplacementClass(
                      title: "", teacher: "", room: "", isFree: false)
                  replacement.room = value
                  assignment.replacementClass = replacement
                }
              )
            )
            .frame(maxWidth: 190)
          }
        }
      }
      .padding(12)
      .background(
        DesignTokens.Colors.schedule.opacity(0.055),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(DesignTokens.Colors.schedule.opacity(0.20), lineWidth: 1)
      }
    }

    private func scheduleChoiceButton(
      title: String, subtitle: String, icon: String, selected: Bool, tint: Color,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(tint.opacity(selected ? 0.18 : 0.08))
            Image(systemName: icon)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(selected ? tint : DesignTokens.Colors.secondaryText)
          }
          .frame(width: 32, height: 32)

          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 12.5, weight: .semibold))
            Text(subtitle)
              .font(.system(size: 10.5, weight: .regular))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(2)
          }

          Spacer(minLength: 0)

          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(selected ? tint : DesignTokens.Colors.secondaryText.opacity(0.65))
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .background(
          selected ? tint.opacity(0.09) : DesignTokens.Colors.hover.opacity(0.28),
          in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(selected ? tint.opacity(0.42) : DesignTokens.Colors.border, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }

    private func compactScheduleChoice(
      title: String, icon: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 7) {
          Image(systemName: icon)
            .font(.system(size: 11.5, weight: .semibold))
          Text(title)
            .font(.system(size: 11.5, weight: .semibold))
          Spacer(minLength: 0)
          if selected {
            Image(systemName: "checkmark")
              .font(.system(size: 10, weight: .bold))
          }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .contentShape(Rectangle())
        .foregroundStyle(selected ? DesignTokens.Colors.schedule : .primary)
        .background(
          selected
            ? DesignTokens.Colors.schedule.opacity(0.11) : DesignTokens.Colors.hover.opacity(0.30),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(
              selected ? DesignTokens.Colors.schedule.opacity(0.35) : DesignTokens.Colors.border,
              lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
    }

    private func scheduleField(
      label: String, placeholder: String, icon: String, text: Binding<String>
    ) -> some View {
      VStack(alignment: .leading, spacing: 5) {
        Text(label)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        HStack(spacing: 8) {
          Image(systemName: icon)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.schedule)
            .frame(width: 16)

          TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
          DesignTokens.Colors.hover.opacity(0.36),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
        }
      }
      .frame(maxWidth: .infinity)
    }
  }

  struct ClassIconPicker: View {
    @Binding var selection: String
    let fallback: ClassIconOption
    let tint: Color

    @State private var isShowingPicker = false

    private var selectedOption: ClassIconOption {
      ClassIconOption(rawValue: selection) ?? fallback
    }

    private let core: [ClassIconOption] = [.general, .reading, .writing, .discussion]
    private let stem: [ClassIconOption] = [.math, .science, .technology, .engineering, .data]
    private let humanities: [ClassIconOption] = [.history, .world, .language]
    private let creative: [ClassIconOption] = [.art, .music, .theater, .photography]
    private let other: [ClassIconOption] = [.health, .physicalEducation, .environment, .graduation]

    var body: some View {
      Button {
        isShowingPicker = true
      } label: {
        HStack(spacing: 11) {
          ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(tint.opacity(0.13))

            Image(systemName: selectedOption.systemImage)
              .font(.system(size: 15.5, weight: .semibold))
              .foregroundStyle(tint)
          }
          .frame(width: 38, height: 38)

          VStack(alignment: .leading, spacing: 2) {
            Text("Class icon")
              .font(.system(size: 11.5, weight: .semibold))

            Text("\(selectedOption.title) · Used anywhere this class appears")
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          Spacer(minLength: 8)

          HStack(spacing: 6) {
            Text("Choose")
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .bold))
          }
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(tint)
          .padding(.horizontal, 10)
          .frame(height: 31)
          .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .strokeBorder(tint.opacity(0.24), lineWidth: 1)
          }
        }
        .padding(10)
        .contentShape(Rectangle())
        .background(
          DesignTokens.Colors.hover.opacity(0.22),
          in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
        }
      }
      .buttonStyle(.plain)
      .popover(isPresented: $isShowingPicker, arrowEdge: .trailing) {
        iconPickerPopover
      }
    }

    private var iconPickerPopover: some View {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(tint.opacity(0.14))

            Image(systemName: selectedOption.systemImage)
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(tint)
          }
          .frame(width: 42, height: 42)

          VStack(alignment: .leading, spacing: 2) {
            Text("Choose a class icon")
              .font(.system(size: 15, weight: .semibold))
            Text("The icon updates everywhere this class appears in RooMate.")
              .font(.system(size: 10.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer(minLength: 8)

          Button {
            isShowingPicker = false
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 10, weight: .bold))
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(DesignTokens.Colors.hover.opacity(0.40), in: Circle())
        }

        Divider()
          .overlay(DesignTokens.Colors.border)

        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            iconGridSection("SCHOOL", options: core)
            iconGridSection("STEM", options: stem)
            iconGridSection("HUMANITIES", options: humanities)
            iconGridSection("CREATIVE", options: creative)
            iconGridSection("MORE", options: other)
          }
          .padding(.trailing, 3)
        }

        Divider()
          .overlay(DesignTokens.Colors.border)

        HStack {
          Text("Selected: \(selectedOption.title)")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)

          Spacer()

          Button {
            selection = fallback.systemImage
            isShowingPicker = false
          } label: {
            Label("Use Level Default", systemImage: "arrow.counterclockwise")
              .font(.system(size: 10.5, weight: .semibold))
              .padding(.horizontal, 10)
              .frame(height: 30)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            DesignTokens.Colors.hover.opacity(0.38),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
          }
        }
      }
      .padding(16)
      .frame(width: 450, height: 520)
      .background(DesignTokens.Colors.surface)
    }

    @ViewBuilder
    private func iconGridSection(_ title: String, options: [ClassIconOption]) -> some View {
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.system(size: 9.5, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 74, maximum: 86), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(options) { option in
            iconOptionButton(option)
          }
        }
      }
    }

    private func iconOptionButton(_ option: ClassIconOption) -> some View {
      let isSelected = selectedOption == option

      return Button {
        selection = option.systemImage
        isShowingPicker = false
      } label: {
        VStack(spacing: 7) {
          ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(isSelected ? tint.opacity(0.16) : DesignTokens.Colors.hover.opacity(0.34))

            Image(systemName: option.systemImage)
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(isSelected ? tint : DesignTokens.Colors.primaryText.opacity(0.82))
              .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isSelected {
              Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .background(DesignTokens.Colors.surface, in: Circle())
                .padding(5)
            }
          }
          .frame(height: 48)

          Text(option.title)
            .font(.system(size: 9.5, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? tint : DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(
          isSelected ? tint.opacity(0.07) : Color.clear,
          in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
              isSelected ? tint.opacity(0.44) : DesignTokens.Colors.border,
              lineWidth: 1
            )
        }
      }
      .buttonStyle(.plain)
      .help(option.title)
    }
  }

  struct ClubEditorRow: View {
    @Binding var club: Club
    let onDelete: () -> Void

    private var accent: Color { club.displayColor }

    private var meetingSummary: String {
      var parts: [String] = []
      let builtInCount = (club.meetsMondayClub ? 1 : 0) + (club.meetsWednesdayClub ? 1 : 0)

      if builtInCount > 0 {
        parts.append("\(builtInCount) built-in")
      }
      if !club.blockMeetings.isEmpty {
        parts.append(
          "\(club.blockMeetings.count) schedule block\(club.blockMeetings.count == 1 ? "" : "s")")
      }
      if !club.otherMeetings.isEmpty {
        parts.append("\(club.otherMeetings.count) extra")
      }

      return parts.isEmpty ? "No meeting times selected" : parts.joined(separator: " • ")
    }

    private var colorBinding: Binding<Color> {
      Binding(
        get: { club.displayColor },
        set: { club.color = CodableColor($0) }
      )
    }

    var body: some View {
      VStack(alignment: .leading, spacing: 14) {
        identityHeader

        Divider().overlay(DesignTokens.Colors.border)

        builtInPeriodsSection
        exactBlocksSection
        extraMeetingsSection
        notesSection
      }
      .padding(14)
      .rooSurface(cornerRadius: 15, elevated: false, border: true)
    }

    private var identityHeader: some View {
      HStack(alignment: .top, spacing: 11) {
        ZStack {
          RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(accent.opacity(0.14))
          Image(systemName: club.displayIconName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accent)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 7) {
          TextField("Club name", text: $club.name)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5, weight: .semibold))

          HStack(spacing: 8) {
            HStack(spacing: 6) {
              Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
              TextField("Room or location", text: $club.room)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
            }
            .padding(.horizontal, 9)
            .frame(height: 31)
            .background(
              DesignTokens.Colors.hover.opacity(0.24),
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )

            Picker("Icon", selection: $club.iconName) {
              ForEach(ClubIconOption.allCases) { option in
                Label(option.title, systemImage: option.systemImage)
                  .tag(option.systemImage)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 142)

            ColorPicker(
              "Club color",
              selection: colorBinding,
              supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 32)
            .help("Club color")
          }

          Text(meetingSummary)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }

        Spacer(minLength: 8)

        Button(role: .destructive, action: onDelete) {
          Image(systemName: "trash")
            .font(.system(size: 11.5, weight: .semibold))
            .frame(width: 31, height: 31)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete club")
      }
    }

    private var builtInPeriodsSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Built-in club periods")
            .font(.system(size: 12, weight: .semibold))
          Text("Use these for the school’s dedicated Monday and Wednesday club periods.")
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        HStack(spacing: 8) {
          clubPeriodButton(
            title: "Monday",
            subtitle: "Music Block + Clubs",
            icon: "music.note.list",
            selected: club.meetsMondayClub
          ) {
            club.meetsMondayClub.toggle()
          }

          clubPeriodButton(
            title: "Wednesday",
            subtitle: "Lunch & Clubs",
            icon: "fork.knife.circle",
            selected: club.meetsWednesdayClub
          ) {
            club.meetsWednesdayClub.toggle()
          }
        }
      }
    }

    private var exactBlocksSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Schedule blocks")
              .font(.system(size: 12, weight: .semibold))
            Text(
              "Place this club on any Level or school block. RooMate will show the club instead of that block on the selected day."
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 12)

          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              addBlockMeeting()
            }
          } label: {
            Label("Add Block", systemImage: "plus")
              .font(.system(size: 10.5, weight: .semibold))
              .padding(.horizontal, 9)
              .frame(height: 29)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(accent.opacity(0.25), lineWidth: 1)
          }
        }

        if club.blockMeetings.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            VStack(alignment: .leading, spacing: 1) {
              Text("No schedule blocks added")
                .font(.system(size: 10.5, weight: .medium))
              Text("Example: Tuesday • Level 4, or Thursday • Office Hours")
                .font(.system(size: 9.5))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
          }
          .padding(.horizontal, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(minHeight: 42)
          .background(
            DesignTokens.Colors.hover.opacity(0.24),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
        } else {
          VStack(spacing: 7) {
            ForEach(club.blockMeetings) { meeting in
              exactBlockRow(binding(for: meeting.id))
            }
          }
        }
      }
    }

    private func exactBlockRow(_ meeting: Binding<Club.BlockMeeting>) -> some View {
      let weekday = meeting.wrappedValue.weekday
      let options = blockOptions(for: weekday)

      return HStack(spacing: 8) {
        Picker(
          "Day",
          selection: Binding(
            get: { meeting.wrappedValue.weekday },
            set: { newWeekday in
              var updated = meeting.wrappedValue
              updated.weekday = newWeekday

              let validOptions = blockOptions(for: newWeekday)
              if !validOptions.contains(updated.block),
                let fallback = defaultBlock(for: newWeekday)
              {
                updated.block = fallback
              }

              meeting.wrappedValue = updated
            }
          )
        ) {
          ForEach(Weekday.allCases) { day in
            Text(day.title)
              .tag(day.calendarWeekdayIndex)
          }
        }
        .labelsHidden()
        .frame(width: 112)

        Picker("Block", selection: meeting.block) {
          ForEach(options, id: \.self) { kind in
            Label(blockTitle(kind), systemImage: blockIcon(kind))
              .tag(kind)
          }
        }
        .labelsHidden()
        .frame(minWidth: 190, maxWidth: .infinity)

        Text(blockTime(kind: meeting.wrappedValue.block, weekday: weekday))
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .frame(width: 92, alignment: .trailing)

        Button(role: .destructive) {
          withAnimation(DesignTokens.Animation.snappy) {
            club.blockMeetings.removeAll { $0.id == meeting.wrappedValue.id }
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 9.5, weight: .bold))
            .frame(width: 27, height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 9)
      .frame(height: 42)
      .background(
        accent.opacity(0.055),
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(accent.opacity(0.20), lineWidth: 1)
      }
    }

    private var extraMeetingsSection: some View {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("Other and after-school meetings")
              .font(.system(size: 12, weight: .semibold))
            Text(
              "These appear alongside the regular schedule, can happen after school, and may overlap another block."
            )
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              club.otherMeetings.append(Club.OtherMeeting())
            }
          } label: {
            Label("Add", systemImage: "plus")
              .font(.system(size: 10.5, weight: .semibold))
              .padding(.horizontal, 9)
              .frame(height: 29)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .background(
            accent.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .strokeBorder(accent.opacity(0.25), lineWidth: 1)
          }
        }

        if club.otherMeetings.isEmpty {
          HStack(spacing: 8) {
            Image(systemName: "calendar.badge.plus")
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text("No other meetings added")
              .font(.system(size: 10.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
          .padding(.horizontal, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 36)
          .background(
            DesignTokens.Colors.hover.opacity(0.24),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
        } else {
          VStack(spacing: 7) {
            ForEach($club.otherMeetings) { $meeting in
              HStack(spacing: 8) {
                Picker("Day", selection: $meeting.weekday) {
                  ForEach(1...7, id: \.self) { idx in
                    Text(Calendar.current.shortWeekdaySymbols[idx - 1]).tag(idx)
                  }
                }
                .labelsHidden()
                .frame(width: 86)

                DatePicker("", selection: $meeting.startTime, displayedComponents: .hourAndMinute)
                  .labelsHidden()
                  .frame(width: 90)

                Text("to")
                  .font(.system(size: 10))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)

                DatePicker("", selection: $meeting.endTime, displayedComponents: .hourAndMinute)
                  .labelsHidden()
                  .frame(width: 90)

                Spacer(minLength: 4)

                Button(role: .destructive) {
                  withAnimation(DesignTokens.Animation.snappy) {
                    club.otherMeetings.removeAll { $0.id == meeting.id }
                  }
                } label: {
                  Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .frame(width: 27, height: 27)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
              .padding(.horizontal, 9)
              .frame(height: 42)
              .background(
                DesignTokens.Colors.hover.opacity(0.25),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
              }
            }
          }
        }
      }
    }

    private var notesSection: some View {
      VStack(alignment: .leading, spacing: 5) {
        Text("NOTES")
          .font(.system(size: 10, weight: .bold))
          .tracking(0.6)
          .foregroundStyle(DesignTokens.Colors.secondaryText)

        TextField("Optional notes about this club", text: $club.otherDaysNote)
          .textFieldStyle(.plain)
          .font(.system(size: 11.5, weight: .medium))
          .padding(.horizontal, 10)
          .frame(height: 34)
          .background(
            DesignTokens.Colors.hover.opacity(0.28),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
          }
      }
    }

    private func binding(for id: UUID) -> Binding<Club.BlockMeeting> {
      Binding(
        get: {
          club.blockMeetings.first(where: { $0.id == id })
            ?? Club.BlockMeeting(id: id)
        },
        set: { updated in
          guard let index = club.blockMeetings.firstIndex(where: { $0.id == id }) else {
            return
          }
          club.blockMeetings[index] = updated
        }
      )
    }

    private func addBlockMeeting() {
      let weekday = Weekday.monday.calendarWeekdayIndex
      let block = defaultBlock(for: weekday) ?? .level(.level1)
      club.blockMeetings.append(
        Club.BlockMeeting(weekday: weekday, block: block)
      )
    }

    private func weekday(for calendarIndex: Int) -> Weekday? {
      switch calendarIndex {
      case 2: .monday
      case 3: .tuesday
      case 4: .wednesday
      case 5: .thursday
      case 6: .friday
      default: nil
      }
    }

    private func blockOptions(for calendarIndex: Int) -> [BlockKind] {
      guard let weekday = weekday(for: calendarIndex),
        let blocks = BellSchedule.weekly[weekday]
      else {
        return []
      }

      var seen = Set<BlockKind>()
      return blocks.compactMap { block in
        seen.insert(block.kind).inserted ? block.kind : nil
      }
    }

    private func defaultBlock(for calendarIndex: Int) -> BlockKind? {
      let options = blockOptions(for: calendarIndex)
      return options.first(where: {
        if case .level = $0 { return true }
        return false
      }) ?? options.first
    }

    private func blockTitle(_ kind: BlockKind) -> String {
      switch kind {
      case .level(let level):
        level.displayName
      case .special(let special):
        special.title
      case .custom(let title):
        title
      }
    }

    private func blockIcon(_ kind: BlockKind) -> String {
      switch kind {
      case .level(let level):
        ClassIconOption.defaultOption(for: level).systemImage
      case .special(let special):
        special.systemImage
      case .custom:
        "calendar.badge.clock"
      }
    }

    private func blockTime(kind: BlockKind, weekday calendarIndex: Int) -> String {
      guard let weekday = weekday(for: calendarIndex),
        let block = BellSchedule.weekly[weekday]?.first(where: { $0.kind == kind })
      else {
        return ""
      }

      return "\(shortTime(block.start))–\(shortTime(block.end))"
    }

    private func shortTime(_ components: DateComponents) -> String {
      let hour24 = components.hour ?? 0
      let minute = components.minute ?? 0
      let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
      return minute == 0
        ? "\(hour12)"
        : String(format: "%d:%02d", hour12, minute)
    }

    private func clubPeriodButton(
      title: String,
      subtitle: String,
      icon: String,
      selected: Bool,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 9) {
          ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(
                selected
                  ? accent.opacity(0.16)
                  : DesignTokens.Colors.hover.opacity(0.32)
              )
            Image(systemName: icon)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(
                selected
                  ? accent
                  : DesignTokens.Colors.secondaryText
              )
          }
          .frame(width: 32, height: 32)

          VStack(alignment: .leading, spacing: 2) {
            Text(title)
              .font(.system(size: 11.5, weight: .semibold))
            Text(subtitle)
              .font(.system(size: 9.5))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          Spacer(minLength: 4)

          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(
              selected
                ? accent
                : DesignTokens.Colors.secondaryText.opacity(0.6)
            )
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .contentShape(Rectangle())
        .background(
          selected ? accent.opacity(0.08) : Color.clear,
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
              selected ? accent.opacity(0.34) : DesignTokens.Colors.border,
              lineWidth: 1
            )
        }
      }
      .buttonStyle(.plain)
    }
  }

#endif
