import SwiftUI
import TelemetryDeck

struct HomeworkView: View {
    @ObservedObject var store: UserScheduleStore

    // MARK: - Sorting & Filtering State
    enum TodoSort: String, CaseIterable, Identifiable {
        case dueDate
        case course
        case points
        case title

        var id: String { rawValue }
        var title: String {
            switch self {
            case .dueDate: "Due Date"
            case .course: "Course"
            case .points: "Points"
            case .title: "Title"
            }
        }

        var systemImage: String {
            switch self {
            case .dueDate: "calendar"
            case .course: "book.closed"
            case .points: "number.circle"
            case .title: "textformat"
            }
        }
    }

    enum CompletionFilter: String, CaseIterable, Identifiable {
        case all, incomplete, complete
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .incomplete: "Incomplete"
            case .complete: "Complete"
            }
        }
        var systemImage: String {
            switch self {
            case .all: "line.3.horizontal.decrease.circle"
            case .incomplete: "circle"
            case .complete: "checkmark.circle.fill"
            }
        }
    }

    @State private var sortMode: TodoSort = .dueDate
    @State private var sortAscending: Bool = true
    @State private var completionFilter: CompletionFilter = .all
    @State private var selectedCourseID: Int? = nil // nil = All courses

    private var completion: (done: Int, total: Int, percent: Double) {
        let total = store.canvasTodos.count
        guard total > 0 else { return (0, 0, 0) }
        let done = store.canvasTodos.reduce(0) { $0 + (store.isTodoCompleted($1.id) ? 1 : 0) }
        return (done, total, Double(done) / Double(total))
    }

    private var segments: [Color] {
        store.canvasTodos.map { store.colorForCanvasCourseName($0.contextName) }
    }

    // MARK: - Helpers for sorting/filtering
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func dueDate(for todo: CanvasTodoItem) -> Date? {
        guard let iso = todo.assignment?.dueAt else { return nil }
        return HomeworkView.isoParser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private func points(for todo: CanvasTodoItem) -> Double? {
        todo.assignment?.pointsPossible
    }

    private var availableCoursesForFilter: [(id: Int?, name: String)] {
        // Build candidates with preferred naming: store name > contextName > "Course #id"
        let fromStore: [(Int, String)] = store.courses.map { ($0.id, $0.name) }
        let fromTodos: [(Int, String)] = store.canvasTodos.compactMap { item in
            guard let id = item.courseID else { return nil }
            let name = store.courses.first(where: { $0.id == id })?.name
                ?? (item.contextName?.isEmpty == false ? item.contextName! : "Course \(id)")
            return (id, name)
        }

        // Merge with de-duplication and a preference for the more descriptive non-empty name
        let mergedPairs = fromStore + fromTodos
        let mergedDict = Dictionary(mergedPairs, uniquingKeysWith: { lhs, rhs in
            // Prefer the store-provided name if it's non-empty; otherwise take the other
            let ltrim = lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            let rtrim = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ltrim.isEmpty, ltrim != "Course" { return lhs }
            if !rtrim.isEmpty { return rhs }
            return lhs
        })

        // Sort deterministically by name
        let sorted = mergedDict.sorted { a, b in
            a.value.localizedCaseInsensitiveCompare(b.value) == .orderedAscending
        }

        // Include "All Courses" first (nil id)
        var result: [(Int?, String)] = [ (nil, "All Courses") ]
        result.append(contentsOf: sorted.map { (Int?($0.key), $0.value) })
        return result
    }

    private var filteredAndSortedTodos: [CanvasTodoItem] {
        var base = store.canvasTodos

        // Filter by completion
        switch completionFilter {
        case .all: break
        case .incomplete:
            base = base.filter { !store.isTodoCompleted($0.id) }
        case .complete:
            base = base.filter { store.isTodoCompleted($0.id) }
        }

        // Filter by course
        if let selectedCourseID {
            base = base.filter { $0.courseID == selectedCourseID }
        }

        // Sort
        base.sort { a, b in
            let ascending = sortAscending
            switch sortMode {
            case .dueDate:
                let da = dueDate(for: a)
                let db = dueDate(for: b)
                // nil due dates go last when ascending, first when descending
                if da == nil && db == nil { return tieBreak(a, b, ascending: ascending) }
                if da == nil { return !ascending }
                if db == nil { return ascending }
                return ascending ? (da! < db!) : (da! > db!)
            case .course:
                let na = (a.contextName ?? "").localizedLowercase
                let nb = (b.contextName ?? "").localizedLowercase
                if na == nb { return tieBreak(a, b, ascending: ascending) }
                return ascending ? (na < nb) : (na > nb)
            case .points:
                let pa = points(for: a) ?? -Double.infinity
                let pb = points(for: b) ?? -Double.infinity
                if pa == pb { return tieBreak(a, b, ascending: ascending) }
                return ascending ? (pa < pb) : (pa > pb)
            case .title:
                let ta = (a.assignment?.name ?? "").localizedLowercase
                let tb = (b.assignment?.name ?? "").localizedLowercase
                if ta == tb { return tieBreak(a, b, ascending: ascending) }
                return ascending ? (ta < tb) : (ta > tb)
            }
        }
        return base
    }

    private func tieBreak(_ a: CanvasTodoItem, _ b: CanvasTodoItem, ascending: Bool) -> Bool {
        // Stable tie-breaker: by title then id
        let ta = (a.assignment?.name ?? "").localizedLowercase
        let tb = (b.assignment?.name ?? "").localizedLowercase
        if ta != tb { return ascending ? (ta < tb) : (ta > tb) }
        return ascending ? (a.id < b.id) : (a.id > b.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Task {
                        async let t1: Void = store.refreshCanvasTodos()
                        async let t2: Void = store.refreshCanvasCoursesAndGrades()
                        _ = await (t1, t2)
                        emitTelemetryForTestConnection()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                // Removed Sort and Filter controls from top bar to relocate next to the To‑Do header

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

            HomeworkProgressHeader(done: completion.done, total: completion.total, percent: completion.percent, segments: segments)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                // Reminder note about completion vs Canvas submission
                Section {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("Marking an item complete here does not submit it on Canvas.")
                            .font(.footnote)
                            .modifier(SecondaryForeground())
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(compatibleBackgroundSecondary())
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.8)
                    )
                    .modifier(HideListSeparatorIfAvailable())
                }

                Section {
                    if store.canvasToken.isEmpty {
                        CompatibleUnavailableView(
                            title: "Enter Canvas API Token",
                            systemImage: "key.fill",
                            description: "Add your Canvas domain and API token in Settings to load your grades."
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
                                .onTapGesture {
                                    openCourse(course: course, domain: store.canvasDomain)
                                }
                        }
                    }
                } header: {
                    Label("Grades", systemImage: "chart.bar.fill")
                }

                Section {
                    if store.canvasToken.isEmpty {
                        CompatibleUnavailableView(
                            title: "Enter Canvas API Token",
                            systemImage: "key.fill",
                            description: "Add your Canvas domain and API token in Settings to load your to‑do items."
                        )
                        .modifier(HideListSeparatorIfAvailable())
                    } else if store.canvasTodos.isEmpty {
                        if store.isFetchingTodos {
                            HStack { ProgressView(); Text("Loading to‑dos…").modifier(SecondaryForeground()) }
                        } else {
                            CompatibleUnavailableView(
                                title: "No To‑Do Items",
                                systemImage: "checkmark.circle",
                                description: "You're all caught up!"
                            )
                            .modifier(HideListSeparatorIfAvailable())
                        }
                    } else {
                        ForEach(filteredAndSortedTodos) { todo in
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
                } header: {
                    // To‑Do header with inline Sort and Filter controls
                    HStack(spacing: 8) {
                        Label("To‑Do", systemImage: "checklist")
                        Spacer(minLength: 8)

                        Menu {
                            // Sort Mode
                            Picker("Sort by", selection: $sortMode) {
                                ForEach(TodoSort.allCases) { mode in
                                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                                }
                            }
                            .pickerStyle(.inline)

                            // Asc/Desc
                            Toggle(isOn: $sortAscending) {
                                Label(sortAscending ? "Ascending" : "Descending",
                                      systemImage: sortAscending ? "arrow.up" : "arrow.down")
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                        }
                        .help("Sort To‑Dos")

                        Menu {
                            // Completion filter
                            Picker("Show", selection: $completionFilter) {
                                ForEach(CompletionFilter.allCases) { f in
                                    Label(f.title, systemImage: f.systemImage).tag(f)
                                }
                            }
                            .pickerStyle(.inline)

                            // Course filter
                            Picker("Course", selection: $selectedCourseID) {
                                ForEach(availableCoursesForFilter, id: \.0) { pair in
                                    Text(pair.1).tag(pair.0)
                                }
                            }
                            .pickerStyle(.inline)

                            // Reset
                            Button(role: .none) {
                                withAnimation(.snappy) {
                                    completionFilter = .all
                                    selectedCourseID = nil
                                }
                            } label: {
                                Label("Reset Filters", systemImage: "arrow.uturn.backward")
                            }
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .help("Filter To‑Dos")
                    }
                }
            }
            .listStyle(.inset)
        }
        .task {
            if !store.canvasToken.isEmpty {
                async let t1: Void = store.refreshCanvasTodos()
                async let t2: Void = store.refreshCanvasCoursesAndGrades()
                _ = await (t1, t2)
            }
        }
    }

    private func emitTelemetryForTestConnection() {
        let todosStatus = store.lastTodosHTTPStatus
        let coursesStatus = store.lastCoursesHTTPStatus

        func sendUnauthorized(endpoint: String, status: Int) {
            TelemetryDeck.signal("CanvasConnectionUnauthorized", parameters: ["endpoint": endpoint, "status": "\(status)"])
        }
        func sendCoursesServerError(status: Int) {
            TelemetryDeck.signal("CanvasCoursesServerError", parameters: ["endpoint": store.lastCoursesEndpoint, "status": "\(status)"])
        }
        func sendGenericFailure(endpoint: String, status: Int) {
            TelemetryDeck.signal("CanvasConnectionFailed", parameters: ["endpoint": endpoint, "status": "\(status)"])
        }

        if let ts = todosStatus, let cs = coursesStatus,
           (200..<300).contains(ts), (200..<300).contains(cs) {
            TelemetryDeck.signal("CanvasConnectionSuccess")
            return
        }

        if let ts = todosStatus, !(200..<300).contains(ts) {
            ts == 401 ? sendUnauthorized(endpoint: store.lastTodosEndpoint, status: ts)
                      : sendGenericFailure(endpoint: store.lastTodosEndpoint, status: ts)
        }

        if let cs = coursesStatus, !(200..<300).contains(cs) {
            if cs == 401 {
                sendUnauthorized(endpoint: store.lastCoursesEndpoint, status: cs)
            } else if (500..<600).contains(cs) {
                sendCoursesServerError(status: cs)
            } else {
                sendGenericFailure(endpoint: store.lastCoursesEndpoint, status: cs)
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

private struct HomeworkProgressHeader: View {
    let done: Int
    let total: Int
    let percent: Double
    let segments: [Color]

    private var percentText: String {
        guard total > 0 else { return "0%" }
        return String(format: "%.0f%%", percent * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(percentText).font(.title3.bold())
                Spacer()
                Text("\(done)/\(total) complete")
                    .font(.subheadline.weight(.semibold))
                    .modifier(SecondaryForeground())
            }
            SegmentedProgressBar(percent: percent, segments: segments)
                .frame(height: 16)
        }
        .padding(.vertical, 6)
    }
}

private struct SegmentedProgressBar: View {
    let percent: Double
    let segments: [Color]

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clipWidth = max(0, min(1, percent)) * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                HStack(spacing: 0) {
                    ForEach(segments.indices, id: \.self) { idx in
                        segments[idx]
                            .frame(width: width / CGFloat(max(1, segments.count)))
                    }
                }
                .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: clipWidth, height: geo.size.height)))
                .mask(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

struct CanvasTodoRow: View {
    let todo: CanvasTodoItem
    let accentColor: Color
    let completed: Bool
    let style: CardColorStyle
    let onToggleCompleted: () -> Void
    let onOpen: () -> Void

    private var title: String { todo.assignment?.name ?? "Untitled" }
    private var course: String { todo.contextName ?? "Course" }

    // Robust ISO8601 parsing (Canvas may include fractional seconds/timezones)
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private var dueText: String {
        guard let iso = todo.assignment?.dueAt,
              let date = CanvasTodoRow.isoParser.date(from: iso)
                ?? ISO8601DateFormatter().date(from: iso) else {
            return "No due date"
        }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Due Today" }
        if cal.isDateInTomorrow(date) { return "Due Tomorrow" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return "Due " + fmt.string(from: date)
    }

    private var pointsText: String? {
        if let pts = todo.assignment?.pointsPossible {
            if pts == floor(pts) {
                return String(format: "%.0f pts", pts)
            } else {
                return String(format: "%.1f pts", pts)
            }
        }
        return nil
    }

    private var submissionTypes: [String] {
        todo.assignment?.submissionTypes ?? []
    }

    private var lockBannerText: String? {
        let assn = todo.assignment
        let isoFmt = CanvasTodoRow.isoParser
        if let locked = assn?.lockedForUser, locked == true {
            if let unlock = assn?.unlockAt, let unlockDate = isoFmt.date(from: unlock) {
                let df = DateFormatter()
                df.dateStyle = .medium
                df.timeStyle = .short
                return "Locked until " + df.string(from: unlockDate)
            }
            if let expl = assn?.lockExplanation, !expl.isEmpty {
                return expl
            }
            return "Locked"
        }
        if let unlock = assn?.unlockAt, let unlockDate = isoFmt.date(from: unlock), unlockDate > Date() {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return "Locked until " + df.string(from: unlockDate)
        }
        return nil
    }

    private var descriptionPreview: String? {
        guard let raw = todo.assignment?.description else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let noHTML = trimmed.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return noHTML
    }

    private var softGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor.opacity(0.20), accentColor.opacity(0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var softStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor.opacity(0.55), accentColor.opacity(0.18)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [accentColor.opacity(0.7), accentColor.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 6)

            // Main tap area opens the item
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .strikethrough(completed, color: .secondary)
                            .opacity(completed ? 0.55 : 1.0)
                        Spacer()
                        HStack(spacing: 10) {
                            if let pointsText {
                                Label(pointsText, systemImage: "number.circle")
                                    .font(.subheadline)
                                    .modifier(SecondaryForeground())
                            }
                            Label(dueText, systemImage: "calendar")
                                .font(.subheadline)
                                .modifier(SecondaryForeground())
                        }
                    }

                    Label(course, systemImage: "book.closed")
                        .font(.subheadline)
                        .modifier(SecondaryForeground())

                    if !submissionTypes.isEmpty {
                        SubmissionChips(submissionTypes: submissionTypes)
                    }

                    if let lockText = lockBannerText {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill")
                            Text(lockText)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.yellow.opacity(0.18))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.yellow.opacity(0.35), lineWidth: 0.8)
                        )
                        .foregroundColor(.yellow)
                    }

                    if let preview = descriptionPreview {
                        Text(preview)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .modifier(SecondaryForeground())
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Completion toggle
            Button(action: onToggleCompleted) {
                ZStack {
                    Circle()
                        .strokeBorder(completed ? Color.green : Color.secondary.opacity(0.4), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if completed {
                        Circle().fill(Color.green).frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
        }
        .padding(10)
        .background(backgroundForStyle)
        .overlay(strokeForStyle)
        .overlay(glowForStyle)
        // Removed the extra quaternary stroke to avoid double borders
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
                .shadow(color: accentColor.opacity(0.10), radius: 8, x: 0, y: 0)
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.10))
                    .blur(radius: 8)
                    .scaleEffect(1.005)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(softGradient)
                    .shadow(color: accentColor.opacity(0.16), radius: 6, x: 0, y: 0)
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
                .stroke(softStrokeGradient, lineWidth: 1.0)
        case .colors:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(softStrokeGradient, lineWidth: 1.2)
        }
    }

    @ViewBuilder
    private var glowForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.08), lineWidth: 3)
                .blur(radius: 5)
        case .colors:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.04), lineWidth: 2)
                .blur(radius: 3)
        }
    }
}

