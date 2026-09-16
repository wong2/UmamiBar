import Foundation

public enum UmamiError: LocalizedError, Sendable {
    case invalidURL
    case unauthorized
    case http(status: Int, body: String)
    case decoding(String)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL."
        case .unauthorized:
            return "Unauthorized — check your credentials."
        case .http(let status, let body):
            return "HTTP \(status): \(body.prefix(200))"
        case .decoding(let detail):
            return "Failed to decode server response: \(detail)"
        case .notConfigured:
            return "Umami is not configured. Open Settings to connect."
        }
    }
}

public actor UmamiClient {
    private let settings: SettingsStore
    private let session: URLSession
    private let decoder = JSONDecoder()

    public init(settings: SettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    private func authHeader() async throws -> String {
        switch settings.kind {
        case .cloud:
            guard !settings.apiKey.isEmpty else { throw UmamiError.notConfigured }
            return "Bearer \(settings.apiKey)"
        case .selfHosted:
            if let token = settings.token {
                return "Bearer \(token)"
            }
            return try await login()
        }
    }

    private func login() async throws -> String {
        let url = try makeURL(path: "/auth/login", query: [:])
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = ["username": settings.username, "password": settings.password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        struct LoginResponse: Decodable { let token: String }
        let decoded = try decoder.decode(LoginResponse.self, from: data)
        settings.token = decoded.token
        return "Bearer \(decoded.token)"
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        guard settings.isConfigured else { throw UmamiError.notConfigured }
        let base = settings.config.apiBase
        guard var comps = URLComponents(string: base + path) else { throw UmamiError.invalidURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw UmamiError.invalidURL }
        return url
    }

    private func request<T: Decodable>(_ path: String, query: [String: String] = [:], retryOnUnauthorized: Bool = true) async throws -> T {
        let url = try makeURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(try await authHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }

        if (http.statusCode == 401 || http.statusCode == 403),
           retryOnUnauthorized, settings.kind == .selfHosted {
            settings.clearSession()
            return try await self.request(path, query: query, retryOnUnauthorized: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw UmamiError.decoding(error.localizedDescription)
        }
    }

    private func rawRequest(path: String, query: [String: String] = [:]) async throws -> Data {
        let url = try makeURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(try await authHeader(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }
        if (http.statusCode == 401 || http.statusCode == 403), settings.kind == .selfHosted {
            settings.clearSession()
            return try await rawRequestOnce(path: path, query: query)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func rawRequestOnce(path: String, query: [String: String]) async throws -> Data {
        let url = try makeURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(try await authHeader(), forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func rangeQuery(_ range: DateRange) -> [String: String] {
        [
            "startAt": String(Int(range.startAt.timeIntervalSince1970 * 1000)),
            "endAt": String(Int(range.endAt.timeIntervalSince1970 * 1000)),
        ]
    }

    public func websites() async throws -> [Website] {
        let data = try await rawRequest(path: "/websites", query: ["includeTeams": "true", "pageSize": "200"])
        return try WebsitesResult.decode(from: data, decoder: decoder)
    }

    public func stats(websiteId: String, range: DateRange) async throws -> WebsiteStats {
        try await request("/websites/\(websiteId)/stats", query: rangeQuery(range))
    }

    public func active(websiteId: String) async throws -> Int {
        let data = try await rawRequest(path: "/websites/\(websiteId)/active")
        return try decoder.decode(ActiveVisitors.self, from: data).visitors
    }

    public func pageviews(websiteId: String, range: DateRange) async throws -> PageviewsResponse {
        var query = rangeQuery(range)
        query["unit"] = range.unit
        query["timezone"] = TimeZone.current.identifier
        return try await request("/websites/\(websiteId)/pageviews", query: query)
    }

    public func metrics(websiteId: String, range: DateRange, type: String, limit: Int = 5) async throws -> [MetricRow] {
        var query = rangeQuery(range)
        query["type"] = type
        query["limit"] = String(limit)
        return try await request("/websites/\(websiteId)/metrics", query: query)
    }

    public func testConnection() async throws -> Int {
        try await websites().count
    }
}
