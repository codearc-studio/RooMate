import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif
import UserNotifications

// Fully redesigned Settings view with tab-based organization
struct SettingsView: View {
    @ObservedObject var store: UserScheduleStore
    
    // Local UI state
    @State private var selectedTab: SettingsTab = .customize
    @State private var selectedLevelIndex: Int = 0
    
    enum SettingsTab: String, CaseIterable {
        case customize = "Customize"
        case classes = "Classes"
        case clubs = "Clubs"
        case schedule = "Schedule"
        
        var icon: String {
            switch self {
            case .customize: return "sparkles"
            case .classes: return "text.book.closed.fill"
            case .clubs: return "person.3.fill"
            case .schedule: return "calendar"
            }
        }
    }
    
    private var editableLevels: [Level] {
        [.level1, .level2, .level3, .level4, .level5, .level6, .level7]
    }
    
    private var appName: String {
        let dict = Bundle.main.infoDictionary
        return dict?["CFBundleDisplayName"] as? String ?? dict?["CFBundleName"] as? String ?? "App"
    }
    
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab navigation
            VStack(spacing: 0) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                        Button(action: {
                            withAnimation(DesignTokens.Animation.snappy) {
                                selectedTab = tab
                            }
                        }) {
                            VStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: tab.icon)
                                    .font(.title3)
                                Text(tab.rawValue)
                                    .font(DesignTokens.Typography.caption)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                                .fill(
                                    selectedTab == tab
                                        ? DesignTokens.Colors.primary.opacity(0.12)
                                        : Color.clear
                                )
                        )
                        .foregroundStyle(selectedTab == tab ? DesignTokens.Colors.primary : .secondary)
                    }
                }
                .padding(DesignTokens.Spacing.md)
                
                Divider()
                    .opacity(0.08)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(compatibleBackgroundSecondary())
            )
            .padding(DesignTokens.Spacing.md)
            
            // Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    switch selectedTab {
                    case .customize:
                        customizeTabContent
                    case .classes:
                        classesTabContent
                    case .clubs:
                        clubsTabContent
                    case .schedule:
                        scheduleTabContent
                    }
                    
                    // Footer
                    VStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                        Text("\(appName) v\(appVersion)")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("Track your schedule with a clean, customizable interface.")
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, DesignTokens.Spacing.lg)
                }
                .padding(DesignTokens.Spacing.lg)
            }
        }
        .navigationTitle("Settings")
        .modifier(SafeAreaTopPadding(4))
        .task { await store.refreshNotificationStatus() }
    }
    
    // MARK: - Tab Contents
    
    private var customizeTabContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            // Theme Section
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "paintbrush.pointed")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.primary)
                    Text("Theme")
                        .font(DesignTokens.Typography.headline2)
                }
                .padding(.bottom, DesignTokens.Spacing.sm)
                
                Text("Choose how RooMate looks")
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DesignTokens.Spacing.md), GridItem(.flexible(), spacing: DesignTokens.Spacing.md), GridItem(.flexible(), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
                    ForEach(AppearancePreference.allCases) { option in
                        ThemeButton(option: option, isSelected: option == store.appearance) {
                            withAnimation(DesignTokens.Animation.snappy) { store.appearance = option }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous).fill(compatibleBackgroundSecondary()))
            .designShadow(DesignTokens.Shadows.small)
            
            // Card Style Section
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "square.grid.2x2")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.accent)
                    Text("Card Style")
                        .font(DesignTokens.Typography.headline2)
                }
                .padding(.bottom, DesignTokens.Spacing.sm)
                
                Text("Customize how cards are displayed")
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
                
                LazyVGrid(columns: [GridItem(.flexible(), spacing: DesignTokens.Spacing.md), GridItem(.flexible(), spacing: DesignTokens.Spacing.md), GridItem(.flexible(), spacing: DesignTokens.Spacing.md)], spacing: DesignTokens.Spacing.md) {
                    ForEach(CardColorStyle.allCases) { style in
                        CardStyleButton(style: style, isSelected: style == store.cardColorStyle) {
                            withAnimation(DesignTokens.Animation.snappy) { store.cardColorStyle = style }
                        }
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous).fill(compatibleBackgroundSecondary()))
            .designShadow(DesignTokens.Shadows.small)
        }
    }
    
    private var classesTabContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "text.book.closed.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.primary)
                    Text("Your Classes")
                        .font(DesignTokens.Typography.headline2)
                }
                
                Text("Edit your class schedule and details")
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.lg)
            
            // Level selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(Array(editableLevels.enumerated()), id: \.offset) { idx, level in
                        LevelTabButton(level: level, isSelected: idx == selectedLevelIndex) {
                            withAnimation(DesignTokens.Animation.snappy) { selectedLevelIndex = idx }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }
            
            // Level editor
            let currentLevel = editableLevels[selectedLevelIndex]
            LevelEditorRow(level: currentLevel, assignment: store.binding(for: currentLevel))
                .padding(DesignTokens.Spacing.lg)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous).fill(compatibleBackgroundSecondary()))
                .designShadow(DesignTokens.Shadows.small)
                .padding(.horizontal, DesignTokens.Spacing.lg)
        }
    }
    
    private var clubsTabContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.primary)
                    Text("Manage Clubs")
                        .font(DesignTokens.Typography.headline2)
                }
                
                Text("Add and organize your clubs and meetings")
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.lg)
            
            Button(action: {
                withAnimation(DesignTokens.Animation.snappy) { store.clubs.append(Club()) }
            }) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    Text("Add New Club")
                        .font(DesignTokens.Typography.body)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(DesignTokens.Spacing.lg)
                .background(DesignTokens.Colors.primary.opacity(0.1))
                .cornerRadius(DesignTokens.Radius.lg)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.lg)
            
            if store.clubs.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "star.slash.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    
                    Text("No Clubs Yet")
                        .font(DesignTokens.Typography.headline3)
                    
                    Text("Add your first club to get started")
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.Spacing.xl)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(compatibleBackgroundSecondary()))
                .padding(.horizontal, DesignTokens.Spacing.lg)
            } else {
                VStack(spacing: DesignTokens.Spacing.md) {
                    ForEach(store.clubs.indices, id: \.self) { index in
                        let clubID = store.clubs[index].id
                        ClubEditorRow(club: $store.clubs[index]) {
                            withAnimation(DesignTokens.Animation.snappy) {
                                store.clubs.removeAll { $0.id == clubID }
                            }
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                
                Button(role: .destructive) {
                    withAnimation(DesignTokens.Animation.snappy) { store.clubs.removeAll() }
                } label: {
                    Text("Remove All Clubs")
                        .frame(maxWidth: .infinity)
                        .padding(DesignTokens.Spacing.lg)
                        .background(DesignTokens.Colors.destructive.opacity(0.1))
                        .cornerRadius(DesignTokens.Radius.lg)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.lg)
            }
        }
    }
    
    private var scheduleTabContent: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.Colors.primary)
                    Text("Special Blocks")
                        .font(DesignTokens.Typography.headline2)
                }
                
                Text("Mark special schedule blocks as free time")
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.lg)

            let musicAssignment = store.assignment(for: .music)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundStyle(DesignTokens.Colors.primary)
                        Text("Music Block")
                            .font(DesignTokens.Typography.headline2)
                    }

                    Text("Is Music Block free sometimes? If so, choose the days it isn’t free.")
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(.secondary)

                    Toggle("Music Block is free sometimes", isOn: Binding(
                        get: { store.assignment(for: .music).isFree },
                        set: { newValue in
                            var music = store.assignment(for: .music)
                            music.isFree = newValue
                            if !newValue {
                                music.musicDaysNotFree = []
                            }
                            store.assignments[.music] = music
                            store.specialFree[.musicClubs] = music.displayIsFree(on: .monday)
                        }
                    ))
                    .tint(DesignTokens.Colors.primary)
                }

                if musicAssignment.isFree {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Text("What days isn’t it free?")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), GridItem(.flexible(), spacing: DesignTokens.Spacing.sm), GridItem(.flexible(), spacing: DesignTokens.Spacing.sm)], spacing: DesignTokens.Spacing.sm) {
                            ForEach(Weekday.allCases) { weekday in
                                let isNotFree = musicAssignment.musicDaysNotFree.contains(weekday.calendarWeekdayIndex)
                                WeekdayToggleButton(weekday: weekday, isSelected: isNotFree) {
                                    withAnimation(DesignTokens.Animation.snappy) {
                                        var music = store.assignment(for: .music)
                                        if isNotFree {
                                            music.musicDaysNotFree.remove(weekday.calendarWeekdayIndex)
                                        } else {
                                            music.musicDaysNotFree.insert(weekday.calendarWeekdayIndex)
                                        }
                                        store.assignments[.music] = music
                                        store.specialFree[.musicClubs] = music.displayIsFree(on: .monday)
                                    }
                                }
                            }
                        }

                        Text("Selected days will count as class time in the schedule.")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous).fill(compatibleBackgroundSecondary()))
            .designShadow(DesignTokens.Shadows.small)
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SpecialBlockToggleRow(
                    title: "Conscious Communities is free",
                    icon: "heart.circle.fill",
                    isOn: Binding(
                        get: { store.specialFree[.consciousCommunities] ?? false },
                        set: { store.specialFree[.consciousCommunities] = $0 }
                    )
                )
                
                SpecialBlockToggleRow(
                    title: "Lunch is free",
                    icon: "fork.knife",
                    isOn: Binding(
                        get: { store.specialFree[.lunch] ?? false },
                        set: { store.specialFree[.lunch] = $0 }
                    )
                )
                
                SpecialBlockToggleRow(
                    title: "Music Block is free",
                    icon: "music.note",
                    isOn: Binding(
                        get: { store.assignments[.music]?.isFree ?? true },
                        set: {
                            var musicAssignment = store.assignments[.music] ?? ClassAssignment.default(for: .music)
                            musicAssignment.isFree = $0
                            store.assignments[.music] = musicAssignment
                            // Also mark the special "Music Block + Clubs" as free so special schedule entries
                            // like Monday's `musicClubs` are treated as free time when this toggle is set.
                            store.specialFree[.musicClubs] = $0
                        }
                    )
                )
            }
            .padding(DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous).fill(compatibleBackgroundSecondary()))
            .designShadow(DesignTokens.Shadows.small)
            .padding(.horizontal, DesignTokens.Spacing.lg)
        }
    }
}
// ...existing code...

