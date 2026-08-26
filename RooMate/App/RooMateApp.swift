//
//  RooMateApp.swift
//  RooMate
//
//  Created by Makai O'Neill on 10/10/25.
//

#if os(macOS)
  import SwiftUI

  extension Notification.Name {
    static let rooMateOpenSettings = Notification.Name(
      "RooMateOpenSettings"
    )
    static let rooMateShowWhatsNew = Notification.Name("RooMateShowWhatsNew")
  }

  #if canImport(TelemetryDeck)
    import TelemetryDeck
  #endif
  #if canImport(Sparkle)
    import Sparkle
  #endif

  enum RooMateWindowID {
    static let main = "main"
  }

  @main
  struct RooMateApp: App {
    @NSApplicationDelegateAdaptor(RooMateMenuBarAppDelegate.self) private var menuBarDelegate
    @AppStorage("RooMateFloatingTimerEnabled") private var floatingTimerEnabled = false
    @AppStorage("RooMateMenuBarEnabled") private var menuBarEnabled = true

    #if canImport(Sparkle)
      private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
      )
    #endif

    init() {
      #if canImport(TelemetryDeck)
        let config = TelemetryDeck.Config(appID: "76FEC112-109A-46BC-8119-522949036DD5")
        config.defaultSignalPrefix = "RooMate."
        TelemetryDeck.initialize(config: config)
        TelemetryTracker.trackAppLaunched()
      #else
        // TelemetryDeck not available for this target; skip telemetry initialization.
      #endif
    }

    private func postQuickAction(_ action: String) {
      NotificationCenter.default.post(
        name: Notification.Name("RooMateQuickAction"),
        object: nil,
        userInfo: ["action": action]
      )
    }

    private func refreshOfficialSchedules() {
      NotificationCenter.default.post(
        name: .rooMateRefreshOfficialSchedules,
        object: nil
      )
    }

    var body: some Scene {
      WindowGroup(id: RooMateWindowID.main) {
        #if canImport(Sparkle)
          ContentView(checkForUpdatesAction: { updaterController.checkForUpdates(nil) })
        #else
          ContentView(checkForUpdatesAction: nil)
        #endif
      }
      .windowStyle(.hiddenTitleBar)
      .commands {
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") {
            NotificationCenter.default.post(
              name: .rooMateOpenSettings,
              object: nil
            )
          }
          .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .appInfo) {
          Button("What’s New in RooMate") {
            NotificationCenter.default.post(name: .rooMateShowWhatsNew, object: nil)
          }
        }

        CommandMenu("Navigate") {
          Button("Today") { postQuickAction("today") }
            .keyboardShortcut("1", modifiers: .command)
          Button("Schedule") { postQuickAction("schedule") }
            .keyboardShortcut("2", modifiers: .command)
          Button("Dining") { postQuickAction("dining") }
            .keyboardShortcut("3", modifiers: .command)
          Button("Sports") { postQuickAction("sports") }
            .keyboardShortcut("4", modifiers: .command)
          Button("Clubs") { postQuickAction("clubs") }
            .keyboardShortcut("5", modifiers: .command)
          Button("Events") { postQuickAction("events") }
            .keyboardShortcut("6", modifiers: .command)
          Button("PacTrack") { postQuickAction("pactrack") }
            .keyboardShortcut("7", modifiers: .command)

          Divider()

          Button("Search RooMate") { postQuickAction("search") }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("Tools") {
          Button("Focus Mode") { postQuickAction("focus") }
            .keyboardShortcut("f", modifiers: [.command, .shift])

          Button("Refresh School Schedules") {
            refreshOfficialSchedules()
          }

          Divider()

          Button(
            floatingTimerEnabled
              ? "Hide Floating Timer"
              : "Show Floating Timer"
          ) {
            floatingTimerEnabled.toggle()
          }

          Button(
            menuBarEnabled
              ? "Hide Menu Bar Companion"
              : "Show Menu Bar Companion"
          ) {
            menuBarEnabled.toggle()
          }
        }

        #if canImport(Sparkle)
          CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
              updaterController.checkForUpdates(nil)
            }
          }
        #endif
      }

    }
  }
#endif
