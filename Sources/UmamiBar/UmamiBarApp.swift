import AppKit
import SwiftUI
import UmamiBarCore

enum SettingsOpener {
    static func open() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

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
                if store.settings.showActiveInMenuBar, let active = store.active {
                    Text("\(active)")
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
