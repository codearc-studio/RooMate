import SwiftUI

/// Global configuration for sport-to-icon mappings
/// Used consistently across the app to display sport icons
struct SportIconConfiguration {
  // Return a system image name if available for the current platform
  private static func availableSystemSymbol(from candidates: [String]) -> String? {
    for name in candidates {
      #if canImport(AppKit)
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
          return name
        }
      #elseif canImport(UIKit)
        if UIImage(systemName: name) != nil {
          return name
        }
      #else
        // Fallback: assume symbol exists
        return name
      #endif
    }
    return nil
  }

  // MARK: - Sports colors

  /// A curated palette used for stable sport/team identity throughout RooMate.
  /// We intentionally do not use Swift's `hashValue` because it can change
  /// between launches. The tiny stable hash below keeps colors consistent.
  private static let identityPalette: [Color] = [
    Color(hex: 0xD86666),  // coral red
    Color(hex: 0xD8874F),  // orange
    Color(hex: 0xC99A3D),  // amber
    Color(hex: 0x7FA451),  // lime
    Color(hex: 0x55A273),  // green
    Color(hex: 0x4A9B93),  // teal
    Color(hex: 0x4B94B7),  // cyan blue
    Color(hex: 0x5C80C5),  // blue
    Color(hex: 0x6D70C0),  // indigo
    Color(hex: 0x8768B8),  // purple
    Color(hex: 0xB66A9A),  // pink
    Color(hex: 0xC66F64),  // warm coral
    Color(hex: 0x6E91A6),  // slate blue
    Color(hex: 0xB4854C),  // gold
  ]

  static func sportColor(for sport: String) -> Color {
    identityColor(for: normalizedSportIdentity(sport))
  }

  static func teamColor(for team: String) -> Color {
    identityColor(for: team.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private static func identityColor(for value: String) -> Color {
    guard !identityPalette.isEmpty else {
      return DesignTokens.Colors.athletics
    }

    let normalized =
      value
      .lowercased()
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalized.isEmpty else {
      return DesignTokens.Colors.athletics
    }

    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in normalized.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }

    return identityPalette[Int(hash % UInt64(identityPalette.count))]
  }

  private static func normalizedSportIdentity(_ value: String) -> String {
    let normalized = value.lowercased()

    if normalized.contains("field hockey") { return "field hockey" }
    if normalized.contains("cross country") { return "cross country" }
    if normalized.contains("soccer") { return "soccer" }
    if normalized.contains("basketball") { return "basketball" }
    if normalized.contains("volleyball") { return "volleyball" }
    if normalized.contains("football") { return "football" }
    if normalized.contains("softball") { return "softball" }
    if normalized.contains("baseball") { return "baseball" }
    if normalized.contains("tennis") { return "tennis" }
    if normalized.contains("golf") { return "golf" }
    if normalized.contains("lacrosse") { return "lacrosse" }
    if normalized.contains("swim") { return "swimming" }
    if normalized.contains("wrestl") { return "wrestling" }
    if normalized.contains("track") { return "track & field" }
    if normalized.contains("ultimate") || normalized.contains("frisbee") {
      return "ultimate frisbee"
    }

    return value
  }

  /// Returns an Image for the given sport, with a sensible fallback if a symbol is unavailable
  static func icon(for sport: String) -> Image {
    let normalized = sport.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    // Map to prioritized symbol candidates (primary -> fallback)
    var candidates: [String] = []

    if normalized.contains("soccer") {
      candidates = ["soccerball.fill", "soccerball", "sportscourt.fill"]
    } else if normalized.contains("basketball") {
      candidates = ["basketball.fill", "sportscourt.fill"]
    } else if normalized.contains("volleyball") {
      candidates = ["volleyball.fill", "sportscourt.fill"]
    } else if normalized.contains("football") {
      candidates = ["football.fill", "sportscourt.fill"]
    } else if normalized.contains("baseball") || normalized.contains("softball") {
      candidates = ["baseball.fill", "sportscourt.fill"]
    } else if normalized.contains("tennis") {
      candidates = ["tennisball.fill", "sportscourt.fill"]
    } else if normalized.contains("golf") {
      candidates = ["flag.fill", "flag", "sportscourt.fill"]
    } else if normalized.contains("track") || normalized.contains("cross") {
      candidates = ["figure.run", "figure.walk", "sportscourt.fill"]
    } else if normalized.contains("lacrosse") {
      candidates = ["figure.lacrosse", "sportscourt.fill"]
    } else if normalized.contains("swimming") {
      candidates = ["figure.pool.swim", "sportscourt.fill"]
    } else if normalized.contains("wrestling") {
      candidates = ["figure.wrestling", "sportscourt.fill"]
    } else if normalized.contains("gymnastics") {
      candidates = ["figure.gymnastics", "sportscourt.fill"]
    } else if normalized.contains("rowing") || normalized.contains("crew") {
      candidates = ["sailboat.fill", "sportscourt.fill"]
    } else if normalized.contains("ultimate") || normalized.contains("frisbee") {
      candidates = ["circle.dashed", "sportscourt.fill"]
    } else if normalized.contains("squash") {
      candidates = ["figure.squash", "sportscourt.fill"]
    } else if normalized.contains("field") && normalized.contains("hockey") {
      candidates = ["figure.hockey", "sportscourt.fill"]
    } else {
      candidates = ["sportscourt.fill"]
    }

    if let chosen = availableSystemSymbol(from: candidates) {
      return Image(systemName: chosen)
    }

    // Last-resort fallback
    return Image(systemName: "sportscourt.fill")
  }

  /// Backwards-compatible helper returning a best-effort name (keeps existing usages that expect a String)
  static func iconName(for sport: String) -> String {
    // We cannot extract the systemName from Image, so return a safe fallback mapping (keeps prior semantics)
    // Prefer explicit common names
    let normalized = sport.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.contains("soccer") { return "soccerball.fill" }
    if normalized.contains("basketball") { return "basketball.fill" }
    if normalized.contains("volleyball") { return "volleyball.fill" }
    if normalized.contains("football") { return "football.fill" }
    if normalized.contains("baseball") || normalized.contains("softball") { return "baseball.fill" }
    if normalized.contains("tennis") { return "tennisball.fill" }
    if normalized.contains("golf") { return "flag.fill" }
    if normalized.contains("track") || normalized.contains("cross") { return "figure.run" }
    if normalized.contains("lacrosse") { return "figure.lacrosse" }
    if normalized.contains("swimming") { return "figure.pool.swim" }
    if normalized.contains("wrestling") { return "figure.wrestling" }
    if normalized.contains("gymnastics") { return "figure.gymnastics" }
    if normalized.contains("rowing") || normalized.contains("crew") { return "sailboat.fill" }
    if normalized.contains("ultimate") || normalized.contains("frisbee") { return "circle.dashed" }
    if normalized.contains("squash") { return "figure.squash" }
    if normalized.contains("field") && normalized.contains("hockey") { return "figure.hockey" }
    return "sportscourt.fill"
  }
}
