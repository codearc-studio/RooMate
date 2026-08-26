import SwiftUI

/// Root background used throughout RooMate. This intentionally does not use
/// NSColor.windowBackgroundColor because macOS's default dark gray is much
/// lighter than the RooMate v6 visual language.
struct BackgroundView: View {
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var store = UserScheduleStore.shared

  var body: some View {
    ZStack {
      if colorScheme == .dark {
        DesignTokens.Colors.background

        if store.theme != .oled {
          // A restrained RooMate glow keeps dark canvases warm. OLED Black
          // intentionally skips these layers so the main canvas stays #000.
          RadialGradient(
            colors: [
              DesignTokens.Colors.today.opacity(0.030),
              Color.clear,
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: 520
          )

          RadialGradient(
            colors: [
              DesignTokens.Colors.events.opacity(0.016),
              Color.clear,
            ],
            center: .topTrailing,
            startRadius: 0,
            endRadius: 620
          )
        }
      } else {
        LinearGradient(
          colors: [
            DesignTokens.Colors.lightCanvasTop,
            DesignTokens.Colors.background,
            DesignTokens.Colors.lightCanvasBottom,
          ],
          startPoint: .top,
          endPoint: .bottom
        )

        // Very restrained warm/cool light keeps the canvas from feeling
        // like a blank system window without turning it into a gradient UI.
        RadialGradient(
          colors: [
            DesignTokens.Colors.today.opacity(0.030),
            Color.clear,
          ],
          center: .topLeading,
          startRadius: 0,
          endRadius: 420
        )

        RadialGradient(
          colors: [
            DesignTokens.Colors.events.opacity(0.020),
            Color.clear,
          ],
          center: .topTrailing,
          startRadius: 0,
          endRadius: 520
        )
      }
    }
    .ignoresSafeArea()
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
    content.foregroundStyle(DesignTokens.Colors.secondaryText)
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

/// Legacy helper used by many existing RooMate cards. Mapping it to the new
/// semantic surface instantly moves those screens off the old system-gray card
/// color while we migrate each screen to `rooSurface()` over time.
func compatibleBackgroundSecondary() -> AnyShapeStyle {
  AnyShapeStyle(DesignTokens.Colors.surface)
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
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2)
        .foregroundStyle(DesignTokens.Colors.secondaryText)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)

        Text(description)
          .font(.subheadline)
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()
    }
    .padding(.vertical, 8)
  }
}

// MARK: - Modern Tab Bar

struct ModernTabBar<Tab>: View where Tab: Hashable {
  @Binding var selectedTab: Tab

  let tabs: [(tab: Tab, label: String, systemImage: String)]

