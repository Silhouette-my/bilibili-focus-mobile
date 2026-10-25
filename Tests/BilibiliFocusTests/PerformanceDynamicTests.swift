import Combine
import FocusCore
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import BilibiliFocus

@MainActor
final class PerformanceDynamicTests: XCTestCase {
    func testTextMeasurementCacheInvalidatesForWidthContentFontsAndExpansion() {
        let view = FocusDynamicTextContentView()
        let text = String(repeating: "稳定行高与缓存键。🙂\n", count: 28)
        let body = UIFont.preferredFont(forTextStyle: .body)
        let button = UIFont.preferredFont(forTextStyle: .subheadline)
        func configure(_ content: String, expanded: Bool = false, font: UIFont? = nil) {
            view.configure(text: content, expanded: expanded, bodyFont: font ?? body, buttonFont: button,
                           scale: 3, rightToLeft: false)
        }
        configure(text)
        let initial = view.measuredSize(width: 326)
        let count = view.measurementCount
        for _ in 0..<10 { configure(text); XCTAssertEqual(view.measuredSize(width: 326), initial) }
        XCTAssertEqual(view.measurementCount, count)
        configure(text, expanded: true)
        XCTAssertGreaterThan(view.measuredSize(width: 326).height, initial.height)
        configure(text)
        XCTAssertEqual(view.measuredSize(width: 326), initial)
        configure(text, font: .systemFont(ofSize: 30))
        XCTAssertGreaterThan(view.measuredSize(width: 326).height, initial.height)
        configure("短文本")
        XCTAssertLessThan(view.measuredSize(width: 326).height, initial.height)
        configure(String(repeating: "width-sensitive text ", count: 12), expanded: true)
        XCTAssertGreaterThan(view.measuredSize(width: 170).height, view.measuredSize(width: 350).height)
        for width in stride(from: 160.0, through: 460.0, by: 10) { _ = view.measuredSize(width: width) }
        XCTAssertLessThanOrEqual(view.cachedMeasurementCount, 4)
        XCTAssertEqual(view.measuredSize(width: 0), .zero)
        XCTAssertEqual(view.measuredSize(width: .infinity), .zero)
    }

    func testFoldControlHasCorrectVisibilityActionsAndAccessibility() {
        let view = FocusDynamicTextContentView()
        var toggles = 0, opens = 0
        view.onToggle = { toggles += 1 }; view.onOpen = { opens += 1 }
        func configure(_ text: String, expanded: Bool, rtl: Bool = false) {
            view.configure(text: text, expanded: expanded, bodyFont: .preferredFont(forTextStyle: .body),
                           buttonFont: .preferredFont(forTextStyle: .subheadline), scale: 3, rightToLeft: rtl)
            view.frame = CGRect(origin: .zero, size: view.measuredSize(width: 326))
            view.setNeedsLayout(); view.layoutIfNeeded()
        }
        configure("短文本", expanded: false)
        XCTAssertTrue(view.foldButton.isHidden); XCTAssertFalse(view.foldButton.isAccessibilityElement)
        view.foldButton.sendActions(for: .touchUpInside); XCTAssertEqual(toggles, 0)
        let text = String(repeating: "长文本🙂\n", count: 20)
        configure(text, expanded: false)
        XCTAssertFalse(view.foldButton.isHidden); XCTAssertTrue(view.foldButton.isAccessibilityElement)
        XCTAssertEqual(view.foldButton.accessibilityLabel, "展开全文")
        view.foldButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(toggles, 1); XCTAssertEqual(opens, 0)
        configure(text, expanded: true, rtl: true)
        XCTAssertEqual(view.foldButton.accessibilityLabel, "收起文本")
        XCTAssertEqual(view.foldButton.frame.maxX, view.bounds.width, accuracy: 0.5)
        let label = view.subviews.first { $0 is UILabel }
        XCTAssertEqual(label?.accessibilityActivate(), true); XCTAssertEqual(opens, 1)
    }

