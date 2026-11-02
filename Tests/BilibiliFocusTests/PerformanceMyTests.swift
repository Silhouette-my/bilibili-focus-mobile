import Combine
import FocusCore
import Foundation
import XCTest
import SwiftUI
import UIKit
@testable import BilibiliFocus

@MainActor
final class PerformanceMyTests: XCTestCase {
    func testRemoteHistorySearchWaitsForSubmitPaginatesAndClearsToNormalHistory() async {
        let api = HistorySearchFixtureAPI()
        let model = FocusHistoryViewModel(service: FocusMyDataService(cookieProvider: PerformanceMyCookieProvider(), requestLoader: { try await api.response($0) }))
        defer { model.suspend() }
        model.query = "  remote  "
        await Task.yield()
        let beforeSubmit = await api.searches
        XCTAssertTrue(beforeSubmit.isEmpty)
        model.submitSearch()
        await eventually { model.visibleItems.count == 1 }
        XCTAssertTrue(model.isSearchingHistory)
        XCTAssertTrue(model.canLoadMore)
        model.loadMore()
        await eventually { model.visibleItems.count == 2 && !model.isLoadingMore }
        model.loadMore()
        await eventually { !model.canLoadMore && !model.isLoadingMore }
        let searches = await api.searches
        XCTAssertEqual(searches.map(\.0), ["remote", "remote", "remote"])
        XCTAssertEqual(searches.map(\.1), [1, 2, 3])
        model.query = ""
        model.clearSearchIfNeeded()
        await eventually { model.visibleItems.first?.bvid == "BV-normal" }
        XCTAssertFalse(model.isSearchingHistory)
        let normalRequests = await api.normalRequests
        XCTAssertEqual(normalRequests, 1)
    }

    func testRemoteHistoryAppendFailureKeepsResultsAndDuplicateOnlyRetryStops() async {
        let api = HistorySearchFixtureAPI()
        await api.failNextSecondPage()
        let model = FocusHistoryViewModel(service: FocusMyDataService(cookieProvider: PerformanceMyCookieProvider(), requestLoader: { try await api.response($0) }))
        defer { model.suspend() }
        model.query = "duplicate"; model.submitSearch()
        await eventually { model.visibleItems.count == 1 }
        model.loadMore()
        await eventually { model.loadMoreError != nil && !model.isLoadingMore }
        XCTAssertEqual(model.visibleItems.count, 1)
        XCTAssertTrue(model.canLoadMore)
        model.loadMore()
        await eventually { !model.canLoadMore && !model.isLoadingMore }
        model.loadMore(); await Task.yield()
        let searches = await api.searches
        XCTAssertEqual(searches.map(\.1), [1, 2, 2])
    }

    func testLateHistorySearchCannotReplaceNewQueryOrSurviveSessionReset() async {
        let api = HistorySearchFixtureAPI()
        let cookies = PerformanceMyCookieProvider()
        let model = FocusHistoryViewModel(service: FocusMyDataService(cookieProvider: cookies, requestLoader: { try await api.response($0) }))
        defer { model.suspend() }
        await api.blockOldSearch()
        model.query = "old"; model.submitSearch()
        await eventuallyAsync { await api.searches.count == 1 }
        model.query = "new"; model.submitSearch()
        await eventually { model.visibleItems.first?.bvid == "BV-new-1" }
        await api.releaseAll()
        await eventuallyAsync { await api.completed == 2 }
        XCTAssertEqual(model.visibleItems.first?.bvid, "BV-new-1")
        await api.blockOldSearch()
        model.query = "old"; model.submitSearch()
        await eventuallyAsync { await api.searches.count == 3 }
        cookies.advance(); model.resetForSessionChange()
        await api.releaseAll()
        await eventuallyAsync { await api.completed == 3 }
        if case .idle = model.state {} else { XCTFail("Old-account search must not publish after reset") }
        XCTAssertEqual(model.query, "")
        XCTAssertFalse(model.isSearchingHistory)
    }