// MARK: - Helper Components

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
                    .fill(isSelected ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.2)) : AnyShapeStyle(compatibleBackgroundSecondary()))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? DesignTokens.Colors.primary : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .primary)
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
                    .fill(isSelected ? AnyShapeStyle(DesignTokens.Colors.accent.opacity(0.2)) : AnyShapeStyle(compatibleBackgroundSecondary()))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? DesignTokens.Colors.accent : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? DesignTokens.Colors.accent : .primary)
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
                    .fill(isSelected ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.15)) : AnyShapeStyle(compatibleBackgroundSecondary()))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? DesignTokens.Colors.primary : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .secondary)
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
                Image(systemName: isSelected ? "checkmark.circle.fill" : weekday.systemImage)
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
                    .fill(isSelected ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.2)) : AnyShapeStyle(compatibleBackgroundSecondary()))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? DesignTokens.Colors.primary : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Special Block Toggle Component

struct SpecialBlockToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
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

    // Removed local ephemeral state: rely on the persisted properties on ClassAssignment

    // ...existing code...

    // Compute which days this level meets according to the bell schedule
    private var daysLevelMeets: Set<Int> {
        var days: Set<Int> = []
        let weekdayMap: [Weekday: Int] = [.monday: 2, .tuesday: 3, .wednesday: 4, .thursday: 5, .friday: 6]
        
        for (weekday, dayIndex) in weekdayMap {
            if let blocks = BellSchedule.weekly[weekday] {
                for block in blocks {
                    if case .level(let blockLevel) = block.kind, blockLevel == level {
                        days.insert(dayIndex)
                        break
                    }
                }
            }
        }
        return days
    }

    var body: some View {
        let daySymbols = Calendar.current.weekdaySymbols
        let allIndices: [Int] = [2, 3, 4, 5, 6]
        // Only show days the class meets on in the bell schedule
        let orderedIndices = allIndices.filter { daysLevelMeets.contains($0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "text.book.closed")
                    .foregroundStyle(DesignTokens.Colors.primary)
                Text(level.displayName)
                    .font(DesignTokens.Typography.headline3)
            }

            Toggle(isOn: Binding(
                get: { assignment.isFree },
                set: { assignment.isFree = $0 }
            )) {
                Label("Is this class free?", systemImage: "sparkles")
            }
            .tint(DesignTokens.Colors.primary)

            if assignment.isFree {
                Text("Free blocks count toward your free time.")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if !assignment.isFree {
                TextField("Class title", text: $assignment.title)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(compatibleBackgroundSecondary())
                    .cornerRadius(DesignTokens.Radius.sm)
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))

                if level != .music {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        TextField("Teacher", text: $assignment.teacher)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(compatibleBackgroundSecondary())
                            .cornerRadius(DesignTokens.Radius.sm)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                        
                        TextField("Room", text: $assignment.room)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: 140)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xs)
                            .background(compatibleBackgroundSecondary())
                            .cornerRadius(DesignTokens.Radius.sm)
                            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                    }
                }
            }

            ColorPicker("Color", selection: Binding(
                get: { assignment.color.swiftUIColor },
                set: { assignment.color = CodableColor($0) }
            ))

            Divider().opacity(0.1)

            Toggle(isOn: Binding(
                get: { assignment.meetsEveryDay },
                set: { assignment.meetsEveryDay = $0 }
            )) {
                Label("Meets every day", systemImage: "calendar")
            }
            .tint(DesignTokens.Colors.primary)

                    if !assignment.meetsEveryDay {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("What days does it meet on?")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)

                        LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
                            ForEach(orderedIndices, id: \.self) { idx in
                                let label = daySymbols[idx - 1]
                                let isSelected = !assignment.daysNotMeeting.contains(idx)

                                Button {
                                    withAnimation(DesignTokens.Animation.snappy) {
                                        if isSelected {
                                            assignment.daysNotMeeting.insert(idx)
                                        } else {
                                            assignment.daysNotMeeting.remove(idx)
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
                                                .fill(isSelected ? AnyShapeStyle(DesignTokens.Colors.primary.opacity(0.15)) : compatibleBackgroundSecondary())
                                        )
                                        .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .primary)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }

                    Text("Class meets on the selected days above")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    
                    // Show single replacement class input
                    if !assignment.daysNotMeeting.isEmpty {
                        Divider().opacity(0.1)
                        
                        Text("What happens on the other days?")
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)

                                Toggle(isOn: Binding(
                                    get: { assignment.replacementClass?.isFree ?? false },
                                    set: {
                                        var replacement = assignment.replacementClass ?? ClassAssignment.ReplacementClass(title: "", teacher: "", room: "")
                                        replacement.isFree = $0
                                        assignment.replacementClass = replacement
                                    }
                                )) {
                                    Label("Is the replacement free?", systemImage: "sparkles")
                                }
                                .tint(DesignTokens.Colors.primary)

                                if assignment.replacementClass?.isFree == true {
                                    Text("Free replacements also count toward your free time.")
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                        
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                                    if assignment.replacementClass?.isFree != true {
                                        TextField("Class name", text: Binding(
                                            get: { assignment.replacementClass?.title ?? "" },
                                            set: {
                                                var replacement = assignment.replacementClass ?? ClassAssignment.ReplacementClass(title: "", teacher: "", room: "")
                                                replacement.title = $0
                                                assignment.replacementClass = replacement
                                            }
                                        ))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, DesignTokens.Spacing.sm)
                                        .padding(.vertical, DesignTokens.Spacing.xs)
                                        .background(compatibleBackgroundSecondary())
                                        .cornerRadius(DesignTokens.Radius.sm)
                                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                                
                                        if level != .music {
                                            HStack(spacing: DesignTokens.Spacing.md) {
                                                TextField("Teacher", text: Binding(
                                                    get: { assignment.replacementClass?.teacher ?? "" },
                                                    set: {
                                                        var replacement = assignment.replacementClass ?? ClassAssignment.ReplacementClass(title: "", teacher: "", room: "")
                                                        replacement.teacher = $0
                                                        assignment.replacementClass = replacement
                                                    }
                                                ))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, DesignTokens.Spacing.sm)
                                                .padding(.vertical, DesignTokens.Spacing.xs)
                                                .background(compatibleBackgroundSecondary())
                                                .cornerRadius(DesignTokens.Radius.sm)
                                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                                        
                                                TextField("Room", text: Binding(
                                                    get: { assignment.replacementClass?.room ?? "" },
                                                    set: {
                                                        var replacement = assignment.replacementClass ?? ClassAssignment.ReplacementClass(title: "", teacher: "", room: "")
                                                        replacement.room = $0
                                                        assignment.replacementClass = replacement
                                                    }
                                                ))
                                                .foregroundStyle(.primary)
                                                .frame(maxWidth: 140)
                                                .padding(.horizontal, DesignTokens.Spacing.sm)
                                                .padding(.vertical, DesignTokens.Spacing.xs)
                                                .background(compatibleBackgroundSecondary())
                                                .cornerRadius(DesignTokens.Radius.sm)
                                                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                                            }
                                        }
                            }
                        }
                    }
                }
                // Use a fade transition only so content appears/disappears without shifting other views
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.22), value: assignment.meetsEveryDay)
            }
        }
    }
}

