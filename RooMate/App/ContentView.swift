import Combine
import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(ServiceManagement)
  import ServiceManagement
#endif
#if canImport(UIKit)
  import UIKit
#endif
#if canImport(UserNotifications)
  import UserNotifications
#endif

struct ContentView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var store = UserScheduleStore.shared
  @StateObject private var sportsStore = SportsStore()
  @StateObject private var eventsStore = EventsStore()
  @StateObject private var menuStore = MenuStore()
  let checkForUpdatesAction: (() -> Void)?
  @State private var selectedTab: Tab = .dashboard
  @State private var updateTrigger = UUID()
  @State private var showSearch = false
  @State private var showWhatsNew = false
  @AppStorage("RooMateLastAcknowledgedWhatsNewVersion")
  private var lastAcknowledgedWhatsNewVersion = ""
  @State private var hoveredSidebarTab: Tab?
  @State private var isEditingSidebar = false
  @State private var draggingSidebarTab: Tab?
  @State private var sidebarDropTarget: Tab?
  @AppStorage("RooMateFloatingTimerEnabled")
  private var floatingTimerEnabled = false

  // V6 onboarding is shown only to genuinely new RooMate installs.
  // Existing users are migrated once and keep going straight into the app,
  // while a partially-completed onboarding session resumes at its last step.
  @AppStorage("RooMateV6OnboardingCompleted")
  private var v6OnboardingCompleted = false
  @AppStorage("RooMateV6OnboardingMigrationChecked")
  private var v6OnboardingMigrationChecked = false
  @AppStorage("RooMateV6OnboardingStep")
  private var v6OnboardingStep = 0
  @State private var onboardingRoutingReady = false

  #if canImport(AppKit)
    // The macOS sidebar is user-resizable and its width is remembered between launches.
    // Keeping a real minimum width lets every sidebar control stay fully visible instead
    // of relying on screenshot-specific offsets that can clip at smaller sizes.
    @AppStorage("RooMateMacSidebarWidth")
    private var storedMacSidebarWidth: Double = 260
    @State private var macSidebarResizeStartWidth: CGFloat?

    private let macSidebarMinimumWidth: CGFloat = 250
    private let macSidebarDefaultWidth: CGFloat = 260
    private let macSidebarMaximumWidth: CGFloat = 360
    private let macSidebarHorizontalInset: CGFloat = 12

    private var macSidebarWidth: CGFloat {
      min(
        max(CGFloat(storedMacSidebarWidth), macSidebarMinimumWidth),
        macSidebarMaximumWidth
      )
    }
  #endif

  @State private var scheduleFocusMode = false

  @State private var selectedDay: Weekday = {
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: Date())
    switch weekday {
    case 2: return .monday
    case 3: return .tuesday
    case 4: return .wednesday
    case 5: return .thursday
    case 6: return .friday
    default: return .monday
    }
  }()

  init(checkForUpdatesAction: (() -> Void)? = nil) {
    self.checkForUpdatesAction = checkForUpdatesAction
  }

  // Compute the next calendar date that corresponds to the selected weekday
  private func nextDate(for weekday: Weekday, from reference: Date = Date()) -> Date {
    let cal = Calendar.current
    let weekdayMap: [Weekday: Int] = [
      .monday: 2, .tuesday: 3, .wednesday: 4, .thursday: 5, .friday: 6,
    ]
    let target = weekdayMap[weekday] ?? 2
    let today = cal.component(.weekday, from: reference)
    var delta = target - today
    if delta < 0 { delta += 7 }
    return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: reference)) ?? reference
  }

  // Blocks for the selected day
  private var blocksForSelectedDay: [BellBlock] {
    store.bellBlocks(for: nextDate(for: selectedDay))
  }

  private func preferredColorScheme(for appearance: AppearancePreference) -> ColorScheme? {
    switch appearance {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }

  // Derived sidebar/tab ordering based on user preferences
  private var sidebarAllTabsInOrder: [Tab] {
    let defaultIDs = [
      Tab.dashboard, .schedule, .menu, .athletics, .clubs, .events,
      .rooPAC, .profile, .links, .settings,
    ].map { $0.title }

    var storedOrder =
      store.sidebarOrder.isEmpty
      ? defaultIDs
      : store.sidebarOrder

    if !storedOrder.contains(Tab.clubs.title) {
      if let sportsIndex = storedOrder.firstIndex(of: Tab.athletics.title) {
        storedOrder.insert(Tab.clubs.title, at: storedOrder.index(after: sportsIndex))
      } else {
        storedOrder.append(Tab.clubs.title)
      }
    }

    func tabForID(_ id: String) -> Tab? {
      Tab.allCases.first(where: { $0.title == id })
    }

    var ordered: [Tab] = []

    for id in storedOrder {
      if let tab = tabForID(id), !ordered.contains(tab) {
        ordered.append(tab)
      }
    }

    for tab in Tab.allCases where !ordered.contains(tab) {
      ordered.append(tab)
    }

    return ordered
  }

  private var requiredSidebarTabs: Set<Tab> {
    [.schedule, .settings]
  }

  private var sidebarOrderedTabs: [Tab] {
    sidebarAllTabsInOrder.filter {
      requiredSidebarTabs.contains($0) || !store.sidebarHidden.contains($0.title)
    }
  }

  private var hasConfiguredSchedule: Bool {
    Level.allCases.contains { level in
      let assignment = store.assignments[level] ?? .default(for: level)
      let trimmed = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
      return assignment.isFree || (!trimmed.isEmpty && trimmed != level.displayName)
    }
  }

  private var sidebarPinnedTabs: [Tab] {
    sidebarOrderedTabs.filter { store.sidebarFavorites.contains($0.title) }
  }

  private var sidebarUnpinnedTabs: [Tab] {
    sidebarOrderedTabs.filter { !store.sidebarFavorites.contains($0.title) }
  }

  // MARK: - Sidebar current/next helpers
  private struct DatedBlock: Identifiable {
    let id = UUID()
    let original: BellBlock
    let startDate: Date
    let endDate: Date
  }

  private func datedBlocksForToday(reference: Date = Date()) -> [DatedBlock] {
    let cal = Calendar.current
    let startOfDay = cal.startOfDay(for: reference)
    let list: [DatedBlock] = store.bellBlocks(for: reference).compactMap {
      (block: BellBlock) -> DatedBlock? in
      guard block.isPrimaryTimelineBlock else { return nil }
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
    return list
  }

  private func weekdayForDate(_ date: Date) -> Weekday {
    let cal = Calendar.current
    switch cal.component(.weekday, from: date) {
    case 2: return .monday
    case 3: return .tuesday
    case 4: return .wednesday
    case 5: return .thursday
    case 6: return .friday
    default: return .monday
    }
  }

  private func blockTitleColorSubtitle(for block: BellBlock, on weekday: Weekday) -> (
    title: String, color: Color, subtitle: String, level: Level?, specialLabel: String?
  ) {
    let presentation = store.schedulePresentation(for: block, on: weekday)

    switch block.kind {
    case .level(let level):
      return (presentation.title, presentation.color, presentation.subtitle, level, nil)
    case .special(let special):
      return (presentation.title, presentation.color, presentation.subtitle, nil, special.title)
    case .custom:
      return (
        presentation.title, presentation.color, presentation.subtitle, nil, "Special Schedule"
      )
    }
  }

  private func sidebarHeaderInfo() -> (
    title: String, subtitle: String, color: Color, progress: Double, remainingText: String,
    nextTitle: String?, nextStartText: String?, nextColor: Color?, nextLevel: Level?,
    nextSpecialLabel: String?, isCountdownMode: Bool
  )? {
    let now = Date()
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: now)
    guard (2...6).contains(weekday) else { return nil }

    let list = datedBlocksForToday(reference: now)
    guard !list.isEmpty else { return nil }

    let boundaryTolerance: TimeInterval = 1.0
    let ref = now

    var current: DatedBlock?
    var next: DatedBlock?

    for (idx, item) in list.enumerated() {
      if (ref >= item.startDate.addingTimeInterval(-boundaryTolerance))
        && (ref < item.endDate.addingTimeInterval(boundaryTolerance))
      {
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

      let weekday = store.scheduleWeekday(for: ref) ?? weekdayForDate(ref)
      let (title, color, subtitle, _, _) = blockTitleColorSubtitle(
        for: current.original, on: weekday)
      let remainingText = formatDuration(remaining)

      var nextTitleStr: String?
      var nextStartText: String?
      var nextColor: Color?
      var nextLevel: Level?
      var nextSpecialLabel: String?
      if let next {
        let (ntitle, ncolor, _, nlevel, nspecialLabel) = blockTitleColorSubtitle(
          for: next.original, on: weekday)
        nextTitleStr = ntitle
        nextColor = ncolor
        nextLevel = nlevel
        nextSpecialLabel = nspecialLabel
        nextStartText = df.string(from: next.startDate)
      }

      return (
        title, subtitle, color, progress, remainingText, nextTitleStr, nextStartText, nextColor,
        nextLevel, nextSpecialLabel, false
      )
    }

    if let next {
      let list = datedBlocksForToday(reference: ref)
      var anchor: Date = Calendar.current.startOfDay(for: next.startDate)
      if let idx = list.firstIndex(where: { $0.id == next.id }), idx > 0 {
        anchor = list[idx - 1].endDate
      }

      let remaining: TimeInterval = max(0.0, next.startDate.timeIntervalSince(ref))
      let totalGap: TimeInterval = max(1.0, next.startDate.timeIntervalSince(anchor))
      let elapsedGap: TimeInterval = max(0.0, ref.timeIntervalSince(anchor))
      let progress = max(0.0, min(1.0, elapsedGap / totalGap))

      let weekday = store.scheduleWeekday(for: ref) ?? weekdayForDate(ref)
      let (ntitle, ncolor, _, nlevel, nspecialLabel) = blockTitleColorSubtitle(
        for: next.original, on: weekday)

      return (
        "No class right now", "Starts soon", .secondary, progress, formatDuration(remaining),
        ntitle, df.string(from: next.startDate), ncolor, nlevel, nspecialLabel, true
      )
    }

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

  @ViewBuilder
  private var sidebarNowCard: some View {
    if let info = sidebarHeaderInfo() {
      Button(action: { selectedTab = .schedule }) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
          HStack {
            Text(info.isCountdownMode ? "UP NEXT" : "NOW")
              .font(.system(size: 9, weight: .semibold))
              .tracking(0.8)
              .foregroundStyle(info.isCountdownMode ? DesignTokens.Colors.today : info.color)
            Spacer()
            Text(
              info.isCountdownMode
                ? info.remainingText
                : "\(Int((info.progress * 100).rounded()))% · \(info.remainingText)"
            )
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Text(info.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)

          if !info.subtitle.isEmpty {
            Text(info.subtitle)
              .font(.system(size: 10))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          ProgressView(value: info.progress)
            .tint(info.isCountdownMode ? DesignTokens.Colors.today : info.color)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rooGlass(cornerRadius: 13)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Open Schedule")
      .id(updateTrigger)
    }
  }

  #if canImport(AppKit)
    private var macSidebarQuickActions: some View {
      HStack(spacing: 7) {
        Button {
          scheduleFocusMode = true
          selectedTab = .schedule
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "rectangle.center.inset.filled")
              .font(.system(size: 10.5, weight: .semibold))
            Text("Focus")
              .font(.system(size: 10.5, weight: .semibold))
          }
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .frame(maxWidth: .infinity)
          .frame(height: 32)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 9)
        .help("Open Schedule in Focus mode")

        Button {
          showSearch = true
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 10.5, weight: .semibold))
            Text("Search")
              .font(.system(size: 10.5, weight: .semibold))
          }
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .frame(maxWidth: .infinity)
          .frame(height: 32)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 9)
        .help("Search RooMate")
      }
    }

    private var macPinnedTabs: [Tab] {
      sidebarPinnedTabs.filter { $0 != .profile }
    }

    private var macMainTabs: [Tab] {
      sidebarUnpinnedTabs.filter {
        $0 != .profile && $0 != .links && $0 != .settings
      }
    }

    private var macUtilityTabs: [Tab] {
      sidebarUnpinnedTabs.filter {
        $0 == .links || $0 == .settings
      }
    }

    private func ensureSidebarOrderInitialized() {
      let completeOrder = sidebarAllTabsInOrder.map(\.title)
      let storedSet = Set(store.sidebarOrder)
      let completeSet = Set(completeOrder)

      if store.sidebarOrder.isEmpty || storedSet != completeSet {
        store.sidebarOrder = completeOrder
      }

      // Schedule and Settings are core navigation destinations and must
      // always remain reachable, even if an older build persisted them as hidden.
      let protectedIDs = Set(requiredSidebarTabs.map(\.title))
      if !store.sidebarHidden.isDisjoint(with: protectedIDs) {
        store.sidebarHidden.subtract(protectedIDs)
      }
    }

    private func toggleSidebarPin(_ tab: Tab) {
      ensureSidebarOrderInitialized()

      withAnimation(DesignTokens.Animation.snappy) {
        if store.sidebarFavorites.contains(tab.title) {
          store.sidebarFavorites.remove(tab.title)
        } else {
          store.sidebarFavorites.insert(tab.title)
        }
      }
    }

    private func toggleSidebarVisibility(_ tab: Tab) {
      ensureSidebarOrderInitialized()
      guard !requiredSidebarTabs.contains(tab) else { return }

      withAnimation(DesignTokens.Animation.snappy) {
        if store.sidebarHidden.contains(tab.title) {
          store.sidebarHidden.remove(tab.title)
        } else {
          store.sidebarHidden.insert(tab.title)

          if selectedTab == tab {
            selectedTab =
              sidebarAllTabsInOrder.first(where: {
                $0 != tab && !store.sidebarHidden.contains($0.title)
              }) ?? .dashboard
          }
        }
      }
    }

    private func moveSidebarTab(_ dragged: Tab, before target: Tab) {
      guard dragged != target else { return }

      ensureSidebarOrderInitialized()
      var order = store.sidebarOrder

      guard let draggedIndex = order.firstIndex(of: dragged.title) else {
        return
      }

      order.remove(at: draggedIndex)

      guard let targetIndex = order.firstIndex(of: target.title) else {
        return
      }

      order.insert(dragged.title, at: targetIndex)

      if order != store.sidebarOrder {
        store.sidebarOrder = order
      }
    }

    private func setSidebarEditing(_ editing: Bool) {
      ensureSidebarOrderInitialized()

      withAnimation(DesignTokens.Animation.snappy) {
        isEditingSidebar = editing

        if !editing {
          draggingSidebarTab = nil
          sidebarDropTarget = nil
        }
      }
    }

    private var macSidebar: some View {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
          Image("RooMark")
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

          Text(DesignTokens.Brand.name)
            .font(DesignTokens.Typography.appTitle)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
            .layoutPriority(1)

          Spacer(minLength: 4)

          if !isEditingSidebar {
            Button {
              withAnimation(DesignTokens.Animation.quick) {
                floatingTimerEnabled.toggle()
              }
            } label: {
              Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                  floatingTimerEnabled
                    ? DesignTokens.Colors.schedule
                    : DesignTokens.Colors.secondaryText
                )
                .frame(width: 30, height: 30)
                .background(
                  floatingTimerEnabled
                    ? DesignTokens.Colors.schedule.opacity(0.10)
                    : DesignTokens.Colors.sidebarHover.opacity(0.55),
                  in: RoundedRectangle(
                    cornerRadius: 9,
                    style: .continuous
                  )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(
              floatingTimerEnabled
                ? "Hide Floating Timer"
                : "Show Floating Timer"
            )
          }

          Button {
            setSidebarEditing(!isEditingSidebar)
          } label: {
            Group {
              if isEditingSidebar {
                Text("Done")
                  .font(
                    .system(
                      size: 10.5,
                      weight: .semibold
                    )
                  )
                  .foregroundStyle(
                    DesignTokens.Colors.schedule
                  )
                  .frame(width: 44, height: 30)
              } else {
                Image(systemName: "slider.horizontal.3")
                  .font(
                    .system(
                      size: 10,
                      weight: .semibold
                    )
                  )
                  .foregroundStyle(
                    DesignTokens.Colors.secondaryText
                  )
                  .frame(width: 30, height: 30)
              }
            }
            .contentShape(
              RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
              )
            )
            .background(
              isEditingSidebar
                ? DesignTokens.Colors.schedule.opacity(0.10)
                : DesignTokens.Colors.sidebarHover.opacity(0.55),
              in: RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
              )
            )
            .overlay {
              if isEditingSidebar {
                RoundedRectangle(
                  cornerRadius: 9,
                  style: .continuous
                )
                .strokeBorder(
                  DesignTokens.Colors.schedule.opacity(0.20),
                  lineWidth: 1
                )
              }
            }
          }
          .buttonStyle(.plain)
          .fixedSize()
          .help(
            isEditingSidebar
              ? "Finish editing sidebar"
              : "Edit sidebar"
          )
          .animation(
            DesignTokens.Animation.quick,
            value: isEditingSidebar
          )
        }
        .padding(.horizontal, macSidebarHorizontalInset)
        .padding(.top, 18)
        .padding(.bottom, isEditingSidebar ? 12 : 18)

        if isEditingSidebar {
          sidebarEditor
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
          VStack(alignment: .leading, spacing: 5) {
            if !macPinnedTabs.isEmpty {
              ForEach(macPinnedTabs, id: \.self) { tab in
                macSidebarButton(tab)
              }

              if !macMainTabs.isEmpty || !macUtilityTabs.isEmpty {
                Divider()
                  .opacity(0.30)
                  .padding(.vertical, 7)
              }
            }

            ForEach(macMainTabs, id: \.self) { tab in
              macSidebarButton(tab)
            }

            if !macUtilityTabs.isEmpty {
              Divider()
                .opacity(0.35)
                .padding(.vertical, 8)

              ForEach(macUtilityTabs, id: \.self) { tab in
                macSidebarButton(tab)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.horizontal, macSidebarHorizontalInset)
          .transition(.opacity)
        }

        Spacer(minLength: 10)

        if !isEditingSidebar {
          if !hasConfiguredSchedule {
            sidebarScheduleSetupHint
              .frame(maxWidth: .infinity)
              .padding(.horizontal, macSidebarHorizontalInset)
              .padding(.bottom, 8)
          }

          macSidebarQuickActions
            .frame(maxWidth: .infinity)
            .padding(.horizontal, macSidebarHorizontalInset)
            .padding(.bottom, 8)

          sidebarProfileButton
            .frame(maxWidth: .infinity)
            .padding(.horizontal, macSidebarHorizontalInset)
            .padding(.bottom, 8)
        }

        if selectedTab != .dashboard && selectedTab != .schedule && !isEditingSidebar {
          sidebarNowCard
            .frame(maxWidth: .infinity)
            .padding(.horizontal, macSidebarHorizontalInset)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background {
        // Let the sidebar itself extend beneath the macOS titlebar area.
        // The window is configured as a full-size content window below,
        // so this keeps the traffic-light strip visually continuous.
        ZStack {
          Rectangle()
            .fill(.thinMaterial)

          DesignTokens.Colors.sidebar
            .opacity(colorScheme == .dark ? 0.96 : 0.90)

          if colorScheme == .light {
            LinearGradient(
              colors: [
                DesignTokens.Colors.lightSidebarTop.opacity(0.72),
                Color.clear,
              ],
              startPoint: .top,
              endPoint: .center
            )
          }
        }
        .ignoresSafeArea()
      }
      .animation(DesignTokens.Animation.snappy, value: isEditingSidebar)
    }

    private var macSidebarResizeHandle: some View {
      ZStack {
        Rectangle()
          .fill(DesignTokens.Colors.borderStrong)
          .frame(width: 1)

        Color.clear
          .frame(width: 9)
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                if macSidebarResizeStartWidth == nil {
                  macSidebarResizeStartWidth = macSidebarWidth
                }

                let startWidth = macSidebarResizeStartWidth ?? macSidebarWidth
                let proposedWidth = startWidth + value.translation.width
                storedMacSidebarWidth = Double(
                  min(
                    max(proposedWidth, macSidebarMinimumWidth),
                    macSidebarMaximumWidth
                  )
                )
              }
              .onEnded { _ in
                macSidebarResizeStartWidth = nil
              }
          )
      }
      .frame(width: 8)
      .zIndex(10)
      .help("Drag to resize the sidebar")
      .onHover { hovering in
        if hovering {
          NSCursor.resizeLeftRight.set()
        } else {
          NSCursor.arrow.set()
        }
      }
      .onTapGesture(count: 2) {
        withAnimation(DesignTokens.Animation.snappy) {
          storedMacSidebarWidth = Double(macSidebarDefaultWidth)
        }
      }
    }

    private var sidebarScheduleSetupHint: some View {
      Button {
        withAnimation(DesignTokens.Animation.navigation) {
          selectedTab = .schedule
        }
      } label: {
        VStack(alignment: .leading, spacing: 9) {
          HStack(spacing: 8) {
            ProfileAvatarView(
              name: store.profileName,
              avatar: store.profileAvatar,
              accentColor: store.profileAccentColor,
              size: 26
            )

            VStack(alignment: .leading, spacing: 1) {
              Text(
                store.profileFirstName.map { "One more thing, \($0)" }
                  ?? "One more thing"
              )
              .font(.system(size: 9, weight: .bold))
              .tracking(0.35)
              .foregroundStyle(store.profileAccentColor)
              .lineLimit(1)

              Text("Set up your schedule")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "arrow.up.right")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(DesignTokens.Colors.subtleText)
          }

          Text(
            "Add your classes so RooMate can personalize Today, timers, and reminders around your day."
          )
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: 5) {
            Image(systemName: "calendar.badge.plus")
              .font(.system(size: 9, weight: .semibold))

            Text("Finish schedule setup")
              .font(.system(size: 9.5, weight: .semibold))
          }
          .foregroundStyle(DesignTokens.Colors.schedule)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .fill(DesignTokens.Colors.surface.opacity(0.76))

            LinearGradient(
              colors: [
                store.profileAccentColor.opacity(colorScheme == .dark ? 0.10 : 0.07),
                DesignTokens.Colors.schedule.opacity(colorScheme == .dark ? 0.055 : 0.04),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
              store.profileAccentColor.opacity(colorScheme == .dark ? 0.24 : 0.18),
              lineWidth: 1
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)
      .help("Set up your schedule")
    }

    private var sidebarProfileButton: some View {
      Button {
        withAnimation(DesignTokens.Animation.navigation) {
          selectedTab = .profile
        }
      } label: {
        HStack(spacing: 10) {
          ProfileAvatarView(
            name: store.profileName,
            avatar: store.profileAvatar,
            accentColor: store.profileAccentColor,
            size: 30
          )

          VStack(alignment: .leading, spacing: 1) {
            Text(
              store.profileName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
                ? "Profile"
                : store.profileDisplayName
            )
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)

            Text(
              store.profileCurrentGrade?.shortTitle
                ?? "Personalize RooMate"
            )
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
          }

          Spacer(minLength: 5)

          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
        .padding(.horizontal, 9)
        .frame(height: 46)
        .contentShape(Rectangle())
        .background(
          selectedTab == .profile
            ? store.profileAccentColor.opacity(0.10)
            : DesignTokens.Colors.sidebarHover.opacity(0.32),
          in: RoundedRectangle(
            cornerRadius: 11,
            style: .continuous
          )
        )
        .overlay {
          RoundedRectangle(
            cornerRadius: 11,
            style: .continuous
          )
          .strokeBorder(
            selectedTab == .profile
              ? store.profileAccentColor.opacity(0.24)
              : DesignTokens.Colors.border.opacity(0.65),
            lineWidth: 1
          )
        }
      }
      .buttonStyle(.plain)
      .help("Open Profile")
    }

    private var sidebarEditor: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            Text("SIDEBAR ITEMS")
              .font(.system(size: 9, weight: .bold))
              .tracking(0.7)
              .foregroundStyle(DesignTokens.Colors.subtleText)

            Spacer()

            Image(systemName: "line.3.horizontal")
              .font(.system(size: 9, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.subtleText)

            Text("Drag to reorder")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.subtleText)
          }
          .padding(.horizontal, 4)
          .padding(.bottom, 2)

          ForEach(sidebarAllTabsInOrder.filter { $0 != .profile }, id: \.self) { tab in
            sidebarEditRow(tab)
          }

          Text("Hidden sections stay here while you edit, so you can show them again anytime.")
            .font(.system(size: 9.5))
            .foregroundStyle(DesignTokens.Colors.subtleText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
      }
      .scrollIndicators(.hidden)
    }

    private func sidebarEditRow(_ tab: Tab) -> some View {
      let isRequired = requiredSidebarTabs.contains(tab)
      let isHidden = !isRequired && store.sidebarHidden.contains(tab.title)
      let isPinned = store.sidebarFavorites.contains(tab.title)
      let isDragging = draggingSidebarTab == tab
      let isDropTarget = sidebarDropTarget == tab && !isDragging

      return HStack(spacing: 9) {
        Image(systemName: "line.3.horizontal")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(
            isDragging
              ? tab.featureColor
              : DesignTokens.Colors.subtleText
          )
          .frame(width: 13)

        if tab == .profile {
          ProfileAvatarView(
            name: store.profileName,
            avatar: store.profileAvatar,
            accentColor: store.profileAccentColor,
            size: 22
          )
        } else {
          Image(systemName: tab.systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tab.featureColor)
            .frame(width: 19)
        }

        VStack(alignment: .leading, spacing: 1) {
          Text(tab.displayTitle)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.primaryText)

          if isHidden {
            Text("Hidden")
              .font(.system(size: 8.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.subtleText)
          }
        }

        Spacer(minLength: 4)

        Button {
          toggleSidebarPin(tab)
        } label: {
          Image(systemName: isPinned ? "pin.fill" : "pin")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
              isPinned
                ? tab.featureColor
                : DesignTokens.Colors.secondaryText
            )
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin" : "Pin to top")

        Button {
          toggleSidebarVisibility(tab)
        } label: {
          Image(systemName: isRequired ? "lock.fill" : (isHidden ? "eye.slash" : "eye"))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(
              isRequired
                ? DesignTokens.Colors.subtleText
                : (isHidden ? DesignTokens.Colors.subtleText : tab.featureColor.opacity(0.88))
            )
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRequired)
        .help(
          isRequired
            ? "Always shown in the sidebar" : (isHidden ? "Show in sidebar" : "Hide from sidebar"))
      }
      .padding(.horizontal, 9)
      .frame(height: 44)
      .background(
        isDropTarget
          ? tab.featureColor.opacity(0.13)
          : DesignTokens.Colors.sidebarHover.opacity(isHidden ? 0.24 : 0.46),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            isDropTarget
              ? tab.featureColor.opacity(0.42)
              : DesignTokens.Colors.sidebarHoverBorder.opacity(isHidden ? 0.30 : 0.62),
            lineWidth: isDropTarget ? 1.2 : 1
          )
      }
      .opacity(isDragging ? 0.56 : (isHidden ? 0.56 : 1))
      .scaleEffect(isDragging ? 0.985 : 1)
      .contentShape(Rectangle())
      .onDrag {
        draggingSidebarTab = tab
        return NSItemProvider(object: NSString(string: tab.title))
      } preview: {
        HStack(spacing: 8) {
          Image(systemName: tab.systemImage)
            .foregroundStyle(tab.featureColor)
          Text(tab.displayTitle)
            .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
          DesignTokens.Colors.surfaceElevated,
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
      }
      .onDrop(
        of: [UTType.plainText],
        delegate: SidebarReorderDropDelegate(
          target: tab,
          draggingTab: $draggingSidebarTab,
          dropTarget: $sidebarDropTarget,
          move: moveSidebarTab
        )
      )
      .animation(DesignTokens.Animation.snappy, value: store.sidebarOrder)
      .animation(DesignTokens.Animation.quick, value: isHidden)
      .animation(DesignTokens.Animation.quick, value: isPinned)
      .animation(DesignTokens.Animation.quick, value: isDragging)
      .animation(DesignTokens.Animation.quick, value: isDropTarget)
    }

    private func macSidebarButton(_ tab: Tab) -> some View {
      let isSelected = selectedTab == tab
      let isHovered = hoveredSidebarTab == tab

      return Button {
        withAnimation(DesignTokens.Animation.snappy) {
          selectedTab = tab
        }
      } label: {
        ZStack {
          if isSelected || isHovered {
            RoundedRectangle(
              cornerRadius: 11,
              style: .continuous
            )
            .fill(
              isSelected
                ? tab.sidebarSelectionColor.opacity(
                  colorScheme == .light ? 0.105 : 0.18
                )
                : DesignTokens.Colors.sidebarHover
            )
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .overlay {
              RoundedRectangle(
                cornerRadius: 11,
                style: .continuous
              )
              .strokeBorder(
                isSelected
                  ? tab.sidebarSelectionColor.opacity(
                    colorScheme == .light ? 0.26 : 0.42
                  )
                  : DesignTokens.Colors.sidebarHoverBorder,
                lineWidth: isSelected ? 1.05 : 1
              )
            }
          }

          HStack(spacing: 11) {
            if tab == .profile {
              ProfileAvatarView(
                name: store.profileName,
                avatar: store.profileAvatar,
                accentColor: store.profileAccentColor,
                size: 24
              )

              VStack(alignment: .leading, spacing: 0) {
                Text(store.profileFirstName ?? "Profile")
                  .font(
                    .system(
                      size: 13.5,
                      weight: isSelected
                        ? .semibold
                        : .medium
                    )
                  )
                  .foregroundStyle(
                    DesignTokens.Colors.primaryText
                  )
                  .lineLimit(1)

                Text(
                  store.profileCurrentGrade?.shortTitle
                    ?? "Set up profile"
                )
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(
                  DesignTokens.Colors.subtleText
                )
                .lineLimit(1)
              }
            } else {
              Image(systemName: tab.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tab.featureColor)
                .frame(width: 20)

              Text(tab.displayTitle)
                .font(
                  .system(
                    size: 14,
                    weight: isSelected
                      ? .semibold
                      : .medium
                  )
                )
                .foregroundStyle(
                  DesignTokens.Colors.primaryText
                )
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if store.sidebarFavorites.contains(tab.title) {
              Image(systemName: "pin.fill")
                .font(
                  .system(
                    size: 8.5,
                    weight: .semibold
                  )
                )
                .foregroundStyle(
                  tab.featureColor.opacity(0.82)
                )
                .accessibilityLabel("Pinned")
                .transition(
                  .scale(scale: 0.78)
                    .combined(with: .opacity)
                )
            }
          }
          .padding(.horizontal, 14)
          .frame(maxWidth: .infinity)
          .frame(height: 42)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .contentShape(Rectangle())
        .animation(
          DesignTokens.Animation.quick,
          value: store.sidebarFavorites
        )
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .frame(height: 42)
      .onHover { hovering in
        withAnimation(.easeOut(duration: 0.12)) {
          hoveredSidebarTab = hovering ? tab : nil
        }
      }
      .contextMenu {
        Button(
          store.sidebarFavorites.contains(tab.title)
            ? "Unpin from Sidebar"
            : "Pin to Top"
        ) {
          toggleSidebarPin(tab)
        }

        Button(
          store.sidebarHidden.contains(tab.title)
            ? "Show in Sidebar"
            : "Hide"
        ) {
          toggleSidebarVisibility(tab)
        }

        Divider()

        Button("Edit Sidebar") {
          setSidebarEditing(true)
        }
      }
    }

    private struct SidebarReorderDropDelegate: DropDelegate {
      let target: Tab
      @Binding var draggingTab: Tab?
      @Binding var dropTarget: Tab?
      let move: (Tab, Tab) -> Void

      func dropEntered(info: DropInfo) {
        guard let draggingTab, draggingTab != target else { return }

        withAnimation(DesignTokens.Animation.snappy) {
          dropTarget = target
          move(draggingTab, target)
        }
      }

      func dropExited(info: DropInfo) {
        guard dropTarget == target else { return }

        withAnimation(DesignTokens.Animation.quick) {
          dropTarget = nil
        }
      }

      func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
      }

      func performDrop(info: DropInfo) -> Bool {
        withAnimation(DesignTokens.Animation.snappy) {
          draggingTab = nil
          dropTarget = nil
        }
        return true
      }
    }

    @ViewBuilder
    private var macDetail: some View {
      ZStack {
        BackgroundView()

        Group {
          switch selectedTab {
          case .dashboard:
            DashboardView(
              store: store,
              sportsStore: sportsStore,
              eventsStore: eventsStore,
              menuStore: menuStore,
              onOpenSchedule: { selectedTab = .schedule },
              onOpenDining: { selectedTab = .menu },
              onOpenSports: { selectedTab = .athletics },
              onOpenClubs: { selectedTab = .clubs },
              onOpenEvents: { selectedTab = .events },
              onOpenPacTrack: { selectedTab = .rooPAC },
              onOpenScheduleFocus: {
                scheduleFocusMode = true
                selectedTab = .schedule
              },
              onSearch: { showSearch = true }
            )

          case .schedule:
            ScheduleWorkspaceView(
              store: store,
              sportsStore: sportsStore,
              selectedDay: $selectedDay,
              isFocusMode: $scheduleFocusMode
            )

          case .settings:
            SettingsView(
              store: store,
              eventsStore: eventsStore,
              checkForUpdatesAction: checkForUpdatesAction,
              onResetCompleted: startV6Onboarding
            )
            .padding(DesignTokens.Spacing.xl)

          case .menu:
            MenuView(store: menuStore)
              .padding(DesignTokens.Spacing.xl)

          case .athletics:
            SportsHubView(store: sportsStore)
              .padding(DesignTokens.Spacing.xl)

          case .clubs:
            ClubsHubView(store: store)
              .padding(DesignTokens.Spacing.xl)

          case .rooPAC:
            RooPACTrackerView(store: store)
              .padding(DesignTokens.Spacing.xl)

          case .events:
            EventsView(store: eventsStore)
              .padding(DesignTokens.Spacing.xl)

          case .profile:
            ProfileView(store: store)
              .padding(DesignTokens.Spacing.xl)

          case .links:
            SchoolLinksView()
              .padding(DesignTokens.Spacing.xl)
          }
        }
        .id(selectedTab)
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.992)),
            removal: .opacity
          )
        )
        .animation(DesignTokens.Animation.content, value: selectedTab)
      }
    }
  #endif

  private var hasExistingRooMateSetup: Bool {
    let savedSportsGames = UserDefaults.standard
      .string(forKey: "RooMateSportsGameReminders")?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // V5.x already persisted into this suite. Checking for the presence of
    // any established preference key makes the upgrade path more reliable
    // than guessing from today's in-memory values alone.
    let legacyDefaults = UserDefaults(suiteName: "dev.roomate.prefs")
    let establishedPreferenceKeys = [
      "UserScheduleAssignments",
      "UserSpecialBlockColors",
      "UserSpecialBlockFree",
      "UserSpecialBlockReplacements",
      "UserClubs",
      "UserAppearancePreference",
      "UserCardColorStyle",
      "SpecialScheduleOverrides",
      "NotificationsEnabled",
      "NotifyClassStartingSoon",
      "NotifyClassEndingSoon",
      "RooPACCurrentGrade",
      "RooPACPlans",
      "ProfileName",
      "ProfileGraduationYear",
      "SidebarOrder",
      "SidebarFavorites",
      "SidebarHidden",
    ]
    let hasPersistedLegacyPreferences = establishedPreferenceKeys.contains {
      legacyDefaults?.object(forKey: $0) != nil
    }

    return hasPersistedLegacyPreferences
      || store.hasProfile
      || !store.assignments.isEmpty
      || !store.clubs.isEmpty
      || !store.rooPacPlans.isEmpty
      || !store.semesterPlanAssignments.isEmpty
      || !store.sidebarOrder.isEmpty
      || !store.sidebarFavorites.isEmpty
      || !store.sidebarHidden.isEmpty
      || store.appearance != .system
      || store.cardColorStyle != .colors
      || store.notifyClassStartingSoon != true
      || store.notifyClassEndingSoon != false
      || !(savedSportsGames ?? "").isEmpty
      || UserDefaults.standard.object(forKey: "RooMateMacSidebarWidth") != nil
  }

  private func resolveV6OnboardingRouting() {
    guard !onboardingRoutingReady else { return }

    if !v6OnboardingMigrationChecked {
      if hasExistingRooMateSetup {
        // RooMate existed before V6 onboarding. Never force
        // an established user through first-run setup after updating.
        v6OnboardingCompleted = true
      } else {
        // New installs begin with notifications explicitly off until the
        // user reaches the permission step and chooses Enable.
        store.notificationsEnabled = false
        v6OnboardingStep = min(max(v6OnboardingStep, 0), 11)
        TelemetryTracker.trackOnboardingStarted()
      }

      v6OnboardingMigrationChecked = true
    }

    onboardingRoutingReady = true
  }

  private func startV6Onboarding() {
    showSearch = false
    v6OnboardingMigrationChecked = true
    v6OnboardingCompleted = false
    v6OnboardingStep = 0
    onboardingRoutingReady = true
    TelemetryTracker.trackOnboardingStarted()
  }

  private func finishV6Onboarding() {
    TelemetryTracker.trackOnboardingCompleted()
    v6OnboardingCompleted = true
    v6OnboardingStep = 0
    selectedTab = .dashboard
    acknowledgeWhatsNew()
  }

  private let currentWhatsNewVersion = "6.0"

  private func maybeShowWhatsNew() {
    guard v6OnboardingCompleted,
      RooMateVersion.compare(RooMateVersion.current, currentWhatsNewVersion) != .orderedAscending,
      RooMateVersion.compare(lastAcknowledgedWhatsNewVersion, currentWhatsNewVersion) == .orderedAscending
    else { return }
    showWhatsNew = true
  }

  private func acknowledgeWhatsNew() {
    lastAcknowledgedWhatsNewVersion = currentWhatsNewVersion
    showWhatsNew = false
  }

  var body: some View {
    Group {
      if !onboardingRoutingReady {
        ZStack {
          BackgroundView()
            .ignoresSafeArea()

          ProgressView()
            .controlSize(.small)
        }
      } else if !v6OnboardingCompleted {
        RooMateOnboardingView(
          store: store,
          sportsStore: sportsStore,
          eventsStore: eventsStore,
          currentStepIndex: $v6OnboardingStep,
          onFinish: finishV6Onboarding
        )
      } else {
        #if canImport(AppKit)
          HStack(spacing: 0) {
            macSidebar
              .frame(width: macSidebarWidth)

            macSidebarResizeHandle

            macDetail
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        #else
          // iOS / other: compact single-window with modern bottom tab bar
          NavigationStack {
            VStack(spacing: 0) {
              // Top app header
              HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                  Text("RooMate")
                    .font(DesignTokens.Typography.headline2)
                    .foregroundStyle(.primary)
                  Text(DesignTokens.Brand.tagline)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(.horizontal, DesignTokens.Spacing.lg)
              .padding(.vertical, DesignTokens.Spacing.sm)

              Divider().opacity(0.06)

              // Content area
              ZStack {
                BackgroundView()

                Group {
                  switch selectedTab {
                  case .dashboard:
                    DashboardView(
                      store: store,
                      sportsStore: sportsStore,
                      eventsStore: eventsStore,
                      menuStore: menuStore,
                      onOpenSchedule: { selectedTab = .schedule },
                      onOpenDining: { selectedTab = .menu },
                      onOpenSports: { selectedTab = .athletics },
                      onOpenClubs: { selectedTab = .clubs },
                      onOpenEvents: { selectedTab = .events },
                      onOpenPacTrack: { selectedTab = .rooPAC },
                      onOpenScheduleFocus: { selectedTab = .schedule },
                      onSearch: { showSearch = true }
                    )

                  case .schedule:
                    VStack(spacing: 0) {
                      // Day picker
                      HStack {
                        Spacer()
                        Picker("Day", selection: $selectedDay) {
                          ForEach(Weekday.allCases) { day in
                            Text(day.title).tag(day)
                          }
                        }
                        .pickerStyle(.segmented)
                        .tint(DesignTokens.Colors.primary)
                        Spacer()
                      }
                      .padding([.top, .horizontal], DesignTokens.Spacing.lg)

                      DayScheduleView(
                        day: selectedDay,
                        blocks: blocksForSelectedDay,
                        store: store
                      )
                      .padding(.top, DesignTokens.Spacing.md)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)

                  case .settings:
                    SettingsView(
                      store: store,
                      eventsStore: eventsStore,
                      checkForUpdatesAction: checkForUpdatesAction,
                      onResetCompleted: startV6Onboarding
                    )
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .menu:
                    MenuView(store: menuStore)
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .athletics:
                    SportsHubView(store: sportsStore)
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .clubs:
                    ClubsHubView(store: store)
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .events:
                    EventsView(store: eventsStore)
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .rooPAC:
                    RooPACTrackerView(store: store)
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .profile:
                    ProfileView(store: store)
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  case .links:
                    SchoolLinksView()
                      .padding(.horizontal, DesignTokens.Spacing.lg)
                  }
                }
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)

              // Modern tab bar (uses user's sidebar preferences for ordering/visibility)
              ModernTabBar(
                selectedTab: $selectedTab,
                items: sidebarOrderedTabs.map {
                  (tab: $0, label: $0.title, systemImage: $0.systemImage)
                }
              )
              .background(compatibleBackgroundSecondary())
            }
            .background(BackgroundView().ignoresSafeArea())
          }
        #endif
      }
    }
    .preferredColorScheme(preferredColorScheme(for: store.appearance))
    .onAppear {
      resolveV6OnboardingRouting()
      maybeShowWhatsNew()
      store.refreshProfileDerivedData()
      Task {
        await store.refreshAnnouncements()
      }
      #if canImport(AppKit)
        ensureSidebarOrderInitialized()
        let clampedSidebarWidth = macSidebarWidth
        if CGFloat(storedMacSidebarWidth) != clampedSidebarWidth {
          storedMacSidebarWidth = Double(clampedSidebarWidth)
        }
      #endif
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .rooMateOpenSettings
      )
    ) { _ in
      guard v6OnboardingCompleted else { return }
      withAnimation(DesignTokens.Animation.navigation) {
        selectedTab = .settings
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .rooMateShowWhatsNew)) { _ in
      guard v6OnboardingCompleted else { return }
      showWhatsNew = true
    }
    .onChange(of: selectedTab) { _, newTab in
      TelemetryTracker.trackTabSelected(telemetryTabName(for: newTab))
    }
    #if canImport(AppKit)
      .onReceive(
        NotificationCenter.default.publisher(
          for: Notification.Name("RooMateQuickAction")
        )
      ) { notification in
        guard v6OnboardingCompleted,
          let action = notification.userInfo?["action"] as? String
        else {
          return
        }

        switch action {
        case "schedule":
          selectedTab = .schedule
        case "focus":
          scheduleFocusMode = true
          selectedTab = .schedule
        case "dining":
          selectedTab = .menu
        case "events":
          selectedTab = .events
        case "sports":
          selectedTab = .athletics
        case "clubs":
          selectedTab = .clubs
        case "pactrack":
          selectedTab = .rooPAC
        case "search":
          showSearch = true
        case "today":
          selectedTab = .dashboard
        default:
          break
        }
      }
    #endif
    .onReceive(
      NotificationCenter.default.publisher(
        for: .rooMateRefreshOfficialSchedules
      )
    ) { _ in
      Task {
        await store.refreshOfficialSpecialSchedules(force: true)
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .rooMateNotificationPreferencesDidChange
      )
    ) { _ in
      Task {
        await sportsStore.refreshSavedGameNotifications()
        await eventsStore.refreshSavedEventNotifications()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .rooMateSportsPreferencesDidChange
      )
    ) { _ in
      Task {
        await sportsStore.refreshSavedGameNotifications()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: .rooMateEventPreferencesDidChange
      )
    ) { _ in
      Task {
        await eventsStore.refreshSavedEventNotifications()
      }
    }
    .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
      updateTrigger = UUID()
    }
    .background {
      #if canImport(AppKit)
        RooMateWindowChromeConfigurator()
          .frame(width: 0, height: 0)
      #endif
    }
    .sheet(isPresented: $showSearch) {
      RooMateSearchSheet(
        sportsStore: sportsStore,
        eventsStore: eventsStore,
        menuStore: menuStore,
        onNavigate: { tab in
          selectedTab = tab
          showSearch = false
        }
      )
    }
    .sheet(isPresented: $showWhatsNew, onDismiss: acknowledgeWhatsNew) {
      RooMateWhatsNewView(onDismiss: acknowledgeWhatsNew)
    }
    .frame(minWidth: 1040, minHeight: 680)
  }

  private func telemetryTabName(for tab: Tab) -> String {
    switch tab {
    case .dashboard: return "Today"
    case .schedule: return "Schedule"
    case .rooPAC: return "PacTrack"
    case .menu: return "Dining"
    case .athletics: return "Sports"
    case .clubs: return "Clubs"
    case .events: return "Events"
    case .profile: return "Profile"
    case .links: return "Links"
    case .settings: return "Settings"
    }
  }

  enum Tab: CaseIterable, Hashable {
    case dashboard
    case schedule
    case rooPAC
    case menu
    case athletics
    case clubs
    case events
    case profile
    case links
    case settings

    var title: String {
      switch self {
      case .dashboard: return "Dashboard"
      case .schedule: return "Schedule"
      case .rooPAC: return "PacTrack"
      case .menu: return "Dining"
      case .athletics: return "Athletics"
      case .clubs: return "Clubs"
      case .events: return "Events"
      case .profile: return "Profile"
      case .links: return "Links"
      case .settings: return "Settings"
      }
    }

    var displayTitle: String {
      switch self {
      case .dashboard: return "Today"
      case .athletics: return "Sports"
      default: return title
      }
    }

    var systemImage: String {
      switch self {
      case .dashboard: return "square.grid.2x2"
      case .schedule: return "calendar"
      case .rooPAC: return "chart.bar.xaxis"
      case .menu: return "fork.knife"
      case .athletics: return "sportscourt"
      case .clubs: return "person.3.fill"
      case .events: return "calendar.circle"
      case .profile: return "person.crop.circle.fill"
      case .links: return "link"
      case .settings: return "gearshape"
      }
    }

    var featureColor: Color {
      switch self {
      case .dashboard: return DesignTokens.Colors.today
      case .schedule: return DesignTokens.Colors.schedule
      case .rooPAC: return DesignTokens.Colors.pacTrack
      case .menu: return DesignTokens.Colors.dining
      case .athletics: return DesignTokens.Colors.athletics
      case .clubs: return DesignTokens.Colors.events
      case .events: return DesignTokens.Colors.events
      case .profile: return DesignTokens.Colors.pacTrack
      case .links: return DesignTokens.Colors.links
      case .settings: return DesignTokens.Colors.settings
      }
    }

    /// Sidebar selection accents are deliberately a little more distinct
    /// than some feature icon colors so the current section reads instantly.
    var sidebarSelectionColor: Color {
      switch self {
      case .dashboard: return DesignTokens.Colors.settings
      case .schedule: return DesignTokens.Colors.schedule
      case .menu: return DesignTokens.Colors.dining
      case .athletics: return DesignTokens.Colors.athletics
      case .clubs: return DesignTokens.Colors.events
      case .events: return DesignTokens.Colors.pacTrack
      case .rooPAC: return DesignTokens.Colors.pacTrack
      case .profile: return DesignTokens.Colors.pacTrack
      case .links: return DesignTokens.Colors.links
      case .settings: return DesignTokens.Colors.settings
      }
    }
  }
}

