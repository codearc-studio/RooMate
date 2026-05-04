import Foundation

actor CanvasAPI {
    func fetchTodos(domain: String, token: String) async throws -> [CanvasTodoItem] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = domain
        comps.path = "/api/v1/users/self/todo"
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode)"
            ])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let items = try decoder.decode([CanvasTodoItem].self, from: data)
        return items
    }

    func fetchCourses(domain: String, token: String) async throws -> [CanvasCourse] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }

        func buildInitialURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/courses"
            comps.queryItems = [
                URLQueryItem(name: "enrollment_type", value: "student"),
                URLQueryItem(name: "per_page", value: "100")
            ]
            return comps.url
        }

        func buildFallbackURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/courses"
            return comps.url
        }

        var all: [CanvasCourse] = []
        var nextURL: URL? = buildInitialURL()
        var usedFallback = false

        while let url = nextURL {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

            if !(200..<300).contains(http.statusCode) {
                if !usedFallback, (500..<600).contains(http.statusCode) {
                    usedFallback = true
                    all.removeAll()
                    nextURL = buildFallbackURL()
                    continue
                }
                throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode) for courses"
                ])
            }

            let page = try JSONDecoder().decode([CanvasCourse].self, from: data)
            all.append(contentsOf: page)

            if let link = http.value(forHTTPHeaderField: "Link") {
                nextURL = Self.parseLinkHeader(link)["next"]
            } else {
                nextURL = nil
            }
        }

        return all
    }

    func fetchEnrollments(domain: String, token: String, courseID: Int) async throws -> [CanvasEnrollment] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }

        func buildInitialURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/courses/\(courseID)/enrollments"
            comps.queryItems = [
                URLQueryItem(name: "user_id", value: "self"),
                URLQueryItem(name: "include[]", value: "grades"),
                URLQueryItem(name: "include[]", value: "total_scores"),
                URLQueryItem(name: "per_page", value: "100")
            ]
            return comps.url
        }

        var all: [CanvasEnrollment] = []
        var nextURL: URL? = buildInitialURL()

        while let url = nextURL {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode) for enrollments"
                ])
            }

            let page = try JSONDecoder().decode([CanvasEnrollment].self, from: data)
            all.append(contentsOf: page)

            if let link = http.value(forHTTPHeaderField: "Link") {
                nextURL = Self.parseLinkHeader(link)["next"]
            } else {
                nextURL = nil
            }
        }

        return all
    }

    private static func parseLinkHeader(_ header: String) -> [String: URL] {
        var result: [String: URL] = [:]
        let parts = header.split(separator: ",")
        for part in parts {
            let sections = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let urlPart = sections.first,
                  urlPart.hasPrefix("<"), urlPart.hasSuffix(">") else { continue }
            let urlString = urlPart.dropFirst().dropLast()
            var rel: String?
            for sec in sections.dropFirst() {
                let pair = sec.split(separator: "=")
                if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == "rel" {
                    rel = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            if let rel, let url = URL(string: String(urlString)) {
                result[rel] = url
            }
        }
        return result
    }
}
