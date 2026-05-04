import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: UserScheduleStore

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Determine today's weekday
    private var todayWeekday: Weekday {
        let cal = Calendar.current
        switch cal.component(.weekday, from: Date()) {
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .monday
        }
    }

    private var todayBlocks: [BellBlock] {
        BellSchedule.weekly[todayWeekday] ?? []
    }

    // Lightweight copy of DayScheduleView’s date mapping for “today”
    private struct DatedBlock: Identifiable {
        let id = UUID()
        let original: BellBlock
        let startDate: Date
        let endDate: Date
    }

    private func datedBlocks(for reference: Date) -> [DatedBlock] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: reference)

        return todayBlocks.compactMap { block in
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
    }

    private func blockTitleColorSubtitle(for block: BellBlock) -> (title: String, color: Color, subtitle: String) {
        switch block.kind {
        case .level(let level):
            let a = store.assignment(for: level)
            let subtitle = [a.teacher, a.room].filter { !$0.isEmpty }.joined(separator: " • ")
            return (a.title, a.color.swiftUIColor, subtitle)
        case .special(let sp):
            return (sp.title, store.color(for: sp), "")
        }
    }

    private func currentHeaderInfo(on reference: Date) -> (title: String, subtitle: String, color: Color, progress: Double, remainingText: String, nextTitle: String?, nextStartText: String?, nextColor: Color?, isCountdownMode: Bool)? {
        let list = datedBlocks(for: reference)
        guard !list.isEmpty else { return nil }

        // Find current or next
        var current: DatedBlock?
        var next: DatedBlock?

        for (idx, item) in list.enumerated() {
            if reference >= item.startDate && reference < item.endDate {
                current = item
                if idx + 1 < list.count { next = list[idx + 1] }
                break
            }
            if reference < item.startDate {
                current = nil
                next = item
                break
            }
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "h:mm a"

        if let current {
            let total = current.endDate.timeIntervalSince(current.startDate)
            let elapsed = reference.timeIntervalSince(current.startDate)
            let remaining = max(0, current.endDate.timeIntervalSince(reference))
            let progress = max(0, min(1, elapsed / max(1, total)))

            let (title, color, subtitle) = blockTitleColorSubtitle(for: current.original)
            let remainingText = "Ends in " + formatDuration(remaining)

            var nextTitleStr: String?
            var nextStartText: String?
            var nextColor: Color?
            if let next {
                let (ntitle, ncolor, _) = blockTitleColorSubtitle(for: next.original)
                nextTitleStr = ntitle
                nextColor = ncolor
                nextStartText = "Starts at " + df.string(from: next.startDate)
            }

            return (title, subtitle, color, progress, remainingText, nextTitleStr, nextStartText, nextColor, false)
        }

        if let next {
            // Countdown mode to next
            let list = datedBlocks(for: reference)
            var anchor: Date = Calendar.current.startOfDay(for: next.startDate)
            if let idx = list.firstIndex(where: { $0.id == next.id }), idx > 0 {
                anchor = list[idx - 1].endDate
            }

            let remaining = max(0, next.startDate.timeIntervalSince(reference))
            let totalGap = max(1, next.startDate.timeIntervalSince(anchor))
            let elapsedGap = max(0, reference.timeIntervalSince(anchor))
            let progress = max(0, min(1, elapsedGap / totalGap))

            let (ntitle, ncolor, _) = blockTitleColorSubtitle(for: next.original)

            return ("No class right now", "Starts soon", .secondary, progress, "Starts in " + formatDuration(remaining), ntitle, "Starts at " + df.string(from: next.startDate), ncolor, true)
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

    // MARK: - To‑dos preview
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func dueDate(for todo: CanvasTodoItem) -> Date? {
        guard let iso = todo.assignment?.dueAt else { return nil }
        return DashboardView.isoParser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private var topTodos: [CanvasTodoItem] {
        let base = store.canvasTodos
            .filter { !store.isTodoCompleted($0.id) }
            .sorted { a, b in
                let da = dueDate(for: a)
                let db = dueDate(for: b)
                switch (da, db) {
                case (nil, nil):
                    return (a.assignment?.name ?? "") < (b.assignment?.name ?? "")
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (let da?, let db?):
                    return da < db
                }
            }
        return Array(base.prefix(5))
    }

    private var gradesList: [(CanvasCourse, GradeSummary?)] {
        store.courses.map { ($0, store.gradesByCourse[$0.id]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    Task {
                        async let t1: Void = store.refreshCanvasTodos()
                        async let t2: Void = store.refreshCanvasCoursesAndGrades()
                        _ = await (t1, t2)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Spacer()

                if store.isFetchingTodos || store.isFetchingGrades {
                    ProgressView().controlSize(.small)
                }

                if let error = store.fetchError ?? store.gradesError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .modifier(SecondaryForeground())
                        .font(.footnote)
                }
            }
            .padding([.top, .horizontal])

            if let announcement = store.pendingAnnouncement {
                UpdateAnnouncementSection(announcement: announcement)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Today header
            if let info = currentHeaderInfo(on: now) {
                CurrentBlockHeader(
                    title: info.title,
                    subtitle: info.subtitle,
                    color: info.color,
                    progress: info.progress,
                    remainingText: info.remainingText,
                    nextTitle: info.nextTitle,
                    nextStartText: info.nextStartText,
                    nextColor: info.nextColor,
                    style: store.cardColorStyle,
                    isCountdownMode: info.isCountdownMode
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

            List {
                Section {
                    if store.canvasToken.isEmpty {
                        CompatibleUnavailableView(
                            title: "Enter Canvas API Token",
                            systemImage: "key.fill",
                            description: "Add your Canvas domain and API token in Settings to show your to‑dos and grades."
                        )
                        .modifier(HideListSeparatorIfAvailable())
                    } else {
                        // Upcoming To‑Dos
                        if topTodos.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                Text("No upcoming to‑dos").modifier(SecondaryForeground())
                                Spacer()
                            }
                            .modifier(HideListSeparatorIfAvailable())
                        } else {
                            ForEach(topTodos) { todo in
                                let color = store.colorForCanvasCourseName(todo.contextName)
                                CanvasTodoRow(
                                    todo: todo,
                                    accentColor: color,
                                    completed: store.isTodoCompleted(todo.id),
                                    style: store.cardColorStyle,
                                    onToggleCompleted: { store.toggleTodoCompleted(todo.id) },
                                    onOpen: { open(todo: todo, domain: store.canvasDomain) }
                                )
                                .contentShape(Rectangle())
                                .modifier(HideListSeparatorIfAvailable())
                            }
                        }
                    }
                } header: {
                    Label("Upcoming To‑Dos", systemImage: "checklist")
                }

                Section {
                    if store.canvasToken.isEmpty {
                        CompatibleUnavailableView(
                            title: "Enter Canvas API Token",
                            systemImage: "key.fill",
                            description: "Add your Canvas domain and API token in Settings to load grades."
                        )
                        .modifier(HideListSeparatorIfAvailable())
                    } else if store.courses.isEmpty && store.isFetchingGrades {
                        HStack { ProgressView(); Text("Loading grades…").modifier(SecondaryForeground()) }
                    } else if store.courses.isEmpty {
                        CompatibleUnavailableView(
                            title: "No Courses",
                            systemImage: "book.closed",
                            description: "We couldn’t find any active courses."
                        )
                        .modifier(HideListSeparatorIfAvailable())
                    } else {
                        ForEach(store.courses) { course in
                            let color = store.colorForCanvasCourseName(course.name)
                            GradesRow(course: course, summary: store.gradesByCourse[course.id], accentColor: color, style: store.cardColorStyle)
                                .contentShape(Rectangle())
                                .onTapGesture { openCourse(course: course, domain: store.canvasDomain) }
                        }
                    }
                } header: {
                    Label("Grades", systemImage: "chart.bar.fill")
                }
            }
            .listStyle(.inset)
        }
        .onReceive(timer) { now = $0 }
        .task {
            if !store.canvasToken.isEmpty {
                async let t1: Void = store.refreshCanvasTodos()
                async let t2: Void = store.refreshCanvasCoursesAndGrades()
                _ = await (t1, t2)
            }
        }
    }

    private func open(todo: CanvasTodoItem, domain: String) {
        let urlString = todo.assignment?.htmlURL ?? todo.htmlURL
        guard let urlString, let url = URL(string: urlString) ?? URL(string: "https://\(domain)") else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    private func openCourse(course: CanvasCourse, domain: String) {
        let urlString = course.htmlURL ?? "https://\(domain)/courses/\(course.id)"
        guard let url = URL(string: urlString) else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

