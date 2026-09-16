import ServiceManagement
import SwiftUI
import UmamiBarCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var kind: ServerKind = .cloud
    @State private var apiKey = ""
    @State private var region: CloudRegion = .auto
    @State private var baseURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var showActive = true
    @State private var refreshInterval: TimeInterval = 60
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Server") {
                Picker("Type", selection: $kind) {
                    ForEach(ServerKind.allCases) { k in
                        Text(k.title).tag(k)
                    }
                }
                .pickerStyle(.segmented)

                if kind == .cloud {
                    SecureField("API key", text: $apiKey)
                    Picker("Region", selection: $region) {
                        ForEach(CloudRegion.allCases) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    Text("Create a key at cloud.umami.is → Settings → API keys")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Server URL", text: $baseURL, prompt: Text("https://analytics.example.com"))
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                }
            }

            Section("General") {
                Toggle("Show active visitors in menu bar", isOn: $showActive)
                Picker("Refresh every", selection: $refreshInterval) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("5 minutes").tag(TimeInterval(300))
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Button(isTesting ? "Testing…" : "Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testSucceeded ? .green : .red)
                    }

                    Spacer()

                    Button("Save") {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear(perform: loadFromStore)
    }

    private func loadFromStore() {
        let s = store.settings
        kind = s.kind
        apiKey = s.apiKey
        region = s.region
        baseURL = s.baseURL
        username = s.username
        password = s.password
        showActive = s.showActiveInMenuBar
        refreshInterval = s.refreshInterval
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyToStore() {
        let s = store.settings
        s.kind = kind
        s.apiKey = apiKey
        s.region = region
        s.baseURL = baseURL
        s.username = username
        s.password = password
        s.showActiveInMenuBar = showActive
        s.refreshInterval = refreshInterval
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let s = SettingsStore()
        s.kind = kind
        s.apiKey = apiKey
        s.region = region
        s.baseURL = baseURL
        s.username = username
        s.password = password
        Task {
            do {
                let count = try await UmamiClient(settings: s).testConnection()
                await MainActor.run {
                    testResult = "Connected — \(count) website\(count == 1 ? "" : "s")"
                    testSucceeded = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = error.localizedDescription
                    testSucceeded = false
                    isTesting = false
                }
            }
        }
    }

    private func save() {
        applyToStore()
        store.reconfigure()
    }
}
