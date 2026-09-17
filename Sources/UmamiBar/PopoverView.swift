import AppKit
import SwiftUI
import UmamiBarCore

struct PopoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var listHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.isReady {
                emptyState
            } else {
                header
                siteList
                if let message = store.errorMessage {
                    errorBanner(message)
                }
            }

            if store.isReady {
                Divider()
            }
            footer
        }
        .padding(12)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        .background(WindowHeightResizer(height: contentHeight))
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
            Text("UmamiBar")
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
            Text("Add your Umami Cloud API key or self-hosted server details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…") {
                openWindow(id: "settings")
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

    private static let metricWidth: CGFloat = 58
    private static let metricSpacing: CGFloat = 8
    private static let rowIndent: CGFloat = 20

    private func metricCell(_ value: Double?, _ previous: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value.map(compactNumber) ?? "–")
                .font(.callout)
                .monospacedDigit()
            deltaText(value ?? 0, previous)
                .font(.caption2)
        }
        .frame(width: Self.metricWidth, alignment: .trailing)
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: Self.metricWidth, alignment: .trailing)
    }

    private var siteList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Self.metricSpacing) {
                Spacer(minLength: 0)
                columnHeader("Visitors")
                columnHeader("Views")
                columnHeader("Visits")
            }
            .padding(.bottom, 2)

            let sorted = store.sites.sorted(by: { $0.website.name < $1.website.name })
            if sorted.isEmpty {
                Group {
                    if store.isLoading || (store.lastUpdated == nil && store.errorMessage == nil) {
                        ProgressView()
                    } else {
                        Text("No websites")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(sorted) { site in
                            HoverableButton {
                                withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
                                    store.toggle(site: site)
                                }
                            } label: {
                                rowLabel(site)
                            }

                            if store.expandedSiteId == site.id {
                                detailView(site)
                                    .padding(.leading, Self.rowIndent)
                                    .padding(.bottom, 4)
                            }

                            if site.id != sorted.last?.id {
                                Divider()
                                    .padding(.leading, Self.rowIndent)
                            }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight == 0 ? nil : min(listHeight, 400))
            }
        }
    }

    private func rowLabel(_ site: SiteSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(store.expandedSiteId == site.id ? 90 : 0))
                .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(site.website.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let active = site.active, active > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
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

            HStack(spacing: Self.metricSpacing) {
                metricCell(site.stats?.visitors, site.stats?.comparison?.visitors)
                metricCell(site.stats?.pageviews, site.stats?.comparison?.pageviews)
                metricCell(site.stats?.visits, site.stats?.comparison?.visits)
            }
        }
        .padding(.vertical, 3)
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
                .frame(maxWidth: .infinity)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailView(_ site: SiteSnapshot) -> some View {
        Group {
            if let detail = site.detail {
                HStack(alignment: .top, spacing: 12) {
                    detailList(title: "Top pages", rows: detail.topPages)
                    detailList(title: "Top referrers", rows: detail.topReferrers)
                }
                .frame(maxWidth: .infinity)
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
            if store.isReady, let last = store.lastUpdated {
                Text("Updated \(relativeTime(last))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if store.isReady {
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
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Divider()
                Button("Quit UmamiBar") {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MenuBarExtra(.window) grows its panel to fit expanding content but never
// shrinks it back, leaving dead translucent space around a centered view.
// Measure the ideal content height and resize the panel to match.
private struct WindowHeightResizer: NSViewRepresentable {
    var height: CGFloat

    final class SyncView: NSView {
        var onMoveToWindow: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { onMoveToWindow?() }
        }
    }

    final class Coordinator {
        var height: CGFloat = 0

        func sync(_ view: NSView) {
            guard height > 0,
                  let window = view.window,
                  let contentView = window.contentView else { return }
            guard abs(contentView.bounds.height - height) > 0.5 else { return }
            window.animator().setContentSize(
                NSSize(width: contentView.bounds.width, height: height)
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SyncView {
        let view = SyncView(frame: .zero)
        view.onMoveToWindow = { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            coordinator?.sync(view)
        }
        return view
    }

    func updateNSView(_ nsView: SyncView, context: Context) {
        context.coordinator.height = height
        context.coordinator.sync(nsView)
    }
}

struct HoverableButton<Label: View>: View {
    @State private var isHovering = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(HoverButtonStyle(isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

struct HoverButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : (isHovering ? 0.05 : 0)))
            )
    }
}
