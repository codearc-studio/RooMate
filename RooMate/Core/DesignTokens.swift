import Foundation
import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif
#if canImport(UIKit)
  import UIKit
#endif

// MARK: - RooMate v6 Design System
//
// Dark mode uses a very dark canvas, but the product remains warm and colorful.
// Color is used as a friendly wayfinding tool rather than as a neon/tech effect.

struct DesignTokens {
  struct Brand {
    static let name = "RooMate"
    static let tagline = "Your school day, all together."
    static let about =
      "An independent student-built app that keeps the parts of your school day in one place."
  }

  struct Colors {
    enum ThemeColorRole {
      case primary, accent, accentHover, accentPressed
      case today, schedule, pacTrack, dining, athletics, events, links, settings
      case success, warning, destructive, info
      case background, sidebar, surface, surfaceElevated, hover
      case canvasTop, canvasBottom, sidebarTop
      case primaryText, secondaryText, subtleText
    }

    struct ThemePalette {
      let primary: UInt32
      let accent: UInt32
      let accentHover: UInt32
      let accentPressed: UInt32
      let today: UInt32
      let schedule: UInt32
      let pacTrack: UInt32
      let dining: UInt32
      let athletics: UInt32
      let events: UInt32
      let links: UInt32
      let settings: UInt32
      let success: UInt32
      let warning: UInt32
      let destructive: UInt32
      let info: UInt32
      let background: UInt32
      let sidebar: UInt32
      let surface: UInt32
      let surfaceElevated: UInt32
      let hover: UInt32
      let canvasTop: UInt32
      let canvasBottom: UInt32
      let sidebarTop: UInt32
      let primaryText: UInt32
      let secondaryText: UInt32
      let subtleText: UInt32

      subscript(role: ThemeColorRole) -> UInt32 {
        switch role {
        case .primary: primary
        case .accent: accent
        case .accentHover: accentHover
        case .accentPressed: accentPressed
        case .today: today
        case .schedule: schedule
        case .pacTrack: pacTrack
        case .dining: dining
        case .athletics: athletics
        case .events: events
        case .links: links
        case .settings: settings
        case .success: success
        case .warning: warning
        case .destructive: destructive
        case .info: info
        case .background: background
        case .sidebar: sidebar
        case .surface: surface
        case .surfaceElevated: surfaceElevated
        case .hover: hover
        case .canvasTop: canvasTop
        case .canvasBottom: canvasBottom
        case .sidebarTop: sidebarTop
        case .primaryText: primaryText
        case .secondaryText: secondaryText
        case .subtleText: subtleText
        }
      }
    }