struct ClubEditorRow: View {
    @Binding var club: Club
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                TextField("Club name", text: $club.name)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Typography.body)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Toggle(isOn: $club.meetsMondayClub) {
                    Text("Monday club period")
                        .font(DesignTokens.Typography.body)
                }
                .tint(DesignTokens.Colors.primary)

                Toggle(isOn: $club.meetsWednesdayClub) {
                    Text("Wednesday club period")
                        .font(DesignTokens.Typography.body)
                }
                .tint(DesignTokens.Colors.primary)
            }

            if !$club.otherMeetings.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    HStack {
                        Text("Other Meeting Days")
                            .font(DesignTokens.Typography.title)

                        Spacer()

                        Button {
                            withAnimation(DesignTokens.Animation.snappy) {
                                club.otherMeetings.append(Club.OtherMeeting())
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach($club.otherMeetings) { $meeting in
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Picker("Day", selection: $meeting.weekday) {
                                ForEach(1...7, id: \.self) { idx in
                                    Text(Calendar.current.weekdaySymbols[idx - 1]).tag(idx)
                                }
                            }
                            .frame(maxWidth: 120)

                            DatePicker("", selection: $meeting.startTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()

                            Text("–").foregroundStyle(.secondary)

                            DatePicker("", selection: $meeting.endTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()

                            Button(role: .destructive) {
                                withAnimation(DesignTokens.Animation.snappy) {
                                    if let idx = club.otherMeetings.firstIndex(where: { $0.id == meeting.id }) {
                                        club.otherMeetings.remove(at: idx)
                                    }
                                }
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(DesignTokens.Spacing.sm)
                        .background(compatibleBackgroundSecondary())
                        .cornerRadius(DesignTokens.Radius.sm)
                    }
                }
            } else {
                Button {
                    withAnimation(DesignTokens.Animation.snappy) {
                        club.otherMeetings.append(Club.OtherMeeting())
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.sm) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add an extra meeting time")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.sm)
                }
                .buttonStyle(.plain)
            }

            TextField("Notes (optional)", text: $club.otherDaysNote)
                .textFieldStyle(.roundedBorder)
                .font(DesignTokens.Typography.body)
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(compatibleBackgroundSecondary())
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
        )
     }
 }
