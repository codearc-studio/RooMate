import SwiftUI

#if canImport(AppKit)
  import AppKit
#endif

struct RooMateWhatsNewView: View {
  let onDismiss: () -> Void

  private let highlights: [(String, String, String, Color)] = [
    (
      "flag.fill", "Markers keep the day active",
      "A future event such as School Day Ends now counts as what’s next instead of ending the day early.",
      DesignTokens.Colors.primary
    ),
    (
      "cup.and.saucer.fill", "Clear gaps between events",
      "When nothing is happening right now, RooMate shows free time and the next published event.",
      DesignTokens.Colors.events
    ),
    (
      "calendar.day.timeline.left", "Special schedules stay contextual",
      "Today and Schedule now understand marker-only orientation and retreat-day timelines.",
      DesignTokens.Colors.schedule
    ),
    (
      "menubar.rectangle", "The same answer everywhere",
      "The menu bar and floating timer now keep future markers visible and use event-aware wording.",
      DesignTokens.Colors.pacTrack
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        Image("RooMark")
          .resizable()
          .scaledToFit()
          .frame(width: 66, height: 66)
        Text("What’s New in RooMate 6.0.5")
          .font(.system(size: 25, weight: .semibold))
        Text("Special schedules now stay active until the day is actually over.")
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
          Text("Bug Report Info")
            .font(.system(size: 20, weight: .semibold))
          Text("Check exactly what RooMate will copy before you share it.")
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
        Label(
          "Your classes, notes, searches, and other personal school information are not included.",
          systemImage: "lock.shield"
        )
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
          Label(
            copied ? "Copied" : "Copy Bug Report Info",
            systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(22)
    .frame(width: 620, height: 480)
    .background(BackgroundView())
  }
}