// MARK: - RooMate V6 Onboarding

private struct RooMateOnboardingView: View {
  @ObservedObject var store: UserScheduleStore
  @ObservedObject var sportsStore: SportsStore
  @ObservedObject var eventsStore: EventsStore
  @Binding var currentStepIndex: Int
  let onFinish: () -> Void

  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedClassLevel: Level = .level1
  @State private var clubDirectorySearch = ""
  @State private var notificationsChoiceMade = false
  @State private var sidebarWasEdited = false
  @StateObject private var clubDirectoryStore = ClubDirectoryStore()
  @AppStorage("RooMateSportsGameReminders") private var savedGameIDsRaw = ""
  @AppStorage("RooMateNotifySavedEvents") private var notifySavedEvents = false
  @AppStorage("RooMateNotifyCalendarEvents") private var notifyCalendarEvents = false
  #if canImport(ServiceManagement)
    @State private var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @State private var launchAtLoginError: String?
  #endif

  private enum Step: Int, CaseIterable, Identifiable {
    case welcome
    case profile
    case classes
    case clubs
    case pacTrack
    case sports
    case events
    case notifications
    case preferences
    case sidebar
    case tour
    case finish

    var id: Int { rawValue }

    var analyticsName: String {
      switch self {
      case .welcome: "welcome"
      case .profile: "profile"
      case .classes: "classes"
      case .clubs: "clubs"
      case .pacTrack: "pactrack"
      case .sports: "sports"
      case .events: "events"
      case .notifications: "notifications"
      case .preferences: "preferences"
      case .sidebar: "sidebar"
      case .tour: "tour"
      case .finish: "finish"
      }
    }