    func testConfirmedHistoryWriteRetiresCapturedAccountAfterSessionChanges() async throws {
        let cookies = PerformanceMyCookieProvider()
        let store = FocusPlaybackProgressStore(persistence: PersonalFixturePlaybackPersistence())
        let scope = FocusPlaybackAccountScope.resolve(cookies: await cookies.loadCookies())
        _ = await store.recordProgressAndEnqueueHistory(accountScope: scope, aid: 42, bvid: "BV-DELETE", cid: 101, positionMilliseconds: 30_000)
        let service = FocusMyDataService(cookieProvider: cookies, requestLoader: { request in
            cookies.advance()
            return (Data(#"{"code":0}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, playbackProgressStore: store)
        try await service.clearHistory(version: 0)
        let pending = await store.pendingHistoryReports(accountScope: scope)
        XCTAssertTrue(pending.isEmpty, "A confirmed server deletion must not be undone by the old account's queue after login changes")
    }

    func testFolderRenamePreservesMetadataAndHistoryDeleteRetiresOutbox() async throws {
        let api = PerformanceMyAPI()
        let cookies = PerformanceMyCookieProvider()
        let store = FocusPlaybackProgressStore(persistence: PersonalFixturePlaybackPersistence())
        let service = FocusMyDataService(cookieProvider: cookies, requestLoader: { try await api.response($0) }, playbackProgressStore: store)
        try await service.renameFolder(id: 1, title: "New title", version: 0)
        let requests = await api.requests
        let rename = try XCTUnwrap(requests.first { $0.url?.path == "/x/v3/fav/folder/edit" })
        let fields = URLComponents(string: "https://fixture.invalid/?" + String(data: rename.httpBody!, encoding: .utf8)!)!.queryItems!
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["intro"], "Original intro")
        XCTAssertEqual(values["privacy"], "1")
        XCTAssertEqual(values["cover"], "original-cover")
        XCTAssertEqual(values["title"], "New title")
        let scope = FocusPlaybackAccountScope.resolve(cookies: await cookies.loadCookies())
        _ = await store.recordProgressAndEnqueueHistory(accountScope: scope, aid: 42, bvid: "BV-DELETE", cid: 101, positionMilliseconds: 30_000)
        _ = await store.recordProgressAndEnqueueHistory(accountScope: scope, aid: 43, bvid: "BV-KEEP", cid: 102, positionMilliseconds: 40_000)
        try await service.deleteHistory(key: "archive_42", version: 0)
        let pending = await store.pendingHistoryReports(accountScope: scope)
        XCTAssertEqual(pending.map(\.aid), [43])
        let resume = await store.recentProgress(accountScope: scope, aid: 42, bvid: "BV-DELETE")
        XCTAssertEqual(resume?.positionMilliseconds, 30_000)
        cookies.advance()
        do { try await service.createFolder(title: "Stale", isPrivate: false, version: 0); XCTFail("Old account generation must not mutate") }
        catch is CancellationError { }
        let after = await api.requests
        XCTAssertFalse(after.contains { $0.url?.path == "/x/v3/fav/folder/add" })
    }

    func testPersonalCenterRendersLoadedEmptyAndManagement() async throws {
        for empty in [false, true] {
            let api = PersonalCenterPresentationAPI(empty: empty)
            let cookies = PerformanceMyCookieProvider()
            let loader: FocusMyDataService.RequestLoader = { try await api.response($0) }
            let service = FocusMyDataService(cookieProvider: cookies, requestLoader: loader)
            let model = FocusMyViewModel(service: service)
            await model.refresh()
            guard case let .loaded(page) = model.state else { return XCTFail("Offline personal center fixture did not load") }
            XCTAssertEqual(page.folders.count, empty ? 0 : 3)
            let view = NavigationStack {
                FocusMyView(viewModel: model, followingService: FocusFollowingAuthorsService(cookieProvider: cookies, requestLoader: loader),
                    onOpenLogin: {}, onOpenHistory: {}, onOpenFavoriteFolder: { _ in }, onOpenVideo: { _ in }, onOpenUser: { _ in }, onOpenSettings: {})
                    .navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
            }
            try await capturePersonalView(view, name: empty ? "my-empty" : "my-loaded")
            if !empty {
                let resources = try await service.fetchFolderContents(mediaID: page.folders[0].id)
                XCTAssertEqual(resources.first?.durationText, "10:00", "Numeric duration:600 payload must render a clock, not raw seconds")
                XCTAssertEqual(FocusMyDataService.formatVideoLength("10:00", seconds: nil), "10:00")
                try await capturePersonalView(FocusMyFoldersView(viewModel: model, onOpenLogin: {}, onOpenFolder: { _ in }), name: "my-folder-management")
                let history = FocusHistoryViewModel(service: service)
                history.loadIfNeeded()
                await eventually { if case .loaded = history.state { return true }; return false }
                try await capturePersonalView(NavigationStack { FocusHistoryView(viewModel: history, onOpenVideo: { _ in }).navigationTitle("播放历史") }, name: "my-history-management")
                let folder = FocusFavoriteFolderViewModel(service: service)
                folder.open(page.folders[0])
                await eventually { if case .loaded = folder.state { return true }; return false }
                try await capturePersonalView(NavigationStack { FocusFavoriteFolderView(viewModel: folder, onOpenVideo: { _ in }).navigationTitle("学习收藏") }, name: "my-favorite-content-management")
                history.suspend(); folder.suspend()
            }
            model.suspend()
        }
    }

    private func capturePersonalView<Content: View>(_ content: Content, name: String) async throws {
        let host = UIHostingController(rootView: content.tint(.pink))
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { window = UIWindow(windowScene: scene) }
        else { window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852)) }
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(size: window.bounds.size).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(host.view.bounds.height, 800)
        window.isHidden = true
        window.rootViewController = nil
    }

    func testHistoryAndFolderReloadReleaseCancelledPagination() async {
        let api = PerformanceMyAPI()
        await api.usePaginatedLists()
        let service = FocusMyDataService(cookieProvider: PerformanceMyCookieProvider(), requestLoader: { try await api.response($0) })
        let history = FocusHistoryViewModel(service: service)
        let folder = FocusFavoriteFolderViewModel(service: service)
        defer { history.suspend(); folder.suspend() }
        history.loadIfNeeded()
        folder.open(FocusMyFolder(id: 1, title: "fixture", mediaCount: 60, coverURL: nil))
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

    func testRefreshRevokesOldFolderActionOwnership() async {
        let api = PerformanceMyAPI()
        let model = makeModel(api: api)
        defer { model.suspend() }
        await model.refresh()
        await api.block("/x/v3/fav/folder/add")
        model.saveFolder(nil, title: "New folder", isPrivate: false)
        await eventuallyAsync { await api.mutationRequests == 1 }
        XCTAssertTrue(model.isManagingFolder)
        await model.refresh()
        XCTAssertFalse(model.isManagingFolder, "Refresh must release the old generation's busy state")
        await api.releaseAll()
        await eventuallyAsync { await api.completedMutationRequests == 1 }
        XCTAssertFalse(model.isManagingFolder)
        XCTAssertNil(model.folderActionError)
    }

    func testProfileAndFolderMetadataPublishBeforeSlowHistory() async {
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
        await api.releaseAll()
        await eventually { model.sectionStates[.history] == .loaded }
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

    func testMyPageDoesNotRequestFolderContents() async {
        let api = PerformanceMyAPI()
        let model = makeModel(api: api)
        defer { model.suspend() }
        await model.refresh()
        guard case let .loaded(page) = model.state else { return XCTFail("Personal center should be visible") }
        XCTAssertEqual(page.folders.count, 12)
        let requests = await api.previewRequests
        XCTAssertEqual(requests, 0, "Folder contents are loaded only when entering a folder")
    }

    private func makeModel(api: PerformanceMyAPI, cookies: PerformanceMyCookieProvider = .init()) -> FocusMyViewModel {
        let loader: BiliAPITransport.RequestLoader = { try await api.response($0) }
        return FocusMyViewModel(
            service: FocusMyDataService(cookieProvider: cookies, requestLoader: loader)
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

private actor HistorySearchFixtureAPI {
    private(set) var searches: [(String, Int)] = []
    private(set) var normalRequests = 0
    private(set) var completed = 0
    private var blocksOld = false
    private var failsSecondPage = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func blockOldSearch() { blocksOld = true }
    func failNextSecondPage() { failsSecondPage = true }
    func releaseAll() { blocksOld = false; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
    func response(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value ?? "") })
        let items: [[String: Any]]
        if url.path == "/x/web-interface/history/search" {
            let keyword = values["keyword"]!
            let page = Int(values["pn"]!)!
            XCTAssertEqual(values["business"], "all")
            searches.append((keyword, page))
            defer { completed += 1 }
            if keyword == "old" && blocksOld { await withCheckedContinuation { waiters.append($0) } }
            if page == 2 && failsSecondPage { failsSecondPage = false; throw URLError(.notConnectedToInternet) }
            if keyword == "duplicate" { items = [item(bvid: "BV-duplicate", viewAt: 100)] }
            else { items = page <= 2 ? [item(bvid: "BV-\(keyword)-\(page)", viewAt: Int64(page))] : [] }
        } else if url.path == "/x/web-interface/history/cursor" {
            normalRequests += 1
            items = [item(bvid: "BV-normal", viewAt: 1)]
        } else { throw URLError(.unsupportedURL) }
        let payload: [String: Any] = ["code": 0, "data": ["list": items, "cursor": ["unrecognized": "opaque"]]]
        return (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    private func item(bvid: String, viewAt: Int64) -> [String: Any] {
        ["title": bvid, "cover": "", "view_at": viewAt, "duration": 600, "progress": 30,
         "history": ["bvid": bvid, "oid": 42, "business": "archive", "cid": 101]]
    }
}

private actor PersonalCenterPresentationAPI {
    let empty: Bool
    init(empty: Bool) { self.empty = empty }
    func response(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = request.url!
        let payload: [String: Any]
        switch url.path {
        case "/x/web-interface/nav": payload = ["isLogin": true, "mid": 42, "uname": "专注看视频", "level_info": ["current_level": 5]]
        case "/x/relation/stat": payload = ["following": 128, "follower": 36]
        case "/x/web-interface/history/cursor": payload = ["list": empty ? [] : [
            ["title": "从零理解光线追踪：让画面真正亮起来", "author_name": "图形学实验室", "cover": "", "view_at": 1_800_000_000, "progress": 126, "duration": 600, "history": ["bvid": "BV1xx411c7mD", "business": "archive", "oid": 42, "cid": 101, "page": 2]],
            ["title": "周末城市漫步｜把平凡的日子拍成电影", "author_name": "生活记录", "cover": "", "view_at": 1_799_999_900, "progress": 30, "duration": 180, "history": ["bvid": "BV1xx411c7mE", "business": "archive", "oid": 43, "cid": 102, "page": 1]],
        ], "cursor": ["max": 0]]
        case "/x/v3/fav/folder/created/list-all": payload = ["list": empty ? [] : [
            ["id": 1, "title": "学习收藏", "media_count": 12], ["id": 2, "title": "摄影灵感", "media_count": 8], ["id": 3, "title": "音乐现场", "media_count": 24],
        ]]
        case "/x/v3/fav/resource/list": payload = ["medias": [["id": 42, "bvid": "BV1xx411c7mD", "title": "从零理解光线追踪", "cover": "", "duration": 600, "upper": ["name": "图形学实验室"], "cnt_info": ["play": 18_000]]]]
        case "/x/web-interface/view": payload = [:]
        case "/x/web-interface/attentions": payload = ["list": []]
        case "/x/relation/followings": payload = ["total": 2, "list": [["mid": 101, "uname": "图形学实验室"], ["mid": 102, "uname": "生活记录"]]]
        default: throw URLError(.unsupportedURL)
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload]), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor PerformanceMyAPI {
    private(set) var requests: [URLRequest] = []
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
        requests.append(request)
        let url = request.url!
        let path = url.path
        let capturedName = name
        if path == "/x/web-interface/nav" { navRequests += 1 }
        let preview = path == "/x/v3/fav/resource/list"
        let mutation = path == "/x/v3/fav/folder/add"
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
        case "/x/v3/fav/folder/add": payload = [:]
        case "/x/v3/fav/folder/info": payload = ["intro": "Original intro", "attr": 1, "cover": "original-cover"]
        case "/x/v3/fav/folder/edit", "/x/v2/history/delete", "/x/v2/history/clear": payload = [:]
        default: throw URLError(.unsupportedURL)
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": payload])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private actor PersonalFixturePlaybackPersistence: FocusPlaybackStatePersistence {
    private var data: Data?
    func loadPlaybackState() -> Data? { data }
    func savePlaybackState(_ data: Data) { self.data = data }
}
