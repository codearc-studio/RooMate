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

struct UpdateAnnouncementSection: View {
    let announcement: UpdateAnnouncement

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("RooMate \(announcement.updateNumber) Is Available!")
                    .font(.title3.bold())
                Spacer()
            }

            if !announcement.changelog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(announcement.changelog)
                    .font(.body)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No details provided.")
                    .font(.body)
                    .modifier(SecondaryForeground())
            }

            HStack(spacing: 10) {
                if let url = announcement.url {
                    Button {
                        #if canImport(AppKit)
                        NSWorkspace.shared.open(url)
                        #elseif canImport(UIKit)
                        UIApplication.shared.open(url)
                        #endif
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else {
                    Text("No download link provided.")
                        .font(.footnote)
                        .modifier(SecondaryForeground())
                }
                Spacer()
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.orange.opacity(0.14), Color.orange.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1.2)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RooMate \(announcement.updateNumber) is available. \(announcement.changelog)")
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

struct CompatibleGradient: ShapeStyle {
    let color: Color
    init(_ color: Color) { self.color = color }

    func _apply(to shape: inout _ShapeStyle_Shape) {
        if #available(iOS 15.0, macOS 12.0, *) {
            color.gradient._apply(to: &shape)
        } else {
            LinearGradient(
                gradient: Gradient(colors: [color.opacity(0.9), color]),
                startPoint: .top,
                endPoint: .bottom
            )._apply(to: &shape)
        }
    }
}

struct CompatibleBackgroundSecondary: ShapeStyle {
    func _apply(to shape: inout _ShapeStyle_Shape) {
        if #available(macOS 14.0, iOS 17.0, *) {
            Color.secondary.opacity(0.15)._apply(to: &shape)
        } else {
            #if canImport(AppKit)
            Color(nsColor: NSColor.windowBackgroundColor).opacity(0.6)._apply(to: &shape)
            #else
            Color(white: 0.95)._apply(to: &shape)
            #endif
        }
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
