import Combine
import Foundation

struct RemoteCacheEnvelope<Value: Codable>: Codable {
  let refreshedAt: Date
  let value: Value
}

enum PersistentRemoteCache {
  private static var directory: URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("com.codearc.RooMate", isDirectory: true)
      .appendingPathComponent("RemoteData", isDirectory: true)
  }

  static func load<Value: Codable>(
    _ type: Value.Type,
    named name: String,
    directory overrideDirectory: URL? = nil
  ) -> RemoteCacheEnvelope<Value>? {
    guard let directory = overrideDirectory ?? directory else { return nil }
    let url = directory.appendingPathComponent(safeFilename(name)).appendingPathExtension("json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(RemoteCacheEnvelope<Value>.self, from: data)
  }

  static func save<Value: Codable>(
    _ value: Value,
    refreshedAt: Date = Date(),
    named name: String,
    directory overrideDirectory: URL? = nil
  ) throws {
    guard let directory = overrideDirectory ?? directory else { return }
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let url = directory.appendingPathComponent(safeFilename(name)).appendingPathExtension("json")
    let envelope = RemoteCacheEnvelope(refreshedAt: refreshedAt, value: value)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(envelope).write(to: url, options: [.atomic])
  }

  private static func safeFilename(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
      .reduce(into: "", { $0.append($1) })
  }
}

enum RemoteServiceID: String, CaseIterable, Codable {
  case specialSchedules = "Special schedules"
  case dining = "Dining"
  case sports = "Sports"
  case events = "Events"
  case clubs = "Clubs"
  case announcements = "Announcements"
}

struct RemoteServiceHealth: Codable, Equatable {
  let loadedSuccessfully: Bool
  let usingSavedData: Bool
  let lastUpdated: Date?
  let errorCategory: String?
}

@MainActor
final class RemoteDataHealthStore: ObservableObject {
  static let shared = RemoteDataHealthStore()

  @Published private(set) var statuses: [RemoteServiceID: RemoteServiceHealth] = [:]

  private init() {}

  func recordSuccess(_ service: RemoteServiceID, refreshedAt: Date) {
    statuses[service] = RemoteServiceHealth(
      loadedSuccessfully: true,
      usingSavedData: false,
      lastUpdated: refreshedAt,
      errorCategory: nil
    )
  }

  func recordFailure(
    _ service: RemoteServiceID,
    error: Error,
    usingSavedData: Bool,
    lastUpdated: Date?
  ) {
    statuses[service] = RemoteServiceHealth(
      loadedSuccessfully: false,
      usingSavedData: usingSavedData,
      lastUpdated: lastUpdated,
      errorCategory: Self.category(for: error)
    )
  }

  private static func category(for error: Error) -> String {
    if error is URLError { return "Network" }
    return "Data format"
  }
}
