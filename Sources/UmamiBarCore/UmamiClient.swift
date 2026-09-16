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
    private let connection: Connection
    private let persistToken: Bool
    private let session: URLSession
    private let decoder = JSONDecoder()
    private var token: String?

    public init(connection: Connection, persistToken: Bool = true, session: URLSession = .shared) {
        self.connection = connection
        self.persistToken = persistToken
        self.session = session
        self.token = persistToken ? Keychain.get("token") : nil
    }

    private func authHeader() async throws -> String {
        switch connection.kind {
        case .cloud:
            guard !connection.apiKey.isEmpty else { throw UmamiError.notConfigured }
            return "Bearer \(connection.apiKey)"
        case .selfHosted:
            if let token {
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
        let body = ["username": connection.username, "password": connection.password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        struct LoginResponse: Decodable { let token: String }
        let decoded = try decoder.decode(LoginResponse.self, from: data)
        token = decoded.token
        if persistToken {
            Keychain.set(decoded.token, for: "token")
        }
        return "Bearer \(decoded.token)"
    }

    private func clearToken() {
        token = nil
        if persistToken {
            Keychain.delete("token")
        }
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        guard connection.isConfigured else { throw UmamiError.notConfigured }
        let base = connection.apiBase
        guard var comps = URLComponents(string: base + path) else { throw UmamiError.invalidURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw UmamiError.invalidURL }
        return url
    }

    private func data(path: String, query: [String: String] = [:], retry: Bool = true) async throws -> Data {
        let url = try makeURL(path: path, query: query)
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(try await authHeader(), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UmamiError.invalidURL }

        if (http.statusCode == 401 || http.statusCode == 403),
           retry, connection.kind == .selfHosted {
            clearToken()
            return try await self.data(path: path, query: query, retry: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw UmamiError.unauthorized }
            throw UmamiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func request<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let data = try await self.data(path: path, query: query)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw UmamiError.decoding(error.localizedDescription)
        }
    }

    private func rangeQuery(_ range: DateRange) -> [String: String] {
        [
            "startAt": String(Int(range.startAt.timeIntervalSince1970 * 1000)),
            "endAt": String(Int(range.endAt.timeIntervalSince1970 * 1000)),
        ]
    }

    public func websites() async throws -> [Website] {
        let data = try await self.data(path: "/websites", query: ["includeTeams": "true", "pageSize": "200"])
        return try WebsitesResult.decode(from: data, decoder: decoder)
    }

    public func stats(websiteId: String, range: DateRange) async throws -> WebsiteStats {
        try await request("/websites/\(websiteId)/stats", query: rangeQuery(range))
    }

    public func active(websiteId: String) async throws -> Int {
        let data = try await self.data(path: "/websites/\(websiteId)/active")
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