    func testSynchronousTextSizingHandlesDynamicTypeRTLUnicodeAndNarrowWidths() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let text = "Unicode 👩🏽‍💻 e\u{301} العربية与中文\n" + String(repeating: "内容不得在首次测量后再改变高度。 ", count: 40)
        let frames = TextSizingFrameEvents()
        defer { frames.stop() }
        for category: ContentSizeCategory in [.large, .extraExtraExtraLarge, .accessibilityExtraExtraExtraLarge] {
            for width: CGFloat in [220, 358] {
                let content = FocusExpandableDynamicText(text: text, onOpenCard: {}, isExpanded: .constant(false))
                    .environment(\.sizeCategory, category).environment(\.layoutDirection, .rightToLeft)
                    .environment(\.legibilityWeight, .bold)
                let host = UIHostingController(rootView: content)
                if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
                let proposal = CGSize(width: width, height: 20_000)
                let initial = host.sizeThatFits(in: proposal)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: width, height: max(844, initial.height + 20))
                window.rootViewController = host; window.makeKeyAndVisible()
                host.view.frame = window.bounds; window.layoutIfNeeded()
                for _ in 0..<3 { await frames.next() }
                let mounted = host.sizeThatFits(in: proposal)
                XCTAssertGreaterThan(initial.height, 0)
                XCTAssertEqual(initial.height, mounted.height, accuracy: 1, "\(category), width \(width)")
                XCTAssertEqual(initial.width, width, accuracy: 1)
                if category == .large, width == 358 {
                    let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Synchronous text RTL"; attachment.lifetime = .keepAlways; add(attachment)
                }
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }

