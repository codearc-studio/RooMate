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

    // Blocks for the selected day, overridden by any special on that date
    private var blocksForSelectedDay: [BellBlock] {
        let date = nextDate(for: selectedDay)
        return store.overrideBlocks(for: date, weekday: selectedDay)
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
        .task {
            Analytics.send(event: "AppLaunched")
            await store.refreshDatedSpecials()
        }
        .preferredColorScheme(store.appearance.colorScheme)
        .frame(minWidth: 700, minHeight: 680)
    }
    
    enum Tab: CaseIterable, Hashable {
        case dashboard
        case schedule
        case settings

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .schedule: return "Schedule"
            case .settings: return "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .dashboard: return "square.grid.2x2"
            case .schedule: return "calendar"
            case .settings: return "gearshape"
            }
        }
    }
    
    @State private var selectedTab: Tab = .dashboard
}

private struct SpecialScheduleRowFromDated: View {
    let schedule: DatedSpecialSchedule
    @ObservedObject var store: UserScheduleStore
    let style: CardColorStyle

    private var leadingColor: Color {
        // Try to infer a color from the first block
        if let first = schedule.blocks.first {
            switch first.kind {
            case .level(let level):
                return store.assignment(for: level).color.swiftUIColor
            case .special(let sp):
                return store.color(for: sp)
            }
        }
        return .accentColor
    }

    private func timeSummary() -> String {
        guard let first = schedule.blocks.first, let last = schedule.blocks.last else { return "—" }

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

        return "\(format(first.start)) – \(format(last.end))"
    }

    private func durationSummary() -> String {
        guard let first = schedule.blocks.first, let last = schedule.blocks.last else { return "—" }
        
        let cal = Calendar.current
        var startComps = first.start
        var endComps = last.end
        
        // Create arbitrary dates to calculate the duration
        startComps.second = 0
        endComps.second = 0
        
        guard let startDate = cal.date(from: startComps),
              let endDate = cal.date(from: endComps) else { return "—" }
        
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

    private var dateText: String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: schedule.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [leadingColor.opacity(0.7), leadingColor.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(schedule.title)
                        .font(.headline)
                    Spacer()
                    Label(timeSummary(), systemImage: "clock")
                        .font(.subheadline)
                        .modifier(SecondaryForeground())
                }

                HStack(spacing: 8) {
                    Label(dateText, systemImage: "calendar")
                        .font(.subheadline)
                        .modifier(SecondaryForeground())
                    Spacer()
                    Label(durationSummary(), systemImage: "hourglass.bottomhalf.filled")
                        .font(.subheadline)
                        .modifier(SecondaryForeground())
                }
            }
            .padding(.vertical, 8)
        }
        .padding(10)
        .background(backgroundForStyle)
        .overlay(strokeForStyle)
        .overlay(glowForStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(compatibleBackgroundSecondary())
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        case .subtle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(compatibleBackgroundSecondary())
                .shadow(color: leadingColor.opacity(0.10), radius: 8, x: 0, y: 0)
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(leadingColor.opacity(0.10))
                    .blur(radius: 8)
                    .scaleEffect(1.005)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [leadingColor.opacity(0.20), leadingColor.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: leadingColor.opacity(0.16), radius: 6, x: 0, y: 0)
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
                .stroke(
                    LinearGradient(
                        colors: [leadingColor.opacity(0.55), leadingColor.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        case .colors:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [leadingColor.opacity(0.55), leadingColor.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        }
    }

    @ViewBuilder
    private var glowForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(leadingColor.opacity(0.08), lineWidth: 3)
                .blur(radius: 5)
        case .colors:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(leadingColor.opacity(0.04), lineWidth: 2)
                .blur(radius: 3)
        }
    }
}

#Preview {
    ContentView()
}
