import Combine
import Foundation

@MainActor
final class RooMateNavigationCoordinator: ObservableObject {
  enum Destination: Equatable {
    case scheduleClass(Level)
    case club(UUID)
    case sportsGame(String)
    case event(String)
    case dining(dateID: String, recipeName: String)
    case settings(String)
  }

  struct Request: Identifiable, Equatable {
    let id = UUID()
    let destination: Destination
  }

  static let shared = RooMateNavigationCoordinator()
  @Published private(set) var request: Request?

  private init() {}

  func navigate(to destination: Destination) {
    request = Request(destination: destination)
  }

  func consume(_ request: Request) {
    if self.request?.id == request.id {
      self.request = nil
    }
  }
}

enum RooMateStableKey {
  static func event(_ event: CalendarEvent) -> String {
    "\(Int(event.startDate.timeIntervalSince1970))|\(event.title)|\(event.location ?? "")"
      .replacingOccurrences(of: "\n", with: " ")
  }
}
