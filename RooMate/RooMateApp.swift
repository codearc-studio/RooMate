//
//  RooMateApp.swift
//  RooMate
//
//  Created by Makai O'Neill on 10/10/25.
//

import SwiftUI
import TelemetryDeck
import Sparkle

@main
struct RooMateApp: App {
    private let sparkleUpdaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    
    init() {
        let config = TelemetryManagerConfiguration(appID: "AE90AD30-CD81-426F-80A3-22F3ECBCCFAB")
        config.defaultSignalPrefix = "RooMate."
        config.defaultParameters = {
            let info = Bundle.main.infoDictionary
            let appVersion = info?["CFBundleShortVersionString"] as? String ?? "—"
            let build = info?["CFBundleVersion"] as? String ?? "—"

            #if canImport(AppKit)
            let osName = "macOS"
            #elseif canImport(UIKit)
            #if os(iOS)
            let osName = "iOS"
            #elseif os(tvOS)
            let osName = "tvOS"
            #elseif os(watchOS)
            let osName = "watchOS"
            #else
            let osName = "AppleOS"
            #endif
            #else
            let osName = "AppleOS"
            #endif

            return [
                "app_version": appVersion,
                "build_number": build,
                "client_platform": osName
            ]
        }

        TelemetryDeck.initialize(config: config)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.sparkleCheckForUpdates, { [sparkleUpdaterController] in
                    sparkleUpdaterController.checkForUpdates(nil)
                })
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    sparkleUpdaterController.checkForUpdates(nil)
                }
            }
        }
    }
}
