import SwiftUI

struct ContentView: View {
  @State private var showingSettings = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 22) {
        Spacer()

        ZStack {
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.tint.opacity(0.12))
          Image(systemName: "macbook.and.iphone")
            .font(.system(size: 46, weight: .medium))
            .foregroundStyle(.tint)
        }
        .frame(width: 104, height: 104)

        VStack(spacing: 8) {
          Text("RooMate for iPhone")
            .font(.title2.weight(.semibold))

          Text(
            "The full RooMate 6 experience is currently on Mac. The iPhone companion is still in development."
          )
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 360)
        }

        Spacer()
      }
      .padding(24)
      .navigationTitle("RooMate")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") {
            showingSettings = true
          }
        }
      }
      .sheet(isPresented: $showingSettings) {
        NavigationStack {
          SettingsView_iOS()
        }
      }
    }
  }
}

#Preview {
  ContentView()
}
