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
            HStack(spacing: 2) {
                Image(systemName: "chart.bar.xaxis")
                if store.settings.showActiveInMenuBar, store.totalActive > 0 {
                    Text("\(store.totalActive)")
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
