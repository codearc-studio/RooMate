import Foundation

actor CanvasAPI {
    // Fetch the current user's To‑Do items.
    // GET /api/v1/users/self/todo
    func fetchTodos(domain: String, token: String) async throws -> [CanvasTodoItem] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }

        func buildInitialURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/users/self/todo"
            // Canvas paginates; per_page up to 100 is typical
            comps.queryItems = [
                URLQueryItem(name: "per_page", value: "100")
            ]
            return comps.url
        }

        var all: [CanvasTodoItem] = []
        var nextURL: URL? = buildInitialURL()

        while let url = nextURL {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode) for todos"
                ])
            }

            let page = try JSONDecoder().decode([CanvasTodoItem].self, from: data)
            all.append(contentsOf: page)

            if let link = http.value(forHTTPHeaderField: "Link") {
                nextURL = Self.parseLinkHeader(link)["next"]
            } else {
                nextURL = nil
            }
        }

        return all
    }

    // Fetch active/enrolled courses for the current user.
    // GET /api/v1/courses
    func fetchCourses(domain: String, token: String) async throws -> [CanvasCourse] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }

        func buildInitialURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/courses"
            // Include useful fields; limit page size
            comps.queryItems = [
                URLQueryItem(name: "enrollment_state", value: "active"),
                URLQueryItem(name: "per_page", value: "100")
            ]
            return comps.url
        }

        var all: [CanvasCourse] = []
        var nextURL: URL? = buildInitialURL()

        while let url = nextURL {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
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

    // Fetch enrollments for a given course (used to compute grade summaries).
    // GET /api/v1/courses/:course_id/enrollments
    func fetchEnrollments(domain: String, token: String, courseID: Int) async throws -> [CanvasEnrollment] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }

        func buildInitialURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/courses/\(courseID)/enrollments"
            comps.queryItems = [
                URLQueryItem(name: "type[]", value: "StudentEnrollment"),
                URLQueryItem(name: "state[]", value: "active"),
                // Important: request grade fields explicitly; some Canvas instances omit them by default.
                URLQueryItem(name: "include[]", value: "grades"),
                URLQueryItem(name: "include[]", value: "total_scores"),
                URLQueryItem(name: "include[]", value: "current_grading_period_scores"),
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

    // Existing method you already had
    func fetchAssignments(domain: String, token: String, courseID: Int) async throws -> [CanvasAssignment] {
        guard !domain.isEmpty, !token.isEmpty else { return [] }

        func buildInitialURL() -> URL? {
            var comps = URLComponents()
            comps.scheme = "https"
            comps.host = domain
            comps.path = "/api/v1/courses/\(courseID)/assignments"
            comps.queryItems = [
                URLQueryItem(name: "include[]", value: "submission"),
                URLQueryItem(name: "per_page", value: "100")
            ]
            return comps.url
        }

        var all: [CanvasAssignment] = []
        var nextURL: URL? = buildInitialURL()

        while let url = nextURL {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "CanvasAPI", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Canvas returned \(http.statusCode) for assignments"
                ])
            }

            let page = try JSONDecoder().decode([CanvasAssignment].self, from: data)
            all.append(contentsOf: page)

            if let link = http.value(forHTTPHeaderField: "Link") {
                nextURL = Self.parseLinkHeader(link)["next"]
            } else {
                nextURL = nil
            }
        }

        return all
    }

    // Parse RFC 5988 Link header into a dictionary keyed by rel (e.g., "next", "prev")
    static func parseLinkHeader(_ header: String) -> [String: URL] {
        var results: [String: URL] = [:]

        let parts = header.split(separator: ",")
        for rawPart in parts {
            let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let urlStart = part.firstIndex(of: "<"),
                  let urlEnd = part.firstIndex(of: ">"),
                  urlStart < urlEnd else { continue }

            let urlString = part[part.index(after: urlStart)..<urlEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: String(urlString)) else { continue }

            let paramsStart = part.index(after: urlEnd)
            let paramsSubstring = part[paramsStart...]
            let paramTokens = paramsSubstring.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            var relValue: String?
            for token in paramTokens {
                if token.lowercased().hasPrefix("rel=") {
                    let relRaw = token.dropFirst(4)
                    let trimmed = relRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    if !trimmed.isEmpty {
                        relValue = String(trimmed)
                        break
                    }
                }
            }

            if let rel = relValue {
                results[rel] = url
            }
        }

        return results
    }
}
