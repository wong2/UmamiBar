import Foundation
import UmamiBarCore

struct SiteSnapshot: Identifiable {
    let website: Website
    var stats: WebsiteStats?
    var active: Int?
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
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    var totalActive: Int {
        sites.compactMap(\.active).reduce(0, +)
    }

    private var refreshTask: Task<Void, Never>?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.client = UmamiClient(connection: settings.connection)
        self.range = settings.dateRange
        if settings.isConfigured {
            startAutoRefresh()
        }
    }

    func loadWebsites() async {
        guard settings.isConfigured else { return }
        do {
            let list = try await client.websites()
            websites = list
            sites = list.map { site in
                if let existing = sites.first(where: { $0.id == site.id }) {
                    return existing
                }
                return SiteSnapshot(website: site)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard settings.isConfigured else { return }
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
    }

    func select(range: DateRange) {
        self.range = range
        settings.dateRange = range
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
}
