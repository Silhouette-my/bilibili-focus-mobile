import Combine
import FocusCore
import Foundation
import XCTest
@testable import BilibiliFocus

@MainActor
final class PerformanceMyTests: XCTestCase {
    func testHistoryAndFolderReloadReleaseCancelledPagination() async {
        let api = PerformanceMyAPI()
        await api.usePaginatedLists()
        let service = FocusMyDataService(cookieProvider: PerformanceMyCookieProvider(), requestLoader: { try await api.response($0) })
        let history = FocusHistoryViewModel(service: service)
        let folder = FocusFavoriteFolderViewModel(service: service)
        defer { history.suspend(); folder.suspend() }
        history.loadIfNeeded()
        folder.open(FocusMyFolder(id: 1, title: "fixture", mediaCount: 60, coverURL: nil, previews: []))
        await eventually {
            if case .loaded = history.state, case .loaded = folder.state { return true }
            return false
        }
        await api.block("/x/web-interface/history/cursor")
        await api.block("/x/v3/fav/resource/list")
        guard case let .loaded(historyItems) = history.state,
              case let .loaded(_, folderItems) = folder.state else { return XCTFail("Initial lists") }
        history.loadMoreIfNeeded(currentItemID: historyItems.last!.id)
        folder.loadMoreIfNeeded(currentItemID: folderItems.last!.id)
        await eventuallyAsync { await api.listRequests == 4 }
        await api.stopBlocking("/x/web-interface/history/cursor")
        await api.stopBlocking("/x/v3/fav/resource/list")
        history.reload()
        folder.reload()
        await eventuallyAsync { await api.listRequests == 6 }
        await eventually {
            if case .loaded = history.state, case .loaded = folder.state { return true }
            return false
        }
        XCTAssertFalse(history.isLoadingMore)
        XCTAssertFalse(folder.isLoadingMore)
        await api.releaseAll()
    }

    func testRefreshRevokesOldWatchLaterActionOwnership() async {
        let api = PerformanceMyAPI()
        let model = makeModel(api: api)
        defer { model.suspend() }
        await model.refresh()
        await api.block("/x/v2/history/toview/del")
        model.removeFromWatchLater(aid: 42)
        await eventuallyAsync { await api.mutationRequests == 1 }
        XCTAssertTrue(model.watchLaterActionsInFlight.contains(42))
        await model.refresh()
        XCTAssertFalse(model.watchLaterActionsInFlight.contains(42), "Refresh must release the old generation's busy state")
        await api.releaseAll()
        await eventuallyAsync { await api.completedMutationRequests == 1 }
        XCTAssertTrue(model.watchLaterActionsInFlight.isEmpty)
        XCTAssertNil(model.actionErrorMessage)
    }

    func testProfileAndFolderMetadataPublishBeforeSlowSectionsAndPreviews() async {
        let api = PerformanceMyAPI()
        await api.block("/x/web-interface/history/cursor")
        await api.block("/x/v3/fav/resource/list")
        let model = makeModel(api: api)
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventually { model.sectionStates[.folders] == .loaded }
        guard case let .loaded(page) = model.state else { return XCTFail("Profile must already be visible") }
        XCTAssertEqual(page.profile.name, "Account one")
        XCTAssertEqual(page.folders.count, 12)
        XCTAssertEqual(model.sectionStates[.history], .loading)
        XCTAssertEqual(model.sectionStates[.previews], .loading)
        await api.releaseAll()
        await eventually { model.sectionStates[.history] == .loaded && model.sectionStates[.previews] == .loaded }
    }

    func testIndependentFailureAndRefreshKeepLoadedContent() async {
        let api = PerformanceMyAPI()
        let model = makeModel(api: api)
        defer { model.suspend() }
        await model.refresh()
        guard case let .loaded(original) = model.state else { return XCTFail("Initial page") }
        XCTAssertEqual(original.history.count, 1)
        await api.fail("/x/web-interface/history/cursor")
        await model.refresh()
        guard case let .loaded(refreshed) = model.state else { return XCTFail("Section failure must not erase profile") }
        XCTAssertEqual(refreshed.history.map(\.id), original.history.map(\.id))
        XCTAssertEqual(model.sectionStates[.folders], .loaded)
        guard case .failed = model.sectionStates[.history] else { return XCTFail("Failed is not empty") }
        await api.fail("/x/web-interface/nav")
        await model.refresh()
        guard case let .loaded(retained) = model.state else { return XCTFail("Refresh must retain same-account data") }
        XCTAssertEqual(retained.history.map(\.id), original.history.map(\.id))
        XCTAssertNotNil(model.refreshErrorMessage)
    }

    func testOldProfileCannotOverwriteNewSessionAfterLogout() async {
        let api = PerformanceMyAPI()
        let cookies = PerformanceMyCookieProvider()
        let model = makeModel(api: api, cookies: cookies)
        defer { model.suspend() }
        await api.block("/x/web-interface/nav")
        model.loadIfNeeded()
        await eventuallyAsync { await api.navRequests == 1 }
        cookies.advance()
        model.resetForSessionChange()
        if case .idle = model.state {} else { XCTFail("Old account must be revoked immediately") }
        await api.setName("Account two")
        await api.stopBlocking("/x/web-interface/nav")
        await model.refresh()
        guard case let .loaded(newPage) = model.state else { return XCTFail("New account") }
        XCTAssertEqual(newPage.profile.name, "Account two")
        await api.releaseAll()
        await Task.yield()
        guard case let .loaded(afterLateResult) = model.state else { return XCTFail("Late old request must not erase new account") }
        XCTAssertEqual(afterLateResult.profile.name, "Account two")
    }

