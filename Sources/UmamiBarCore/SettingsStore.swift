import Foundation

@Observable
public final class SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var kind: ServerKind {
        get { ServerKind(rawValue: defaults.string(forKey: "kind") ?? "") ?? .cloud }
        set { defaults.set(newValue.rawValue, forKey: "kind") }
    }

    public var baseURL: String {
        get { defaults.string(forKey: "baseURL") ?? "" }
        set { defaults.set(newValue, forKey: "baseURL") }
    }

    public var region: CloudRegion {
        get { CloudRegion(rawValue: defaults.string(forKey: "region") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "region") }
    }

    public var username: String {
        get { defaults.string(forKey: "username") ?? "" }
        set { defaults.set(newValue, forKey: "username") }
    }

    public var selectedWebsiteId: String? {
        get { defaults.string(forKey: "selectedWebsiteId") }
        set { defaults.set(newValue, forKey: "selectedWebsiteId") }
    }

    public var dateRange: DateRange {
        get { DateRange(rawValue: defaults.string(forKey: "dateRange") ?? "") ?? .today }
        set { defaults.set(newValue.rawValue, forKey: "dateRange") }
    }

    public var showActiveInMenuBar: Bool {
        get { defaults.object(forKey: "showActiveInMenuBar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showActiveInMenuBar") }
    }

    public var refreshInterval: TimeInterval {
        get {
            let v = defaults.double(forKey: "refreshInterval")
            return v > 0 ? v : 60
        }
        set { defaults.set(newValue, forKey: "refreshInterval") }
    }

    public var apiKey: String {
        get { Keychain.get("apiKey") ?? "" }
        set { Keychain.set(newValue, for: "apiKey") }
    }

    public var password: String {
        get { Keychain.get("password") ?? "" }
        set { Keychain.set(newValue, for: "password") }
    }

    public var token: String? {
        get { Keychain.get("token") }
        set {
            if let newValue {
                Keychain.set(newValue, for: "token")
            } else {
                Keychain.delete("token")
            }
        }
    }

    public var isConfigured: Bool {
        switch kind {
        case .cloud:
            return !apiKey.isEmpty
        case .selfHosted:
            return !baseURL.isEmpty && !username.isEmpty && !password.isEmpty
        }
    }

    public var config: ServerConfig {
        ServerConfig(kind: kind, baseURL: baseURL, region: region)
    }

    public func clearSession() {
        Keychain.delete("token")
    }
}
