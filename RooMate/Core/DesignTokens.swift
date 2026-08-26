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
    // MARK: Brand / primary interaction
    //
    // Dark mode keeps RooMate's warm cream/orange glow. Light mode uses
    // deeper versions of the same hues so colored controls stay crisp on
    // pale surfaces instead of becoming pastel or low-contrast.
    static let primary = adaptive(light: 0xC96F3A, dark: 0xF29A5A)
    static let accent = adaptive(light: 0xC95F49, dark: 0xEE795E)
    static let accentHover = adaptive(light: 0xD98550, dark: 0xF5AA72)
    static let accentPressed = adaptive(light: 0xA94F3A, dark: 0xD96F51)

    // MARK: Feature identity
    // Feature colors intentionally shift darker in light mode. This lets
    // RooMate stay colorful without relying on muddy translucent fills.
    static let today = adaptive(light: 0xB86A2E, dark: 0xF2A65A)
    static let schedule = adaptive(light: 0x4B739C, dark: 0x78A6D0)
    static let pacTrack = adaptive(light: 0x7359A8, dark: 0x9A78C8)
    static let dining = adaptive(light: 0xB96B2B, dark: 0xECA45F)
    static let athletics = adaptive(light: 0x3E7E60, dark: 0x67B68A)
    static let events = adaptive(light: 0x3F789D, dark: 0x6FAACB)
    static let links = adaptive(light: 0x5F6C7F, dark: 0x8794A8)
    static let settings = adaptive(light: 0x666C77, dark: 0x9A9FA9)

    // MARK: Semantic
    static let success = adaptive(light: 0x39795A, dark: 0x67B68A)
    static let warning = adaptive(light: 0xA56D19, dark: 0xE8B45F)
    static let destructive = adaptive(light: 0xB45353, dark: 0xD97777)
    static let info = adaptive(light: 0x47739F, dark: 0x78A6D0)

    // MARK: Main surfaces
    // Light mode is intentionally warm rather than stark white. The
    // hierarchy is canvas -> sidebar -> card -> elevated card.
    static let background = adaptive(light: 0xF4F1EC, dark: 0x090A0C)
    static let sidebar = adaptive(light: 0xECE8E2, dark: 0x101216)
    static let surface = adaptive(light: 0xFBFAF8, dark: 0x15171A)
    static let surfaceElevated = adaptive(light: 0xFFFFFF, dark: 0x1B1D22)
    static let hover = adaptive(light: 0xEAE5DE, dark: 0x22252A)

    // Canvas-only light colors used by BackgroundView. They are deliberately
    // exposed here so every screen shares the same warm paper foundation.
    static let lightCanvasTop = Color(hex: 0xFAF8F4)
    static let lightCanvasBottom = Color(hex: 0xF1EEE8)
    static let lightSidebarTop = Color(hex: 0xF2EEE8)

    static let selection = adaptiveWithAlpha(
      light: 0x2C2A27, lightAlpha: 0.060,
      dark: 0xFFFFFF, darkAlpha: 0.095
    )
    static let selectionBorder = adaptiveWithAlpha(
      light: 0x2C2A27, lightAlpha: 0.105,
      dark: 0xFFFFFF, darkAlpha: 0.10
    )

    static let sidebarHover = adaptiveWithAlpha(
      light: 0x342F2A, lightAlpha: 0.050,
      dark: 0xFFFFFF, darkAlpha: 0.055
    )
    static let sidebarHoverBorder = adaptiveWithAlpha(
      light: 0x342F2A, lightAlpha: 0.085,
      dark: 0xFFFFFF, darkAlpha: 0.065
    )

    static let primaryText = adaptive(light: 0x202126, dark: 0xF5F5F6)
    static let secondaryText = adaptive(light: 0x64676D, dark: 0xA7ABB2)
    static let subtleText = adaptive(light: 0x8A8D94, dark: 0x747A84)

    static let border = adaptiveWithAlpha(
      light: 0x302D29, lightAlpha: 0.095,
      dark: 0xFFFFFF, darkAlpha: 0.075
    )
    static let borderStrong = adaptiveWithAlpha(
      light: 0x302D29, lightAlpha: 0.155,
      dark: 0xFFFFFF, darkAlpha: 0.12
    )

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

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
      #if canImport(AppKit)
        let dynamic = NSColor(
          name: nil,
          dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return nsColor(match == .darkAqua ? dark : light, alpha: 1)
          })
        return Color(nsColor: dynamic)
      #elseif canImport(UIKit)
        return Color(
          uiColor: UIColor { traits in
            uiColor(traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
          })
      #else
        return Color(hex: light)
      #endif
    }

    private static func adaptiveWithAlpha(
      light: UInt32,
      lightAlpha: CGFloat,
      dark: UInt32,
      darkAlpha: CGFloat
    ) -> Color {
      #if canImport(AppKit)
        let dynamic = NSColor(
          name: nil,
          dynamicProvider: { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            if match == .darkAqua {
              return nsColor(dark, alpha: darkAlpha)
            }
            return nsColor(light, alpha: lightAlpha)
          })
        return Color(nsColor: dynamic)
      #elseif canImport(UIKit)
        return Color(
          uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark {
              return uiColor(dark, alpha: darkAlpha)
            }
            return uiColor(light, alpha: lightAlpha)
          })
      #else
        return Color(hex: light).opacity(lightAlpha)
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