    func testCollapsedTextInitialSizingMatchesMountedAndRemountedCard() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let text = String(repeating: "未展开的长文本不能在首轮布局之后插入按钮改变高度。\n", count: 28)
        let card = DynamicCard(id: "collapsed-sizing", kind: .text,
            author: .init(name: "Fixture", avatarURL: nil), publishTime: "fixture", text: text,
            coverURLs: [], targetURL: URL(string: "https://www.bilibili.com/opus/42")!, videoURL: nil)
        var previousHeight: CGFloat?
        for _ in 0..<3 {
            let view = FocusDynamicCardView(card: card, areImagesExpanded: .constant(false),
                isTextExpanded: .constant(false), onOpenCard: {}, onOpenUser: { _ in }, onOpenImage: { _ in })
            let host = UIHostingController(rootView: view)
            if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
            let proposal = CGSize(width: 358, height: 10_000)
            let initial = host.sizeThatFits(in: proposal).height
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 358, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            window.layoutIfNeeded()
            // Never settle before capturing the first proposed size.
            let frames = TextSizingFrameEvents()
            for _ in 0..<6 { await frames.next() }
            let mounted = host.sizeThatFits(in: proposal).height
            frames.stop()
            window.isHidden = true; window.rootViewController = nil
            let attachment = XCTAttachment(string: "initial=\(initial), mounted=\(mounted)")
            attachment.name = "collapsed-text-first-layout"; attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(initial, mounted, accuracy: 1,
                "The first proposed card height must already include its fold control, without a preference-driven second pass")
            if let previousHeight { XCTAssertEqual(initial, previousHeight, accuracy: 1, "A new row instance must have the same height") }
            previousHeight = mounted
        }
    }

    func testFixtureHostDisablesLiveAccountAndNetworkInitialization() {
        XCTAssertEqual(ProcessInfo.processInfo.environment["FOCUS_FIXTURE_TESTS"], "1",
                       "The test host must receive TestAction fixture isolation; inheriting LaunchAction would initialize live state")
    }

    func testClearingFeedCacheRevokesASuspendedBackgroundRefreshWriter() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DynamicFeedSnapshotStore(fileURL: directory.appendingPathComponent("feed.json"))
        let cookies = DynamicPerformanceCookies()
        let scope = FocusPlaybackAccountScope.resolve(cookies: await cookies.loadCookies())
        try await store.save(cards: [productionCard(id: "cached")], nextOffset: nil, scope: scope, revision: 0)
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["late"], next: nil, held: true)
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: cookies, snapshotStore: store,
                                                                          requestLoader: { try await api.respond($0) }))
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventuallyAsync { await api.requestCount == 1 }
        model.clearCachedFeed()
        await eventually { model.cacheMessage != nil }
        await api.releaseAll()
        await eventuallyAsync { await api.completedCount == 1 }
        XCTAssertEqual(cards(model).map(\.id), ["cached"])
        XCTAssertFalse(model.hasPendingUpdates)
        let saved = await store.load(scope: scope)
        XCTAssertNil(saved)
    }

    func testApplyingNewDynamicsRevokesAnOldSnapshotPaginationFlight() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DynamicFeedSnapshotStore(fileURL: directory.appendingPathComponent("feed.json"))
        let cookies = DynamicPerformanceCookies()
        let scope = FocusPlaybackAccountScope.resolve(cookies: await cookies.loadCookies())
        try await store.save(cards: [productionCard(id: "cached")], nextOffset: "cached-next", scope: scope, revision: 0)
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["new"], next: "new-next", held: true)
        await api.configure("cached-next", ids: ["old-append"], next: "old-cursor", held: true)
        await api.configure("new-next", ids: ["new-append"], next: nil)
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: cookies, snapshotStore: store,
                                                                          requestLoader: { try await api.respond($0) }))
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventuallyAsync { await api.requestCount == 1 }
        model.updateScrollOffset(420)
        await api.releaseAll()
        await eventually { !model.isRefreshing && model.hasPendingUpdates }
        model.loadMore()
        await eventuallyAsync { await api.requestCount == 2 }
        XCTAssertTrue(model.isLoadingMore)
        model.updateScrollOffset(0)
        await eventually { cards(model).first?.id == "new" && !model.isRefreshing }
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertEqual(cards(model).map(\.id), ["new"])
        await api.releaseAll()
        await eventuallyAsync { await api.completedCount == 2 }
        XCTAssertEqual(cards(model).map(\.id), ["new"], "An old cursor cannot replace the accepted first page")
        model.loadMore()
        await eventually { !model.isLoadingMore && cards(model).map(\.id) == ["new", "new-append"] }
        XCTAssertFalse(model.hasMore)
        let saved = await store.load(scope: scope)
        XCTAssertEqual(saved?.cards.map(\.id), ["new", "new-append"], "Retained context cannot be persisted with an unrelated cursor")
    }

    func testColdStartShowsSnapshotThenAutomaticallyAppliesUpdatesWithoutResettingReadingState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DynamicFeedSnapshotStore(fileURL: directory.appendingPathComponent("feed.json"))
        let cookies = DynamicPerformanceCookies()
        let scope = FocusPlaybackAccountScope.resolve(cookies: await cookies.loadCookies())
        let cached = productionCard(id: "cached")
        try await store.save(cards: [cached], nextOffset: "cached-next", scope: scope, revision: 0)
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["new"], next: "new-next", held: true)
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: cookies, snapshotStore: store,
                                                                          requestLoader: { try await api.respond($0) }))
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventuallyAsync { await api.requestCount == 1 }
        XCTAssertEqual(cards(model).map(\.id), ["cached"])
        model.updateScrollOffset(420)
        let revision = model.dataRevision
        await api.releaseAll()
        await eventually { model.hasPendingUpdates && !model.isRefreshing }
        XCTAssertEqual(cards(model).map(\.id), ["cached"])
        XCTAssertEqual(model.scrollOffsetY, 420)
        XCTAssertEqual(model.dataRevision, revision)
        model.updateScrollOffset(0)
        await eventually { cards(model).map(\.id) == ["new"] }
        XCTAssertFalse(model.hasPendingUpdates)
    }

    func testAutomaticRefreshRequiresSixtySecondsVisibilityAndForeground() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["initial"], next: nil)
        var now = Date()
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: DynamicPerformanceCookies(),
            snapshotStore: .init(fileURL: nil), requestLoader: { try await api.respond($0) }), now: { now })
        defer { model.suspend() }
        await model.refresh()
        now.addTimeInterval(59)
        model.setVisibility(false)
        model.setVisibility(true)
        model.loadIfNeeded()
        model.refreshAutomaticallyIfDue()
        var count = await apiCount(api)
        XCTAssertEqual(count, 1, "Quick detail returns must not issue a request")
        now.addTimeInterval(1)
        model.setVisibility(false)
        model.refreshAutomaticallyIfDue()
        count = await apiCount(api)
        XCTAssertEqual(count, 1)
        model.setApplicationActive(false)
        model.setVisibility(true)
        model.loadIfNeeded()
        model.refreshAutomaticallyIfDue()
        count = await apiCount(api)
        XCTAssertEqual(count, 1)
        await api.configure("", ids: ["new", "initial"], next: nil)
        model.setApplicationActive(true)
        await eventually { cards(model).first?.id == "new" && !model.isRefreshing }
        count = await apiCount(api)
        XCTAssertEqual(count, 2)
        model.setVisibility(false)
        model.setVisibility(true)
        model.loadIfNeeded()
        count = await apiCount(api)
        XCTAssertEqual(count, 2)
    }

    func testAutomaticRefreshWaitsForInteractionThenAppliesWithoutAButton() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["old"], next: nil)
        var now = Date()
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: DynamicPerformanceCookies(),
            snapshotStore: .init(fileURL: nil), requestLoader: { try await api.respond($0) }), now: { now })
        defer { model.suspend() }
        await model.refresh()
        model.updateScrollOffset(420)
        let revision = model.dataRevision
        model.scrollAnchor.applyContentUpdate = { _ in false }
        now.addTimeInterval(60)
        await api.configure("", ids: ["new", "old"], next: nil)
        model.refreshAutomaticallyIfDue()
        await eventually { model.hasPendingUpdates && !model.isRefreshing }
        XCTAssertEqual(cards(model).map(\.id), ["old"])
        model.updateScrollOffset(0)
        model.scrollAnchor.applyContentUpdate = { update in update(); return true }
        model.markDisplayed()
        await eventually { !model.hasPendingUpdates }
        XCTAssertEqual(cards(model).map(\.id), ["new", "old"])
        XCTAssertEqual(model.scrollOffsetY, 0)
        XCTAssertEqual(model.dataRevision, revision + 1)
    }

    func testAutomaticHeadResetsPaginationToItsOwnCursor() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["a", "b"], next: "old-next")
        await api.configure("old-next", ids: ["c", "d"], next: "tail")
        await api.configure("new-next", ids: ["e"], next: nil)
        var now = Date()
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: DynamicPerformanceCookies(),
            snapshotStore: .init(fileURL: nil), requestLoader: { try await api.respond($0) }), now: { now })
        defer { model.suspend() }
        await model.refresh()
        model.loadMore()
        await eventually { cards(model).count == 4 && !model.isLoadingMore }
        now.addTimeInterval(60)
        await api.configure("", ids: ["new", "a", "b"], next: "new-next")
        model.refreshAutomaticallyIfDue()
        await eventually { cards(model).first?.id == "new" && !model.isRefreshing }
        XCTAssertEqual(cards(model).map(\.id), ["new", "a", "b"])
        model.loadMore()
        await eventually { !model.hasMore && !model.isLoadingMore }
        XCTAssertEqual(cards(model).map(\.id), ["new", "a", "b", "e"])
    }

    func testTopAutomaticRefreshReplacesUnrelatedHeadsAndCanPublishAnEmptyPage() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["initial"], next: "initial-next")
        var now = Date()
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: DynamicPerformanceCookies(),
            snapshotStore: .init(fileURL: nil), requestLoader: { try await api.respond($0) }), now: { now })
        defer { model.suspend() }
        await model.refresh()
        for id in ["new-head", "another-unrelated-head"] {
            now.addTimeInterval(60)
            await api.configure("", ids: [id], next: "\(id)-next")
            model.refreshAutomaticallyIfDue()
            await eventually { !model.isRefreshing && cards(model).map(\.id) == [id] }
        }
        now.addTimeInterval(60)
        await api.configure("", ids: [], next: nil)
        model.refreshAutomaticallyIfDue()
        await eventually { !model.isRefreshing && cards(model).isEmpty }
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.hasPendingUpdates)
        XCTAssertEqual(model.scrollOffsetY, 0)
    }

    func testDeepReadingKeepsItsPagesUntilReturningToTopThenDiscardsTheOldCursor() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["already-read", "reading", "following"], next: "old-next")
        var now = Date()
        let model = FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: DynamicPerformanceCookies(),
            snapshotStore: .init(fileURL: nil), requestLoader: { try await api.respond($0) }), now: { now })
        defer { model.suspend() }
        await model.refresh()
        model.updateScrollOffset(420)
        now.addTimeInterval(60)
        await api.configure("", ids: ["new-head"], next: "new-next")
        model.refreshAutomaticallyIfDue()
        await eventually { !model.isRefreshing && model.hasPendingUpdates }
        XCTAssertEqual(cards(model).map(\.id), ["already-read", "reading", "following"])
        now.addTimeInterval(60)
        await api.configure("", ids: ["top-head"], next: nil)
        model.refreshAutomaticallyIfDue()
        await eventuallyAsync { await api.completedCount == 3 }
        XCTAssertEqual(cards(model).map(\.id), ["already-read", "reading", "following"], "Later 60s checks still fetch without rebuilding a deep reading list")
        model.updateScrollOffset(0)
        await eventually { !model.isRefreshing && cards(model).first?.id == "top-head" }
        XCTAssertEqual(cards(model).map(\.id), ["top-head"])
        XCTAssertFalse(model.hasMore)
    }

    private func apiCount(_ api: DynamicPerformanceAPI) async -> Int { await api.requestCount }

    func testFirstPagePublishesWithoutSecondPageAndEmptyContinuationIsBounded() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: [], next: "a")
        await api.configure("a", ids: ["1", "1", "2"], next: "a", held: true)
        let model = makeModel(api)
        defer { model.suspend() }
        model.selectFilter(.video)
        await model.refresh()
        XCTAssertEqual(cards(model).count, 0)
        XCTAssertTrue(model.hasMore, "A filtered/empty page must retain an explicit continuation")
        let initialCount = await api.requestCount
        XCTAssertEqual(initialCount, 1, "The first page must not await or fetch an unsolicited second page")
        model.loadMore()
        model.loadMore()
        await eventuallyAsync { await api.requestCount == 2 }
        XCTAssertEqual(cards(model).count, 0)
        XCTAssertTrue(model.isLoadingMore)
        await api.releaseAll()
        await eventually { !model.isLoadingMore }
        XCTAssertEqual(cards(model).map(\.id), ["1", "2"])
        XCTAssertFalse(model.hasMore, "Repeated cursor must terminate, even if the server says has_more")
        model.loadMore()
        let finalCount = await api.requestCount
        XCTAssertEqual(finalCount, 2)
    }

    func testRefreshAndAppendFailureKeepContentAndExposeLocalRetry() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["original"], next: "a")
        let model = makeModel(api)
        defer { model.suspend() }
        await model.refresh()
        await api.configure("", ids: [], next: nil, fails: true)
        await model.refresh()
        XCTAssertEqual(cards(model).map(\.id), ["original"])
        XCTAssertNotNil(model.refreshErrorMessage, "Stale-if-error must not disguise a failed explicit refresh")
        await api.configure("a", ids: [], next: nil, fails: true)
        model.loadMore()
        await eventually { model.appendErrorMessage != nil }
        XCTAssertEqual(cards(model).map(\.id), ["original"])
        await api.configure("a", ids: ["next"], next: "terminal", hasMore: false)
        model.loadMore()
        await eventually { !model.isLoadingMore && cards(model).count == 2 }
        XCTAssertNil(model.appendErrorMessage)
        XCTAssertFalse(model.hasMore)
    }

    func testOldSessionResponseCannotPublishAndHiddenFeedCannotAppend() async {
        let api = DynamicPerformanceAPI()
        let cookies = DynamicPerformanceCookies()
        await api.configure("", ids: ["old"], next: "old-next", held: true)
        let model = makeModel(api, cookies: cookies)
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventuallyAsync { await api.requestCount == 1 }
        cookies.advance()
        model.resetForSessionChange()
        await api.configure("", ids: ["new"], next: "next")
        model.loadIfNeeded()
        await eventually { cards(model).map(\.id) == ["new"] }
        await api.releaseAll()
        await eventuallyAsync { await api.completedCount == 2 }
        XCTAssertEqual(cards(model).map(\.id), ["new"])
        model.setVisibility(false)
        model.loadMore()
        let count = await api.requestCount
        XCTAssertEqual(count, 2)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testConfirmedUnchangedAccountRestartsAnInterruptedInitialRequest() async {
        let api = DynamicPerformanceAPI()
        let cookies = DynamicPerformanceCookies()
        await api.configure("", ids: ["old-snapshot"], next: nil, held: true)
        let model = makeModel(api, cookies: cookies)
        defer { model.suspend() }
        model.loadIfNeeded()
        await eventuallyAsync { await api.requestCount == 1 }
        cookies.advance() // Same synthetic credential, new authoritative snapshot.
        await api.configure("", ids: ["current-snapshot"], next: nil)
        model.reconcileSessionVersion(cookies.sessionVersion)
        await eventually { cards(model).map(\.id) == ["current-snapshot"] }
        await api.releaseAll()
        await eventuallyAsync { await api.completedCount == 2 }
        XCTAssertEqual(cards(model).map(\.id), ["current-snapshot"])
        XCTAssertNil(model.refreshErrorMessage)
    }

    func testLateAppendCannotPolluteChangedFilterOrFreshPage() async {
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["first"], next: "a")
        await api.configure("a", ids: ["late"], next: nil, held: true)
        let model = makeModel(api)
        defer { model.suspend() }
        await model.refresh()
        model.loadMore()
        await eventuallyAsync { await api.requestCount == 2 }
        model.selectFilter(.video)
        await api.configure("", ids: ["fresh"], next: nil)
        await model.refresh()
        await api.releaseAll()
        await eventuallyAsync { await api.completedCount == 3 }
        XCTAssertEqual(cards(model).map(\.id), ["fresh"])
        XCTAssertEqual(model.selectedFilter, .video)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testRefreshDisplayDiagnosticDoesNotCountRetainedRows() async {
        BiliPerformanceStore.shared.clear()
        let api = DynamicPerformanceAPI()
        await api.configure("", ids: ["first"], next: nil)
        let model = makeModel(api)
        defer { model.suspend() }
        await model.refresh()
        model.markDisplayed()
        XCTAssertEqual(displayCount, 1)
        await api.configure("", ids: ["new"], next: nil, held: true)
        let refresh = Task { await model.refresh() }
        await eventuallyAsync { await api.requestCount == 2 }
        model.markDisplayed()
        XCTAssertEqual(displayCount, 1, "Old retained rows cannot end the new display span")
        await api.releaseAll()
        await refresh.value
        model.markDisplayed()
        XCTAssertEqual(displayCount, 2)
    }

    func testExpansionStateSurvivesBindingsAndIsBoundedByStableID() {
        let model = makeModel(DynamicPerformanceAPI())
        let card = productionCard()
        model.expansionBinding(for: card, images: false).wrappedValue = true
        model.expansionBinding(for: card, images: true).wrappedValue = true
        XCTAssertTrue(model.expansionBinding(for: card, images: false).wrappedValue)
        XCTAssertTrue(model.expansionBinding(for: card, images: true).wrappedValue)
        let changed = productionCard(text: "changed content")
        XCTAssertFalse(model.expansionBinding(for: changed, images: false).wrappedValue)
        for index in 0..<600 {
            model.expansionBinding(for: productionCard(id: "row-\(index)"), images: false).wrappedValue = true
        }
        XCTAssertLessThanOrEqual(model.expansionStates.count, 512)
        model.resetForSessionChange()
        XCTAssertTrue(model.expansionStates.isEmpty)
    }

    func testActualLongTextMultiImageCardKeepsScreenPositionAcrossRepeatedRemountAndPagination() async throws {
        let feed = makeModel(DynamicPerformanceAPI())
        let card = productionCard()
        feed.expansionBinding(for: card, images: false).wrappedValue = true
        feed.expansionBinding(for: card, images: true).wrappedValue = true
        let model = ProductionDynamicHarnessModel(feed: feed, card: card)
        let host = UIHostingController(rootView: ProductionDynamicHarness(model: model))
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        window.layoutIfNeeded()
        defer { window.isHidden = true; window.rootViewController = nil; feed.suspend() }
        await eventually { self.scrollView(in: host.view) != nil }
        let scroll = try XCTUnwrap(scrollView(in: host.view))
        func screenFrame() -> CGRect {
            guard let marker = model.marker else { return .zero }
            return marker.convert(marker.bounds, to: window)
        }
        model.offset = 820
        model.revision += 1
        await eventually {
            screenFrame().height > 1_000 && abs(scroll.contentOffset.y + scroll.adjustedContentInset.top - 820) < 2
                && model.anchor.scrollView === scroll && model.anchor.frame(for: card.id) != nil
        }
        XCTAssertGreaterThan(screenFrame().height, 1_000, "The expanded production card must be physically laid out")
        XCTAssertEqual(scroll.contentOffset.y + scroll.adjustedContentInset.top, 820, accuracy: 2,
                       "The bridge input is a normalized offset, not UIKit's inset-adjusted raw offset")
        model.anchor.capture(preferredID: card.id)
        let snapshot = try XCTUnwrap(model.anchor.snapshot)
        XCTAssertEqual(snapshot.id, card.id)
        let originalY = screenFrame().minY
        let originalHeight = screenFrame().height
        XCTAssertGreaterThanOrEqual(originalY, 0)
        XCTAssertLessThan(originalY, scroll.bounds.height)
        for pass in 1...4 {
            model.active = false
            await eventually { !model.observedActive }
            XCTAssertFalse(model.observedActive, "The hidden layout must be delivered before remount")
            model.rowEpoch += 1  // Reconstruct the real card, not a fixed-height surrogate.
            model.leadingHeight += 22
            model.tailRows += 1 // A pagination boundary changes the list's content size.
            // A lazy row need not be materialized while restoration is suspended.
            // Reactivate first, then require the replacement (not its former
            // instance) to reach layout at the original on-screen position.
            model.active = true
            await eventually {
                model.observedActive && model.measuredEpoch == model.rowEpoch
                    && abs(screenFrame().height - originalHeight) < 2
                    && abs(screenFrame().minY - originalY) <= 2
            }
            XCTAssertEqual(model.measuredEpoch, model.rowEpoch, "Replacement row must reach layout")
            XCTAssertEqual(screenFrame().height, originalHeight, accuracy: 2, "Expanded replacement must preserve its height")
            XCTAssertEqual(screenFrame().minY, originalY, accuracy: 2,
                           "Return \(pass): offset=\(scroll.contentOffset.y), epoch=\(model.measuredEpoch), anchor=\(String(describing: model.anchor.snapshot)), contentFrame=\(String(describing: model.anchor.frame(for: card.id)))")
            XCTAssertTrue(feed.expansionBinding(for: card, images: true).wrappedValue)
            XCTAssertTrue(feed.expansionBinding(for: card, images: false).wrappedValue)
        }
    }

    private var displayCount: Int { BiliPerformanceStore.shared.snapshot().filter { $0.stage == .dynamicDisplayed && $0.outcome == .success }.count }
    private func makeModel(_ api: DynamicPerformanceAPI, cookies: DynamicPerformanceCookies = .init()) -> FocusDynamicFeedViewModel {
        FocusDynamicFeedViewModel(service: DynamicFeedService(cookieProvider: cookies, snapshotStore: .init(fileURL: nil),
                                                             requestLoader: { try await api.respond($0) }))
    }
    private func cards(_ model: FocusDynamicFeedViewModel) -> [DynamicCard] {
        guard case let .loaded(cards) = model.state else { return [] }
        return cards
    }
    private func productionCard(id: String = "actual-card", text: String = String(repeating: "长文本真实动态卡片，检查展开状态和返回位置。\n", count: 32)) -> DynamicCard {
        DynamicCard(id: id, kind: .image, author: .init(name: "Fixture author", avatarURL: nil), publishTime: "fixture",
                    text: text, coverURLs: (0..<6).map { URL(string: "https://focus-image.test/\($0).png")! },
                    targetURL: URL(string: "https://www.bilibili.com/opus/42")!, videoURL: nil)
    }
    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(condition(), "Expected controlled layout/state event", file: file, line: line)
    }
    private func eventuallyAsync(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        let satisfied = await condition()
        XCTAssertTrue(satisfied, "Expected controlled request event", file: file, line: line)
    }
}