    func testPreviewConcurrencyAndTotalAreBounded() async {
        let api = PerformanceMyAPI()
        await api.block("/x/v3/fav/resource/list")
        let model = makeModel(api: api)
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventuallyAsync { await api.previewRequests == 2 }
        let pending = await api.activePreviews
        XCTAssertEqual(pending, 2)
        guard case let .loaded(page) = model.state else { return XCTFail("Metadata should not wait for previews") }
        XCTAssertEqual(page.folders.count, 12)
        await api.releaseAll()
        await eventually { model.sectionStates[.previews] == .loaded }
        let requests = await api.previewRequests
        let maximum = await api.maximumActivePreviews
        XCTAssertEqual(requests, FocusMyViewModel.previewFolderLimit)
        XCTAssertLessThanOrEqual(maximum, FocusMyViewModel.previewConcurrency)
    }

    private func makeModel(api: PerformanceMyAPI, cookies: PerformanceMyCookieProvider = .init()) -> FocusMyViewModel {
        let loader: BiliAPITransport.RequestLoader = { try await api.response($0) }
        return FocusMyViewModel(
            service: FocusMyDataService(cookieProvider: cookies, requestLoader: loader),
            watchLaterService: FocusWatchLaterService(cookieProvider: cookies, requestLoader: loader)
        )
    }

    private func eventually(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Controlled event did not arrive", file: file, line: line)
    }

    private func eventuallyAsync(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        let reached = await condition()
        XCTAssertTrue(reached, "Controlled request did not arrive", file: file, line: line)
    }
}

private final class PerformanceMyCookieProvider: CookieSnapshotProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var version: UInt64 = 0
    var sessionVersion: UInt64 { lock.withLock { version } }
    var sessionReadiness: CookieSessionReadiness { .authenticated }
    func advance() { lock.withLock { version += 1 } }
    func loadCookies() async -> [HTTPCookie] {
        ["SESSDATA", "bili_jct"].map {
            HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: $0, .value: "synthetic-only"])!
        }
    }
}

private actor PerformanceMyAPI {
    private var failures: Set<String> = []
    private var blocked: Set<String> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var name = "Account one"
    private(set) var navRequests = 0
    private(set) var previewRequests = 0
    private(set) var activePreviews = 0
    private(set) var maximumActivePreviews = 0
    private(set) var mutationRequests = 0
    private(set) var completedMutationRequests = 0
    private var paginatedLists = false
    private(set) var listRequests = 0
    func usePaginatedLists() { paginatedLists = true }
    func fail(_ path: String) { failures.insert(path) }
    func block(_ path: String) { blocked.insert(path) }
    func stopBlocking(_ path: String) { blocked.remove(path) }
    func setName(_ value: String) { name = value }
    func releaseAll() {
        blocked.removeAll()
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
    func response(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let path = url.path
        let capturedName = name
        if path == "/x/web-interface/nav" { navRequests += 1 }
        let preview = path == "/x/v3/fav/resource/list"
        let mutation = path == "/x/v2/history/toview/del"
        if path == "/x/web-interface/history/cursor" || preview { listRequests += 1 }
        if mutation { mutationRequests += 1 }
        if preview {
            previewRequests += 1; activePreviews += 1
            maximumActivePreviews = max(maximumActivePreviews, activePreviews)
        }
        defer {
            if preview { activePreviews -= 1 }
            if mutation { completedMutationRequests += 1 }
        }
        if blocked.contains(path) { await withCheckedContinuation { waiters.append($0) } }
        // This fixture intentionally ignores cancellation so stale-result tests
        // exercise the production generation fence, not a cooperative loader.
        if failures.contains(path) { throw URLError(.notConnectedToInternet) }
        let payload: [String: Any]
        switch path {
        case "/x/web-interface/nav": payload = ["isLogin": true, "mid": 42, "uname": capturedName]
        case "/x/relation/stat": payload = ["following": 7, "follower": 8]
        case "/x/web-interface/history/cursor":
            let items = (0..<(paginatedLists ? 20 : 1)).map { index in
                ["title": "fixture history", "cover": "https://image.test/cover.png", "view_at": 99,
                 "history": ["bvid": "BV-fixture-\(index)"]] as [String: Any]
            }
            payload = ["list": items, "cursor": ["max": paginatedLists ? 1 : 0]]
        case "/x/v3/fav/folder/created/list-all":
            payload = ["list": (1...12).map { ["id": $0, "title": "Folder \($0)", "media_count": 3] as [String: Any] }]
        case "/x/v3/fav/resource/list":
            payload = ["medias": (0..<(paginatedLists ? 20 : 0)).map { ["bvid": "BV-fixture-\($0)", "title": "fixture"] }]
        case "/x/v2/history/toview": payload = ["list": [], "count": 0]
        case "/x/v2/history/toview/del": payload = [:]
        default: throw URLError(.unsupportedURL)
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