    var title: String {
      switch self {
      case .welcome: "Welcome"
      case .profile: "Profile"
      case .classes: "Classes"
      case .clubs: "Clubs"
      case .pacTrack: "PacTrack"
      case .sports: "Sports"
      case .events: "Events"
      case .notifications: "Notifications"
      case .preferences: "App Preferences"
      case .sidebar: "Sidebar"
      case .tour: "How RooMate Works"
      case .finish: "Ready"
      }
    }

    var subtitle: String {
      switch self {
      case .welcome: "Meet your school-day home base"
      case .profile: "Make RooMate feel like yours"
      case .classes: "Tell RooMate what your Levels mean"
      case .clubs: "Add the clubs you actually attend"
      case .pacTrack: "Start your RooPAC plan"
      case .sports: "Choose individual game reminders"
      case .events: "Choose the calendars you want"
      case .notifications: "Choose the reminders you want"
      case .preferences: "Set up how RooMate behaves"
      case .sidebar: "Keep your favorite sections close"
      case .tour: "Know where everything lives"
      case .finish: "RooMate is ready"
      }
    }

    var systemImage: String {
      switch self {
      case .welcome: "sparkles"
      case .profile: "person.crop.circle.fill"
      case .classes: "books.vertical.fill"
      case .clubs: "person.3.fill"
      case .pacTrack: "chart.bar.xaxis"
      case .sports: "sportscourt.fill"
      case .events: "calendar.badge.clock"
      case .notifications: "bell.badge.fill"
      case .preferences: "switch.2"
      case .sidebar: "sidebar.left"
      case .tour: "rectangle.3.group.fill"
      case .finish: "checkmark.seal.fill"
      }
    }

