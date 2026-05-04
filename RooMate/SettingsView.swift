import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UserScheduleStore

    @State private var isClassesExpanded: Bool = true
    @State private var showToken: Bool = false
    @State private var testResult: String?
    @State private var showTokenHelp: Bool = false

    @State private var isCustomizationExpanded: Bool = true
    @State private var isNotificationsExpanded: Bool = true

    private var editableLevels: [Level] {
        [.level1, .level2, .level3, .level4, .level5, .level6, .level7, .music]
    }

    private var notificationStatusText: String {
        #if canImport(UserNotifications)
        switch store.notificationAuthStatus {
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
        #else
        return "Unavailable"
        #endif
    }

    private var appName: String {
        let dict = Bundle.main.infoDictionary
        return dict?["CFBundleDisplayName"] as? String
            ?? dict?["CFBundleName"] as? String
            ?? "App"
    }
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private let feedbackEmail = "29makaio@abingtonfriends.net"
    private let websiteURL = URL(string: "https://roomateafs.net")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: 4)

                Button {
                    withAnimation(.snappy) { isCustomizationExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isCustomizationExpanded ? 90 : 0))
                            .modifier(SecondaryForeground())
                            .animation(.snappy, value: isCustomizationExpanded)
                        Image(systemName: "paintbrush.pointed").foregroundStyle(.secondary)
                        Text("Customization").font(.title2.bold())
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Customization")
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isCustomizationExpanded ? "Expanded" : "Collapsed")

                if isCustomizationExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Appearance").font(.headline)
                            Text("Choose light, dark, or follow the system.")
                                .font(.footnote)
                                .modifier(SecondaryForeground())

                            Picker("Appearance", selection: $store.appearance) {
                                ForEach(AppearancePreference.allCases) { option in
                                    Label(option.title, systemImage: option.systemImage).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(.blue)
                            .accessibilityLabel("Appearance")
                        }

                        Divider().opacity(0.2)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Class Card Colors").font(.headline)
                            Text("Pick how colorful class cards should look.")
                                .font(.footnote)
                                .modifier(SecondaryForeground())

                            Picker("Class Card Colors", selection: $store.cardColorStyle) {
                                ForEach(CardColorStyle.allCases) { style in
                                    Label(style.title, systemImage: style.systemImage).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(.blue)
                            .accessibilityLabel("Class Card Colors")
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CompatibleBackgroundSecondary())
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.8)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                #if canImport(AppKit)
                Button {
                    withAnimation(.snappy) { isNotificationsExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isNotificationsExpanded ? 90 : 0))
                            .modifier(SecondaryForeground())
                            .animation(.snappy, value: isNotificationsExpanded)
                        Image(systemName: "bell.badge.fill").foregroundStyle(.secondary)
                        Text("Notifications").font(.title2.bold())
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .tint(.blue)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Notifications")
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isNotificationsExpanded ? "Expanded" : "Collapsed")

                if isNotificationsExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $store.notificationsEnabled) {
                            Text("Enable notifications")
                        }
                        .toggleStyle(.switch)
                        .tint(.blue)

                        HStack {
                            Label("Status: \(notificationStatusText)", systemImage: "info.circle")
                                .modifier(SecondaryForeground())
                            Spacer()
                            Button {
                                Task { @MainActor in await store.refreshNotificationStatus() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Class Alerts").font(.headline).tint(.blue)

                            Toggle(isOn: $store.notifyClassStartingSoon) {
                                Label("Notify when a class is starting soon", systemImage: "bell.and.waveform.fill")
                            }
                            .disabled(!store.notificationsEnabled)
                            .tint(.blue)

                            Toggle(isOn: $store.notifyClassEndingSoon) {
                                Label("Notify when a class is ending soon", systemImage: "bell.circle.fill")
                            }
                            .disabled(!store.notificationsEnabled)
                            .tint(.blue)

                            Text("These settings control which class alerts we schedule. You can adjust timing and permissions in System Settings.")
                                .font(.footnote)
                                .modifier(SecondaryForeground())
                        }

                        HStack(spacing: 10) {
                            Button {
                                Task { @MainActor in await store.requestNotificationPermission() }
                            } label: {
                                Label("Request Permission", systemImage: "bell.badge")
                            }

                            Button { store.openSystemNotificationSettings() } label: {
                                Label("Open System Settings", systemImage: "gearshape")
                            }

                            Button {
                                Task { @MainActor in await store.sendTestNotification() }
                            } label: {
                                Label("Send Test", systemImage: "paperplane.fill")
                            }
                            .disabled(!(store.notificationAuthStatus == .authorized || store.notificationAuthStatus == .provisional))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CompatibleBackgroundSecondary())
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.8)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                #endif

                VStack(alignment: .leading, spacing: 12) {
                    Text("Canvas Key (For Homework And Grades) (Optional)")
                        .font(.title2.bold())

                    HStack {
                        Text("Domain").frame(width: 80, alignment: .leading)
                        TextField("afs.instructure.com", text: $store.canvasDomain)
                            .textFieldStyle(.roundedBorder)
                            #if canImport(UIKit)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            #else
                            .autocorrectionDisabled()
                            .modifier(MacURLContentTypeIfAvailable())
                            #endif
                    }

                    HStack(alignment: .center, spacing: 8) {
                        Text("API Token").frame(width: 80, alignment: .leading)

                        if showToken {
                            TextField("Paste token", text: $store.canvasToken)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                            #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                            #endif
                        } else {
                            SecureField("Paste token", text: $store.canvasToken)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                        }

                        Button { showToken.toggle() } label: {
                            Image(systemName: showToken ? "eye.slash.fill" : "eye.fill")
                        }
                        .help(showToken ? "Hide Token" : "Show Token")

                        Button { showTokenHelp = true } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .help("How to get your Canvas API token")
                        .popover(isPresented: $showTokenHelp, arrowEdge: .top) {
                            TokenHelpView(domain: store.canvasDomain, isPresented: $showTokenHelp)
                                .frame(minWidth: 320)
                                .padding()
                        }

                        Button(role: .destructive) {
                            Task { @MainActor in store.clearCanvasToken() }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Clear saved API token")
                    }

                    HStack {
                        Button {
                            Task {
                                async let t1: Void = store.refreshCanvasTodos()
                                async let t2: Void = store.refreshCanvasCoursesAndGrades()
                                _ = await (t1, t2)

                                if let err = store.fetchError ?? store.gradesError {
                                    testResult = "Failed: \(err)"
                                } else {
                                    testResult = "Success: \(store.canvasTodos.count) todos, \(store.courses.count) courses"
                                }
                            }
                        } label: {
                            Label("Test Connection", systemImage: "wifi")
                        }

                        if store.isFetchingTodos || store.isFetchingGrades {
                            ProgressView().controlSize(.small)
                        }

                        if let testResult {
                            Text(testResult)
                                .font(.footnote)
                                .modifier(SecondaryForeground())
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CompatibleBackgroundSecondary())
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.8)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Updates").font(.title2.bold())
                    Text("Click Check For Updates To Check For New Features Or Bug Fixes.")
                        .font(.footnote)
                        .modifier(SecondaryForeground())

                    HStack(spacing: 10) {
                        Button {
                            Task { @MainActor in await store.refreshUpdateAnnouncement() }
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                        }

                        if let pending = store.pendingAnnouncement {
                            Text("Pending: \(pending.updateNumber)")
                                .font(.footnote)
                                .modifier(SecondaryForeground())
                        } else {
                            Text("No pending announcements")
                                .font(.footnote)
                                .modifier(SecondaryForeground())
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CompatibleBackgroundSecondary())
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.8)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 0)
                
                Button {
                    withAnimation(.snappy) { isClassesExpanded.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isClassesExpanded ? 90 : 0))
                            .modifier(SecondaryForeground())
                            .animation(.snappy, value: isClassesExpanded)
                        Text("Your Classes").font(.title2.bold())
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .tint(.blue)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Your Classes")
                .accessibilityAddTraits(.isButton)
                .accessibilityValue(isClassesExpanded ? "Expanded" : "Collapsed")

                if isClassesExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(editableLevels, id: \.self) { level in
                            LevelEditorRow(level: level, assignment: store.binding(for: level))
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(CompatibleBackgroundSecondary())
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(.quaternary, lineWidth: 0.8)
                                )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Special Blocks").font(.title2.bold())

                        SpecialColorRow(title: SpecialBlock.lunch.title, systemImage: SpecialBlock.lunch.systemImage, color: store.colorBinding(for: .lunch))
                        SpecialColorRow(title: SpecialBlock.officeHours.title, systemImage: SpecialBlock.officeHours.systemImage, color: store.colorBinding(for: .officeHours))
                        SpecialColorRow(title: SpecialBlock.worship.title, systemImage: SpecialBlock.worship.systemImage, color: store.colorBinding(for: .worship))
                        SpecialColorRow(title: SpecialBlock.consciousCommunities.title, systemImage: SpecialBlock.consciousCommunities.systemImage, color: store.colorBinding(for: .consciousCommunities))
                        SpecialColorRow(title: SpecialBlock.advisory.title, systemImage: SpecialBlock.advisory.systemImage, color: store.colorBinding(for: .advisory))
                        SpecialColorRow(title: SpecialBlock.assembly.title, systemImage: SpecialBlock.assembly.systemImage, color: store.colorBinding(for: .assembly))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(CompatibleBackgroundSecondary())
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.8)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                VStack(spacing: 6) {
                    Text("\(appName) — Version \(appVersion)")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("RooMate helps you track your schedule, homework, and grades with a clean, customizable interface.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .modifier(SecondaryForeground())
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 8)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .modifier(SafeAreaTopPadding(6))
        .task { await store.refreshNotificationStatus() }
    }

    // About helpers
    private func openMail(to address: String, subject: String, body: String) {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "mailto:\(address)?subject=\(subjectEncoded)&body=\(bodyEncoded)"
        guard let url = URL(string: urlString) else { return }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    private func defaultFeedbackBody() -> String {
        #if canImport(AppKit)
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #else
        let osVersion = UIDevice.current.systemVersion
        #endif
        return """

        Please write your feedback above this line.

        —
        App: \(appName)
        Version: \(appVersion)
        OS: \(osVersion)
        """
    }
}

struct LevelEditorRow: View {
    let level: Level
    @Binding var assignment: ClassAssignment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(level.displayName).font(.headline)

            TextField("Class title", text: $assignment.title)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Teacher", text: $assignment.teacher)
                    .textFieldStyle(.roundedBorder)

                TextField("Room", text: $assignment.room)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }

            ColorPicker("Color", selection: Binding(
                get: { assignment.color.swiftUIColor },
                set: { assignment.color = CodableColor($0) }
            ))
        }
    }
}

