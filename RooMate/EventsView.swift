import SwiftUI

struct EventsView: View {
    @ObservedObject var store: EventsStore
    @State private var selectedSource: CalendarSource
    @State private var selectedGrouping: CalendarGroupingMode
    @State private var periodOffset: Int = 0

    init(store: EventsStore) {
        self.store = store
        _selectedSource = State(initialValue: store.selectedSource)
        _selectedGrouping = State(initialValue: store.selectedGrouping)
    }

    private var visiblePeriodDate: Date {
        date(for: selectedGrouping, offset: periodOffset)
    }

    private var visiblePeriodInterval: DateInterval {
        periodInterval(for: selectedGrouping, relativeTo: visiblePeriodDate)
    }

    private var visibleEvents: [CalendarEvent] {
        store.events
            .filter { eventOverlapsVisiblePeriod($0) }
            .sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Colors.primary.opacity(0.22),
                                    DesignTokens.Colors.accent.opacity(0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.primary)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Events")
                        .font(DesignTokens.Typography.headline2)
                    Text("Catch every Roo moment in style")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading {
                    ProgressView().scaleEffect(0.8)
                }
                Button {
                    periodOffset = 0
                } label: {
                    Image(systemName: "calendar.badge.clock")
                }
                .help(resetButtonHelp)

                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh events")
            }
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.primary.opacity(0.12),
                                DesignTokens.Colors.accent.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
            )
            .designShadow(DesignTokens.Shadows.small)
            .padding(.bottom, DesignTokens.Spacing.lg)

            // Controls row with source picker and view mode toggle
            VStack(spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Picker("Calendar Source", selection: $selectedSource) {
                        ForEach(CalendarSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Picker("Group by", selection: $selectedGrouping) {
                        ForEach(CalendarGroupingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.lg)

            periodNavigation
                .padding(.bottom, DesignTokens.Spacing.lg)

            // Error display
            if let err = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                    Text("Failed to load events: \(err.localizedDescription)")
                    Spacer()
                }
                .padding(8)
                .background(Color.yellow.opacity(0.06))
                .cornerRadius(8)
                .padding(.bottom, DesignTokens.Spacing.md)
            }

            // Content based on view mode
            if visibleEvents.isEmpty {
                VStack(spacing: DesignTokens.Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(DesignTokens.Colors.primary.opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.primary)
                    }
                    Text(store.isLoading ? "Loading…" : "No events found")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.secondary)
                    Text("Check a different date range or refresh for the latest happenings.")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(DesignTokens.Spacing.xl)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                        .fill(compatibleBackgroundSecondary())
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
                )
                .designShadow(DesignTokens.Shadows.small)
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xl) {
                        ForEach(visibleEvents) { event in
                            EventRow(event: event, isPast: isPast(event))
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.lg)
                    .padding(.top, DesignTokens.Spacing.sm)
                    .padding(.bottom, DesignTokens.Spacing.lg)
                }
            }
        }
        .onChange(of: selectedSource) { newValue in
            DispatchQueue.main.async {
                store.setSource(newValue)
            }
        }
        .onChange(of: selectedGrouping) { newValue in
            periodOffset = 0
            DispatchQueue.main.async {
                store.selectedGrouping = newValue
            }
        }
        .onAppear {
            selectedSource = store.selectedSource
            selectedGrouping = store.selectedGrouping
            if store.events.isEmpty {
                DispatchQueue.main.async {
                    store.refresh()
                }
            }
        }
    }

    private var periodNavigation: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button {
                periodOffset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(previousPeriodHelp)

            Spacer(minLength: DesignTokens.Spacing.sm)

            VStack(spacing: 2) {
                Text(periodTitle)
                    .font(DesignTokens.Typography.title)
                Text(periodSubtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            Spacer(minLength: DesignTokens.Spacing.sm)

            Button {
                periodOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(nextPeriodHelp)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(compatibleBackgroundSecondary())
        )
    }

    private var periodTitle: String {
        let calendar = Calendar.current
        switch selectedGrouping {
        case .day:
            if periodOffset == 0, calendar.isDate(visiblePeriodDate, inSameDayAs: Date()) { return "Today" }
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            return formatter.string(from: visiblePeriodDate)
        case .week:
            if periodOffset == 0 { return "This Week" }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Week of \(formatter.string(from: visiblePeriodInterval.start))"
        case .month:
            if periodOffset == 0 { return "This Month" }
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: visiblePeriodDate)
        }
    }

    private var periodSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        switch selectedGrouping {
        case .day:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: visiblePeriodDate)
        case .week:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let end = Calendar.current.date(byAdding: .day, value: 6, to: visiblePeriodInterval.start) ?? visiblePeriodInterval.end
            return "\(formatter.string(from: visiblePeriodInterval.start)) – \(formatter.string(from: end))"
        case .month:
            formatter.dateFormat = "yyyy"
            return formatter.string(from: visiblePeriodDate)
        }
    }

    private var resetButtonHelp: String {
        switch selectedGrouping {
        case .day: "Jump back to today"
        case .week: "Jump back to this week"
        case .month: "Jump back to this month"
        }
    }

    private var previousPeriodHelp: String {
        switch selectedGrouping {
        case .day: "Previous day"
        case .week: "Previous week"
        case .month: "Previous month"
        }
    }

    private var nextPeriodHelp: String {
        switch selectedGrouping {
        case .day: "Next day"
        case .week: "Next week"
        case .month: "Next month"
        }
    }

    private func date(for mode: CalendarGroupingMode, offset: Int, from reference: Date = Date()) -> Date {
        let calendar = Calendar.current
        let base: Date
        switch mode {
        case .day:
            base = calendar.startOfDay(for: reference)
            return calendar.date(byAdding: .day, value: offset, to: base) ?? base
        case .week:
            base = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? calendar.startOfDay(for: reference)
            return calendar.date(byAdding: .weekOfYear, value: offset, to: base) ?? base
        case .month:
            base = calendar.dateInterval(of: .month, for: reference)?.start ?? calendar.startOfDay(for: reference)
            return calendar.date(byAdding: .month, value: offset, to: base) ?? base
        }
    }

    private func periodInterval(for mode: CalendarGroupingMode, relativeTo date: Date) -> DateInterval {
        let calendar = Calendar.current
        switch mode {
        case .day:
            return calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 7 * 24 * 60 * 60)
        case .month:
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 31 * 24 * 60 * 60)
        }
    }

    private func eventOverlapsVisiblePeriod(_ event: CalendarEvent) -> Bool {
        let end = event.endDate ?? event.startDate
        return event.startDate < visiblePeriodInterval.end && end >= visiblePeriodInterval.start
    }

    private func isPast(_ event: CalendarEvent) -> Bool {
        let end = event.endDate ?? event.startDate
        return end < Date()
    }
}

