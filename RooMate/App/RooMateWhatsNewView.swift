import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

struct RooMateWhatsNewView: View {
  let onDismiss: () -> Void

  private let highlights: [(String, String, String, Color)] = [
    ("sparkles", "A redesigned Today", "See what’s happening now, what comes next, announcements, and the day at a glance.", DesignTokens.Colors.primary),
    ("calendar", "Day, Week, and Plan", "Move between the live schedule, a complete week, and the Semester Planner without losing context.", DesignTokens.Colors.schedule),
    ("fork.knife", "Dining, Sports, Clubs, and Events", "School life beyond the bell schedule now has a home in RooMate.", DesignTokens.Colors.dining),
    ("chart.bar.xaxis", "PacTrack", "Keep an on-device view of RooPAC progress and future choices.", DesignTokens.Colors.pacTrack),
    ("magnifyingglass", "Search with Command-K", "Jump straight to pages, classes, teams, games, events, dining, and settings.", DesignTokens.Colors.info),
    ("menubar.rectangle", "There when you need it", "Use the menu bar companion, floating timer, improved reminders, and new customization.", DesignTokens.Colors.events),
  ]

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        Image("RooMark")
          .resizable()
          .scaledToFit()
          .frame(width: 66, height: 66)
        Text("What’s New in RooMate 6")
          .font(.system(size: 25, weight: .semibold))
        Text("A more complete, dependable companion for the school day.")
          .font(.system(size: 12))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
      }
      .padding(.top, 26)
      .padding(.bottom, 20)

      ScrollView {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
          ForEach(Array(highlights.enumerated()), id: \.offset) { _, highlight in
            HStack(alignment: .top, spacing: 11) {
              Image(systemName: highlight.0)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(highlight.3)
                .frame(width: 34, height: 34)
                .background(highlight.3.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

              VStack(alignment: .leading, spacing: 4) {
                Text(highlight.1)
                  .font(.system(size: 12.5, weight: .semibold))
                Text(highlight.2)
                  .font(.system(size: 10.5))
                  .foregroundStyle(DesignTokens.Colors.secondaryText)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .rooSurface(cornerRadius: 13, elevated: false, border: true)
          }
        }
        .padding(.horizontal, 22)
      }

      Button("Continue", action: onDismiss)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .padding(22)
    }
    .frame(width: 660, height: 590)
    .background(BackgroundView())
  }
}

struct RooMateDiagnosticsView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var copied = false

  private var diagnostics: String { RooMateSupportDiagnostics.summary() }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Diagnostics Summary")
            .font(.system(size: 20, weight: .semibold))
          Text("Review exactly what RooMate will copy before sharing it.")
            .font(.system(size: 11))
            .foregroundStyle(DesignTokens.Colors.secondaryText)
        }
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }

      ScrollView {
        Text(diagnostics)
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
      }
      .background(DesignTokens.Colors.surface, in: RoundedRectangle(cornerRadius: 12))
      .overlay { RoundedRectangle(cornerRadius: 12).stroke(DesignTokens.Colors.border) }

      HStack {
        Label("No student-entered content is included.", systemImage: "lock.shield")
          .font(.system(size: 10.5))
          .foregroundStyle(DesignTokens.Colors.secondaryText)
        Spacer()
        Button {
          #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diagnostics, forType: .string)
          #endif
          copied = true
        } label: {
          Label(copied ? "Copied" : "Copy Diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(22)
    .frame(width: 620, height: 480)
    .background(BackgroundView())
  }
}
