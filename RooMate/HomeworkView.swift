import SwiftUI
import TelemetryDeck

struct HomeworkView: View {
    @ObservedObject var store: UserScheduleStore

    private var completion: (done: Int, total: Int, percent: Double) {
        let total = store.canvasTodos.count
        guard total > 0 else { return (0, 0, 0) }
        let done = store.canvasTodos.reduce(0) { $0 + (store.isTodoCompleted($1.id) ? 1 : 0) }
        return (done, total, Double(done) / Double(total))
    }

    private var segments: [Color] {
        store.canvasTodos.map { store.colorForCanvasCourseName($0.contextName) }
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
                            GradesRow(course: course, summary: store.gradesByCourse[course.id])
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
                        ForEach(store.canvasTodos) { todo in
                            let color = store.colorForCanvasCourseName(todo.contextName)

                            CanvasTodoRow(
                                todo: todo,
                                accentColor: color,
                                completed: store.isTodoCompleted(todo.id),
                                onToggleCompleted: { store.toggleTodoCompleted(todo.id) },
                                onOpen: { open(todo: todo, domain: store.canvasDomain) }
                            )
                            .contentShape(Rectangle())

                            HStack {
                                Text(store.isTodoCompleted(todo.id) ? "✓ Completed" : "○ Incomplete")
                                    .font(.caption)
                                    .modifier(SecondaryForeground())
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Label("To‑Do", systemImage: "checklist")
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
    let onToggleCompleted: () -> Void
    let onOpen: () -> Void

    private var title: String { todo.assignment?.name ?? "Untitled" }
    private var course: String { todo.contextName ?? "Course" }

    private var dueText: String {
        guard let iso = todo.assignment?.dueAt, let date = ISO8601DateFormatter().date(from: iso) else {
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

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(CompatibleGradient(accentColor))
                .frame(width: 6)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .strikethrough(completed, color: .secondary)
                            .opacity(completed ? 0.55 : 1.0)
                        Spacer()
                        Label(dueText, systemImage: "calendar")
                            .font(.subheadline)
                            .modifier(SecondaryForeground())
                    }
                    HStack(spacing: 10) {
                        Label(course, systemImage: "book.closed")
                            .font(.subheadline)
                            .modifier(SecondaryForeground())
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
            .tint(.blue)
            .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
        }
    }
}

struct GradesRow: View {
    let course: CanvasCourse
    let summary: GradeSummary?

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(CompatibleGradient(.accentColor))
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
    }
}
