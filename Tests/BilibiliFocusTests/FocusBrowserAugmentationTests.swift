#if canImport(UIKit)
@testable import BilibiliFocus
import WebKit
import XCTest

@MainActor
final class FocusBrowserAugmentationTests: XCTestCase {
    func testNewBrowserEntryDoesNotAdoptRetainedSearchPageAsParent() {
        let (model, webView, _, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        let searchURL = URL(string: "https://search.bilibili.com/all?keyword=fixture")!
        let videoURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        model.open(searchURL, context: .search)
        webView.pageURL = searchURL
        model.webView = webView
        model.commitNavigationState(from: webView)
        model.prepareForDismiss()
        model.webView = nil
        model.open(videoURL, context: .search)
        // WebKit reports the old document as the source of the initial load.
        model.noteUpcomingNavigation(to: videoURL, from: searchURL, navigationType: .other)
        guard case .close = model.resolveAppBackAction() else {
            return XCTFail("A fresh App route must close, not revisit a retained web search")
        }
    }

    func testCommittedWebSearchStillProvidesItsOwnBackParent() {
        let (model, webView, _, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        let searchURL = URL(string: "https://search.bilibili.com/all?keyword=fixture")!
        let videoURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        model.open(searchURL, context: .search)
        webView.pageURL = searchURL
        model.webView = webView
        model.commitNavigationState(from: webView)
        model.noteUpcomingNavigation(to: videoURL, from: searchURL, navigationType: .linkActivated)
        guard case let .navigate(parent) = model.resolveAppBackAction() else {
            return XCTFail("A committed in-browser search remains the web detail's parent")
        }
        XCTAssertEqual(parent, searchURL)
        guard case .close = model.resolveAppBackAction() else {
            return XCTFail("The parent must be consumed only once")
        }
    }

    func testRestoredCommittedWebSearchRemainsParentWithoutNewCommit() {
        let (model, webView, _, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        let searchURL = URL(string: "https://search.bilibili.com/all?keyword=fixture")!
        let videoURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        model.open(searchURL, context: .search)
        webView.pageURL = searchURL
        model.webView = webView
        model.commitNavigationState(from: webView)
        let previousSession = model.activeRouteRequestSessionID
        // A native video covers the browser, then pops back to its retained document.
        model.prepareForDismiss()
        model.resume(searchURL, context: .search)
        XCTAssertTrue(model.isSessionActive)
        XCTAssertNotEqual(model.activeRouteRequestSessionID, previousSession)
        XCTAssertFalse(model.isLoadingPage)
        model.noteUpcomingNavigation(to: videoURL, from: searchURL, navigationType: .linkActivated)
        guard case let .navigate(parent) = model.resolveAppBackAction() else {
            return XCTFail("Restoring the same committed document must retain its legitimate parent role")
        }
        XCTAssertEqual(parent, searchURL)
    }

    func testCacheExpiresAndEvictsLeastRecentlyUsedPayload() {
        var cache = FocusNativePageAugmentCache()
        let now = Date(timeIntervalSince1970: 100)
        for index in 0..<32 {
            cache.store(Self.payload(mid: Int64(index)), for: "\(index)", now: now)
        }
        XCTAssertNotNil(cache.payload(for: "0", now: now))
        cache.store(Self.payload(mid: 32), for: "32", now: now)
        XCTAssertNil(cache.payload(for: "1", now: now))
        XCTAssertNotNil(cache.payload(for: "0", now: now))
        XCTAssertNil(cache.payload(for: "0", now: now.addingTimeInterval(60)))
    }

    func testAccountResetDiscardsCachedFollowState() async {
        let (model, webView, service, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        await navigate(model, webView, to: "BV1xx411c7mD", expectedMID: 11)
        model.resetForSessionChange()
        await service.setFollowing(true)
        await navigate(model, webView, to: "BV1xx411c7mD", expectedMID: 11)
        XCTAssertTrue(model.nativeVideoAuthorIsFollowing)
        let loads = await service.loadCount
        XCTAssertEqual(loads, 2, "Account reset must reload rather than reapply the previous account's relation")
    }

    func testFollowCompletionFromPreviousPageCannotReplaceCurrentAuthor() async {
        let (model, webView, service, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        await navigate(model, webView, to: "BV1xx411c7mD", expectedMID: 11)
        XCTAssertTrue(model.handleFocusActionURL(URL(string: "focus://toggle-follow")!))
        for _ in 0..<1_000 {
            if await service.hasPendingFollow { break }
            await Task.yield()
        }
        let pending = await service.hasPendingFollow
        XCTAssertTrue(pending)
        await navigate(model, webView, to: "BV1zz411c7mE", expectedMID: 22)
        // Model a transport that completes even after its task was cancelled.
        await service.finishFollow()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.nativeVideoAuthorMID, 22)
        XCTAssertFalse(model.nativeVideoAuthorIsFollowing)
    }

    func testSameAccountVersionChangeReleasesScheduledLoadAndRejectsLatePayload() async {
        let (model, webView, service, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        await service.suspendNextLoad()
        let url = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        model.open(url, context: .dynamic)
        webView.pageURL = url
        model.webView = webView
        model.updateNavigationState(from: webView)
        for _ in 0..<1_000 {
            if await service.hasPendingLoad { break }
            await Task.yield()
        }
        let pending = await service.hasPendingLoad
        XCTAssertTrue(pending)
        await service.setFollowing(true)
        service.version.advance()
        model.reconcileSessionVersion(service.sessionVersion)
        for _ in 0..<1_000 {
            if model.nativeVideoAuthorIsFollowing { break }
            await Task.yield()
        }
        XCTAssertTrue(model.nativeVideoAuthorIsFollowing)
        await service.finishLoad()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(model.nativeVideoAuthorIsFollowing, "Late pre-rotation payload must not replace the refreshed relation")
        let loads = await service.loadCount
        XCTAssertEqual(loads, 2)
    }

    func testSameAccountVersionChangeReleasesFollowBusyState() async {
        let (model, webView, service, defaults, suite) = makeBrowser()
        defer { model.prepareForDismiss(); defaults.removePersistentDomain(forName: suite) }
        await navigate(model, webView, to: "BV1xx411c7mD", expectedMID: 11)
        let actionURL = URL(string: "focus://toggle-follow")!
        _ = model.handleFocusActionURL(actionURL)
        for _ in 0..<1_000 {
            if await service.hasPendingFollow { break }
            await Task.yield()
        }
        service.version.advance()
        model.reconcileSessionVersion(service.sessionVersion)
        _ = model.handleFocusActionURL(actionURL)
        for _ in 0..<1_000 {
            if await service.pendingFollowCount == 2 { break }
            await Task.yield()
        }
        let followCount = await service.pendingFollowCount
        XCTAssertEqual(followCount, 2, "Cookie rotation must release the previous request's busy state")
        await service.finishFollow()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(model.nativeVideoAuthorIsFollowing)
        await service.finishFollow()
        for _ in 0..<1_000 {
            if model.nativeVideoAuthorIsFollowing { break }
            await Task.yield()
        }
        XCTAssertTrue(model.nativeVideoAuthorIsFollowing)
    }

    private func makeBrowser() -> (FocusBrowserViewModel, PageWebView, AugmentService, UserDefaults, String) {
        let suite = "FocusBrowserAugmentation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = FocusBrowserViewModel(settingsStore: FocusSettingsStore(userDefaults: defaults))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = PageWebView(frame: .zero, configuration: configuration)
        let service = AugmentService()
        model.nativePageAugmentService = service
        return (model, webView, service, defaults, suite)
    }

    private func navigate(_ model: FocusBrowserViewModel, _ webView: PageWebView, to bvid: String, expectedMID: Int64) async {
        model.webView = nil
        let url = URL(string: "https://www.bilibili.com/video/\(bvid)/")!
        model.open(url, context: .dynamic)
        webView.pageURL = url
        model.webView = webView
        model.updateNavigationState(from: webView)
        for _ in 0..<1_000 {
            if model.nativeVideoAuthorMID == expectedMID { return }
            await Task.yield()
        }
        XCTFail("Expected page payload for author \(expectedMID)")
    }

    fileprivate static func payload(mid: Int64, following: Bool = false) -> FocusNativePageAugmentPayload {
        .video(FocusNativeVideoAugmentPayload(title: "Fixture", authorName: "Author \(mid)", authorAvatarURL: "", authorSpaceURL: "", authorMID: mid, authorFollowers: 100, authorFollowersText: "100", authorIsFollowing: following, groups: [], comments: []))
    }
}

@MainActor
private final class PageWebView: WKWebView {
    var pageURL: URL?
    override var url: URL? { pageURL }
}

private actor AugmentService: FocusNativePageAugmentServing {
    nonisolated let version = SessionVersion()
    nonisolated var sessionVersion: UInt64 { version.value }
    private var following = false
    private var followContinuations: [CheckedContinuation<(isFollowing: Bool, followers: Int64), Never>] = []
    private var shouldSuspendLoad = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private(set) var loadCount = 0
    var hasPendingFollow: Bool { !followContinuations.isEmpty }
    var pendingFollowCount: Int { followContinuations.count }
    var hasPendingLoad: Bool { loadContinuation != nil }

    func setFollowing(_ value: Bool) { following = value }
    func suspendNextLoad() { shouldSuspendLoad = true }
    func finishLoad() { loadContinuation?.resume(); loadContinuation = nil }

    func loadPayload(for url: URL, kind: FocusNativePageKind) async -> FocusNativePageAugmentPayload? {
        loadCount += 1
        let mid: Int64 = url.path.contains("BV1xx") ? 11 : 22
        let payload = await FocusBrowserAugmentationTests.payload(mid: mid, following: following)
        if shouldSuspendLoad {
            shouldSuspendLoad = false
            await withCheckedContinuation { loadContinuation = $0 }
        }
        return payload
    }

    func updateFollowState(mid: Int64, shouldFollow: Bool, expectedSessionVersion: UInt64) async throws -> (isFollowing: Bool, followers: Int64) {
        await withCheckedContinuation { followContinuations.append($0) }
    }

    func finishFollow() {
        if !followContinuations.isEmpty {
            followContinuations.removeFirst().resume(returning: (true, 101))
        }
    }
}

private final class SessionVersion: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: UInt64 = 0
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return storedValue }
    func advance() { lock.lock(); defer { lock.unlock() }; storedValue += 1 }
}
#endif