private final class DynamicPerformanceCookies: CookieSnapshotProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var version: UInt64 = 0
    var sessionVersion: UInt64 { lock.withLock { version } }
    var sessionReadiness: CookieSessionReadiness { .authenticated }
    func advance() { lock.withLock { version += 1 } }
    func loadCookies() async -> [HTTPCookie] {
        [HTTPCookie(properties: [.domain: ".bilibili.com", .path: "/", .name: "SESSDATA", .value: "synthetic-only"])!]
    }
}

private actor DynamicPerformanceAPI {
    private struct Page { let ids: [String]; let next: String?; let hasMore: Bool; let held: Bool; let fails: Bool }
    private var pages: [String: Page] = [:]
    private var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    private(set) var completedCount = 0
    func configure(_ offset: String, ids: [String], next: String?, hasMore: Bool = true, held: Bool = false, fails: Bool = false) {
        pages[offset] = Page(ids: ids, next: next, hasMore: hasMore, held: held, fails: fails)
    }
    func releaseAll() {
        let continuations = pending; pending.removeAll()
        continuations.forEach { $0.resume() }
    }
    func respond(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value ?? ""
        let page = pages[offset] ?? Page(ids: [], next: nil, hasMore: false, held: false, fails: false)
        requestCount += 1
        defer { completedCount += 1 }
        if page.held { await withCheckedContinuation { pending.append($0) } }
        // Intentionally ignore cancellation: production generation checks must fence late responses.
        if page.fails { throw URLError(.notConnectedToInternet) }
        let items: [[String: Any]] = page.ids.map { id in
            ["id_str": id, "type": "DYNAMIC_TYPE_AV", "modules": [
                "module_author": ["name": "fixture"],
                "module_dynamic": ["desc": ["text": id], "major": ["archive": [
                    "title": id, "bvid": "BV1xx411c7mD", "jump_url": "https://www.bilibili.com/video/BV1xx411c7mD/"
                ]]]
            ]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["code": 0, "data": ["items": items, "offset": page.next ?? "", "has_more": page.hasMore]])
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private final class ProductionDynamicHarnessModel: ObservableObject {
    let feed: FocusDynamicFeedViewModel
    let card: DynamicCard
    let anchor = FocusDynamicFeedVisualAnchor()
    @Published var active = true
    @Published var offset: CGFloat = 0
    @Published var revision = 0
    @Published var rowEpoch = 0
    @Published var leadingHeight: CGFloat = 900
    @Published var tailRows = 8
    var observedActive = false
    var measuredEpoch = -1
    weak var marker: UIView?
    init(feed: FocusDynamicFeedViewModel, card: DynamicCard) { self.feed = feed; self.card = card }
}

@MainActor
private struct ProductionDynamicHarness: View {
    @ObservedObject var model: ProductionDynamicHarnessModel
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Color.clear.frame(height: model.leadingHeight)
                FocusDynamicCardView(card: model.card,
                    areImagesExpanded: model.feed.expansionBinding(for: model.card, images: true),
                    isTextExpanded: model.feed.expansionBinding(for: model.card, images: false),
                    onOpenCard: {}, onOpenUser: { _ in }, onOpenImage: { _ in })
                    .background(ProductionCardProbe(epoch: model.rowEpoch) { view, epoch in
                        model.marker = view
                        model.measuredEpoch = epoch
                    })
                    .focusDynamicFeedAnchor(id: model.card.id, anchor: model.anchor)
                    .id(model.rowEpoch)
                ForEach(0..<model.tailRows, id: \.self) { _ in Color.clear.frame(height: 120) }
            }
            .padding(.horizontal, 16)
            .coordinateSpace(name: FocusDynamicFeedVisualAnchor.coordinateSpace)
            .background {
                ProductionScrollBridge(model: model).frame(width: 0, height: 0)
            }
        }
    }
}