  init(selectedTab: Binding<Tab>, tabs: [(tab: Tab, label: String, systemImage: String)] = []) {
    self._selectedTab = selectedTab
    self.tabs =
      tabs.isEmpty
      ? {
        if let tabs = [
          (
            tab: ContentView.Tab.dashboard as? Tab, label: "Today",
            systemImage: "square.grid.2x2.fill"
          ),
          (tab: ContentView.Tab.schedule as? Tab, label: "Schedule", systemImage: "calendar"),
          (tab: ContentView.Tab.menu as? Tab, label: "Dining", systemImage: "fork.knife"),
          (
            tab: ContentView.Tab.athletics as? Tab, label: "Sports", systemImage: "sportscourt.fill"
          ),
          (tab: ContentView.Tab.events as? Tab, label: "Events", systemImage: "calendar.circle"),
          (tab: ContentView.Tab.settings as? Tab, label: "Settings", systemImage: "gearshape"),
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
        .overlay(DesignTokens.Colors.border)
        .opacity(0.7)

      HStack(spacing: 0) {
        ForEach(tabs.indices, id: \.self) { index in
          let tab = tabs[index]
          TabBarItem(
            isSelected: selectedTab == tab.tab,
            label: tab.label,
            systemImage: tab.systemImage
          )
          .onTapGesture {
            withAnimation(DesignTokens.Animation.snappy) {
              selectedTab = tab.tab
            }
          }

          if index < tabs.count - 1 {
            Spacer()
          }
        }
      }
      .padding(.horizontal, DesignTokens.Spacing.lg)
      .padding(.vertical, DesignTokens.Spacing.md)
    }
    .background(DesignTokens.Colors.sidebar)
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
        .foregroundStyle(
          isSelected ? DesignTokens.Colors.primary : DesignTokens.Colors.secondaryText)

      Text(label)
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(
          isSelected ? DesignTokens.Colors.primary : DesignTokens.Colors.secondaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, DesignTokens.Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        .fill(isSelected ? DesignTokens.Colors.primary.opacity(0.14) : Color.clear)
        .animation(DesignTokens.Animation.snappy, value: isSelected)
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
          .foregroundStyle(DesignTokens.Colors.subtleText)
          .padding(.horizontal, DesignTokens.Spacing.md)
      }

      VStack(spacing: 0) {
        content
      }
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
          .fill(DesignTokens.Colors.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      )
      .padding(.horizontal, DesignTokens.Spacing.md)

      if let footer = footer, !footer.isEmpty {
        Text(footer)
          .font(DesignTokens.Typography.caption)
          .foregroundStyle(DesignTokens.Colors.secondaryText)
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

  init(
    icon: String? = nil,
    title: String,
    subtitle: String? = nil,
    action: (() -> Void)? = nil,
    @ViewBuilder accessory: () -> Accessory = { EmptyView() }
  ) {
    self.icon = icon
    self.title = title
    self.subtitle = subtitle
    self.action = action
    self.accessory = accessory()
  }

  var body: some View {
    Group {
      if let action = action {
        Button(action: action) {
          content
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        content
          .padding(.horizontal, DesignTokens.Spacing.md)
          .padding(.vertical, DesignTokens.Spacing.md)
      }
    }
    .accessibilityElement(children: .combine)
    .overlay(alignment: .bottom) {
      Divider()
        .overlay(DesignTokens.Colors.border)
        .opacity(0.8)
        .padding(.leading, icon == nil ? 0 : 44)
    }
  }

  private var content: some View {
    HStack(spacing: DesignTokens.Spacing.md) {
      if let icon = icon {
        ZStack {
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .fill(DesignTokens.Colors.primary.opacity(0.10))
          Image(systemName: icon)
            .foregroundStyle(DesignTokens.Colors.primary)
            .font(.body)
        }
        .frame(width: 32, height: 32)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(DesignTokens.Typography.body)
          .foregroundStyle(DesignTokens.Colors.primaryText)

        if let subtitle = subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .lineLimit(2)
        }
      }

      Spacer()
      accessory
        .alignmentGuide(.firstTextBaseline) { d in d[.firstTextBaseline] }
    }
  }
}

struct SettingsToggle: View {
  let icon: String?
  let title: String
  @Binding var isOn: Bool
  var subtitle: String?

  var body: some View {
    SettingsRow(
      icon: icon, title: title, subtitle: subtitle,
      accessory: {
        Toggle("", isOn: $isOn)
          .labelsHidden()
          .tint(DesignTokens.Colors.primary)
      })
  }
}

struct SettingsNavigationRow<Destination: View>: View {
  let icon: String?
  let title: String
  let subtitle: String?
  @ViewBuilder var destination: Destination

  init(
    icon: String? = nil, title: String, subtitle: String? = nil,
    @ViewBuilder destination: () -> Destination
  ) {
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
      SettingsRow(
        icon: icon, title: title, subtitle: subtitle,
        accessory: {
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.subtleText)
        })
    }
    .buttonStyle(.plain)
  }
}

// MARK: - ModernTabBar enhancements for custom tabs
extension ModernTabBar {
  init(selectedTab: Binding<Tab>, items: [(tab: Tab, label: String, systemImage: String)]) {
    self._selectedTab = selectedTab
    self.tabs = items
  }
}

struct RemoteDataStatusLabel: View {
  let lastUpdated: Date?
  let usingSavedData: Bool

  var body: some View {
    if let lastUpdated {
      Label(
        statusText(lastUpdated),
        systemImage: usingSavedData ? "clock.badge.exclamationmark" : "checkmark.circle"
      )
      .font(.system(size: 9.5, weight: .medium))
      .foregroundStyle(
        usingSavedData ? DesignTokens.Colors.warning : DesignTokens.Colors.subtleText
      )
      .help(
        usingSavedData
          ? "RooMate will try again when you’re connected." : "The latest school data is loaded.")
    }
  }

  private func statusText(_ date: Date) -> String {
    if usingSavedData {
      return "Using saved data · Updated \(date.formatted(date: .omitted, time: .shortened))"
    }

    let elapsed = max(0, Date().timeIntervalSince(date))
    if elapsed < 60 { return "Updated just now" }
    if elapsed < 60 * 60 { return "Updated \(Int(elapsed / 60)) min ago" }
    return "Last updated \(date.formatted(date: .omitted, time: .shortened))"
  }
}
