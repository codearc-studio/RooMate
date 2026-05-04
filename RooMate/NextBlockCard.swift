import SwiftUI

struct NextBlockCard: View {
    let title: String
    let startText: String
    let color: Color
    let style: CardColorStyle

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
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [color.opacity(0.7), color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Label("Up Next", systemImage: "forward.fill")
                        .font(.caption)
                        .modifier(SecondaryForeground())
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Label(startText, systemImage: "clock")
                        .font(.subheadline)
                        .modifier(SecondaryForeground())
                        .labelStyle(.titleAndIcon)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(12)
        .background(backgroundForStyle)
        .overlay(strokeForStyle)
        .overlay(glowForStyle)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Up next: \(title), \(startText)")
    }

    @ViewBuilder
    private var backgroundForStyle: some View {
        switch style {
        case .none:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CompatibleBackgroundSecondary())
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        case .subtle:
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CompatibleBackgroundSecondary())
                .shadow(color: color.opacity(0.12), radius: 10, x: 0, y: 0)
        case .colors:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.12))
                    .blur(radius: 10)
                    .scaleEffect(1.01)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(softGradient)
                    .shadow(color: color.opacity(0.18), radius: 8, x: 0, y: 0)
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
                .stroke(color.opacity(0.10), lineWidth: 4)
                .blur(radius: 7)
        case .colors:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.06), lineWidth: 2)
                .blur(radius: 4)
        }
    }
}