private struct SubmissionChips: View {
    let submissionTypes: [String]

    // Map known Canvas keys to friendly labels
    private func friendlyLabel(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // Hide blanks and "none"
        if lower == "none" { return nil }

        switch lower {
        case "on_paper": return "On Paper"
        case "online_upload": return "Online Upload"
        case "external_tool": return "External Tool"
        default:
            // Fallback: prettify snake_case to Title Case
            let parts = lower.split(separator: "_")
            let pretty = parts.map { $0.capitalized }.joined(separator: " ")
            return pretty.isEmpty ? nil : pretty
        }
    }

    private var displayItems: [String] {
        submissionTypes.compactMap { friendlyLabel(for: $0) }
    }

    var body: some View {
        // If nothing to show, render nothing
        if displayItems.isEmpty {
            EmptyView()
        } else {
            let cols = [GridItem(.adaptive(minimum: 90), spacing: 6)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                ForEach(displayItems, id: \.self) { kind in
                    Text(kind)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.6)
                        )
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct GradesRow: View {
    let course: CanvasCourse
    let summary: GradeSummary?
    let accentColor: Color
    let style: CardColorStyle

    private var softGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor.opacity(0.22), accentColor.opacity(0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var softStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor.opacity(0.7), accentColor.opacity(0.2)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [accentColor.opacity(0.7), accentColor.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(course.name).font(.headline)
                    Spacer()
                    if let summary {
                        Label(summary.displayCurrent, systemImage: "chart.bar")
                            .font(.subheadline)
                            .modifier(SecondaryForeground())
                    } else {
                        Text("No grade yet")
                            .font(.subheadline)
                            .modifier(SecondaryForeground())
                    }
                }

                if let code = course.courseCode, !code.isEmpty {
                    Text(code)
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
        // Removed extra quaternary border to match To‑Do rows and avoid double outlines
    }

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(compatibleBackgroundSecondary())
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        case .subtle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(compatibleBackgroundSecondary())
                .shadow(color: accentColor.opacity(0.12), radius: 10, x: 0, y: 0)
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .blur(radius: 10)
                    .scaleEffect(1.01)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(softGradient)
                    .shadow(color: accentColor.opacity(0.18), radius: 8, x: 0, y: 0)
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
                .stroke(softStrokeGradient, lineWidth: 1.2)
        case .colors:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(softStrokeGradient, lineWidth: 1.4)
        }
    }

    @ViewBuilder
    private var glowForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.10), lineWidth: 4)
                .blur(radius: 7)
        case .colors:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accentColor.opacity(0.06), lineWidth: 2)
                .blur(radius: 4)
        }
    }
}

// Legacy FlowLayout kept for reference but unused by To‑Do chips now
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let runSpacing: CGFloat
    @ViewBuilder var content: Content

    init(spacing: CGFloat = 8, runSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.runSpacing = runSpacing
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            var x: CGFloat = 0
            var y: CGFloat = 0

            ZStack(alignment: .topLeading) {
                content
                    .alignmentGuide(.leading) { d in
                        if (abs(x - d.width) > width) {
                            x = 0
                            y -= (d.height + runSpacing)
                        }
                        let result = x
                        if d.width <= width {
                            x -= (d.width + spacing)
                        }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = y
                        return result
                    }
            }
        }
        .frame(minHeight: 0)
    }
}