@MainActor
private struct ProductionCardProbe: UIViewRepresentable {
    let epoch: Int
    let onResolve: (UIView, Int) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        onResolve(view, epoch)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { onResolve(view, epoch) }
}

@MainActor
final class TextSizingFrameEvents: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void, Never>?
    func next() async {
        if link == nil {
            link = CADisplayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        await withCheckedContinuation { continuation = $0 }
    }
    @objc private func tick() { let pending = continuation; continuation = nil; pending?.resume() }
    func stop() { link?.invalidate(); link = nil; tick() }
}

/// Observe the production coordinator after it actually receives activation,
/// rather than treating an unrelated SwiftUI geometry preference as an ACK.
@MainActor
private struct ProductionScrollBridge: UIViewRepresentable {
    @ObservedObject var model: ProductionDynamicHarnessModel
    func makeCoordinator() -> FocusDynamicFeedScrollBridge.Coordinator { .init() }
    func makeUIView(context: Context) -> FocusDynamicFeedScrollProbeView {
        let view = FocusDynamicFeedScrollProbeView()
        view.isUserInteractionEnabled = false
        apply(to: view, coordinator: context.coordinator)
        return view
    }
    func updateUIView(_ view: FocusDynamicFeedScrollProbeView, context: Context) {
        apply(to: view, coordinator: context.coordinator)
    }
    private func apply(to view: FocusDynamicFeedScrollProbeView, coordinator: FocusDynamicFeedScrollBridge.Coordinator) {
        coordinator.update(probe: view, offsetY: model.offset, restorationRevision: model.revision,
                           isActive: model.active, visualAnchor: model.anchor,
                           onOffsetChange: { model.offset = $0 })
        model.observedActive = model.active
    }
    static func dismantleUIView(_ view: FocusDynamicFeedScrollProbeView, coordinator: FocusDynamicFeedScrollBridge.Coordinator) {
        view.onDidMoveToWindow = nil
        coordinator.detach()
    }
}
