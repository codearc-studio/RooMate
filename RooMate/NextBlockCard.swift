import SwiftUI

struct NextBlockCard: View {
    let title: String
    let startText: String
    let color: Color
    let style: CardColorStyle
    let level: Level?
    let specialLabel: String?

    private var softGradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.22), color.opacity(0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var softStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.7), color.opacity(0.2)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Label("Up Next", systemImage: "forward.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DesignTokens.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    if let level = level, title != "Free" {
                        Text(level.displayName)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    } else if let specialLabel = specialLabel, !specialLabel.isEmpty, title != "Free" {
                        Text(specialLabel)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Label(startText, systemImage: "clock.fill")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(backgroundForStyle)
        .overlay(strokeForStyle)
        .overlay(glowForStyle)
        .cornerRadius(DesignTokens.Radius.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Up next: \(title), \(startText)")
    }

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(compatibleBackgroundSecondary())
                .designShadow(DesignTokens.Shadows.small)
        case .subtle:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .fill(compatibleBackgroundSecondary())
                .designShadow(DesignTokens.Shadows.small)
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(color.opacity(0.12))
                    .blur(radius: 10)
                    .scaleEffect(1.01)
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(softGradient)
                    .designShadow(DesignTokens.Shadows.medium)
            }
        }
    }

    @ViewBuilder
    private var strokeForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(softStrokeGradient, lineWidth: 1.2)
        case .colors:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                .stroke(softStrokeGradient, lineWidth: 1.4)
        }
    }

    @ViewBuilder
    private var glowForStyle: some View {
        switch style {
        case .none:
            EmptyView()
        case .subtle:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(color.opacity(0.10), lineWidth: 4)
                .blur(radius: 7)
        case .colors:
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .stroke(color.opacity(0.06), lineWidth: 2)
                .blur(radius: 4)
        }
    }
}

