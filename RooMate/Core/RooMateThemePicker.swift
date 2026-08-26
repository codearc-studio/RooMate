import SwiftUI

enum RooMateThemePickerStyle {
  case settings
  case onboarding

  var cardMinimumWidth: CGFloat {
    switch self {
    case .settings: 170
    case .onboarding: 150
    }
  }

  var previewHeight: CGFloat {
    switch self {
    case .settings: 66
    case .onboarding: 50
    }
  }
}

/// A shared, visual theme gallery used by both onboarding and Settings.
struct RooMateThemePicker: View {
  @Environment(\.colorScheme) private var colorScheme

  @Binding var selection: RooMateTheme
  let style: RooMateThemePickerStyle

  var body: some View {
    VStack(alignment: .leading, spacing: style == .settings ? 16 : 12) {
      if style == .settings {
        selectedThemeSummary
      } else {
        compactSelectionSummary
      }

      VStack(alignment: .leading, spacing: 9) {
        HStack {
          Text("CHOOSE A THEME")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.75)
            .foregroundStyle(DesignTokens.Colors.subtleText)

          Spacer()

          Text("3 light · 3 dark · 1 automatic")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: style.cardMinimumWidth), spacing: 10)],
          spacing: 10
        ) {
          ForEach(RooMateTheme.allCases) { theme in
            themeCard(theme)
          }
        }
      }

      if style == .settings {
        Label(
          "System follows your Mac. Every other theme keeps its chosen light or dark appearance.",
          systemImage: "info.circle"
        )
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
    }
  }

  private var selectedThemeSummary: some View {
    let palette = resolvedPalette(for: selection)

    return HStack(spacing: 18) {
      themePreview(selection)
        .frame(width: 228, height: 104)
        .overlay {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(Color(hex: palette.primaryText).opacity(0.14), lineWidth: 1)
        }

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 7) {
          Image(systemName: selection.systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.primary)

          Text("CURRENT THEME")
            .font(.system(size: 9, weight: .bold))
            .tracking(0.75)
            .foregroundStyle(DesignTokens.Colors.subtleText)
        }

        Text(selection.title)
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)

        Text(selection.longDescription)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
          .fixedSize(horizontal: false, vertical: true)

        appearanceBadge(for: selection)
      }

      Spacer(minLength: 0)
    }
    .padding(14)
    .background(
      LinearGradient(
        colors: [
          DesignTokens.Colors.primary.opacity(colorScheme == .light ? 0.075 : 0.12),
          DesignTokens.Colors.hover.opacity(0.18),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(DesignTokens.Colors.primary.opacity(0.22), lineWidth: 1)
    }
  }

  private var compactSelectionSummary: some View {
    HStack(spacing: 9) {
      ZStack {
        Circle()
          .fill(DesignTokens.Colors.settings.opacity(0.13))
        Image(systemName: selection.systemImage)
          .font(.system(size: 10.5, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.settings)
      }
      .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 1) {
        Text("Selected: \(selection.title)")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(DesignTokens.Colors.primaryText)
        Text(selection.subtitle)
          .font(.system(size: 9.5, weight: .medium))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }

      Spacer()

      appearanceBadge(for: selection)
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 42)
    .background(
      DesignTokens.Colors.settings.opacity(colorScheme == .light ? 0.055 : 0.09),
      in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .strokeBorder(DesignTokens.Colors.settings.opacity(0.22), lineWidth: 1)
    }
  }

  private func themeCard(_ theme: RooMateTheme) -> some View {
    let selected = selection == theme

    return Button {
      withAnimation(DesignTokens.Animation.snappy) {
        selection = theme
      }
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        themePreview(theme)
          .frame(height: style.previewHeight)

        HStack(spacing: 7) {
          Image(systemName: theme.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(
              selected ? DesignTokens.Colors.primary : DesignTokens.Colors.secondaryText
            )

          VStack(alignment: .leading, spacing: 1) {
            Text(theme.title)
              .font(.system(size: 11.5, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primaryText)

            Text(theme.subtitle)
              .font(.system(size: 9.2, weight: .medium))
              .foregroundStyle(DesignTokens.Colors.secondaryText)
              .lineLimit(1)
          }

          Spacer(minLength: 3)

          if selected {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(DesignTokens.Colors.primary)
              .transition(.scale.combined(with: .opacity))
          }
        }
      }
      .padding(9)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        selected
          ? DesignTokens.Colors.primary.opacity(colorScheme == .light ? 0.075 : 0.11)
          : DesignTokens.Colors.hover.opacity(0.20),
        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(
            selected
              ? DesignTokens.Colors.primary.opacity(0.42)
              : DesignTokens.Colors.border,
            lineWidth: selected ? 1.35 : 1
          )
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(theme.title). \(theme.subtitle)")
    .accessibilityValue(selected ? "Selected" : theme.appearanceLabel)
    .accessibilityHint("Choose \(theme.title) as RooMate's theme")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func appearanceBadge(for theme: RooMateTheme) -> some View {
    Text(theme.appearanceLabel.uppercased())
      .font(.system(size: 8.5, weight: .bold))
      .tracking(0.55)
      .foregroundStyle(DesignTokens.Colors.secondaryText)
      .padding(.horizontal, 7)
      .frame(height: 20)
      .background(DesignTokens.Colors.hover.opacity(0.42), in: Capsule())
      .overlay {
        Capsule()
          .strokeBorder(DesignTokens.Colors.border, lineWidth: 1)
      }
  }

  @ViewBuilder
  private func themePreview(_ theme: RooMateTheme) -> some View {
    if theme == .system {
      HStack(spacing: 0) {
        themePreviewPane(.system, systemDark: false)
        themePreviewPane(.system, systemDark: true)
      }
      .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    } else {
      themePreviewPane(theme, systemDark: false)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
  }

  private func themePreviewPane(_ theme: RooMateTheme, systemDark: Bool) -> some View {
    let palette = DesignTokens.Colors.palette(for: theme, systemDark: systemDark)
    let dark = theme == .system ? systemDark : theme.isDark

    return ZStack {
      Color(hex: palette.background)
      VStack(spacing: 6) {
        HStack(spacing: 4) {
          Circle()
            .fill(Color(hex: palette.primary).opacity(0.92))
            .frame(width: 5, height: 5)

          RoundedRectangle(cornerRadius: 2)
            .fill(Color(hex: palette.primaryText).opacity(dark ? 0.40 : 0.29))
            .frame(width: 31, height: 4)

          Spacer()

          Circle()
            .fill(Color(hex: palette.schedule).opacity(0.72))
            .frame(width: 4, height: 4)
        }

        HStack(spacing: 5) {
          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
              .fill(Color(hex: palette.sidebar))
            RoundedRectangle(cornerRadius: 2)
              .fill(Color(hex: palette.subtleText).opacity(dark ? 0.24 : 0.15))
              .frame(height: 5)
          }
          .frame(width: 18)

          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
              .fill(Color(hex: palette.schedule).opacity(dark ? 0.30 : 0.20))

            HStack(spacing: 4) {
              RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: palette.surface))
              RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: palette.surfaceElevated))
            }
          }
        }
      }
      .padding(7)
    }
  }

  private func resolvedPalette(for theme: RooMateTheme) -> DesignTokens.Colors.ThemePalette {
    DesignTokens.Colors.palette(for: theme, systemDark: colorScheme == .dark)
  }
}
