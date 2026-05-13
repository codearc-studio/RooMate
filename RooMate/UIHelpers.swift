import SwiftUI

struct BackgroundView: View {
    var body: some View {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #elseif canImport(AppKit)
        Color(nsColor: NSColor.windowBackgroundColor)
        #else
        Color.white
        #endif
    }
}

// MARK: - Modifiers and helpers

struct SafeAreaTopPadding: ViewModifier {
    let value: CGFloat
    init(_ value: CGFloat) { self.value = value }
    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 16.0, *) {
            content.safeAreaPadding(.top, value)
        } else {
            content.padding(.top, value)
        }
    }
}

struct HideListSeparatorIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, iOS 15.0, *) {
            content.listRowSeparator(.hidden)
        } else {
            content
        }
    }
}

struct SecondaryForeground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, iOS 15.0, *) {
            content.foregroundStyle(.secondary)
        } else {
            content.foregroundColor(.secondary)
        }
    }
}

// Replaces `struct CompatibleGradient: ShapeStyle`
func compatibleGradient(_ color: Color) -> AnyShapeStyle {
    if #available(iOS 15.0, macOS 12.0, *) {
        return AnyShapeStyle(color.gradient)
    } else {
        return AnyShapeStyle(
            LinearGradient(
                gradient: Gradient(colors: [color.opacity(0.9), color]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// Replaces `struct CompatibleBackgroundSecondary: ShapeStyle`
func compatibleBackgroundSecondary() -> AnyShapeStyle {
    if #available(macOS 14.0, iOS 17.0, *) {
        return AnyShapeStyle(Color.secondary.opacity(0.15))
    } else {
        #if canImport(AppKit)
        return AnyShapeStyle(Color(nsColor: NSColor.windowBackgroundColor).opacity(0.6))
        #else
        return AnyShapeStyle(Color(white: 0.95))
        #endif
    }
}

struct MacURLContentTypeIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(AppKit)
        if #available(macOS 14.0, *) {
            content.textContentType(.URL)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct CompatibleUnavailableView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        if #available(macOS 14.0, iOS 17.0, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
        } else {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(description).font(.subheadline).modifier(SecondaryForeground())
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Modern Tab Bar

struct ModernTabBar<Tab>: View where Tab: Hashable {
    @Binding var selectedTab: Tab
    
    let tabs: [(tab: Tab, label: String, systemImage: String)]
    
    init(selectedTab: Binding<Tab>, tabs: [(tab: Tab, label: String, systemImage: String)] = []) {
        self._selectedTab = selectedTab
        self.tabs = tabs.isEmpty ? {
            // Default tabs for ContentView
            if let tabs = [
                (tab: ContentView.Tab.dashboard as? Tab, label: "Dashboard", systemImage: "square.grid.2x2"),
                (tab: ContentView.Tab.schedule as? Tab, label: "Schedule", systemImage: "calendar"),
                (tab: ContentView.Tab.settings as? Tab, label: "Settings", systemImage: "gearshape")
            ].compactMap({ $0 }) as? [(tab: Tab, label: String, systemImage: String)] {
                tabs
            } else {
                []
            }
        }() : tabs
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.1)
            
            HStack(spacing: 0) {
                // For default ContentView.Tab usage
                if selectedTab is ContentView.Tab {
                    TabBarItem(
                        isSelected: (selectedTab as? ContentView.Tab) == .dashboard,
                        label: "Dashboard",
                        systemImage: "square.grid.2x2"
                    )
                    .onTapGesture {
                        withAnimation(DesignTokens.Animation.snappy) {
                            selectedTab = ContentView.Tab.dashboard as! Tab
                        }
                    }
                    
                    Spacer()
                    
                    TabBarItem(
                        isSelected: (selectedTab as? ContentView.Tab) == .schedule,
                        label: "Schedule",
                        systemImage: "calendar"
                    )
                    .onTapGesture {
                        withAnimation(DesignTokens.Animation.snappy) {
                            selectedTab = ContentView.Tab.schedule as! Tab
                        }
                    }
                    
                    TabBarItem(
                        isSelected: (selectedTab as? ContentView.Tab) == .events,
                        label: "Events",
                        systemImage: "calendar.circle"
                    )
                    .onTapGesture {
                        withAnimation(DesignTokens.Animation.snappy) {
                            selectedTab = ContentView.Tab.events as! Tab
                        }
                    }
                    
                    TabBarItem(
                        isSelected: (selectedTab as? ContentView.Tab) == .settings,
                        label: "Settings",
                        systemImage: "gearshape"
                    )
                    .onTapGesture {
                        withAnimation(DesignTokens.Animation.snappy) {
                            selectedTab = ContentView.Tab.settings as! Tab
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.95, green: 0.95, blue: 0.95).opacity(0.95),
                        Color(red: 0.95, green: 0.95, blue: 0.95)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(Color(red: 0.95, green: 0.95, blue: 0.95))
    }
}

struct TabBarItem: View {
    let isSelected: Bool
    let label: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .secondary)
            
            Text(label)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(isSelected ? DesignTokens.Colors.primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(isSelected ? DesignTokens.Colors.primary.opacity(0.08) : Color.clear)
                .animation(.snappy(duration: 0.2), value: isSelected)
        )
    }
}
// MARK: - Settings Building Blocks

struct SettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if let title = title, !title.isEmpty {
                Text(title.uppercased())
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(compatibleBackgroundSecondary())
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, DesignTokens.Spacing.md)

            if let footer = footer, !footer.isEmpty {
                Text(footer)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
}

struct SettingsRow<Accessory: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var accessory: Accessory
    var action: (() -> Void)?

    init(icon: String? = nil,
         title: String,
         subtitle: String? = nil,
         action: (() -> Void)? = nil,
         @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        Group {
            if let action = action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(
            Rectangle()
                .fill(Color.clear)
        )
        .overlay(alignment: .bottom) {
            Divider().opacity(0.1)
                .padding(.leading, icon == nil ? 0 : 44)
        }
    }

    private var content: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            if let icon = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(compatibleGradient(DesignTokens.Colors.primary as Color))
                        .opacity(0.18)
                    Image(systemName: icon)
                        .foregroundStyle(DesignTokens.Colors.primary)
                        .font(.body)
                }
                .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(.primary)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            accessory
                .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
        }
    }
}

// Convenience toggles and navigation chevrons matching the style
struct SettingsToggle: View {
    let icon: String?
    let title: String
    @Binding var isOn: Bool
    var subtitle: String?

    var body: some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle, accessory:  {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        })
    }
}

struct SettingsNavigationRow<Destination: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    @ViewBuilder var destination: Destination

    init(icon: String? = nil, title: String, subtitle: String? = nil, @ViewBuilder destination: () -> Destination) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
                .navigationTitle(title)
        } label: {
            SettingsRow(icon: icon, title: title, subtitle: subtitle, accessory:  {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            })
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ModernTabBar enhancements for custom tabs
extension ModernTabBar {
    // Provide an initializer for custom tabs without relying on ContentView.Tab
    init(selectedTab: Binding<Tab>, items: [(tab: Tab, label: String, systemImage: String)]) {
        self._selectedTab = selectedTab
        self.tabs = items
    }
}