struct SpecialColorRow: View {
    let title: String
    let systemImage: String
    @Binding var color: Color

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage).font(.headline)
            Spacer()
            ColorPicker("", selection: $color)
                .labelsHidden()
                .frame(maxWidth: 220)
        }
        .padding(.vertical, 4)
    }
}

struct TokenHelpView: View {
    let domain: String
    @Binding var isPresented: Bool

    private var domainURL: URL? { URL(string: "https://\(domain)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Get your Canvas API Token", systemImage: "questionmark.circle.fill")
                    .font(.headline)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill").modifier(SecondaryForeground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text("Steps")
                .font(.subheadline.weight(.semibold))
                .modifier(SecondaryForeground())

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open Canvas in a web browser and sign in.")
                Text("2. Go to Account > Settings.")
                Text("3. Scroll to the Approved Integrations or New Access Token section.")
                Text("4. Create a new token, give it a purpose, make the expiry date the maximum (120 days) and copy the token value.")
                Text("5. Paste the token here. Keep it secret.")
                Text("! Make sure to write down your token, you won't be able to get it again.")
            }
            .font(.callout)

            if let url = domainURL {
                Button {
                    #if canImport(AppKit)
                    NSWorkspace.shared.open(url)
                    #elseif canImport(UIKit)
                    UIApplication.shared.open(url)
                    #endif
                } label: {
                    Label("Open \(domain)", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.top, 4)
            }

            Text("Note: You can revoke this token anytime from Canvas settings.")
                .font(.footnote)
                .modifier(SecondaryForeground())
                .padding(.top, 6)
        }
        .padding()
    }
}
