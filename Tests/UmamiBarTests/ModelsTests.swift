import XCTest
@testable import UmamiBarCore

final class ModelsTests: XCTestCase {
    func testStatsNumericForm() throws {
        let json = """
        {"pageviews": 100, "visitors": 50, "visits": 60, "bounces": 20, "totaltime": 3000,
         "comparison": {"pageviews": 80, "visitors": 40, "visits": 50, "bounces": 25, "totaltime": 2500}}
        """.data(using: .utf8)!
        let stats = try JSONDecoder().decode(WebsiteStats.self, from: json)
        XCTAssertEqual(stats.pageviews, 100)
        XCTAssertEqual(stats.visitors, 50)
        XCTAssertEqual(stats.comparison?.pageviews, 80)
    }

    func testStatsValuePrevForm() throws {
        let json = """
        {"pageviews": {"value": 100, "prev": 80}, "visitors": {"value": 50, "prev": 40},
         "visits": {"value": 60, "prev": 50}, "bounces": {"value": 20, "prev": 25},
         "totaltime": {"value": 3000, "prev": 2500}}
        """.data(using: .utf8)!
        let stats = try JSONDecoder().decode(WebsiteStats.self, from: json)
        XCTAssertEqual(stats.pageviews, 100)
        XCTAssertEqual(stats.comparison?.pageviews, 80)
        XCTAssertEqual(stats.comparison?.visitors, 40)
    }

    func testWebsitesWrapped() throws {
        let json = """
        {"data": [{"id": "1", "name": "Blog", "domain": "blog.example.com"}], "count": 1}
        """.data(using: .utf8)!
        let sites = try WebsitesResult.decode(from: json)
        XCTAssertEqual(sites.count, 1)
        XCTAssertEqual(sites[0].name, "Blog")
    }

    func testWebsitesBareArray() throws {
        let json = """
        [{"id": "1", "name": "Blog", "domain": "blog.example.com"},
         {"id": "2", "name": "Shop", "domain": "shop.example.com"}]
        """.data(using: .utf8)!
        let sites = try WebsitesResult.decode(from: json)
        XCTAssertEqual(sites.count, 2)
        XCTAssertEqual(sites[1].id, "2")
    }

    func testActiveObjectForm() throws {
        let json = "{\"visitors\": 7}".data(using: .utf8)!
        let active = try JSONDecoder().decode(ActiveVisitors.self, from: json)
        XCTAssertEqual(active.visitors, 7)
    }

    func testActiveArrayForm() throws {
        let json = "[{\"x\": 4}]".data(using: .utf8)!
        let active = try JSONDecoder().decode(ActiveVisitors.self, from: json)
        XCTAssertEqual(active.visitors, 4)
    }

    func testConnectionAPIBase() {
        XCTAssertEqual(
            Connection(kind: .cloud, region: .auto, apiKey: "k").apiBase,
            "https://api.umami.is/v1")
        XCTAssertEqual(
            Connection(kind: .cloud, region: .us, apiKey: "k").apiBase,
            "https://api.umami.is/v1/us")
        XCTAssertEqual(
            Connection(kind: .cloud, region: .eu, apiKey: "k").apiBase,
            "https://api.umami.is/v1/eu")
        XCTAssertEqual(
            Connection(kind: .selfHosted, baseURL: "https://analytics.example.com/",
                       username: "u", password: "p").apiBase,
            "https://analytics.example.com/api")
    }
}