    static func palette(for theme: RooMateTheme, systemDark: Bool = false) -> ThemePalette {
      switch theme == .system ? (systemDark ? RooMateTheme.rooDark : .rooLight) : theme {
      case .system, .rooLight:
        ThemePalette(
          primary: 0xA8582D, accent: 0xB34B3B, accentHover: 0xAE592F,
          accentPressed: 0x8F432F, today: 0x9F562B, schedule: 0x426E93,
          pacTrack: 0x6A519A, dining: 0xA15528, athletics: 0x347258,
          events: 0x376F91, links: 0x586577, settings: 0x5C616B,
          success: 0x347254, warning: 0x8E5C0E, destructive: 0xA94343,
          info: 0x3E6D95, background: 0xF4F1EC, sidebar: 0xECE8E2,
          surface: 0xFBFAF8, surfaceElevated: 0xFFFFFF, hover: 0xEAE5DE,
          canvasTop: 0xFAF8F4, canvasBottom: 0xF1EEE8, sidebarTop: 0xF2EEE8,
          primaryText: 0x202126, secondaryText: 0x55585E, subtleText: 0x666970
        )
      case .sunrise:
        ThemePalette(
          primary: 0xA64F2C, accent: 0xB4483B, accentHover: 0xC35F37,
          accentPressed: 0x873A24, today: 0xA9502D, schedule: 0x3D6F94,
          pacTrack: 0x6A519A, dining: 0xA75A27, athletics: 0x34765A,
          events: 0x376F91, links: 0x586577, settings: 0x5C616B,
          success: 0x347254, warning: 0x8D5B0D, destructive: 0xA74242,
          info: 0x3E6D95, background: 0xF8F0E7, sidebar: 0xF0E2D6,
          surface: 0xFFF9F2, surfaceElevated: 0xFFFFFF, hover: 0xEEDDD0,
          canvasTop: 0xFFFAF3, canvasBottom: 0xF4E9DE, sidebarTop: 0xF5E8DC,
          primaryText: 0x2A201B, secondaryText: 0x68574F, subtleText: 0x725E55
        )
      case .courtyard:
        ThemePalette(
          primary: 0x8F4F2F, accent: 0x3F7458, accentHover: 0x568A6D,
          accentPressed: 0x2F5D46, today: 0x95502B, schedule: 0x416B8C,
          pacTrack: 0x65508B, dining: 0x945627, athletics: 0x347058,
          events: 0x386A87, links: 0x52616A, settings: 0x566159,
          success: 0x326C53, warning: 0x80600E, destructive: 0x9A4444,
          info: 0x386989, background: 0xF1F5EF, sidebar: 0xE5EDE3,
          surface: 0xF9FCF7, surfaceElevated: 0xFFFFFF, hover: 0xDDE8DA,
          canvasTop: 0xF8FBF6, canvasBottom: 0xECF2E9, sidebarTop: 0xEAF1E7,
          primaryText: 0x1D2821, secondaryText: 0x4F5E55, subtleText: 0x5C6B62
        )
      case .rooDark:
        ThemePalette(
          primary: 0xF29A5A, accent: 0xEE795E, accentHover: 0xF5AA72,
          accentPressed: 0xD96F51, today: 0xF2A65A, schedule: 0x78A6D0,
          pacTrack: 0x9A78C8, dining: 0xECA45F, athletics: 0x67B68A,
          events: 0x6FAACB, links: 0x8794A8, settings: 0x9A9FA9,
          success: 0x67B68A, warning: 0xE8B45F, destructive: 0xD97777,
          info: 0x78A6D0, background: 0x090A0C, sidebar: 0x101216,
          surface: 0x15171A, surfaceElevated: 0x1B1D22, hover: 0x22252A,
          canvasTop: 0x0B0C0F, canvasBottom: 0x08090B, sidebarTop: 0x121419,
          primaryText: 0xF5F5F6, secondaryText: 0xA7ABB2, subtleText: 0x818791
        )
      case .midnight:
        ThemePalette(
          primary: 0xF0A16A, accent: 0xF27E68, accentHover: 0xF5AE7D,
          accentPressed: 0xD86D59, today: 0xF2A65A, schedule: 0x80B3E3,
          pacTrack: 0xA58BD5, dining: 0xEFB06D, athletics: 0x74C397,
          events: 0x79B8DE, links: 0x98A8C1, settings: 0xACB4C2,
          success: 0x76C49A, warning: 0xEAC06D, destructive: 0xE78585,
          info: 0x83B4E0, background: 0x070C14, sidebar: 0x0D1420,
          surface: 0x131C29, surfaceElevated: 0x192537, hover: 0x223148,
          canvasTop: 0x0A101B, canvasBottom: 0x060A11, sidebarTop: 0x101827,
          primaryText: 0xF4F7FB, secondaryText: 0xACB8C9, subtleText: 0x8390A3
        )
      case .oled:
        ThemePalette(
          primary: 0xF7A367, accent: 0xFF806B, accentHover: 0xFFB17F,
          accentPressed: 0xE3705C, today: 0xF5A45C, schedule: 0x82B5E2,
          pacTrack: 0xAA8CD8, dining: 0xF1AE68, athletics: 0x75C599,
          events: 0x7CB9DB, links: 0x9CA9BC, settings: 0xB0B4BC,
          success: 0x75C599, warning: 0xEDBE68, destructive: 0xE88989,
          info: 0x84B5E0, background: 0x000000, sidebar: 0x030303,
          surface: 0x080808, surfaceElevated: 0x101010, hover: 0x191919,
          canvasTop: 0x000000, canvasBottom: 0x000000, sidebarTop: 0x030303,
          primaryText: 0xF7F7F7, secondaryText: 0xB6B6B6, subtleText: 0x898989
        )
      }
    }

    // MARK: Brand / primary interaction
    static var primary: Color { themed(.primary) }
    static var accent: Color { themed(.accent) }
    static var accentHover: Color { themed(.accentHover) }
    static var accentPressed: Color { themed(.accentPressed) }