struct EventRow: View {
    let event: CalendarEvent
    var isPast: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            HStack(alignment: .top) {
                Circle()
                    .fill(isPast ? Color.secondary.opacity(0.35) : DesignTokens.Colors.accent)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(DesignTokens.Typography.title)
                        .lineLimit(2)
                    if event.isMultiDay {
                        Text("All-day / multi-day")
                            .font(DesignTokens.Typography.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DesignTokens.Colors.primary.opacity(0.12))
                            .foregroundStyle(DesignTokens.Colors.primary)
                            .clipShape(Capsule())
                    }
                    
                    // Date and time info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(formatDateForDisplay(event.startDate))
                                .font(DesignTokens.Typography.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        if event.isMultiDay, let endDate = event.endDate {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Ends: \(formatDateForDisplay(endDate))")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let endDate = event.endDate {
                            HStack(spacing: 8) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatTimeForDisplay(endDate))
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Spacer()
            }
            
            // Location (if available)
            if let location = event.location, !location.trimmingCharacters(in: .whitespaces).isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(location)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.primary)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DesignTokens.Colors.primary.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(compatibleBackgroundSecondary())
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(isPast ? Color.secondary.opacity(0.08) : DesignTokens.Colors.primary.opacity(0.12), lineWidth: 1)
        )
        .designShadow(isPast ? DesignTokens.Shadows.subtle : DesignTokens.Shadows.small)
        .opacity(isPast ? 0.72 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTimeForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct EventsCalendarView: View {
    let events: [CalendarEvent]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                ForEach(events.sorted { $0.startDate < $1.startDate }) { event in
                    EventRow(event: event)
                        .padding(.horizontal, DesignTokens.Spacing.md)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                                .fill(compatibleBackgroundSecondary())
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
        }
    }
}

#Preview {
    EventsView(store: EventsStore())
}
