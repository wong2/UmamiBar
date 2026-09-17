import Foundation
import UmamiBarCore

struct SiteDetail {
    var topPages: [MetricRow]
    var topReferrers: [MetricRow]
}

struct SiteSnapshot: Identifiable {
    let website: Website
    var stats: WebsiteStats?
    var active: Int?
    var detail: SiteDetail?
    var id: String { website.id }
}

@Observable
@MainActor
final class AppStore {
    let settings: SettingsStore
    private(set) var client: UmamiClient

    var websites: [Website] = []
    var sites: [SiteSnapshot] = []
    var range: DateRange
    var expandedSiteId: String?
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?
    private let demoMode = ProcessInfo.processInfo.environment["UMAMIBAR_DEMO"] == "1"

    var isReady: Bool { demoMode || settings.isConfigured }

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.client = UmamiClient(connection: settings.connection)
        self.range = settings.dateRange
        if demoMode {
            installDemoData()
        } else if settings.isConfigured {
            startAutoRefresh()
        }
    }

    func loadWebsites() async {
        guard !demoMode, settings.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await client.websites()
            websites = list
            sites = list.map { site in
                if let existing = sites.first(where: { $0.id == site.id }) {
                    return existing
                }
                return SiteSnapshot(website: site)
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard !demoMode, settings.isConfigured else { return }
        if websites.isEmpty {
            await loadWebsites()
        }
        let targets = websites
        guard !targets.isEmpty else { return }

        isLoading = true
        defer {
            isLoading = false
            lastUpdated = Date()
        }

        let client = self.client
        let range = self.range
        let results: [String: (stats: WebsiteStats?, active: Int?, failed: Bool)] = await withTaskGroup(
            of: (String, WebsiteStats?, Int?, Bool).self
        ) { group in
            var collected: [String: (WebsiteStats?, Int?, Bool)] = [:]
            var pending = targets.makeIterator()
            var inFlight = 0

            func enqueue(_ site: Website) {
                group.addTask {
                    do {
                        let stats = try await client.stats(websiteId: site.id, range: range)
                        let active = try await client.active(websiteId: site.id)
                        return (site.id, stats, active, false)
                    } catch {
                        return (site.id, nil, nil, true)
                    }
                }
            }

            while inFlight < 4, let site = pending.next() {
                enqueue(site)
                inFlight += 1
            }
            while let (id, stats, active, failed) = await group.next() {
                collected[id] = (stats, active, failed)
                if let site = pending.next() {
                    enqueue(site)
                }
            }
            return collected
        }

        var failures = 0
        sites = targets.map { site in
            var snap = sites.first(where: { $0.id == site.id }) ?? SiteSnapshot(website: site)
            if let result = results[site.id] {
                if result.failed {
                    failures += 1
                } else {
                    snap.stats = result.stats
                    snap.active = result.active
                }
            }
            return snap
        }
        errorMessage = failures == targets.count ? "Failed to load stats for all websites." : nil

        if let expandedSiteId {
            await loadDetail(for: expandedSiteId)
        }
    }

    func toggle(site: SiteSnapshot) {
        if expandedSiteId == site.id {
            expandedSiteId = nil
        } else {
            expandedSiteId = site.id
            Task { await loadDetail(for: site.id) }
        }
    }

    func loadDetail(for id: String) async {
        do {
            async let pages = client.metrics(websiteId: id, range: range, type: "path")
            async let referrers = client.metrics(websiteId: id, range: range, type: "referrer")
            let detail = try await SiteDetail(topPages: Array(pages.prefix(5)),
                                            topReferrers: Array(referrers.prefix(5)))
            if let index = sites.firstIndex(where: { $0.id == id }) {
                sites[index].detail = detail
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(range: DateRange) {
        self.range = range
        settings.dateRange = range
        for index in sites.indices {
            sites[index].detail = nil
        }
        Task { await refresh() }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.settings.refreshInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.refresh()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func reconfigure() {
        client = UmamiClient(connection: settings.connection)
        settings.clearSession()
        websites = []
        sites = []
        expandedSiteId = nil
        errorMessage = nil
        lastUpdated = nil
        Task {
            await loadWebsites()
            await refresh()
        }
        if settings.isConfigured {
            startAutoRefresh()
        } else {
            stopAutoRefresh()
        }
    }

    // Fabricated data for screenshots/previews: UMAMIBAR_DEMO=1
    private func installDemoData() {
        func stats(_ visitors: Double, _ views: Double, _ visits: Double,
                   _ pv: Double, _ vv: Double, _ iv: Double) -> WebsiteStats {
            WebsiteStats(pageviews: views, visitors: visitors, visits: visits,
                         bounces: visitors * 0.4, totaltime: visitors * 180,
                         comparison: .init(pageviews: pv, visitors: vv,
                                           visits: iv, bounces: 0, totaltime: 0))
        }

        let shop = Website(id: "demo-shop", name: "acme-shop.com", domain: "acme-shop.com")
        let blog = Website(id: "demo-blog", name: "blog.janedoe.dev", domain: "blog.janedoe.dev")
        let docs = Website(id: "demo-docs", name: "docs.example.io", domain: "docs.example.io")

        websites = [shop, blog, docs]
        sites = [
            SiteSnapshot(website: shop,
                         stats: stats(12438, 28412, 15937, 24300, 10765, 13770),
                         active: 43),
            SiteSnapshot(website: blog,
                         stats: stats(3214, 5870, 3990, 5375, 2980, 3720),
                         active: 8,
                         detail: SiteDetail(
                            topPages: [
                                MetricRow(x: "/", y: 2104),
                                MetricRow(x: "/posts/swiftui-menubar-apps", y: 1462),
                                MetricRow(x: "/posts/self-hosting-umami", y: 987),
                                MetricRow(x: "/about", y: 342),
                                MetricRow(x: "/posts/homelab-2025", y: 211),
                            ],
                            topReferrers: [
                                MetricRow(x: "news.ycombinator.com", y: 1203),
                                MetricRow(x: "google.com", y: 891),
                                MetricRow(x: "t.co", y: 244),
                                MetricRow(x: "reddit.com", y: 187),
                                MetricRow(x: "lobste.rs", y: 96),
                            ])),
            SiteSnapshot(website: docs,
                         stats: stats(987, 1452, 1120, 1710, 1155, 1300),
                         active: 2),
        ]
        expandedSiteId = blog.id
        lastUpdated = Date()
    }
}
