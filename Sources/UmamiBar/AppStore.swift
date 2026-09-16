import Foundation
import UmamiBarCore

@Observable
@MainActor
final class AppStore {
    let settings: SettingsStore
    private(set) var client: UmamiClient

    var websites: [Website] = []
    var selectedWebsite: Website?
    var range: DateRange
    var stats: WebsiteStats?
    var active: Int?
    var series: PageviewsResponse?
    var topPages: [MetricRow] = []
    var topReferrers: [MetricRow] = []
    var isLoading = false
    var errorMessage: String?
    var lastUpdated: Date?

    private var refreshTask: Task<Void, Never>?

    init(settings: SettingsStore = SettingsStore()) {
        self.settings = settings
        self.client = UmamiClient(settings: settings)
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
            if let saved = settings.selectedWebsiteId, let match = list.first(where: { $0.id == saved }) {
                selectedWebsite = match
            } else {
                selectedWebsite = list.first
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let site = selectedWebsite, settings.isConfigured else { return }
        isLoading = true
        defer {
            isLoading = false
            lastUpdated = Date()
        }
        do {
            async let statsTask = client.stats(websiteId: site.id, range: range)
            async let activeTask = client.active(websiteId: site.id)
            async let seriesTask = client.pageviews(websiteId: site.id, range: range)
            async let pagesTask = client.metrics(websiteId: site.id, range: range, type: "path")
            async let referrersTask = client.metrics(websiteId: site.id, range: range, type: "referrer")

            stats = try await statsTask
            active = try await activeTask
            series = try await seriesTask
            topPages = try await pagesTask
            topReferrers = try await referrersTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(website: Website) {
        selectedWebsite = website
        settings.selectedWebsiteId = website.id
        Task { await refresh() }
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
        client = UmamiClient(settings: settings)
        settings.clearSession()
        websites = []
        selectedWebsite = nil
        stats = nil
        active = nil
        series = nil
        topPages = []
        topReferrers = []
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
