import AppKit
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
    @State private var refreshInterval: TimeInterval = 60
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var isTesting = false

    private static let labelWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Type", selection: $kind) {
                ForEach(ServerKind.allCases) { k in
                    Text(k.title).tag(k)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    if kind == .cloud {
                        row("API key") {
                            SecureField("", text: $apiKey, prompt: Text("umami_api_…"))
                        }
                        row("Region") {
                            Picker("", selection: $region) {
                                ForEach(CloudRegion.allCases) { r in
                                    Text(r.title).tag(r)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        row("") {
                            Text("Create a key at cloud.umami.is → Settings → API keys")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        row("Server URL") {
                            TextField("", text: $baseURL, prompt: Text("https://analytics.example.com"))
                        }
                        row("Username") {
                            TextField("", text: $username)
                        }
                        row("Password") {
                            SecureField("", text: $password)
                        }
                    }
                }
                .textFieldStyle(.roundedBorder)
                .padding(6)
            } label: {
                Label(kind == .cloud ? "Umami Cloud" : "Self-hosted server",
                      systemImage: kind == .cloud ? "cloud" : "server.rack")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    row("Refresh every") {
                        Picker("", selection: $refreshInterval) {
                            Text("30 seconds").tag(TimeInterval(30))
                            Text("1 minute").tag(TimeInterval(60))
                            Text("5 minutes").tag(TimeInterval(300))
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    row("Startup") {
                        VStack(alignment: .leading, spacing: 2) {
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
                    }
                }
                .padding(6)
            } label: {
                Label("General", systemImage: "gearshape")
            }

            HStack(spacing: 8) {
                Button(isTesting ? "Testing…" : "Test Connection") {
                    testConnection()
                }
                .disabled(isTesting)

                if isTesting {
                    ProgressView().controlSize(.small)
                } else if let testResult {
                    Label {
                        Text(testResult).lineLimit(1).truncationMode(.middle)
                    } icon: {
                        Image(systemName: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    }
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
        .padding(20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: loadFromStore)
        .onChange(of: kind) { _, _ in testResult = nil }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadFromStore() {
        let s = store.settings
        kind = s.kind
        apiKey = s.apiKey
        region = s.region
        baseURL = s.baseURL
        username = s.username
        password = s.password
        refreshInterval = s.refreshInterval
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var formConnection: Connection {
        Connection(kind: kind, baseURL: baseURL, region: region,
                   apiKey: apiKey, username: username, password: password)
    }

    private func applyToStore() {
        let s = store.settings
        s.apply(formConnection)
        s.refreshInterval = refreshInterval
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let client = UmamiClient(connection: formConnection, persistToken: false)
        Task {
            do {
                let count = try await client.testConnection()
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
        NSApplication.shared.keyWindow?.performClose(nil)
    }
}