    // MARK: Feature identity
    static var today: Color { themed(.today) }
    static var schedule: Color { themed(.schedule) }
    static var pacTrack: Color { themed(.pacTrack) }
    static var dining: Color { themed(.dining) }
    static var athletics: Color { themed(.athletics) }
    static var events: Color { themed(.events) }
    static var links: Color { themed(.links) }
    static var settings: Color { themed(.settings) }

    // MARK: Semantic
    static var success: Color { themed(.success) }
    static var warning: Color { themed(.warning) }
    static var destructive: Color { themed(.destructive) }
    static var info: Color { themed(.info) }

    // MARK: Main surfaces
    static var background: Color { themed(.background) }
    static var sidebar: Color { themed(.sidebar) }
    static var surface: Color { themed(.surface) }
    static var surfaceElevated: Color { themed(.surfaceElevated) }
    static var hover: Color { themed(.hover) }
    static var lightCanvasTop: Color { themed(.canvasTop) }
    static var lightCanvasBottom: Color { themed(.canvasBottom) }
    static var lightSidebarTop: Color { themed(.sidebarTop) }

    static var selection: Color {
      themedWithAlpha(.primaryText, lightAlpha: 0.060, darkAlpha: 0.095)
    }
    static var selectionBorder: Color {
      themedWithAlpha(.primaryText, lightAlpha: 0.105, darkAlpha: 0.10)
    }
    static var sidebarHover: Color {
      themedWithAlpha(.primaryText, lightAlpha: 0.050, darkAlpha: 0.055)
    }
    static var sidebarHoverBorder: Color {
      themedWithAlpha(.primaryText, lightAlpha: 0.085, darkAlpha: 0.065)
    }

    static var primaryText: Color { themed(.primaryText) }
    static var secondaryText: Color { themed(.secondaryText) }
    static var subtleText: Color { themed(.subtleText) }
    static var border: Color {
      themedWithAlpha(.primaryText, lightAlpha: 0.095, darkAlpha: 0.075)
    }
    static var borderStrong: Color {
      themedWithAlpha(.primaryText, lightAlpha: 0.155, darkAlpha: 0.12)
    }

    // Brand/icon colors, used sparingly in onboarding/About/identity moments.
    static let iconCreamTop = Color(hex: 0xFFF5E2)
    static let iconCreamBottom = Color(hex: 0xFDE8C9)
    static let iconOrangeTop = Color(hex: 0xFFD47B)
    static let iconOrangeMiddle = Color(hex: 0xFDAB60)
    static let iconOrangeBottom = Color(hex: 0xFC7056)

    static let brandGradient = LinearGradient(
      stops: [
        .init(color: iconOrangeTop, location: 0.0),
        .init(color: iconOrangeMiddle, location: 0.52),
        .init(color: iconOrangeBottom, location: 1.0),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )

    private static let themeDefaultsKey = "UserThemePreference"

    private static func persistedTheme() -> RooMateTheme {
      let defaults = UserDefaults(suiteName: "dev.roomate.prefs") ?? .standard
      guard let data = defaults.data(forKey: themeDefaultsKey),
        let theme = try? JSONDecoder().decode(RooMateTheme.self, from: data)
      else {
        return .system
      }
      return theme
    }

    private static func themed(_ role: ThemeColorRole) -> Color {
      #if canImport(AppKit)
        let dynamic = NSColor(
          name: nil,
          dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let theme = persistedTheme()
            return nsColor(
              palette(for: theme, systemDark: match == .darkAqua)[role],
              alpha: 1
            )
          })
        return Color(nsColor: dynamic)
      #elseif canImport(UIKit)
        return Color(
          uiColor: UIColor { traits in
            let theme = persistedTheme()
            return uiColor(
              palette(for: theme, systemDark: traits.userInterfaceStyle == .dark)[role],
              alpha: 1
            )
          })
      #else
        return Color(hex: palette(for: persistedTheme())[role])
      #endif
    }

    private static func themedWithAlpha(
      _ role: ThemeColorRole,
      lightAlpha: CGFloat,
      darkAlpha: CGFloat
    ) -> Color {
      #if canImport(AppKit)
        let dynamic = NSColor(
          name: nil,
          dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let systemDark = match == .darkAqua
            let theme = persistedTheme()
            let isDark = theme == .system ? systemDark : theme.isDark
            return nsColor(
              palette(for: theme, systemDark: systemDark)[role],
              alpha: isDark ? darkAlpha : lightAlpha
            )
          })
        return Color(nsColor: dynamic)
      #elseif canImport(UIKit)
        return Color(
          uiColor: UIColor { traits in
            let systemDark = traits.userInterfaceStyle == .dark
            let theme = persistedTheme()
            let isDark = theme == .system ? systemDark : theme.isDark
            return uiColor(
              palette(for: theme, systemDark: systemDark)[role],
              alpha: isDark ? darkAlpha : lightAlpha
            )
          })
      #else
        let theme = persistedTheme()
        return Color(hex: palette(for: theme)[role]).opacity(theme.isDark ? darkAlpha : lightAlpha)
      #endif
    }

