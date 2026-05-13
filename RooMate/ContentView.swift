import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
import TelemetryDeck

struct ContentView: View {
    @StateObject private var store = UserScheduleStore()
    @StateObject private var sportsStore = SportsStore()
    @StateObject private var eventsStore = EventsStore()
    @State private var selectedTab: Tab = .dashboard

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

    // Compute the next calendar date that corresponds to the selected weekday
    private func nextDate(for weekday: Weekday, from reference: Date = Date()) -> Date {
        let cal = Calendar.current
        let weekdayMap: [Weekday: Int] = [.monday: 2, .tuesday: 3, .wednesday: 4, .thursday: 5, .friday: 6]
        let target = weekdayMap[weekday] ?? 2
        let today = cal.component(.weekday, from: reference)
        var delta = target - today
        if delta < 0 { delta += 7 }
        return cal.date(byAdding: .day, value: delta, to: cal.startOfDay(for: reference)) ?? reference
    }

    // Blocks for the selected day
    private var blocksForSelectedDay: [BellBlock] {
        BellSchedule.weekly[selectedDay] ?? []
    }

    private func preferredColorScheme(for appearance: AppearancePreference) -> ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        Group {
#if canImport(AppKit)
        // macOS: use a sidebar-centric split view
        NavigationSplitView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RooMate")
                            .font(DesignTokens.Typography.brandTitle(size: 30))
                            .tracking(0.2)
                        Text("Schedule at a glance")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)

                List(selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200)
        } detail: {
            ZStack {
                BackgroundView()
                // Detail area shows the selected content
                Group {
                    switch selectedTab {
                    case .dashboard:
                        DashboardView(store: store)
                            .padding(.all, DesignTokens.Spacing.lg)

                    case .schedule:
                        VStack(spacing: 0) {
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
                            .padding(.horizontal, DesignTokens.Spacing.lg)
                        }

                    case .settings:
                        SettingsView(store: store)
                            .padding(.all, DesignTokens.Spacing.lg)
                    case .athletics:
                        AthleticsView(store: sportsStore)
                            .padding(.all, DesignTokens.Spacing.lg)
                    case .events:
                        EventsView(store: eventsStore)
                            .padding(.all, DesignTokens.Spacing.lg)
                    }
                }
            }
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
                        Text("Modern school schedule at a glance")
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
                            DashboardView(store: store)
                                .padding(.top, DesignTokens.Spacing.lg)
                                .padding(.horizontal, DesignTokens.Spacing.lg)

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
                            SettingsView(store: store)
                                .padding(.horizontal, DesignTokens.Spacing.lg)
                        case .athletics:
                            AthleticsView(store: sportsStore)
                                .padding(.horizontal, DesignTokens.Spacing.lg)
                        case .events:
                            EventsView(store: eventsStore)
                                .padding(.horizontal, DesignTokens.Spacing.lg)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Modern tab bar
                ModernTabBar(selectedTab: $selectedTab)
                    .background(compatibleBackgroundSecondary())
            }
            .background(BackgroundView().ignoresSafeArea())
        }
#endif
        }
        .preferredColorScheme(preferredColorScheme(for: store.appearance))
        .frame(minWidth: 700, minHeight: 680)
    }
    
    enum Tab: CaseIterable, Hashable {
        case dashboard
        case schedule
        case athletics
        case events
        case settings

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .schedule: return "Schedule"
            case .athletics: return "Athletics"
            case .events: return "Events"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .schedule: return "calendar"
            case .athletics: return "sportscourt"
            case .events: return "calendar.circle"
            case .settings: return "gearshape"
            }
        }
    }
}

#Preview {
    ContentView()
}
