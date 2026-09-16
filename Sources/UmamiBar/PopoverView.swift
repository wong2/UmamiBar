import AppKit
import SwiftUI
import UmamiBarCore

struct PopoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.settings.isConfigured {
                emptyState
            } else {
                header
                siteList
                if let message = store.errorMessage {
                    errorBanner(message)
                }
            }

            footer
        }
        .padding(12)
        .frame(width: 360)
        .overlay {
            if store.isLoading && store.sites.allSatisfy({ $0.stats == nil }) && store.settings.isConfigured {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .task {
            await store.loadWebsites()
            await store.refresh()
        }
        .onAppear {
            if let last = store.lastUpdated,
               Date().timeIntervalSince(last) > store.settings.refreshInterval {
                Task { await store.refresh() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Websites")
                .font(.headline)

            Spacer()

            Menu {
                ForEach(DateRange.allCases) { range in
                    Button(range.title) { store.select(range: range) }
                }
            } label: {
                Text(store.range.title)
                    .font(.system(.callout))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Connect to Umami")
                .font(.headline)
            Text("Add your Umami Cloud API key or self-hosted server to see analytics here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func deltaText(_ current: Double, _ previous: Double?) -> Text {
        guard let previous, previous > 0 else { return Text("") }
        let delta = (current - previous) / previous
        return Text(String(format: "%@%.0f%%", delta >= 0 ? "↑" : "↓", abs(delta) * 100))
            .foregroundStyle(delta >= 0 ? .green : .red)
    }

    private func metricCell(_ value: Double?, _ previous: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value.map(compactNumber) ?? "–")
                .font(.callout.weight(.medium))
                .monospacedDigit()
            deltaText(value ?? 0, previous)
                .font(.caption2)
        }
    }

    private var siteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                GridRow {
                    Text("")
                    Text("Visitors")
                    Text("Views")
                    Text("Visits")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(store.sites.sorted(by: { $0.website.name < $1.website.name })) { site in
                        GridRow {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(site.website.name)
                                    .font(.callout)
                                    .lineLimit(1)
                                if let active = site.active, active > 0 {
                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 6, height: 6)
                                        Text("\(active) active")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(site.website.domain)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .gridColumnAlignment(.leading)

                            metricCell(site.stats?.visitors, site.stats?.comparison?.visitors)
                            metricCell(site.stats?.pageviews, site.stats?.comparison?.pageviews)
                            metricCell(site.stats?.visits, site.stats?.comparison?.visits)
                        }
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(360, CGFloat(max(store.sites.count, 1)) * 46))

            if store.sites.isEmpty && !store.isLoading {
                Text("No websites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .lineLimit(2)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.settings.isConfigured {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text("\(store.totalActive) active")
                    .font(.caption)
            }

            Spacer()

            if store.settings.isConfigured, let last = store.lastUpdated {
                Text(relativeTime(last))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if store.settings.isConfigured {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                        .animation(store.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: store.isLoading)
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoading)
            }

            Menu {
                Button("Open Umami dashboard") {
                    if let url = URL(string: store.settings.connection.dashboardURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Quit UmamiBar") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
