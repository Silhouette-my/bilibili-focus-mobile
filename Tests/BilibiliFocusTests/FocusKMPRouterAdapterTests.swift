import FocusCore
import Foundation
import XCTest
@testable import BilibiliFocus

final class FocusKMPRouterAdapterTests: XCTestCase {
    func testSharedRouterMatchesSwiftHomepageFixtures() throws {
        struct Fixture {
            let name: String
            let rawURL: String
            let redirectEnabled: Bool
            let defaultEntry: FocusCore.FocusEntry
            let expected: FocusCore.FocusEntry?
        }

        let fixtures = [
            Fixture(
                name: "www",
                rawURL: "https://www.bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "bare host",
                rawURL: "https://bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "mobile",
                rawURL: "https://m.bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "no trailing slash",
                rawURL: "https://www.bilibili.com",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "index query fragment",
                rawURL: "https://www.bilibili.com/index.html?spm_id_from=333#reply",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "uppercase scheme and host",
                rawURL: "HTTPS://WWW.BILIBILI.COM/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "default HTTPS port",
                rawURL: "https://www.bilibili.com:443/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "userinfo",
                rawURL: "https://reader:secret@www.bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "video",
                rawURL: "https://www.bilibili.com/video/BV1TEST/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: nil
            ),
            Fixture(
                name: "dynamic host",
                rawURL: "https://t.bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: nil
            ),
            Fixture(
                name: "malicious suffix",
                rawURL: "https://www.bilibili.com.attacker.example/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: nil
            ),
            Fixture(
                name: "disabled",
                rawURL: "https://www.bilibili.com/",
                redirectEnabled: false,
                defaultEntry: .search,
                expected: nil
            ),
            Fixture(
                name: "dynamic entry",
                rawURL: "https://www.bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .dynamic,
                expected: .dynamic
            ),
            Fixture(
                name: "search entry",
                rawURL: "https://www.bilibili.com/",
                redirectEnabled: true,
                defaultEntry: .search,
                expected: .search
            ),
        ]

        for fixture in fixtures {
            let url = try XCTUnwrap(URL(string: fixture.rawURL), fixture.name)
            let settings = FocusCore.FocusSettings(
                redirectEnabled: fixture.redirectEnabled,
                defaultEntry: fixture.defaultEntry
            )
            let expectedShared = fixture.expected.map {
                FocusKMPRouterAdapter.SharedResult.redirect($0)
            } ?? .allow

            let shared = FocusKMPRouterAdapter.sharedResult(for: url, settings: settings)
            let evaluation = FocusKMPRouterAdapter.evaluate(for: url, settings: settings)

            XCTAssertEqual(shared, expectedShared, fixture.name)
            XCTAssertEqual(evaluation.shared, expectedShared, fixture.name)
            XCTAssertEqual(evaluation.baseline, fixture.expected, fixture.name)
            XCTAssertTrue(evaluation.isConsistent, fixture.name)
            XCTAssertEqual(evaluation.resolvedTarget, fixture.expected, fixture.name)
            XCTAssertEqual(
                FocusKMPRouterAdapter.redirectTarget(for: url, settings: settings),
                fixture.expected,
                fixture.name
            )
        }
    }

    func testNormalizationKeepsOnlySchemeHostAndPath() throws {
        let url = try XCTUnwrap(
            URL(string: "HTTPS://reader:secret@WWW.BILIBILI.COM:443/index.html?from=home#reply")
        )

        XCTAssertEqual(
            FocusKMPRouterAdapter.normalizedURLString(for: url),
            "https://www.bilibili.com/index.html"
        )
    }

    func testResolutionFallsBackToSwiftForMismatchOrUnmappedEntry() {
        let mismatch = FocusKMPRouterAdapter.evaluate(
            sharedResult: .redirect(.dynamic),
            baseline: .search
        )
        XCTAssertFalse(mismatch.isConsistent)
        XCTAssertEqual(mismatch.resolvedTarget, .search)

        let unmapped = FocusKMPRouterAdapter.evaluate(
            sharedResult: .unmappedEntry,
            baseline: .dynamic
        )
        XCTAssertFalse(unmapped.isConsistent)
        XCTAssertEqual(unmapped.resolvedTarget, .dynamic)

        let unavailable = FocusKMPRouterAdapter.evaluate(
            sharedResult: .unavailable,
            baseline: nil
        )
        XCTAssertFalse(unavailable.isConsistent)
        XCTAssertNil(unavailable.resolvedTarget)
    }
}