    #if canImport(AppKit)
      private static func nsColor(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
          srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
          green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255,
          alpha: alpha
        )
      }
    #endif

    #if canImport(UIKit)
      private static func uiColor(_ hex: UInt32, alpha: CGFloat) -> UIColor {
        UIColor(
          red: CGFloat((hex >> 16) & 0xFF) / 255,
          green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255,
          alpha: alpha
        )
      }
    #endif
  }

  struct Typography {
    static let headline2 = Font.system(size: 28, weight: .semibold)
    static let headline3 = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let subheadline = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 13, weight: .regular)

    static let appTitle = Font.system(size: 24, weight: .semibold)
    static let pageTitle = Font.system(size: 26, weight: .semibold)
    static let heroTitle = Font.system(size: 30, weight: .semibold)
    static let heroCountdown = Font.system(size: 36, weight: .semibold, design: .rounded)
    static let sectionTitle = Font.system(size: 14, weight: .semibold)
    static let metadata = Font.system(size: 12, weight: .medium)

    static func brandTitle(size: CGFloat = 28) -> Font {
      .system(size: size, weight: .semibold)
    }
  }

  struct Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 36
  }

  struct Radius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 10
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
  }

  struct Shadows {
    static let subtle = Shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 1)
    static let small = Shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
    static let medium = Shadow(color: Color.black.opacity(0.17), radius: 12, x: 0, y: 5)
    static let large = Shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 8)
  }

  struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
  }

  struct Animation {
    /// Tiny hover/selection feedback. Keep this nearly instantaneous.
    static let quick = SwiftUI.Animation.easeOut(duration: 0.14)

    /// Small control changes such as filters, pills, and sidebar states.
    static let snappy = SwiftUI.Animation.snappy(duration: 0.22)

    /// General content replacement without a bouncy feel.
    static let content = SwiftUI.Animation.smooth(duration: 0.27)

    /// Larger in-place navigation such as Sports → Teams → Team.
    static let navigation = SwiftUI.Animation.spring(
      response: 0.34,
      dampingFraction: 0.90,
      blendDuration: 0.08
    )

    static let smooth = SwiftUI.Animation.smooth(duration: 0.32)
  }
}

extension Color {
  init(hex: UInt32, alpha: Double = 1.0) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255.0,
      green: Double((hex >> 8) & 0xFF) / 255.0,
      blue: Double(hex & 0xFF) / 255.0,
      opacity: alpha
    )
  }

  /// Returns whichever of black or white has the stronger WCAG contrast
  /// against this color. Use it for glyphs or text placed on arbitrary class,
  /// profile, or themed feature colors.
  var accessibleForegroundColor: Color {
    let red: Double
    let green: Double
    let blue: Double

    #if canImport(AppKit)
      guard let color = NSColor(self).usingColorSpace(.sRGB) else {
        return DesignTokens.Colors.primaryText
      }
      red = Double(color.redComponent)
      green = Double(color.greenComponent)
      blue = Double(color.blueComponent)
    #elseif canImport(UIKit)
      var resolvedRed: CGFloat = 0
      var resolvedGreen: CGFloat = 0
      var resolvedBlue: CGFloat = 0
      var alpha: CGFloat = 0
      guard
        UIColor(self).getRed(
          &resolvedRed,
          green: &resolvedGreen,
          blue: &resolvedBlue,
          alpha: &alpha
        )
      else {
        return DesignTokens.Colors.primaryText
      }
      red = Double(resolvedRed)
      green = Double(resolvedGreen)
      blue = Double(resolvedBlue)
    #else
      return .white
    #endif

    func linearized(_ component: Double) -> Double {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }

    let luminance =
      0.2126 * linearized(red)
      + 0.7152 * linearized(green)
      + 0.0722 * linearized(blue)
    let whiteContrast = 1.05 / (luminance + 0.05)
    let blackContrast = (luminance + 0.05) / 0.05
    return blackContrast >= whiteContrast ? .black : .white
  }
}

private struct AdaptiveDesignShadowModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let shadow: DesignTokens.Shadow

  func body(content: Content) -> some View {
    content.shadow(
      color: colorScheme == .dark
        ? shadow.color
        : Color.black.opacity(0.055),
      radius: colorScheme == .dark ? shadow.radius : max(3, shadow.radius * 0.82),
      x: shadow.x,
      y: colorScheme == .dark ? shadow.y : max(1, shadow.y * 0.72)
    )
  }
}

private struct RooSurfaceModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat
  let elevated: Bool
  let border: Bool

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(elevated ? DesignTokens.Colors.surfaceElevated : DesignTokens.Colors.surface)
      }
      .overlay {
        if border {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
        }
      }
      .shadow(
        color: colorScheme == .dark
          ? Color.black.opacity(elevated ? 0.18 : 0.10)
          : Color.black.opacity(elevated ? 0.085 : 0.045),
        radius: elevated ? 12 : 6,
        x: 0,
        y: elevated ? 5 : 2
      )
  }
}

private struct RooGlassModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    #if os(macOS)
      if #available(macOS 26.0, *) {
        content
          .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
      } else {
        fallback(content)
      }
    #else
      fallback(content)
    #endif
  }

  private func fallback(_ content: Content) -> some View {
    content
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)

          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
              colorScheme == .dark
                ? Color.black.opacity(0.30)
                : Color.white.opacity(0.58)
            )
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(DesignTokens.Colors.borderStrong, lineWidth: 1)
      }
      .shadow(
        color: Color.black.opacity(colorScheme == .dark ? 0.13 : 0.045),
        radius: 10,
        x: 0,
        y: 4
      )
  }
}

private struct RooGlassPanelModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  @ViewBuilder
  func body(content: Content) -> some View {
    #if os(macOS)
      if #available(macOS 26.0, *) {
        content
          .glassEffect(.regular, in: .rect(cornerRadius: 0))
      } else {
        fallback(content)
      }
    #else
      fallback(content)
    #endif
  }

  private func fallback(_ content: Content) -> some View {
    content
      .background(.ultraThinMaterial)
      .overlay {
        colorScheme == .dark
          ? Color.black.opacity(0.18)
          : Color.white.opacity(0.22)
      }
  }
}

private struct RooInteractiveGlassModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let cornerRadius: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    #if os(macOS)
      if #available(macOS 26.0, *) {
        content
          .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
      } else {
        fallback(content)
      }
    #else
      fallback(content)
    #endif
  }

  private func fallback(_ content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(.ultraThinMaterial)
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .strokeBorder(DesignTokens.Colors.borderStrong, lineWidth: 1)
      }
  }
}

private struct RooFloatingShadowModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  func body(content: Content) -> some View {
    content.shadow(
      color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.085),
      radius: colorScheme == .dark ? 18 : 16,
      x: 0,
      y: colorScheme == .dark ? 8 : 6
    )
  }
}

/// Wraps nearby Liquid Glass views so the system can render them as a coordinated group.
struct RooGlassEffectGroup<Content: View>: View {
  let spacing: CGFloat
  private let content: Content

  init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  @ViewBuilder
  var body: some View {
    #if os(macOS)
      if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: spacing) {
          content
        }
      } else {
        content
      }
    #else
      content
    #endif
  }
}

extension View {
  func designShadow(_ shadow: DesignTokens.Shadow) -> some View {
    modifier(AdaptiveDesignShadowModifier(shadow: shadow))
  }

  func rooSurface(
    cornerRadius: CGFloat = DesignTokens.Radius.lg,
    elevated: Bool = false,
    border: Bool = true
  ) -> some View {
    modifier(RooSurfaceModifier(cornerRadius: cornerRadius, elevated: elevated, border: border))
  }

  func rooGlass(cornerRadius: CGFloat = DesignTokens.Radius.lg) -> some View {
    modifier(RooGlassModifier(cornerRadius: cornerRadius))
  }

  func rooGlassPanel() -> some View {
    modifier(RooGlassPanelModifier())
  }

  func rooInteractiveGlass(cornerRadius: CGFloat = DesignTokens.Radius.lg) -> some View {
    modifier(RooInteractiveGlassModifier(cornerRadius: cornerRadius))
  }

  func rooFloatingShadow() -> some View {
    modifier(RooFloatingShadowModifier())
  }
}
