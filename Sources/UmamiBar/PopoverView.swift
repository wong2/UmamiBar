import AppKit
import Charts
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
                statGrid
                chart
                topLists
                if let message = store.errorMessage {
                    errorBanner(message)
                }
            }

            footer
        }
        .padding(12)
        .frame(width: 360)
        .overlay {
            if store.isLoading && store.stats == nil && store.settings.isConfigured {
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
            Menu {
                ForEach(store.websites) { site in
                    Button {
                        store.select(website: site)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(site.name)
                            Text(site.domain)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Text(store.selectedWebsite?.name ?? "Select website")
                    .font(.system(.headline))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

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

    private struct StatCard: View {
        let title: String
        let value: String
        let delta: Double?
        var lowerIsBetter = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    if let delta {
                        let good = lowerIsBetter ? delta < 0 : delta >= 0
                        Text(String(format: "%@%.0f%%", delta >= 0 ? "↑" : "↓", abs(delta) * 100))
                            .font(.caption2)
                            .foregroundStyle(good ? .green : .red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func delta(_ current: Double, _ previous: Double?) -> Double? {
        guard let previous, previous > 0 else { return nil }
        return (current - previous) / previous
    }

    private var statGrid: some View {
        let s = store.stats
        let bounceRate = s.map { $0.visits > 0 ? $0.bounces / $0.visits : 0 } ?? 0
        let prevBounceRate = s?.comparison.map { $0.visits > 0 ? $0.bounces / $0.visits : 0 }
        let avgTime = s.map { $0.visits > 0 ? $0.totaltime / $0.visits : 0 } ?? 0
        let prevAvgTime = s?.comparison.map { $0.visits > 0 ? $0.totaltime / $0.visits : 0 }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCard(title: "Visitors", value: compactNumber(s?.visitors ?? 0), delta: delta(s?.visitors ?? 0, s?.comparison?.visitors))
            StatCard(title: "Views", value: compactNumber(s?.pageviews ?? 0), delta: delta(s?.pageviews ?? 0, s?.comparison?.pageviews))
            StatCard(title: "Visits", value: compactNumber(s?.visits ?? 0), delta: delta(s?.visits ?? 0, s?.comparison?.visits))
            StatCard(title: "Bounce rate", value: percent(bounceRate), delta: delta(bounceRate, prevBounceRate), lowerIsBetter: true)
            StatCard(title: "Avg. visit", value: duration(seconds: avgTime), delta: delta(avgTime, prevAvgTime))
        }
    }

    private var chart: some View {
        Group {
            if let series = store.series, series.pageviews.count >= 2 {
                Chart {
                    ForEach(Array(series.pageviews.enumerated()), id: \.offset) { _, point in
                        if let date = point.date {
                            AreaMark(x: .value("Time", date), y: .value("Views", point.y))
                                .foregroundStyle(Gradient(colors: [.accentColor.opacity(0.3), .accentColor.opacity(0.02)]))
                            LineMark(x: .value("Time", date), y: .value("Views", point.y))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            } else {
                Text("Not enough data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 90)
    }

    private func metricList(title: String, rows: [MetricRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            let max = rows.map(\.y).max() ?? 1
            ForEach(rows) { row in
                HStack {
                    Text(row.x.isEmpty ? "(direct)" : row.x)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(compactNumber(row.y))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: geo.size.width * CGFloat(row.y / max))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private var topLists: some View {
        HStack(alignment: .top, spacing: 12) {
            metricList(title: "Top pages", rows: store.topPages)
            metricList(title: "Top referrers", rows: store.topReferrers)
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
                Text("\(store.active ?? 0) active")
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
