import AppKit
import SwiftUI
import UmamiBarCore

@main
struct UmamiBarApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
    }
}
