import FocusCore
import Foundation
import XCTest
@testable import BilibiliFocus

@MainActor
final class FocusSearchOwnershipTests: XCTestCase {
    func testRepeatedSearchVideoRoundTripsKeepAppHierarchy() {
        withApp { app in
            app.searchKeyword = "fixture"
            app.submitSearch()
            for bvid in ["BV1xx411c7mD", "BV1zz411c7mE", "BV1xx411c7mD"] {
                app.openNativeVideo(URL(string: "https://www.bilibili.com/video/\(bvid)/")!)
                XCTAssertEqual(app.routeStack.count, 2)
                app.handleTopLevelBack()
                guard case let .searchResults(query) = app.route else {
                    return XCTFail("Each sibling video must return to native search")
                }
                XCTAssertEqual(query.keyword, "fixture")
                XCTAssertEqual(app.routeStack.count, 1)
            }
        }
    }

    func testNestedSearchVideosReturnOneAppLayerAtATime() {
        withApp { app in
            app.searchKeyword = "fixture"
            app.submitSearch()
            let first = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
            app.openNativeVideo(first)
            app.openNativeVideo(URL(string: "https://www.bilibili.com/video/BV1zz411c7mE/")!)
            app.handleTopLevelBack()
            guard case let .video(_, url) = app.route else { return XCTFail("Expected parent video") }
            XCTAssertEqual(url, first)
            app.handleTopLevelBack()
            guard case .searchResults = app.route else { return XCTFail("Expected native search") }
        }
    }