    var tint: Color {
      switch self {
      case .welcome: DesignTokens.Colors.primary
      case .profile: DesignTokens.Colors.pacTrack
      case .classes: DesignTokens.Colors.schedule
      case .clubs: DesignTokens.Colors.events
      case .pacTrack: DesignTokens.Colors.pacTrack
      case .sports: DesignTokens.Colors.athletics
      case .events: DesignTokens.Colors.events
      case .notifications: DesignTokens.Colors.warning
      case .preferences: DesignTokens.Colors.settings
      case .sidebar: DesignTokens.Colors.settings
      case .tour: DesignTokens.Colors.primary
      case .finish: DesignTokens.Colors.success
      }
    }

    var canSkip: Bool {
      switch self {
      case .clubs, .pacTrack, .sports, .notifications, .preferences, .sidebar:
        true
      default:
        false
      }
    }
  }

  private struct SidebarChoice: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
  }

  private var currentStep: Step {
    Step(rawValue: min(max(currentStepIndex, 0), Step.allCases.count - 1)) ?? .welcome
  }

  private var progress: Double {
    Double(currentStep.rawValue) / Double(max(1, Step.allCases.count - 1))
  }

  private var savedGameIDs: Set<String> {
    Set(savedGameIDsRaw.split(separator: "\n").map(String.init))
  }

  private var onboardingSportsGames: [SportsGame] {
    let start = Calendar.current.startOfDay(for: Date())
    return sportsStore.liveGames
      .filter {
        guard let date = $0.date else { return false }
        return date >= start && $0.status != .cancelled && $0.status != .eliminated
      }
      .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
      .prefix(8)
      .map { $0 }
  }

  private var configuredClassCount: Int {
    Level.allCases.reduce(0) { count, level in
      let assignment = store.assignments[level] ?? .default(for: level)
      let trimmed = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let configured = assignment.isFree || (!trimmed.isEmpty && trimmed != level.displayName)
      return count + (configured ? 1 : 0)
    }
  }

  private var selectedPacTrackCount: Int {
    RooPACActivityType.officialCases.reduce(0) { result, activity in
      result + ((store.rooPacPlans[activity]?.isSelected ?? false) ? 1 : 0)
    }
  }

  private var sidebarChoiceDefinitions: [SidebarChoice] {
    [
      .init(
        id: "Dashboard", title: "Today", systemImage: "square.grid.2x2",
        tint: DesignTokens.Colors.today),
      .init(
        id: "Schedule", title: "Schedule", systemImage: "calendar",
        tint: DesignTokens.Colors.schedule),
      .init(
        id: "Dining", title: "Dining", systemImage: "fork.knife", tint: DesignTokens.Colors.dining),
      .init(
        id: "Athletics", title: "Sports", systemImage: "sportscourt",
        tint: DesignTokens.Colors.athletics),
      .init(
        id: "Clubs", title: "Clubs", systemImage: "person.3.fill", tint: DesignTokens.Colors.events),
      .init(
        id: "Events", title: "Events", systemImage: "calendar.circle",
        tint: DesignTokens.Colors.events),
      .init(
        id: "PacTrack", title: "PacTrack", systemImage: "chart.bar.xaxis",
        tint: DesignTokens.Colors.pacTrack),
      .init(
        id: "Profile", title: "Profile", systemImage: "person.crop.circle.fill",
        tint: store.profileAccentColor),
      .init(id: "Links", title: "Links", systemImage: "link", tint: DesignTokens.Colors.links),
      .init(
        id: "Settings", title: "Settings", systemImage: "gearshape",
        tint: DesignTokens.Colors.settings),
    ]
  }

  private var protectedSidebarChoiceIDs: Set<String> {
    ["Schedule", "Settings"]
  }

  private var sidebarChoices: [SidebarChoice] {
    let byID = Dictionary(uniqueKeysWithValues: sidebarChoiceDefinitions.map { ($0.id, $0) })
    let stored = store.sidebarOrder.filter { byID[$0] != nil }
    let orderedIDs = stored + sidebarChoiceDefinitions.map(\.id).filter { !stored.contains($0) }
    return orderedIDs.compactMap { byID[$0] }
  }

  private var sidebarHasCustomization: Bool {
    let defaultIDs = [
      "Dashboard", "Schedule", "Dining", "Athletics", "Clubs", "Events", "PacTrack", "Profile",
      "Links", "Settings",
    ]
    let orderChanged = !store.sidebarOrder.isEmpty && store.sidebarOrder != defaultIDs
    return orderChanged || !store.sidebarFavorites.isEmpty || !store.sidebarHidden.isEmpty
  }

  private var canContinueCurrentStep: Bool {
    switch currentStep {
    case .welcome, .tour, .finish:
      return true
    case .profile:
      return !store.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || store.profileGraduationYear != nil
        || store.profileAvatar != .initials
        || store.profileAccent != .orange
        || store.profileCustomAccent != nil
    case .classes:
      return configuredClassCount > 0
    case .clubs:
      return store.clubs.contains {
        !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
    case .pacTrack:
      return selectedPacTrackCount > 0
    case .sports:
      return !savedGameIDs.isEmpty
    case .events:
      return !eventsStore.selectedSources.isEmpty
    case .notifications:
      return notificationsChoiceMade || notificationsAreActive
    case .preferences:
      return true
    case .sidebar:
      return sidebarWasEdited || sidebarHasCustomization
    }
  }

  var body: some View {
    HStack(spacing: 0) {
      onboardingRail
        .frame(width: 236)

      mainPanel
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background {
      ZStack {
        BackgroundView()
          .ignoresSafeArea()

        Circle()
          .fill(currentStep.tint.opacity(colorScheme == .dark ? 0.11 : 0.07))
          .frame(width: 520, height: 520)
          .blur(radius: 90)
          .offset(x: 330, y: -260)
          .allowsHitTesting(false)

        Circle()
          .fill(DesignTokens.Colors.primary.opacity(colorScheme == .dark ? 0.07 : 0.045))
          .frame(width: 440, height: 440)
          .blur(radius: 100)
          .offset(x: -260, y: 310)
          .allowsHitTesting(false)
      }
    }
    .animation(DesignTokens.Animation.content, value: currentStepIndex)
  }

  private var onboardingRail: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image("RooMark")
          .resizable()
          .scaledToFit()
          .environment(\.colorScheme, .light)
          .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 1) {
          Text("RooMate")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text("GETTING STARTED")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.85)
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
      }
      .padding(.top, 47)
      .padding(.horizontal, 20)

      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 5) {
          ForEach(Step.allCases) { step in
            onboardingRailRow(step)
          }
        }
        .padding(.top, 24)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }
      .frame(maxHeight: .infinity)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("SETUP PROGRESS")
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(DesignTokens.Colors.subtleText)
          Spacer()
          Text("\(Int((progress * 100).rounded()))%")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(currentStep.tint)
        }

        ProgressView(value: progress)
          .tint(currentStep.tint)
      }
      .padding(14)
      .background(
        DesignTokens.Colors.sidebarHover.opacity(0.50),
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 18)
    }
    .background {
      ZStack {
        Rectangle().fill(.thinMaterial)
        DesignTokens.Colors.sidebar.opacity(colorScheme == .dark ? 0.94 : 0.90)
      }
      .ignoresSafeArea()
    }
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(DesignTokens.Colors.borderStrong)
        .frame(width: 1)
    }
  }

  private func onboardingRailRow(_ step: Step) -> some View {
    let active = step == currentStep
    let complete = step.rawValue < currentStep.rawValue

    return HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(active ? step.tint.opacity(0.16) : DesignTokens.Colors.hover.opacity(0.22))

        Image(systemName: complete ? "checkmark" : step.systemImage)
          .font(.system(size: 10.5, weight: .bold))
          .foregroundStyle(complete || active ? step.tint : DesignTokens.Colors.subtleText)
      }
      .frame(width: 28, height: 28)

      Text(step.title)
        .font(.system(size: 11.5, weight: active ? .semibold : .medium))
        .foregroundStyle(
          active ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText)

      Spacer(minLength: 4)

      if active {
        Circle()
          .fill(step.tint)
          .frame(width: 5, height: 5)
      }
    }
    .padding(.horizontal, 9)
    .frame(height: 38)
    .background(
      active ? step.tint.opacity(colorScheme == .dark ? 0.075 : 0.055) : Color.clear,
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
  }

  private var mainPanel: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(currentStep.tint.opacity(0.13))
          Image(systemName: currentStep.systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(currentStep.tint)
        }
        .frame(width: 42, height: 42)

        VStack(alignment: .leading, spacing: 2) {
          Text(currentStep.title)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(currentStep.subtitle)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Text("\(currentStep.rawValue + 1) of \(Step.allCases.count)")
          .font(.system(size: 10.5, weight: .semibold, design: .rounded))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(DesignTokens.Colors.hover.opacity(0.36), in: Capsule())
      }
      .padding(.top, 43)
      .padding(.horizontal, 30)
      .padding(.bottom, 18)

      Divider()
        .overlay(DesignTokens.Colors.border)

      ScrollView {
        Group {
          switch currentStep {
          case .welcome:
            welcomeStep
          case .profile:
            profileStep
          case .classes:
            classesStep
          case .clubs:
            clubsStep
          case .pacTrack:
            pacTrackStep
          case .sports:
            sportsStep
          case .events:
            eventsStep
          case .notifications:
            notificationsStep
          case .preferences:
            preferencesStep
          case .sidebar:
            sidebarStep
          case .tour:
            tourStep
          case .finish:
            finishStep
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, alignment: .center)
      }

      Divider()
        .overlay(DesignTokens.Colors.border)

      onboardingFooter
    }
  }

  private var onboardingFooter: some View {
    HStack(spacing: 10) {
      if currentStep != .welcome {
        Button {
          goBack()
        } label: {
          Label("Back", systemImage: "chevron.left")
            .font(.system(size: 11.5, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rooInteractiveGlass(cornerRadius: 10)
      }

      Spacer()

      if currentStep.canSkip {
        Button("Skip for now") {
          skipCurrentStep()
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
      }

      Button {
        continueFromCurrentStep()
      } label: {
        HStack(spacing: 7) {
          Text(primaryButtonTitle)
          Image(systemName: currentStep == .finish ? "arrow.right.circle.fill" : "chevron.right")
            .font(.system(size: 10.5, weight: .bold))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .contentShape(Rectangle())
        .background(
          canContinueCurrentStep ? currentStep.tint : DesignTokens.Colors.subtleText.opacity(0.52),
          in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .shadow(
          color: canContinueCurrentStep ? currentStep.tint.opacity(0.18) : .clear,
          radius: 8,
          y: 3
        )
      }
      .buttonStyle(.plain)
      .disabled(!canContinueCurrentStep)
      .opacity(canContinueCurrentStep ? 1 : 0.72)
      .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 16)
    .background(DesignTokens.Colors.surface.opacity(colorScheme == .dark ? 0.80 : 0.72))
  }

  private var primaryButtonTitle: String {
    switch currentStep {
    case .welcome: "Get Started"
    case .finish: "Open RooMate"
    default: "Continue"
    }
  }

  private func continueFromCurrentStep() {
    guard canContinueCurrentStep else { return }

    if currentStep == .finish {
      TelemetryTracker.trackOnboardingStepCompleted(currentStep.analyticsName, skipped: false)
      onFinish()
      return
    }
    TelemetryTracker.trackOnboardingStepCompleted(currentStep.analyticsName, skipped: false)
    advance()
  }

  private func skipCurrentStep() {
    TelemetryTracker.trackOnboardingStepCompleted(currentStep.analyticsName, skipped: true)
    if currentStep == .notifications {
      Task { @MainActor in
        await store.setNotificationsEnabled(false)
        advance()
      }
    } else {
      advance()
    }
  }

  private func advance() {
    guard currentStep.rawValue < Step.allCases.count - 1 else { return }
    withAnimation(DesignTokens.Animation.navigation) {
      currentStepIndex = currentStep.rawValue + 1
    }
  }

  private func goBack() {
    guard currentStep.rawValue > 0 else { return }
    withAnimation(DesignTokens.Animation.navigation) {
      currentStepIndex = currentStep.rawValue - 1
    }
  }

  // MARK: Welcome

  private var welcomeStep: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(alignment: .center, spacing: 22) {
        Image("RooMark")
          .resizable()
          .scaledToFit()
          .environment(\.colorScheme, .light)
          .frame(width: 98, height: 98)

        VStack(alignment: .leading, spacing: 8) {
          Text(DesignTokens.Brand.tagline)
            .font(.system(size: 31, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(
            "Set up the parts that are yours. RooMate will organize the rest and surface what matters when you need it."
          )
          .font(.system(size: 13.5, weight: .regular))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      onboardingCard(
        title: "Make RooMate yours",
        subtitle:
          "A few choices now make Today, reminders, clubs, sports, and the rest of RooMate feel personal from the start.",
        icon: "slider.horizontal.3",
        tint: DesignTokens.Colors.primary
      ) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
          welcomeFeature(
            icon: "books.vertical.fill", title: "Your classes",
            detail: "Level names, teachers, rooms, and free periods",
            tint: DesignTokens.Colors.schedule)
          welcomeFeature(
            icon: "person.3.fill", title: "My Clubs",
            detail: "Your club list, including after-school and overlapping meeting times",
            tint: DesignTokens.Colors.events)
          welcomeFeature(
            icon: "chart.bar.xaxis", title: "PacTrack",
            detail: "A starting plan for this year's RooPACs", tint: DesignTokens.Colors.pacTrack)
          welcomeFeature(
            icon: "sportscourt.fill", title: "Sports",
            detail: "Browse games and choose individual reminders",
            tint: DesignTokens.Colors.athletics)
          welcomeFeature(
            icon: "bell.badge.fill", title: "Reminders",
            detail: "You decide whether RooMate can notify you", tint: DesignTokens.Colors.warning)
          welcomeFeature(
            icon: "sidebar.left", title: "Sidebar",
            detail: "Choose the sections you want visible or pinned",
            tint: DesignTokens.Colors.settings)
          welcomeFeature(
            icon: "rectangle.3.group.fill", title: "Quick tour",
            detail: "Today, Schedule, Dining, Sports, Clubs, Events, PacTrack, Links, and search",
            tint: DesignTokens.Colors.primary)
        }
      }

      HStack(spacing: 8) {
        Image(systemName: "externaldrive.badge.checkmark")
          .foregroundStyle(DesignTokens.Colors.success)
        Text("RooMate saves your progress, so you can close this and finish later.")
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 4)
    }
  }

  private func welcomeFeature(icon: String, title: String, detail: String, tint: Color) -> some View
  {
    HStack(alignment: .top, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(tint.opacity(0.12))
        Image(systemName: icon)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(tint)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        Text(detail)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      DesignTokens.Colors.hover.opacity(0.24),
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  // MARK: Profile

  private var profileStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Start with you",
        subtitle:
          "Your graduation year lets RooMate update your grade and yearly RooPAC goal automatically.",
        icon: "person.crop.circle.fill",
        tint: DesignTokens.Colors.pacTrack
      ) {
        HStack(alignment: .center, spacing: 18) {
          ProfileAvatarView(
            name: store.profileName,
            avatar: store.profileAvatar,
            accentColor: store.profileAccentColor,
            size: 82
          )

          VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
              Text("YOUR NAME")
                .onboardingFieldLabel()
              TextField("Name", text: $store.profileName)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                  DesignTokens.Colors.hover.opacity(0.30),
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
              Text("GRADUATION YEAR")
                .onboardingFieldLabel()
              Picker("Graduation Year", selection: $store.profileGraduationYear) {
                Text("Choose a year").tag(nil as Int?)
                ForEach(RooPACGrade.validGraduationYears(), id: \.self) { year in
                  Text("Class of \(String(year))").tag(Optional(year))
                }
              }
              .labelsHidden()
              .pickerStyle(.menu)
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }

      onboardingCard(
        title: "Choose an avatar",
        subtitle: "This appears in the sidebar and your Profile.",
        icon: "face.smiling",
        tint: store.profileAccentColor
      ) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 9)], spacing: 9) {
          ForEach(profileAvatarOptions) { option in
            let selected = store.profileAvatar == option
            Button {
              withAnimation(DesignTokens.Animation.quick) {
                store.profileAvatar = option
              }
            } label: {
              VStack(spacing: 7) {
                ProfileAvatarView(
                  name: store.profileName,
                  avatar: option,
                  accentColor: store.profileAccentColor,
                  size: 42
                )
                Text(option.title)
                  .font(.system(size: 9.5, weight: .semibold))
                  .foregroundStyle(
                    selected ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText
                  )
                  .lineLimit(1)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
              .background(
                selected
                  ? store.profileAccentColor.opacity(0.10)
                  : DesignTokens.Colors.hover.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                  .strokeBorder(
                    selected ? store.profileAccentColor.opacity(0.42) : DesignTokens.Colors.border,
                    lineWidth: 1)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }

      onboardingCard(
        title: "Accent color",
        subtitle:
          "Pick a preset or choose any color you want. This is the same profile color control available later in Settings.",
        icon: "paintpalette.fill",
        tint: store.profileAccentColor
      ) {
        HStack(spacing: 10) {
          ForEach(ProfileAccentChoice.allCases) { accent in
            let selected = store.profileCustomAccent == nil && store.profileAccent == accent
            Button {
              withAnimation(DesignTokens.Animation.quick) {
                store.profileAccent = accent
                store.profileCustomAccent = nil
              }
            } label: {
              ZStack {
                Circle()
                  .fill(accent.color)
                  .frame(width: 30, height: 30)
                if selected {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                }
              }
              .padding(4)
              .background(selected ? accent.color.opacity(0.13) : Color.clear, in: Circle())
            }
            .buttonStyle(.plain)
            .help(accent.title)
          }

          Divider()
            .frame(height: 30)
            .overlay(DesignTokens.Colors.border)

          ColorPicker(
            "Custom",
            selection: Binding(
              get: { store.profileAccentColor },
              set: { store.profileCustomAccent = CodableColor($0) }
            ),
            supportsOpacity: false
          )
          .labelsHidden()
          .help("Choose any profile color")

          if store.profileCustomAccent != nil {
            Text("Custom")
              .font(.system(size: 9.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()
        }
      }

      onboardingCard(
        title: "Today greeting",
        subtitle: "Choose whether Today can greet you by your first name.",
        icon: "hand.wave.fill",
        tint: store.profileAccentColor
      ) {
        onboardingToggleRow(
          title: "Personalized greeting",
          subtitle: "Use your first name in the Today greeting when your profile has one.",
          systemImage: "text.bubble.fill",
          tint: store.profileAccentColor,
          isOn: $store.profileGreetingEnabled,
          disabled: false
        )
      }
    }
  }

  private var profileAvatarOptions: [ProfileAvatarChoice] {
    ProfileAvatarChoice.allCases
  }

  // MARK: Classes

  private var classesStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Set up your Levels",
        subtitle:
          "RooMate's bell schedule already knows when each Level meets. You just tell it what class belongs there.",
        icon: "books.vertical.fill",
        tint: DesignTokens.Colors.schedule
      ) {
        HStack(spacing: 14) {
          Label(
            "\(configuredClassCount) of \(Level.allCases.count) set up",
            systemImage: configuredClassCount == Level.allCases.count
              ? "checkmark.circle.fill" : "circle.dotted"
          )
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(
            configuredClassCount == Level.allCases.count
              ? DesignTokens.Colors.success : DesignTokens.Colors.secondaryText)
          Spacer()
          Text("Set each class’s name, icon, color, and meeting days here.")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
      }

      HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 6) {
          ForEach(Level.allCases) { level in
            classLevelButton(level)
          }
        }
        .frame(width: 178)

        classEditor(selectedClassLevel)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private func classLevelButton(_ level: Level) -> some View {
    let assignment = store.assignments[level] ?? .default(for: level)
    let selected = selectedClassLevel == level
    let trimmed = assignment.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let configured = assignment.isFree || (!trimmed.isEmpty && trimmed != level.displayName)

    return Button {
      withAnimation(DesignTokens.Animation.quick) {
        selectedClassLevel = level
      }
    } label: {
      HStack(spacing: 9) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(assignment.color.swiftUIColor.opacity(selected ? 0.19 : 0.10))
          Image(systemName: assignment.displaySystemImage(for: level))
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(assignment.color.swiftUIColor)
        }
        .frame(width: 30, height: 30)

        VStack(alignment: .leading, spacing: 1) {
          Text(level.displayName)
            .font(.system(size: 10.5, weight: .semibold))
          Text(
            assignment.isFree
              ? "Free" : (configured ? assignment.displayTitle(for: level) : "Set up")
          )
          .font(.system(size: 8.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(1)
        }

        Spacer(minLength: 2)

        if configured {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.success)
        }
      }
      .padding(.horizontal, 8)
      .frame(height: 42)
      .background(
        selected
          ? DesignTokens.Colors.schedule.opacity(0.09) : DesignTokens.Colors.hover.opacity(0.20),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(
            selected ? DesignTokens.Colors.schedule.opacity(0.42) : DesignTokens.Colors.border,
            lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func classEditor(_ level: Level) -> some View {
    let assignment = store.binding(for: level)
    let value = assignment.wrappedValue
    let color = value.color.swiftUIColor

    return VStack(alignment: .leading, spacing: 15) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.opacity(0.14))
          Image(systemName: value.displaySystemImage(for: level))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
        }
        .frame(width: 46, height: 46)

        VStack(alignment: .leading, spacing: 2) {
          Text(level.displayName)
            .font(.system(size: 17, weight: .semibold))
          Text(
            value.isFree
              ? "RooMate will show this as free time."
              : "Set the class details, icon, color, and meeting pattern here."
          )
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        Spacer()

        Toggle("Free", isOn: assignment.isFree)
          .toggleStyle(.switch)
          .controlSize(.small)
      }

      if !value.isFree {
        VStack(alignment: .leading, spacing: 10) {
          onboardingTextField("CLASS NAME", placeholder: "e.g. Chemistry", text: assignment.title)

          HStack(spacing: 10) {
            onboardingTextField("TEACHER", placeholder: "Teacher", text: assignment.teacher)
            onboardingTextField("ROOM", placeholder: "Room", text: assignment.room)
              .frame(maxWidth: 170)
          }
        }

        OnboardingClassIconPicker(
          selection: assignment.iconName,
          fallback: ClassIconOption.defaultOption(for: level),
          tint: color
        )

        VStack(alignment: .leading, spacing: 7) {
          Text("COLOR")
            .onboardingFieldLabel()
          HStack(spacing: 7) {
            ForEach(Array(classColorOptions.enumerated()), id: \.offset) { _, option in
              let optionColor = CodableColor(option)
              let selected = value.color == optionColor
              Button {
                assignment.color.wrappedValue = optionColor
              } label: {
                ZStack {
                  Circle()
                    .fill(option)
                    .frame(width: 24, height: 24)
                  if selected {
                    Image(systemName: "checkmark")
                      .font(.system(size: 8, weight: .black))
                      .foregroundStyle(.white)
                  }
                }
              }
              .buttonStyle(.plain)
            }

            ColorPicker(
              "Any color",
              selection: Binding(
                get: { assignment.wrappedValue.color.swiftUIColor },
                set: { assignment.color.wrappedValue = CodableColor($0) }
              ),
              supportsOpacity: false
            )
            .labelsHidden()
            .help("Choose any class color")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider().overlay(DesignTokens.Colors.border)

        VStack(alignment: .leading, spacing: 10) {
          Toggle(
            "Meets every scheduled day",
            isOn: Binding(
              get: { assignment.wrappedValue.meetsEveryDay },
              set: { meetsEveryDay in
                var updated = assignment.wrappedValue
                updated.meetsEveryDay = meetsEveryDay
                if meetsEveryDay {
                  updated.daysNotMeeting = []
                } else if updated.replacementClass == nil {
                  updated.replacementClass = .init(
                    title: "", teacher: "", room: "", isFree: true)
                }
                assignment.wrappedValue = updated
              }
            )
          )
          .toggleStyle(.switch)
          .controlSize(.small)
          .font(.system(size: 10.5, weight: .semibold))

          if !assignment.wrappedValue.meetsEveryDay {
            VStack(alignment: .leading, spacing: 7) {
              Text("MEETING DAYS")
                .onboardingFieldLabel()
              HStack(spacing: 6) {
                ForEach(Weekday.allCases) { weekday in
                  let meets = !assignment.wrappedValue.daysNotMeeting.contains(
                    weekday.calendarWeekdayIndex)
                  Button {
                    toggleClassMeetingDay(level, weekday: weekday)
                  } label: {
                    Text(String(weekday.title.prefix(3)))
                      .font(.system(size: 9.5, weight: .semibold))
                      .foregroundStyle(
                        meets ? DesignTokens.Colors.schedule : DesignTokens.Colors.secondaryText
                      )
                      .frame(maxWidth: .infinity)
                      .frame(height: 29)
                      .background(
                        meets
                          ? DesignTokens.Colors.schedule.opacity(0.11)
                          : DesignTokens.Colors.hover.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                      )
                      .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                          .strokeBorder(
                            meets
                              ? DesignTokens.Colors.schedule.opacity(0.35)
                              : DesignTokens.Colors.border,
                            lineWidth: 1)
                      }
                  }
                  .buttonStyle(.plain)
                }
              }
            }

            if !assignment.wrappedValue.daysNotMeeting.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Text("WHEN THIS CLASS DOESN'T MEET")
                  .onboardingFieldLabel()

                Toggle(
                  "Show as free time",
                  isOn: classReplacementFreeBinding(level)
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 10, weight: .semibold))

                if !(store.assignments[level]?.replacementClass?.isFree ?? true) {
                  HStack(spacing: 8) {
                    onboardingTextField(
                      "REPLACEMENT",
                      placeholder: "e.g. Lab / Study Hall",
                      text: classReplacementTextBinding(level, keyPath: \.title)
                    )
                    onboardingTextField(
                      "ROOM",
                      placeholder: "Room",
                      text: classReplacementTextBinding(level, keyPath: \.room)
                    )
                    .frame(maxWidth: 150)
                  }
                }
              }
              .padding(10)
              .background(
                DesignTokens.Colors.schedule.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
              )
            }
          }
        }
      } else {
        HStack(spacing: 9) {
          Image(systemName: "cup.and.saucer.fill")
            .foregroundStyle(DesignTokens.Colors.pacTrack)
          Text(
            "Free periods still appear in Today and Schedule, but RooMate won't attach a teacher or room."
          )
          .font(.system(size: 10.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          DesignTokens.Colors.pacTrack.opacity(0.08),
          in: RoundedRectangle(cornerRadius: 11, style: .continuous))
      }
    }
    .padding(16)
    .rooSurface(cornerRadius: 16, elevated: false, border: true)
  }

  private func toggleClassMeetingDay(_ level: Level, weekday: Weekday) {
    var assignment = store.assignments[level] ?? .default(for: level)
    assignment.meetsEveryDay = false
    if assignment.daysNotMeeting.contains(weekday.calendarWeekdayIndex) {
      assignment.daysNotMeeting.remove(weekday.calendarWeekdayIndex)
    } else {
      assignment.daysNotMeeting.insert(weekday.calendarWeekdayIndex)
    }
    if assignment.replacementClass == nil {
      assignment.replacementClass = .init(title: "", teacher: "", room: "", isFree: true)
    }
    store.assignments[level] = assignment
  }

  private func classReplacementFreeBinding(_ level: Level) -> Binding<Bool> {
    Binding(
      get: { store.assignments[level]?.replacementClass?.isFree ?? true },
      set: { isFree in
        var assignment = store.assignments[level] ?? .default(for: level)
        var replacement =
          assignment.replacementClass
          ?? .init(title: "", teacher: "", room: "", isFree: true)
        replacement.isFree = isFree
        assignment.replacementClass = replacement
        store.assignments[level] = assignment
      }
    )
  }

  private func classReplacementTextBinding(
    _ level: Level,
    keyPath: WritableKeyPath<ClassAssignment.ReplacementClass, String>
  ) -> Binding<String> {
    Binding(
      get: { store.assignments[level]?.replacementClass?[keyPath: keyPath] ?? "" },
      set: { value in
        var assignment = store.assignments[level] ?? .default(for: level)
        var replacement =
          assignment.replacementClass
          ?? .init(title: "", teacher: "", room: "", isFree: false)
        replacement[keyPath: keyPath] = value
        assignment.replacementClass = replacement
        store.assignments[level] = assignment
      }
    )
  }

  private var classColorOptions: [Color] {
    [
      DesignTokens.Colors.schedule,
      DesignTokens.Colors.pacTrack,
      DesignTokens.Colors.events,
      DesignTokens.Colors.athletics,
      DesignTokens.Colors.dining,
      DesignTokens.Colors.accent,
      DesignTokens.Colors.warning,
      DesignTokens.Colors.primary,
    ]
  }

  private struct OnboardingClassIconPicker: View {
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

        Divider().overlay(DesignTokens.Colors.border)

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

        Divider().overlay(DesignTokens.Colors.border)

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

  // MARK: Clubs

  private var clubsStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Club Directory",
        subtitle:
          "Find the clubs you attend and add them straight to My Clubs. You can also add one yourself if it is not listed.",
        icon: "rectangle.grid.2x2.fill",
        tint: DesignTokens.Colors.events
      ) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.secondaryText)

            TextField("Search the club directory", text: $clubDirectorySearch)
              .textFieldStyle(.plain)
              .font(.system(size: 11, weight: .medium))

            if !clubDirectorySearch.isEmpty {
              Button {
                clubDirectorySearch = ""
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 11, weight: .semibold))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 10)
          .frame(height: 36)
          .background(
            DesignTokens.Colors.hover.opacity(0.30),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
          }

          if clubDirectoryStore.isLoading && clubDirectoryStore.clubs.isEmpty {
            HStack(spacing: 9) {
              ProgressView()
                .controlSize(.small)
              Text("Loading the club directory…")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
          } else if clubDirectoryStore.clubs.isEmpty {
            VStack(spacing: 8) {
              Image(systemName: "rectangle.grid.2x2")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.events)
              Text(
                clubDirectoryStore.lastError == nil
                  ? "No directory clubs are available yet."
                  : "The directory could not load right now."
              )
              .font(.system(size: 10.5, weight: .semibold))
              Button("Try Again") {
                Task { await clubDirectoryStore.refresh() }
              }
              .font(.system(size: 10, weight: .semibold))
              .buttonStyle(.plain)
              .foregroundStyle(DesignTokens.Colors.events)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
          } else {
            let entries = filteredOnboardingDirectoryEntries
            if entries.isEmpty {
              Text("No clubs match that search.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 56)
            } else {
              LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)],
                spacing: 9
              ) {
                ForEach(entries) { entry in
                  onboardingDirectoryClubCard(entry)
                }
              }
            }
          }
        }
      }

      onboardingCard(
        title: "My Clubs",
        subtitle:
          "After adding a club, set the exact meeting details RooMate should use in Today, Schedule, the sidebar, and notifications.",
        icon: "person.3.fill",
        tint: DesignTokens.Colors.events
      ) {
        HStack(spacing: 10) {
          Label(
            store.clubs.isEmpty
              ? "No clubs selected"
              : "\(store.clubs.count) club\(store.clubs.count == 1 ? "" : "s")",
            systemImage: "person.3"
          )
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          Spacer()
          Button {
            withAnimation(DesignTokens.Animation.snappy) {
              store.clubs.append(Club())
            }
          } label: {
            Label("Add It Yourself", systemImage: "plus")
              .font(.system(size: 10.5, weight: .semibold))
              .padding(.horizontal, 10)
              .frame(height: 31)
          }
          .buttonStyle(.plain)
          .rooInteractiveGlass(cornerRadius: 9)
        }
      }

      if store.clubs.isEmpty {
        HStack(spacing: 10) {
          Image(systemName: "arrow.up")
            .foregroundStyle(DesignTokens.Colors.events)
          Text("Choose clubs from the directory, or add one yourself if it’s missing.")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rooSurface(cornerRadius: 13, elevated: false, border: true)
      } else {
        VStack(spacing: 10) {
          ForEach(store.clubs.indices, id: \.self) { index in
            simpleClubEditor(index)
          }
        }

        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(DesignTokens.Colors.success)
          Text(
            "Set built-in club periods, exact Level or school-block meetings, room, icon, any color, notes, and additional or after-school meeting times here."
          )
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .padding(.horizontal, 4)
      }
    }
    .task {
      if clubDirectoryStore.clubs.isEmpty && clubDirectoryStore.isConfigured {
        await clubDirectoryStore.refresh()
      }
    }
  }

  private func simpleClubEditor(_ index: Int) -> some View {
    guard store.clubs.indices.contains(index) else { return AnyView(EmptyView()) }
    let clubID = store.clubs[index].id
    let club = Binding<Club>(
      get: { store.clubs.first(where: { $0.id == clubID }) ?? Club(id: clubID) },
      set: { updated in
        guard let liveIndex = store.clubs.firstIndex(where: { $0.id == clubID }) else { return }
        store.clubs[liveIndex] = updated
      }
    )

    return AnyView(
      ClubEditorRow(
        club: club,
        onDelete: {
          withAnimation(DesignTokens.Animation.snappy) {
            store.clubs.removeAll { $0.id == clubID }
          }
        }
      )
    )
  }

  private var filteredOnboardingDirectoryEntries: [ClubDirectoryEntry] {
    let query = clubDirectorySearch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return clubDirectoryStore.clubs }
    return clubDirectoryStore.clubs.filter { entry in
      entry.name.localizedCaseInsensitiveContains(query)
        || entry.category.localizedCaseInsensitiveContains(query)
        || entry.description.localizedCaseInsensitiveContains(query)
    }
  }

  private func onboardingDirectoryClubCard(_ entry: ClubDirectoryEntry) -> some View {
    let tint = onboardingDirectoryColor(entry.colorHex)
    let added = isOnboardingDirectoryClubAdded(entry)

    return HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(tint.opacity(0.13))
        Image(systemName: entry.iconName)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(tint)
      }
      .frame(width: 39, height: 39)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.name)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)
        Text(entry.category.isEmpty ? "Club" : entry.category)
          .font(.system(size: 8.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      Button {
        toggleOnboardingDirectoryClub(entry)
      } label: {
        Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(added ? DesignTokens.Colors.success : tint)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(added ? "Remove from My Clubs" : "Add to My Clubs")
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
    .background(
      added ? DesignTokens.Colors.success.opacity(0.055) : DesignTokens.Colors.hover.opacity(0.22),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          added ? DesignTokens.Colors.success.opacity(0.30) : DesignTokens.Colors.border,
          lineWidth: 1
        )
    }
  }

  private func isOnboardingDirectoryClubAdded(_ entry: ClubDirectoryEntry) -> Bool {
    store.clubs.contains { club in
      club.name.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(entry.name.trimmingCharacters(in: .whitespacesAndNewlines))
        == .orderedSame
    }
  }

  private func toggleOnboardingDirectoryClub(_ entry: ClubDirectoryEntry) {
    if let index = store.clubs.firstIndex(where: { club in
      club.name.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(entry.name.trimmingCharacters(in: .whitespacesAndNewlines))
        == .orderedSame
    }) {
      withAnimation(DesignTokens.Animation.snappy) {
        _ = store.clubs.remove(at: index)
      }
      return
    }

    let club = Club(
      name: entry.name,
      color: CodableColor(onboardingDirectoryColor(entry.colorHex)),
      iconName: entry.iconName
    )
    withAnimation(DesignTokens.Animation.snappy) {
      store.clubs.append(club)
    }
  }

  private func onboardingDirectoryColor(_ hex: String) -> Color {
    let trimmed =
      hex
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
      return DesignTokens.Colors.events
    }
    return Color(hex: value)
  }

  // MARK: PacTrack

  private var pacTrackStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Start your PacTrack plan",
        subtitle:
          "Select the activities you're expecting to use toward this year's RooPAC requirement. This is a plan, not an official submission.",
        icon: "chart.bar.xaxis",
        tint: DesignTokens.Colors.pacTrack
      ) {
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(DesignTokens.Colors.pacTrack.opacity(0.12))
            Image(systemName: "graduationcap.fill")
              .foregroundStyle(DesignTokens.Colors.pacTrack)
          }
          .frame(width: 42, height: 42)

          VStack(alignment: .leading, spacing: 2) {
            Text(store.rooPACCurrentGrade.title)
              .font(.system(size: 12.5, weight: .semibold))
            Text("\(store.rooPACCurrentGrade.requirement) RooPACs required this year")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Text("\(selectedPacTrackCount) selected")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.pacTrack)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(DesignTokens.Colors.pacTrack.opacity(0.10), in: Capsule())
        }
      }

      VStack(spacing: 8) {
        ForEach(RooPACActivityType.officialCases) { activity in
          pacTrackActivityRow(activity)
        }
      }
    }
  }

  private func pacTrackActivityRow(_ activity: RooPACActivityType) -> some View {
    let plan = store.rooPacPlans[activity] ?? RooPACPlan()
    let selected = plan.isSelected
    let credits = plan.overrideCredits ?? activity.minCredits

    return VStack(alignment: .leading, spacing: 9) {
      Button {
        withAnimation(DesignTokens.Animation.quick) {
          togglePacActivity(activity)
        }
      } label: {
        HStack(spacing: 11) {
          ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
              .fill(
                selected
                  ? DesignTokens.Colors.pacTrack.opacity(0.14)
                  : DesignTokens.Colors.hover.opacity(0.24))
            Image(systemName: activity.icon)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(
                selected ? DesignTokens.Colors.pacTrack : DesignTokens.Colors.secondaryText)
          }
          .frame(width: 36, height: 36)

          VStack(alignment: .leading, spacing: 2) {
            Text(activity.shortTitle)
              .font(.system(size: 11.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)
            Text(activity.rangeDescription)
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(
              selected ? DesignTokens.Colors.pacTrack : DesignTokens.Colors.subtleText)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if selected {
        if activity == .other {
          HStack(spacing: 9) {
            TextField(
              "Activity name",
              text: Binding(
                get: { store.rooPacPlans[activity]?.customTitle ?? "" },
                set: { title in
                  var updated = store.rooPacPlans[activity] ?? RooPACPlan(isSelected: true)
                  updated.customTitle = title
                  store.rooPacPlans[activity] = updated
                }
              )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(
              DesignTokens.Colors.hover.opacity(0.26),
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
            }

            Stepper(
              "\(credits) RooPAC\(credits == 1 ? "" : "s")",
              value: pacCreditsBinding(activity),
              in: 0...12
            )
            .font(.system(size: 10, weight: .semibold))
            .controlSize(.small)
            .fixedSize()
          }
          .padding(.leading, 47)
        } else if activity.hasVariableValue {
          HStack {
            Text("Planned value")
              .font(.system(size: 9.5, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
            Spacer()
            Stepper(
              "\(credits) RooPAC\(credits == 1 ? "" : "s")",
              value: pacCreditsBinding(activity),
              in: activity.minCredits...activity.maxCredits
            )
            .font(.system(size: 10, weight: .semibold))
            .controlSize(.small)
            .fixedSize()
          }
          .padding(.leading, 47)
        }
      }
    }
    .padding(11)
    .background(
      selected
        ? DesignTokens.Colors.pacTrack.opacity(0.055) : DesignTokens.Colors.hover.opacity(0.16),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          selected ? DesignTokens.Colors.pacTrack.opacity(0.30) : DesignTokens.Colors.border,
          lineWidth: 1)
    }
  }

  private func togglePacActivity(_ activity: RooPACActivityType) {
    var plan = store.rooPacPlans[activity] ?? RooPACPlan()
    plan.isSelected.toggle()
    if plan.isSelected && activity.hasVariableValue && plan.overrideCredits == nil {
      plan.overrideCredits = activity == .other ? 1 : activity.minCredits
    }
    if !plan.isSelected {
      plan.overrideCredits = nil
    }
    store.rooPacPlans[activity] = plan
  }

  private func pacCreditsBinding(_ activity: RooPACActivityType) -> Binding<Int> {
    Binding(
      get: {
        store.rooPacPlans[activity]?.overrideCredits ?? activity.minCredits
      },
      set: { newValue in
        var plan = store.rooPacPlans[activity] ?? RooPACPlan(isSelected: true)
        plan.isSelected = true
        plan.overrideCredits = min(max(newValue, activity.minCredits), activity.maxCredits)
        store.rooPacPlans[activity] = plan
      }
    )
  }

  // MARK: Sports

  private var sportsStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Sports games and reminders",
        subtitle:
          "Browse upcoming games and choose only the matchups you want RooMate to remind you about.",
        icon: "sportscourt.fill",
        tint: DesignTokens.Colors.athletics
      ) {
        HStack(spacing: 10) {
          Image(systemName: "wrench.and.screwdriver.fill")
            .foregroundStyle(DesignTokens.Colors.athletics)
          Text("Team pages are unavailable for now. You can still see who is playing in each game.")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
      }

      if sportsStore.isLoading && onboardingSportsGames.isEmpty {
        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          Text("Loading games…")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .rooSurface(cornerRadius: 15, elevated: false, border: true)
      } else if onboardingSportsGames.isEmpty {
        VStack(spacing: 11) {
          Image(systemName: "wifi.exclamationmark")
            .font(.system(size: 23, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.warning)
          Text("Games aren't available right now")
            .font(.system(size: 13.5, weight: .semibold))
          Text("You can continue setup and check Sports again later.")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
          Button("Try Again") { sportsStore.refresh() }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .rooSurface(cornerRadius: 15, elevated: false, border: true)
      } else {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 9)], spacing: 9) {
          ForEach(onboardingSportsGames) { game in
            sportsGameReminderChoice(game)
          }
        }
      }
    }
  }

  private func sportsGameReminderChoice(_ game: SportsGame) -> some View {
    let selected = savedGameIDs.contains(game.id)
    let tint = SportIconConfiguration.teamColor(for: game.team)

    return Button {
      var gameIDs = savedGameIDs
      if selected {
        gameIDs.remove(game.id)
      } else {
        gameIDs.insert(game.id)
      }
      savedGameIDsRaw = gameIDs.sorted().joined(separator: "\n")
      NotificationCenter.default.post(name: .rooMateSportsPreferencesDidChange, object: nil)
    } label: {
      HStack(spacing: 10) {
        SportIconConfiguration.icon(for: game.team)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 32, height: 32)
          .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

        VStack(alignment: .leading, spacing: 3) {
          Text(game.team)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .lineLimit(1)
          Text(game.opponent.isEmpty ? game.rawDateString : "vs \(game.opponent) • \(game.rawDateString)")
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(1)
        }

        Spacer(minLength: 4)

        Image(systemName: selected ? "bell.fill" : "bell")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(selected ? tint : DesignTokens.Colors.subtleText)
      }
      .padding(.horizontal, 10)
      .frame(minHeight: 50)
      .contentShape(Rectangle())
      .background(
        selected ? tint.opacity(0.07) : DesignTokens.Colors.hover.opacity(0.15),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
          .strokeBorder(selected ? tint.opacity(0.36) : DesignTokens.Colors.border, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .help(selected ? "Remove game reminder" : "Remind me about this game")
  }

  // MARK: Events

  private var eventsStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Choose your event calendars",
        subtitle:
          "Pick one or several school calendars. All Events is the convenience option that includes everything.",
        icon: "calendar.badge.clock",
        tint: DesignTokens.Colors.events
      ) {
        VStack(spacing: 7) {
          eventSourceOnboardingRow(.allEvents)
          Divider().overlay(DesignTokens.Colors.border)
          ForEach(CalendarSource.individualCases) { source in
            eventSourceOnboardingRow(source)
          }
        }
      }

      onboardingCard(
        title: "Default Events view",
        subtitle: "Choose how Events opens. You can switch views at any time.",
        icon: "calendar",
        tint: DesignTokens.Colors.events
      ) {
        HStack(spacing: 8) {
          ForEach(CalendarGroupingMode.allCases) { grouping in
            let selected = eventsStore.selectedGrouping == grouping
            Button {
              eventsStore.selectedGrouping = grouping
            } label: {
              Text(grouping.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(
                  selected ? DesignTokens.Colors.events : DesignTokens.Colors.secondaryText
                )
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                  selected
                    ? DesignTokens.Colors.events.opacity(0.11)
                    : DesignTokens.Colors.hover.opacity(0.22),
                  in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                      selected
                        ? DesignTokens.Colors.events.opacity(0.34)
                        : DesignTokens.Colors.border,
                      lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func eventSourceOnboardingRow(_ source: CalendarSource) -> some View {
    let selected = eventsStore.selectedSources.contains(source)
    return Button {
      withAnimation(DesignTokens.Animation.quick) {
        eventsStore.toggleSource(source)
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: selected ? "checkmark.square.fill" : "square")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(selected ? DesignTokens.Colors.events : DesignTokens.Colors.subtleText)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text(source.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          if source == .allEvents {
            Text("Includes All School, Upper School, Middle School, and Lower School")
              .font(.system(size: 9.2, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }
        Spacer()
      }
      .padding(.horizontal, 9)
      .frame(minHeight: source == .allEvents ? 44 : 36)
      .contentShape(Rectangle())
      .background(
        selected ? DesignTokens.Colors.events.opacity(0.055) : Color.clear,
        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: App Preferences

  private var preferencesStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Appearance",
        subtitle: "Choose the theme RooMate should use everywhere.",
        icon: "circle.lefthalf.filled",
        tint: DesignTokens.Colors.settings
      ) {
        HStack(spacing: 8) {
          ForEach(AppearancePreference.allCases) { appearance in
            let selected = store.appearance == appearance
            Button {
              withAnimation(DesignTokens.Animation.content) {
                store.appearance = appearance
              }
            } label: {
              HStack(spacing: 7) {
                Image(systemName: appearance.systemImage)
                Text(appearance.title)
              }
              .font(.system(size: 10.5, weight: .semibold))
              .foregroundStyle(
                selected ? DesignTokens.Colors.settings : DesignTokens.Colors.secondaryText
              )
              .frame(maxWidth: .infinity)
              .frame(height: 35)
              .background(
                selected
                  ? DesignTokens.Colors.settings.opacity(0.11)
                  : DesignTokens.Colors.hover.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .strokeBorder(
                    selected
                      ? DesignTokens.Colors.settings.opacity(0.34)
                      : DesignTokens.Colors.border,
                    lineWidth: 1)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }

      #if canImport(ServiceManagement)
        onboardingCard(
          title: "Startup",
          subtitle: "Choose whether RooMate should be ready when you sign in to your Mac.",
          icon: "power",
          tint: DesignTokens.Colors.settings
        ) {
          onboardingToggleRow(
            title: "Open at Login",
            subtitle: launchAtLoginStatusText,
            systemImage: "power",
            tint: DesignTokens.Colors.success,
            isOn: launchAtLoginBinding,
            disabled: false
          )
        }

        if let launchAtLoginError {
          Text(launchAtLoginError)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.destructive)
        }
      #endif

      HStack(spacing: 8) {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Text(
          "Other optional Mac utilities stay in Settings so first-run setup remains focused on the choices that affect your RooMate experience."
        )
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 4)
    }
    #if canImport(ServiceManagement)
      .onAppear { refreshOnboardingLaunchAtLoginStatus() }
    #endif
  }

  #if canImport(ServiceManagement)
    private var launchAtLoginBinding: Binding<Bool> {
      Binding(
        get: {
          launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval
        },
        set: { enabled in
          setOnboardingLaunchAtLogin(enabled)
        }
      )
    }

    private var launchAtLoginStatusText: String {
      switch launchAtLoginStatus {
      case .enabled:
        return "Open RooMate automatically when you sign in."
      case .requiresApproval:
        return "Allow RooMate in System Settings before it can open when you log in."
      case .notRegistered:
        return "Off by default. Turn it on if you want RooMate ready at sign-in."
      case .notFound:
        return "This copy of RooMate can’t open automatically when you log in."
      @unknown default:
        return "RooMate couldn’t check this setting right now."
      }
    }

    private func refreshOnboardingLaunchAtLoginStatus() {
      launchAtLoginStatus = SMAppService.mainApp.status
    }

    private func setOnboardingLaunchAtLogin(_ enabled: Bool) {
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
        launchAtLoginError = "RooMate couldn’t change this setting. You can skip it and try again later in Settings."
      }
      refreshOnboardingLaunchAtLoginStatus()
    }
  #endif

  // MARK: Notifications

  private var notificationsStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Choose exactly what RooMate can remind you about",
        subtitle:
          "Permission is requested only if you choose Enable. Every reminder type stays individually controllable here and later in Settings.",
        icon: "bell.badge.fill",
        tint: DesignTokens.Colors.warning
      ) {
        HStack(spacing: 12) {
          ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
              .fill(notificationStatusTint.opacity(0.12))
            Image(systemName: notificationStatusIcon)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(notificationStatusTint)
          }
          .frame(width: 44, height: 44)

          VStack(alignment: .leading, spacing: 2) {
            Text(notificationStatusTitle)
              .font(.system(size: 12.5, weight: .semibold))
            Text(notificationStatusDetail)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }

          Spacer()

          if notificationsAreActive {
            Button {
              notificationsChoiceMade = true
              Task { @MainActor in
                await store.setNotificationsEnabled(false)
              }
            } label: {
              Label("On", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.Colors.success)
            .controlSize(.small)
          } else if store.notificationAuthStatus == .denied {
            Button("System Settings") {
              openNotificationSystemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          } else {
            Button {
              notificationsChoiceMade = true
              Task { @MainActor in
                await store.setNotificationsEnabled(true)
              }
            } label: {
              Label("Enable", systemImage: "bell.badge.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.warning)
            .controlSize(.small)
          }
        }
      }

      onboardingCard(
        title: "School day reminders",
        subtitle: "Class and club reminders are sent shortly before the thing you need to get to.",
        icon: "clock.badge.checkmark",
        tint: DesignTokens.Colors.schedule
      ) {
        VStack(spacing: 0) {
          onboardingToggleRow(
            title: "Class starting soon",
            subtitle: "5 minutes before a class begins.",
            systemImage: "bell.and.waves.left.and.right.fill",
            tint: DesignTokens.Colors.schedule,
            isOn: $store.notifyClassStartingSoon,
            disabled: !notificationsAreActive
          )
          Divider().overlay(DesignTokens.Colors.border)
          onboardingToggleRow(
            title: "Class ending soon",
            subtitle: "5 minutes before a class ends.",
            systemImage: "hourglass.bottomhalf.filled",
            tint: DesignTokens.Colors.warning,
            isOn: $store.notifyClassEndingSoon,
            disabled: !notificationsAreActive
          )
          Divider().overlay(DesignTokens.Colors.border)
          onboardingToggleRow(
            title: "Club meetings",
            subtitle: "5 minutes before My Clubs meetings, including additional meetings.",
            systemImage: "person.3.fill",
            tint: DesignTokens.Colors.events,
            isOn: $store.notifyClubMeetings,
            disabled: !notificationsAreActive
          )
          Divider().overlay(DesignTokens.Colors.border)
          onboardingToggleRow(
            title: "Special schedules & closures",
            subtitle: "A 7:15 AM heads-up when today's schedule is different or school is closed.",
            systemImage: "calendar.badge.exclamationmark",
            tint: DesignTokens.Colors.warning,
            isOn: $store.notifySpecialScheduleMorning,
            disabled: !notificationsAreActive
          )
        }
      }

      onboardingCard(
        title: "Dining & Events",
        subtitle: "Optional reminders for the things you save in RooMate. Sports reminders are selected per game.",
        icon: "sparkles",
        tint: DesignTokens.Colors.warning
      ) {
        VStack(spacing: 0) {
          onboardingToggleRow(
            title: "Lunch menu",
            subtitle: "15 minutes before your first lunch block, remind you today's menu is ready.",
            systemImage: "fork.knife",
            tint: DesignTokens.Colors.dining,
            isOn: $store.notifyDiningLunch,
            disabled: !notificationsAreActive
          )
          Divider().overlay(DesignTokens.Colors.border)
          onboardingToggleRow(
            title: "Selected event calendars",
            subtitle:
              "30 minutes before events in the calendars you selected; 8:00 AM for all-day events.",
            systemImage: "calendar.badge.clock",
            tint: DesignTokens.Colors.events,
            isOn: Binding(
              get: { notifyCalendarEvents },
              set: { enabled in
                notifyCalendarEvents = enabled
                NotificationCenter.default.post(
                  name: .rooMateEventPreferencesDidChange,
                  object: nil
                )
              }
            ),
            disabled: !notificationsAreActive
          )
          Divider().overlay(DesignTokens.Colors.border)
          onboardingToggleRow(
            title: "Saved events",
            subtitle: "30 minutes before timed events; 8:00 AM for saved all-day events.",
            systemImage: "bookmark.fill",
            tint: DesignTokens.Colors.events,
            isOn: Binding(
              get: { notifySavedEvents },
              set: { enabled in
                notifySavedEvents = enabled
                NotificationCenter.default.post(
                  name: .rooMateEventPreferencesDidChange,
                  object: nil
                )
              }
            ),
            disabled: !notificationsAreActive
          )
        }
      }

      HStack(spacing: 8) {
        Image(systemName: "hand.raised.fill")
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Text(
          "RooMate schedules these locally from the data already used by the app. You can pause everything for an hour or the rest of the day from Settings."
        )
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 4)
    }
    .task {
      await store.refreshNotificationStatus()
    }
  }

  private var notificationsAreActive: Bool {
    #if canImport(UserNotifications)
      return store.notificationsEnabled
        && (store.notificationAuthStatus == .authorized
          || store.notificationAuthStatus == .provisional)
    #else
      return store.notificationsEnabled
    #endif
  }

  private var notificationStatusTitle: String {
    #if canImport(UserNotifications)
      switch store.notificationAuthStatus {
      case .authorized, .provisional:
        return store.notificationsEnabled
          ? "Notifications are on" : "Notifications are paused in RooMate"
      case .denied:
        return "Notifications are off in System Settings"
      case .notDetermined:
        return "Notifications haven’t been turned on"
      @unknown default:
        return "RooMate couldn’t check notification settings"
      }
    #else
      return store.notificationsEnabled ? "Notifications are on" : "Notifications are off"
    #endif
  }

  private var notificationStatusDetail: String {
    #if canImport(UserNotifications)
      switch store.notificationAuthStatus {
      case .authorized, .provisional:
        return store.notificationsEnabled
          ? "RooMate can send your selected schedule reminders."
          : "You can enable them again whenever you want."
      case .denied:
        return "Allow RooMate in System Settings if you want reminders."
      case .notDetermined:
        return "Nothing is sent until you explicitly enable notifications."
      @unknown default:
        return "You can continue setup without notifications."
      }
    #else
      return "You can change this later in Settings."
    #endif
  }

  private var notificationStatusIcon: String {
    #if canImport(UserNotifications)
      switch store.notificationAuthStatus {
      case .authorized, .provisional:
        return store.notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill"
      case .denied: return "bell.slash.fill"
      case .notDetermined: return "bell.fill"
      @unknown default: return "questionmark.circle.fill"
      }
    #else
      return store.notificationsEnabled ? "bell.badge.fill" : "bell.slash.fill"
    #endif
  }

  private var notificationStatusTint: Color {
    #if canImport(UserNotifications)
      switch store.notificationAuthStatus {
      case .authorized, .provisional:
        return store.notificationsEnabled
          ? DesignTokens.Colors.success : DesignTokens.Colors.secondaryText
      case .denied: return DesignTokens.Colors.destructive
      case .notDetermined: return DesignTokens.Colors.warning
      @unknown default: return DesignTokens.Colors.secondaryText
      }
    #else
      return store.notificationsEnabled
        ? DesignTokens.Colors.success : DesignTokens.Colors.secondaryText
    #endif
  }

  private func openNotificationSystemSettings() {
    #if canImport(AppKit)
      guard
        let url = URL(
          string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
      else { return }
      NSWorkspace.shared.open(url)
    #endif
  }

  // MARK: Sidebar

  private var sidebarStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      onboardingCard(
        title: "Make the sidebar yours",
        subtitle:
          "Choose what stays visible, pin favorites, and put sections in the order you want. The preview updates as you edit.",
        icon: "sidebar.left",
        tint: DesignTokens.Colors.settings
      ) {
        HStack(spacing: 14) {
          Label(
            "\(sidebarChoices.filter { protectedSidebarChoiceIDs.contains($0.id) || !store.sidebarHidden.contains($0.id) }.count) visible",
            systemImage: "eye.fill")
          Label(
            "\(sidebarChoices.filter { store.sidebarFavorites.contains($0.id) }.count) pinned",
            systemImage: "pin.fill")
          Spacer()
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      HStack(alignment: .top, spacing: 14) {
        VStack(spacing: 7) {
          ForEach(sidebarChoices) { choice in
            sidebarChoiceRow(choice)
          }
        }
        .frame(maxWidth: .infinity)

        onboardingSidebarPreview
          .frame(width: 220)
      }
    }
    .onAppear { ensureOnboardingSidebarOrder() }
  }

  private var onboardingSidebarPreview: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "figure.kangaroo")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primary)
        VStack(alignment: .leading, spacing: 0) {
          Text("RooMate")
            .font(.system(size: 12, weight: .bold))
          Text("SIDEBAR PREVIEW")
            .font(.system(size: 7.2, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }
      }
      .padding(.bottom, 3)

      let visibleChoices = sidebarChoices.filter {
        protectedSidebarChoiceIDs.contains($0.id) || !store.sidebarHidden.contains($0.id)
      }
      let pinnedChoices = visibleChoices.filter { store.sidebarFavorites.contains($0.id) }
      let regularChoices = visibleChoices.filter { !store.sidebarFavorites.contains($0.id) }

      if !pinnedChoices.isEmpty {
        Text("PINNED")
          .font(.system(size: 7.5, weight: .bold))
          .tracking(0.8)
          .foregroundStyle(DesignTokens.Colors.subtleText)
        ForEach(pinnedChoices) { choice in
          if choice.id == "Profile" {
            onboardingSidebarPreviewProfile(pinned: true)
          } else {
            onboardingSidebarPreviewRow(choice, pinned: true)
          }
        }
        Divider().overlay(DesignTokens.Colors.border)
      }

      ForEach(regularChoices) { choice in
        if choice.id == "Profile" {
          onboardingSidebarPreviewProfile(pinned: false)
        } else {
          onboardingSidebarPreviewRow(choice, pinned: false)
        }
      }

      Spacer(minLength: 8)

      VStack(alignment: .leading, spacing: 5) {
        Text("NOW")
          .font(.system(size: 7.2, weight: .bold))
          .tracking(0.9)
          .foregroundStyle(DesignTokens.Colors.subtleText)
        HStack(spacing: 7) {
          Circle()
            .fill(DesignTokens.Colors.schedule)
            .frame(width: 7, height: 7)
          VStack(alignment: .leading, spacing: 1) {
            Text("Your current block")
              .font(.system(size: 9, weight: .semibold))
            Text("Progress and what’s next")
              .font(.system(size: 7.8, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        DesignTokens.Colors.hover.opacity(0.24),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
    }
    .padding(12)
    .frame(minHeight: 390, alignment: .top)
    .background(
      DesignTokens.Colors.surface.opacity(0.88),
      in: RoundedRectangle(cornerRadius: 15, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  private func onboardingSidebarPreviewRow(_ choice: SidebarChoice, pinned: Bool) -> some View {
    HStack(spacing: 8) {
      Image(systemName: choice.systemImage)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(choice.tint)
        .frame(width: 17)
      Text(choice.title)
        .font(.system(size: 9.2, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)
      Spacer()
      if pinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 7.5, weight: .semibold))
          .foregroundStyle(choice.tint)
      }
    }
    .padding(.horizontal, 7)
    .frame(height: 27)
    .background(
      choice.id == "Dashboard"
        ? choice.tint.opacity(0.09)
        : Color.clear,
      in: RoundedRectangle(cornerRadius: 7, style: .continuous)
    )
  }

  private func onboardingSidebarPreviewProfile(pinned: Bool) -> some View {
    HStack(spacing: 8) {
      ProfileAvatarView(
        name: store.profileName,
        avatar: store.profileAvatar,
        accentColor: store.profileAccentColor,
        size: 18
      )
      Text(store.profileFirstName ?? "Profile")
        .font(.system(size: 9.2, weight: .semibold))
      Spacer()
      if pinned {
        Image(systemName: "pin.fill")
          .font(.system(size: 7.5, weight: .semibold))
          .foregroundStyle(store.profileAccentColor)
      }
    }
    .padding(.horizontal, 7)
    .frame(height: 27)
  }

  private func sidebarChoiceRow(_ choice: SidebarChoice) -> some View {
    let isProtected = protectedSidebarChoiceIDs.contains(choice.id)
    let visible = isProtected || !store.sidebarHidden.contains(choice.id)
    let pinned = store.sidebarFavorites.contains(choice.id)
    let index = sidebarChoices.firstIndex(where: { $0.id == choice.id }) ?? 0

    return HStack(spacing: 9) {
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.subtleText)
        .frame(width: 12)

      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(choice.tint.opacity(visible ? 0.13 : 0.055))
        Image(systemName: choice.systemImage)
          .font(.system(size: 12.5, weight: .semibold))
          .foregroundStyle(visible ? choice.tint : DesignTokens.Colors.subtleText)
      }
      .frame(width: 36, height: 36)

      VStack(alignment: .leading, spacing: 2) {
        Text(choice.title)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(
            visible ? DesignTokens.Colors.primaryText : DesignTokens.Colors.secondaryText)
        Text(
          isProtected
            ? "Always visible"
            : (visible
              ? (pinned ? "Visible • pinned to top" : "Visible in sidebar") : "Hidden from sidebar")
        )
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      HStack(spacing: 0) {
        Button {
          moveSidebarChoice(choice.id, direction: -1)
        } label: {
          Image(systemName: "chevron.up")
            .font(.system(size: 9, weight: .bold))
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(index == 0)
        .help("Move up")

        Button {
          moveSidebarChoice(choice.id, direction: 1)
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .bold))
            .frame(width: 24, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(index >= sidebarChoices.count - 1)
        .help("Move down")
      }
      .foregroundStyle(DesignTokens.Colors.secondaryText)

      Button {
        withAnimation(DesignTokens.Animation.quick) {
          toggleSidebarPin(choice.id)
        }
      } label: {
        Image(systemName: pinned ? "pin.fill" : "pin")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(pinned ? choice.tint : DesignTokens.Colors.secondaryText)
          .frame(width: 30, height: 30)
      }
      .buttonStyle(.plain)
      .disabled(!visible)
      .opacity(visible ? 1 : 0.35)
      .help(pinned ? "Unpin" : "Pin to top")

      Button {
        withAnimation(DesignTokens.Animation.quick) {
          toggleSidebarVisibility(choice.id)
        }
      } label: {
        Image(systemName: isProtected ? "lock.fill" : (visible ? "eye.fill" : "eye.slash"))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(
            isProtected
              ? DesignTokens.Colors.subtleText
              : (visible ? DesignTokens.Colors.secondaryText : DesignTokens.Colors.subtleText)
          )
          .frame(width: 30, height: 30)
      }
      .buttonStyle(.plain)
      .disabled(isProtected)
      .help(
        isProtected
          ? "Always shown in the sidebar" : (visible ? "Hide from sidebar" : "Show in sidebar"))
    }
    .padding(.horizontal, 11)
    .frame(height: 54)
    .background(
      DesignTokens.Colors.hover.opacity(visible ? 0.20 : 0.10),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
    .opacity(visible ? 1 : 0.70)
  }

  private func ensureOnboardingSidebarOrder() {
    let defaultIDs = [
      "Dashboard", "Schedule", "Dining", "Athletics", "Clubs", "Events", "PacTrack", "Profile",
      "Links", "Settings",
    ]
    let expected = Set(defaultIDs)
    let current = Set(store.sidebarOrder)
    if store.sidebarOrder.isEmpty || current != expected {
      store.sidebarOrder = defaultIDs
    }

    store.sidebarHidden.remove("Schedule")
    store.sidebarHidden.remove("Settings")
  }

  private func moveSidebarChoice(_ id: String, direction: Int) {
    ensureOnboardingSidebarOrder()

    var orderedChoices = sidebarChoices.map(\.id)
    guard let currentIndex = orderedChoices.firstIndex(of: id) else { return }
    let targetIndex = currentIndex + direction
    guard orderedChoices.indices.contains(targetIndex) else { return }

    orderedChoices.swapAt(currentIndex, targetIndex)

    var fullOrder = store.sidebarOrder
    guard fullOrder.count == orderedChoices.count else { return }
    for (slot, orderedID) in zip(fullOrder.indices, orderedChoices) {
      fullOrder[slot] = orderedID
    }

    store.sidebarOrder = fullOrder
    sidebarWasEdited = true
  }

  private func toggleSidebarVisibility(_ id: String) {
    guard !protectedSidebarChoiceIDs.contains(id) else {
      store.sidebarHidden.remove(id)
      return
    }

    if store.sidebarHidden.contains(id) {
      store.sidebarHidden.remove(id)
    } else {
      store.sidebarHidden.insert(id)
      store.sidebarFavorites.remove(id)
    }
    sidebarWasEdited = true
  }

  private func toggleSidebarPin(_ id: String) {
    if store.sidebarFavorites.contains(id) {
      store.sidebarFavorites.remove(id)
    } else {
      store.sidebarFavorites.insert(id)
    }
    sidebarWasEdited = true
  }

  // MARK: How RooMate Works

  private var tourStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .fill(DesignTokens.Colors.today.opacity(0.13))
            Image(systemName: "square.grid.2x2.fill")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.today)
          }
          .frame(width: 38, height: 38)

          VStack(alignment: .leading, spacing: 2) {
            Text("Start on Today")
              .font(.system(size: 14, weight: .semibold))
            Text("RooMate helps you quickly answer three questions about your day.")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
          }
        }

        HStack(spacing: 8) {
          tourFlowPill(
            number: "1", title: "NOW", detail: "What am I doing?", tint: DesignTokens.Colors.today)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
          tourFlowPill(
            number: "2", title: "NEXT", detail: "What comes after?",
            tint: DesignTokens.Colors.schedule)
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
          tourFlowPill(
            number: "3", title: "ACT", detail: "Where should I go?",
            tint: DesignTokens.Colors.primary)
        }
      }
      .padding(15)
      .rooSurface(cornerRadius: 15, elevated: false, border: true)

      VStack(alignment: .leading, spacing: 9) {
        Text("YOUR ROOMATE TOOLS")
          .font(.system(size: 8.5, weight: .bold))
          .tracking(1.2)
          .foregroundStyle(DesignTokens.Colors.subtleText)

        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3),
          spacing: 9
        ) {
          tourFeatureTile(
            icon: "calendar", title: "Schedule + Plan",
            detail: "Day, Week, special schedules, and Semester Planner.",
            tint: DesignTokens.Colors.schedule)
          tourFeatureTile(
            icon: "fork.knife", title: "Dining",
            detail: "Menus, stations, filters, favorites, and calendar browsing.",
            tint: DesignTokens.Colors.dining)
          tourFeatureTile(
            icon: "sportscourt.fill", title: "Sports",
            detail: "Games, schedule changes, and individual reminders.",
            tint: DesignTokens.Colors.athletics)
          tourFeatureTile(
            icon: "person.3.fill", title: "Clubs",
            detail: "Directory, My Clubs, and meetings in your schedule.",
            tint: DesignTokens.Colors.events)
          tourFeatureTile(
            icon: "calendar.circle.fill", title: "Events",
            detail: "Multiple calendars, saved events, and Day/Week/Month views.",
            tint: DesignTokens.Colors.events)
          tourFeatureTile(
            icon: "chart.bar.xaxis", title: "PacTrack",
            detail: "Plan RooPACs, including your own custom activities.",
            tint: DesignTokens.Colors.pacTrack)
          tourFeatureTile(
            icon: "link", title: "Links",
            detail: "Important resources, favorites, and your own custom links.",
            tint: DesignTokens.Colors.links)
          tourFeatureTile(
            icon: "megaphone.fill", title: "Announcements",
            detail: "Important RooMate notices appear directly on Today.",
            tint: DesignTokens.Colors.warning)
          tourFeatureTile(
            icon: "magnifyingglass", title: "Search",
            detail: "Press ⌘K to find pages, classes, clubs, events, games, and food.",
            tint: DesignTokens.Colors.primary)
        }
      }

      HStack(spacing: 9) {
        tourUtilityChip(
          icon: "magnifyingglass", title: "⌘K Search", tint: DesignTokens.Colors.primary)
        tourUtilityChip(
          icon: "calendar.badge.clock", title: "Special Schedules",
          tint: DesignTokens.Colors.schedule)
        tourUtilityChip(
          icon: "bell.badge.fill", title: "Smart Reminders", tint: DesignTokens.Colors.warning)
        tourUtilityChip(
          icon: "arrow.triangle.2.circlepath", title: "Auto Refresh",
          tint: DesignTokens.Colors.success)
      }

      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(DesignTokens.Colors.success)
        Text(
          "Your setup is already done. These are places to use RooMate, not more settings you need to finish."
        )
        .font(.system(size: 9.8, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.horizontal, 4)
    }
  }

  private func tourFlowPill(number: String, title: String, detail: String, tint: Color) -> some View
  {
    HStack(spacing: 9) {
      Text(number)
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(tint, in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 8.5, weight: .bold))
          .tracking(0.7)
          .foregroundStyle(tint)
        Text(detail)
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
      }
      Spacer(minLength: 2)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .frame(height: 48)
    .background(
      tint.opacity(0.06),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
  }

  private func tourFeatureTile(icon: String, title: String, detail: String, tint: Color)
    -> some View
  {
    HStack(alignment: .top, spacing: 9) {
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(tint.opacity(0.12))
        Image(systemName: icon)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(tint)
      }
      .frame(width: 30, height: 30)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
          .lineLimit(1)
        Text(detail)
          .font(.system(size: 8.8, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
    .background(
      DesignTokens.Colors.hover.opacity(0.18),
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  private func tourUtilityChip(icon: String, title: String, tint: Color) -> some View {
    HStack(spacing: 7) {
      Image(systemName: icon)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(tint)
      Text(title)
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(DesignTokens.Colors.primaryText)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .frame(height: 38)
    .background(
      tint.opacity(0.055),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  // MARK: Finish

  private var finishStep: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(spacing: 13) {
        ZStack {
          Circle()
            .fill(DesignTokens.Colors.success.opacity(0.12))
            .frame(width: 92, height: 92)
          Circle()
            .strokeBorder(DesignTokens.Colors.success.opacity(0.28), lineWidth: 1)
            .frame(width: 92, height: 92)
          Image(systemName: "checkmark")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.success)
        }

        Text(store.profileFirstName.map { "You're ready, \($0)." } ?? "You're ready.")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(
          "Your core setup is complete. Start on Today and let RooMate keep your schedule, activities, reminders, and school-day tools together. Everything you chose here stays editable later."
        )
        .font(.system(size: 12.5, weight: .regular))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: 10)], spacing: 10) {
        finishMetric(
          icon: "person.crop.circle.fill",
          title: store.hasProfile ? store.profileDisplayName : "Profile",
          value: store.profileCurrentGrade?.shortTitle ?? "Optional",
          tint: DesignTokens.Colors.pacTrack)
        finishMetric(
          icon: "books.vertical.fill", title: "Classes",
          value: "\(configuredClassCount)/\(Level.allCases.count) set",
          tint: DesignTokens.Colors.schedule)
        finishMetric(
          icon: "person.3.fill", title: "Clubs", value: "\(store.clubs.count) added",
          tint: DesignTokens.Colors.events)
        finishMetric(
          icon: "chart.bar.xaxis", title: "PacTrack", value: "\(selectedPacTrackCount) selected",
          tint: DesignTokens.Colors.pacTrack)
        finishMetric(
          icon: "sportscourt.fill",
          title: "Sports",
          value: "\(savedGameIDs.count) reminder\(savedGameIDs.count == 1 ? "" : "s")",
          tint: DesignTokens.Colors.athletics
        )
        finishMetric(
          icon: "calendar.circle.fill",
          title: "Events",
          value: eventsStore.selectionTitle,
          tint: DesignTokens.Colors.events
        )
        finishMetric(
          icon: "bell.badge.fill", title: "Notifications",
          value: notificationsAreActive ? "On" : "Off", tint: DesignTokens.Colors.warning)
      }

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 9) {
          Image(systemName: "gearshape.fill")
            .foregroundStyle(DesignTokens.Colors.settings)
          Text(
            "Need to change something later? Everything from onboarding remains editable in RooMate."
          )
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        HStack(spacing: 9) {
          Image(systemName: "command")
            .foregroundStyle(DesignTokens.Colors.primary)
          Text(
            "Mac basics: ⌘K searches RooMate, the Navigate menu has quick section shortcuts, and ⌘Q quits RooMate completely."
          )
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        DesignTokens.Colors.settings.opacity(0.07),
        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
  }

  private func finishMetric(icon: String, title: String, value: String, tint: Color) -> some View {
    HStack(spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(tint.opacity(0.12))
        Image(systemName: icon)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(tint)
      }
      .frame(width: 35, height: 35)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Text(value)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
      }

      Spacer()
    }
    .padding(11)
    .background(
      DesignTokens.Colors.hover.opacity(0.18),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
    }
  }

  // MARK: Shared onboarding UI

  private func onboardingCard<Content: View>(
    title: String,
    subtitle: String,
    icon: String,
    tint: Color,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(spacing: 10) {
        ZStack {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(tint.opacity(0.12))
          Image(systemName: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
        }
        .frame(width: 34, height: 34)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
          Text(subtitle)
            .font(.system(size: 9.8, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      content()
    }
    .padding(15)
    .rooSurface(cornerRadius: 15, elevated: false, border: true)
  }

  private func onboardingTextField(_ label: String, placeholder: String, text: Binding<String>)
    -> some View
  {
    VStack(alignment: .leading, spacing: 5) {
      Text(label)
        .onboardingFieldLabel()
      TextField(placeholder, text: text)
        .textFieldStyle(.plain)
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 35)
        .background(
          DesignTokens.Colors.hover.opacity(0.28),
          in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func onboardingToggleRow(
    title: String,
    subtitle: String,
    systemImage: String,
    tint: Color,
    isOn: Binding<Bool>,
    disabled: Bool
  ) -> some View {
    HStack(spacing: 11) {
      Image(systemName: systemImage)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(disabled ? DesignTokens.Colors.subtleText : tint)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 11.5, weight: .semibold))
        Text(subtitle)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 52)
    .opacity(disabled ? 0.48 : 1)
    .allowsHitTesting(!disabled)
  }
}

extension Text {
  fileprivate func onboardingFieldLabel() -> some View {
    self
      .font(.system(size: 8.5, weight: .bold))
      .tracking(0.65)
      .foregroundStyle(DesignTokens.Colors.subtleText)
  }
}

#if canImport(AppKit)
  private final class RooMateWindowChromeView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      configureWindow()
    }

    func configureWindow() {
      guard let window else { return }

      window.styleMask.insert(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.titlebarSeparatorStyle = .none
      window.isMovableByWindowBackground = true
    }
  }

  private struct RooMateWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> RooMateWindowChromeView {
      RooMateWindowChromeView(frame: .zero)
    }

    func updateNSView(_ nsView: RooMateWindowChromeView, context: Context) {
      nsView.configureWindow()
    }
  }
#endif

#Preview {
  ContentView()
}
