import SwiftUI

struct SettingsView_iOS: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Form {
      Section("About this build") {
        LabeledContent("Status", value: "Companion in development")
        LabeledContent("Primary app", value: "macOS")
      }

      Section {
        Text(
          "The iPhone target is intentionally lightweight while RooMate 6 is finalized on Mac. It does not yet share the Mac app's full schedule, dining, sports, clubs, events, or PacTrack experience."
        )
        .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Settings")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { dismiss() }
      }
    }
  }
}
