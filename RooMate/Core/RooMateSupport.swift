import Foundation

enum RooMateVersion {
  static var current: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  }

  static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let left = numericComponents(lhs)
    let right = numericComponents(rhs)
    let count = max(left.count, right.count)
    for index in 0..<count {
      let l = index < left.count ? left[index] : 0
      let r = index < right.count ? right[index] : 0
      if l < r { return .orderedAscending }
      if l > r { return .orderedDescending }
    }
    return .orderedSame
  }

  private static func numericComponents(_ version: String) -> [Int] {
    version.split(separator: ".").map { component in
      Int(component.prefix(while: \.isNumber)) ?? 0
    }
  }
}

@MainActor
enum RooMateSupportDiagnostics {
  static func summary(at date: Date = Date()) -> String {
    let architecture: String
    #if arch(arm64)
      architecture = "Apple silicon (arm64)"
    #elseif arch(x86_64)
      architecture = "Intel (x86_64)"
    #else
      architecture = "Unknown"
    #endif

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]

    var lines = [
      "RooMate bug report info",
      "Version: \(RooMateVersion.current)",
      "Build: \(RooMateVersion.build)",
      "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "Mac type: \(architecture)",
      "Time: \(formatter.string(from: date))",
      "School data:",
    ]

    for service in RemoteServiceID.allCases {
      let value: String
      if let status = RemoteDataHealthStore.shared.statuses[service] {
        if status.loadedSuccessfully {
          value = "Loaded"
        } else if status.usingSavedData {
          value = "Using saved data"
        } else {
          value = "Couldn’t load"
        }
      } else {
        value = "Not checked yet"
      }
      lines.append("- \(service.rawValue): \(value)")
    }

    lines.append("")
    lines.append("This does not include names, classes, teachers, rooms, clubs, teams, searches, plans, assignments, announcements, notes, or other personal school information.")
    return lines.joined(separator: "\n")
  }
}
