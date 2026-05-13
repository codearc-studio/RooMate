import SwiftUI

struct AthleticsView: View {
    @ObservedObject var store: SportsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignTokens.Colors.accent.opacity(0.22),
                                    DesignTokens.Colors.primary.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "sportscourt.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Athletics")
                        .font(DesignTokens.Typography.headline2)
                    Text("It's a great day to be a Roo!")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if store.isLoading {
                    ProgressView().scaleEffect(0.8)
                }

                Button(action: { store.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh athletics feed")
            }
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignTokens.Colors.accent.opacity(0.12),
                                DesignTokens.Colors.primary.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
            )
            .designShadow(DesignTokens.Shadows.small)
            .padding(.bottom, DesignTokens.Spacing.lg)

            if let err = store.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("Failed to load athletics feed: \(err.localizedDescription)")
                    Spacer()
                }
                .padding(DesignTokens.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                        .fill(Color.yellow.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.20), lineWidth: 1)
                )
                .padding(.bottom, DesignTokens.Spacing.lg)
            }

            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.xl) {
                    if store.games.isEmpty {
                        VStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "trophy.fill")
                                .font(.title2)
                                .foregroundStyle(DesignTokens.Colors.accent)
                            Text(store.isLoading ? "Loading…" : "No games found")
                                .font(DesignTokens.Typography.body)
                            Text("Try refreshing for the latest sports updates.")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(DesignTokens.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                                .fill(compatibleBackgroundSecondary())
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 1)
                        )
                    }

                    ForEach(store.games) { game in
                        AthleticsGameRow(game: game, statusColor: statusColor(game.status), statusLabel: statusLabel(for: game.status), locationLabel: displayLocation(game.location), isLoadingPlaceholder: game.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.top, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.lg)
            }
        }
        .onAppear { if store.games.isEmpty { store.refresh() } }
    }

    private func statusColor(_ status: SportsGame.Status) -> Color {
        switch status {
        case .scheduled: return .accentColor
        case .cancelled: return .red
        case .rescheduled: return .orange
        case .conditional: return .yellow
        case .eliminated: return .gray
        }
    }

    private func displayLocation(_ loc: String) -> String? {
        let trimmed = loc.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let up = trimmed.uppercased()
        if up == "H" { return "Home" }
        if up == "A" { return "Away" }
        return trimmed
    }

    private func statusLabel(for status: SportsGame.Status) -> String {
        switch status {
        case .scheduled: return "Scheduled"
        case .cancelled: return "Cancelled"
        case .rescheduled: return "Rescheduled"
        case .conditional: return "Conditional"
        case .eliminated: return "Eliminated"
        }
    }
}

struct AthleticsGameRow: View {
    let game: SportsGame
    let statusColor: Color
    let statusLabel: String
    let locationLabel: String?
    let isLoadingPlaceholder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(statusColor.opacity(isLoadingPlaceholder ? 0.35 : 1.0))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(game.rawDateString)
                            .font(.subheadline).bold()
                        Text(game.day)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !game.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(game.time)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Text(game.team)
                            .font(.headline)
                            .strikethrough(isLoadingPlaceholder, color: .secondary)
                        Text("vs")
                            .foregroundStyle(.secondary)
                        Text(game.opponent)
                            .font(.headline)
                            .strikethrough(isLoadingPlaceholder, color: .secondary)
                    }

                    HStack(spacing: 8) {
                        if let locationLabel {
                            Text(locationLabel)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(statusColor.opacity(0.16))
                                .foregroundStyle(statusColor)
                                .clipShape(Capsule())
                        }

                        Text(statusLabel)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesignTokens.Colors.primary.opacity(0.10))
                            .foregroundStyle(DesignTokens.Colors.primary)
                            .clipShape(Capsule())
                    }
                }
            }

            if !game.notesFormatted.isEmpty {
                Text(game.notesFormatted)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .fill(compatibleBackgroundSecondary())
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous)
                .strokeBorder(statusColor.opacity(0.14), lineWidth: 1)
        )
        .designShadow(isLoadingPlaceholder ? DesignTokens.Shadows.subtle : DesignTokens.Shadows.small)
        .opacity(isLoadingPlaceholder ? 0.82 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AthleticsView(store: SportsStore())
}
