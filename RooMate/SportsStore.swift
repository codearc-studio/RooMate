import Foundation
import Combine

/// Observable store that fetches and holds sports games
@MainActor
final class SportsStore: ObservableObject {
    @Published private(set) var games: [SportsGame] = []
    @Published private(set) var lastError: Error?
    @Published private(set) var isLoading: Bool = false

    private var task: Task<Void, Never>? = nil

    private let csvURL = URL(string: "https://docs.google.com/spreadsheets/d/1qjS03N92vjx6MXc0PTgOJfTSsY6HAJKFCpu0rVuoyOk/gviz/tq?tqx=out:csv")!

    func refresh() {
        task?.cancel()
        isLoading = true
        lastError = nil
        task = Task { [weak self] in
            guard let self = self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: csvURL)
                let parsed = SportsCSVParser.parseSportsGames(from: data)
                self.games = parsed.sorted { (a, b) -> Bool in
                    if let ad = a.date, let bd = b.date { return ad < bd }
                    return a.rawDateString < b.rawDateString
                }
            } catch {
                if (error as NSError).code == NSURLErrorCancelled { return }
                self.lastError = error
                self.games = []
            }
            self.isLoading = false
        }
    }

    deinit {
        task?.cancel()
    }
}
