import Foundation

@Observable
public final class SettingsStore {
    private let defaults: UserDefaults
    private var revision = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var kind: ServerKind {
        get { _ = revision; return ServerKind(rawValue: defaults.string(forKey: "kind") ?? "") ?? .cloud }
        set { defaults.set(newValue.rawValue, forKey: "kind"); revision += 1 }
    }

    public var baseURL: String {
        get { _ = revision; return defaults.string(forKey: "baseURL") ?? "" }
        set { defaults.set(newValue, forKey: "baseURL"); revision += 1 }
    }

    public var region: CloudRegion {
        get { _ = revision; return CloudRegion(rawValue: defaults.string(forKey: "region") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "region"); revision += 1 }
    }

    public var username: String {
        get { _ = revision; return defaults.string(forKey: "username") ?? "" }
        set { defaults.set(newValue, forKey: "username"); revision += 1 }
    }

    public var selectedWebsiteId: String? {
        get { _ = revision; return defaults.string(forKey: "selectedWebsiteId") }
        set { defaults.set(newValue, forKey: "selectedWebsiteId"); revision += 1 }
    }

    public var dateRange: DateRange {
        get { _ = revision; return DateRange(rawValue: defaults.string(forKey: "dateRange") ?? "") ?? .today }
        set { defaults.set(newValue.rawValue, forKey: "dateRange"); revision += 1 }
    }

    public var refreshInterval: TimeInterval {
        get {
            _ = revision
            let v = defaults.double(forKey: "refreshInterval")
            return v > 0 ? v : 60
        }
        set { defaults.set(newValue, forKey: "refreshInterval"); revision += 1 }
    }

    public var apiKey: String {
        get { _ = revision; return Keychain.get("apiKey") ?? "" }
        set { Keychain.set(newValue, for: "apiKey"); revision += 1 }
    }

    public var password: String {
        get { _ = revision; return Keychain.get("password") ?? "" }
        set { Keychain.set(newValue, for: "password"); revision += 1 }
    }

    public var token: String? {
        get { _ = revision; return Keychain.get("token") }
        set {
            if let newValue {
                Keychain.set(newValue, for: "token")
            } else {
                Keychain.delete("token")
            }
            revision += 1
        }
    }

    public var isConfigured: Bool {
        connection.isConfigured
    }

    public var connection: Connection {
        _ = revision
        return Connection(kind: kind, baseURL: baseURL, region: region,
                          apiKey: apiKey, username: username, password: password)
    }

    public func apply(_ c: Connection) {
        defaults.set(c.kind.rawValue, forKey: "kind")
        defaults.set(c.baseURL, forKey: "baseURL")
        defaults.set(c.region.rawValue, forKey: "region")
        defaults.set(c.username, forKey: "username")
        Keychain.set(c.apiKey, for: "apiKey")
        Keychain.set(c.password, for: "password")
        revision += 1
    }

    public func clearSession() {
        Keychain.delete("token")
        revision += 1
    }
}
