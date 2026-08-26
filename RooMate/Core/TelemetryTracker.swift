//
//  TelemetryTracker.swift
//  RooMate
//
//  Privacy-conscious product analytics. RooMate deliberately avoids sending
//  names, class details, club names/notes, team names, dining search text,
//  PacTrack selections, or other student-entered content.
//

import Foundation

#if canImport(TelemetryDeck)
  import TelemetryDeck

  enum TelemetryTracker {
    private static func signal(_ name: String, parameters: [String: String] = [:]) {
      TelemetryDeck.signal(name, parameters: parameters)
    }

    static func trackAppLaunched() {
      signal("App.Launched")
    }

    static func trackTabSelected(_ tabName: String) {
      signal("Navigation.TabSelected", parameters: ["tabName": tabName])
    }

    static func trackScheduleModeSelected(_ mode: String) {
      signal("Schedule.ModeSelected", parameters: ["mode": mode])
    }

    static func trackSemesterPlannerCopiedCurrentSchedule() {
      signal("SemesterPlanner.CopiedCurrentSchedule")
    }

    static func trackSemesterPlannerCleared() {
      signal("SemesterPlanner.Cleared")
    }

    static func trackOnboardingStarted() {
      signal("Onboarding.Started")
    }

    static func trackOnboardingStepCompleted(_ step: String, skipped: Bool) {
      signal(
        skipped ? "Onboarding.StepSkipped" : "Onboarding.StepCompleted",
        parameters: ["step": step]
      )
    }

    static func trackOnboardingCompleted() {
      signal("Onboarding.Completed")
    }

    static func trackDiningFavoriteChanged(isFavorite: Bool, favoriteCount: Int) {
      signal(
        "Dining.FavoriteChanged",
        parameters: [
          "action": isFavorite ? "added" : "removed",
          "favoriteCount": String(max(0, favoriteCount)),
        ]
      )
    }

    static func trackSportsGameViewed() {
      signal("Sports.GameViewed")
    }

    static func trackMenuBarOpened() {
      signal("MenuBar.Opened")
    }

    static func trackFloatingTimerShown(compact: Bool) {
      signal(
        "FloatingTimer.Shown",
        parameters: ["mode": compact ? "compact" : "detailed"]
      )
    }

    static func trackAnnouncementFeedLoaded(totalCount: Int, activeCount: Int) {
      signal(
        "Announcements.FeedLoaded",
        parameters: [
          "totalCount": String(max(0, totalCount)),
          "activeCount": String(max(0, activeCount)),
        ]
      )
    }

    static func trackAnnouncementDismissed(level: String) {
      signal("Announcements.Dismissed", parameters: ["level": level])
    }

    static func trackAnnouncementLinkOpened(level: String) {
      signal("Announcements.LinkOpened", parameters: ["level": level])
    }

    static func trackScraperFailure(
      signal signalName: String, target: String, errorType: String
    ) {
      signal(
        signalName,
        parameters: [
          "errorType": errorType,
          "target": target,
        ]
      )
    }
  }
#else
  enum TelemetryTracker {
    static func trackAppLaunched() {}
    static func trackTabSelected(_ tabName: String) {}
    static func trackScheduleModeSelected(_ mode: String) {}
    static func trackSemesterPlannerCopiedCurrentSchedule() {}
    static func trackSemesterPlannerCleared() {}
    static func trackOnboardingStarted() {}
    static func trackOnboardingStepCompleted(_ step: String, skipped: Bool) {}
    static func trackOnboardingCompleted() {}
    static func trackDiningFavoriteChanged(isFavorite: Bool, favoriteCount: Int) {}
    static func trackSportsGameViewed() {}
    static func trackMenuBarOpened() {}
    static func trackFloatingTimerShown(compact: Bool) {}
    static func trackAnnouncementFeedLoaded(totalCount: Int, activeCount: Int) {}
    static func trackAnnouncementDismissed(level: String) {}
    static func trackAnnouncementLinkOpened(level: String) {}
    static func trackScraperFailure(signal: String, target: String, errorType: String) {}
  }
#endif
