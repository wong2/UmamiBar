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

    private static let metricWidth: CGFloat = 60

    private func metricCell(_ value: Double?, _ previous: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value.map(compactNumber) ?? "–")
                .font(.callout.weight(.medium))
                .monospacedDigit()
            deltaText(value ?? 0, previous)
                .font(.caption2)
        }
        .frame(width: Self.metricWidth, alignment: .trailing)
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: Self.metricWidth, alignment: .trailing)
    }

    private var siteList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                columnHeader("Visitors")
                columnHeader("Views")
                columnHeader("Visits")
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.sites.sorted(by: { $0.website.name < $1.website.name })) { site in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.toggle(site: site)
                            }
                        } label: {
                            rowLabel(site)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        if store.expandedSiteId == site.id {
                            detailView(site)
                                .padding(.leading, 18)
                                .padding(.bottom, 4)
                        }
                        Divider()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(400, CGFloat(max(store.sites.count, 1)) * 50 + (store.expandedSiteId != nil ? 190 : 0)))

            if store.sites.isEmpty && !store.isLoading {
                Text("No websites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func rowLabel(_ site: SiteSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(store.expandedSiteId == site.id ? 90 : 0))
                .frame(width: 10)

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
            .frame(maxWidth: .infinity, alignment: .leading)

            metricCell(site.stats?.visitors, site.stats?.comparison?.visitors)
            metricCell(site.stats?.pageviews, site.stats?.comparison?.pageviews)
            metricCell(site.stats?.visits, site.stats?.comparison?.visits)
        }
    }

    private func detailStat(_ title: String, value: Double, previous: Double?, format: (Double) -> String, lowerIsBetter: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(format(value))
                    .font(.callout)
                if let previous, previous > 0 {
                    let delta = (value - previous) / previous
                    let good = lowerIsBetter ? delta < 0 : delta >= 0
                    Text(String(format: "%@%.0f%%", delta >= 0 ? "↑" : "↓", abs(delta) * 100))
                        .font(.caption2)
                        .foregroundStyle(good ? .green : .red)
                }
            }
        }
    }

    private func detailList(title: String, rows: [MetricRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            let max = rows.map(\.y).max() ?? 1
            ForEach(rows) { row in
                HStack {
                    Text(row.x.isEmpty ? "(direct)" : row.x)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(compactNumber(row.y))
                        .font(.caption.monospacedDigit())
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

    private func detailView(_ site: SiteSnapshot) -> some View {
        Group {
            if let detail = site.detail, let stats = site.stats {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 24) {
                        detailStat("Bounce rate",
                                   value: stats.visits > 0 ? stats.bounces / stats.visits : 0,
                                   previous: stats.comparison.map { $0.visits > 0 ? $0.bounces / $0.visits : 0 },
                                   format: percent,
                                   lowerIsBetter: true)
                        detailStat("Avg. visit",
                                   value: stats.visits > 0 ? stats.totaltime / stats.visits : 0,
                                   previous: stats.comparison.map { $0.visits > 0 ? $0.totaltime / $0.visits : 0 },
                                   format: { duration(seconds: $0) })
                    }
                    HStack(alignment: .top, spacing: 12) {
                        detailList(title: "Top pages", rows: detail.topPages)
                        detailList(title: "Top referrers", rows: detail.topReferrers)
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
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
        HStack(alignment: .center, spacing: 10) {
            if store.settings.isConfigured, let last = store.lastUpdated {
                Text("Updated \(relativeTime(last))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.settings.isConfigured {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Group {
                        if store.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