    func testQueuedBrowserVideoCannotReopenAfterReturningToSearch() async {
        let suite = "FocusSearchRoute-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = FocusAppViewModel(settingsStore: FocusSettingsStore(userDefaults: defaults))
        app.searchKeyword = "fixture"
        app.submitSearch()
        // An unrecognized video URL uses the retained web fallback.
        app.openMyVideo(URL(string: "https://www.bilibili.com/video/unsupported/")!)
        XCTAssertTrue(app.isBrowserActive)
        app.browserViewModel.openNativeVideo(URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        app.handleTopLevelBack()
        for _ in 0..<10 { await Task.yield() }
        guard case .searchResults = app.route else {
            return XCTFail("A delayed request from the dismissed browser must not reopen an old video")
        }
        XCTAssertEqual(app.routeStack.count, 1)
    }

    func testDuplicateBrowserHandoffsPushOnlyOneNativeLayer() async {
        let suite = "FocusSearchRoute-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = FocusAppViewModel(settingsStore: FocusSettingsStore(userDefaults: defaults))
        app.searchKeyword = "fixture"
        app.submitSearch()
        app.openMyVideo(URL(string: "https://www.bilibili.com/video/unsupported/")!)
        let videoURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        app.browserViewModel.openNativeVideo(videoURL)
        app.browserViewModel.openNativeVideo(videoURL)
        await eventually { app.isNativeVideoActive }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(app.routeStack.count, 3, "Duplicate WebKit callbacks must not create duplicate video layers")
        app.handleTopLevelBack()
        XCTAssertTrue(app.isBrowserActive)
        app.handleTopLevelBack()
        guard case .searchResults = app.route else { return XCTFail("Expected search after closing fallback") }
    }

    private func withApp(_ body: (FocusAppViewModel) -> Void) {
        let suite = "FocusSearchRoute-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(FocusAppViewModel(settingsStore: FocusSettingsStore(userDefaults: defaults)))
    }

    func testCachedFilterSelectionRevokesInFlightFilter() async throws {
        let api = SearchOwnershipAPI()
        let model = makeModel(api)
        defer { model.suspend() }
        model.search(SearchQuery(keyword: "cached"))
        await eventually { if case .loaded = model.state { return true }; return false }
        await api.hold("cached/bili_user/1")
        model.selectFilter(.users)
        await eventuallyAsync { await api.hasPendingRequest }
        model.selectFilter(.video)
        XCTAssertEqual(sections(model).map(\.filter), [.video])
        await api.release()
        await eventuallyAsync { await api.completedHeldRequest }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(model.selectedFilter, .video)
        XCTAssertEqual(sections(model).map(\.filter), [.video])
    }

    func testNewSearchRevokesOldPaginationAndReleasesLoadingState() async {
        let api = SearchOwnershipAPI()
        let model = makeModel(api)
        defer { model.suspend() }
        model.search(SearchQuery(keyword: "old"))
        await eventually { if case .loaded = model.state { return true }; return false }
        await api.hold("old/video/2")
        let section = sections(model)[0]
        model.loadMoreIfNeeded(currentItemID: section.items[0].id, in: section)
        await eventuallyAsync { await api.hasPendingRequest }
        model.search(SearchQuery(keyword: "new"))
        await eventually { sections(model).first?.items.first?.id == "new/all/1" }
        XCTAssertFalse(model.isLoadingMore)
        await api.release()
        await eventuallyAsync { await api.completedHeldRequest }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(sections(model).flatMap(\.items).map(\.id), ["new/all/1"])
    }

    func testRefreshWaitsForItsRequest() async {
        let api = SearchOwnershipAPI()
        let model = makeModel(api)
        defer { model.suspend() }
        model.search(SearchQuery(keyword: "refresh"))
        await eventually { if case .loaded = model.state { return true }; return false }
        await api.hold("refresh/all/1")
        var completed = false
        let refresh = Task { await model.refresh(); completed = true }
        await eventuallyAsync { await api.hasPendingRequest }
        XCTAssertFalse(completed, "Pull-to-refresh must remain active until the request finishes")
        await api.release()
        await refresh.value
        XCTAssertTrue(completed)
    }

    private func makeModel(_ api: SearchOwnershipAPI) -> FocusSearchResultsViewModel {
        FocusSearchResultsViewModel(service: SearchResultService(cookieProvider: SearchOwnershipCookies(), requestLoader: {
            try await api.respond($0)
        }))
    }

    private func sections(_ model: FocusSearchResultsViewModel) -> [SearchResultSection] {
        guard case let .loaded(sections) = model.state else { return [] }
        return sections
    }

    private func eventually(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !predicate(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    private func eventuallyAsync(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !(await predicate()), ContinuousClock.now < deadline { await Task.yield() }
        let result = await predicate()
        XCTAssertTrue(result, file: file, line: line)
    }
}

private struct SearchOwnershipCookies: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] { [] }
}

private actor SearchOwnershipAPI {
    private var heldKey: String?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var completedHeldRequest = false
    var hasPendingRequest: Bool { continuation != nil }
    func hold(_ key: String) { heldKey = key; completedHeldRequest = false }
    func release() { heldKey = nil; continuation?.resume(); continuation = nil }

    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let payload: [String: Any]
        if url.path == "/x/web-interface/nav" {
            payload = ["wbi_img": [
                "img_url": "https://image.test/7cd084941338484aae1ad9425b84077c.png",
                "sub_url": "https://image.test/4932caff0ff746eab6f01bf08b70ac45.png"
            ]]
        } else {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            func value(_ name: String, _ fallback: String) -> String { query.first { $0.name == name }?.value ?? fallback }
            let type = value("search_type", "all")
            let key = "\(value("keyword", ""))/\(type)/\(value("page", "1"))"
            let wasHeld = key == heldKey
            if wasHeld { await withCheckedContinuation { continuation = $0 } }
            // Ignore cancellation deliberately to exercise UI request ownership.
            if wasHeld { completedHeldRequest = true }
            if type == "bili_user" {
                payload = ["result": [["mid": "42", "uname": key]], "page": 1, "numPages": 1]
            } else {
                let video: [String: Any] = ["bvid": key, "title": key, "arcurl": "https://www.bilibili.com/video/BV1xx411c7mD/"]
                payload = type == "all"
                    ? ["result": [["result_type": "video", "data": [video]]]]
                    : ["result": [video], "page": 2, "numPages": 2]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
