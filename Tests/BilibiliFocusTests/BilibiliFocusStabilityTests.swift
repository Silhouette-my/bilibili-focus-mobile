import FocusCore
import UIKit
import WebKit
import XCTest
@testable import BilibiliFocus

@MainActor
final class BilibiliFocusStabilityTests: XCTestCase {
    func testArticleRoutingAcceptsOnlySupportedBilibiliVariants() {
        let variants = [
            "https://www.bilibili.com/read/cv123?from=search",
            "https://m.bilibili.com/read/cv123",
            "https://www.bilibili.com/read/mobile?id=123&from=app",
            "bilibili://article/123",
            "bilibili://article/cv123",
        ]

        for raw in variants {
            let url = URL(string: raw)!
            XCTAssertEqual(FocusArticleRouting.extractCVID(from: url), 123, raw)
            XCTAssertEqual(FocusArticleRouting.canonicalURL(for: url)?.absoluteString, "https://www.bilibili.com/read/cv123", raw)
        }
        XCTAssertNil(FocusArticleRouting.extractCVID(from: URL(string: "https://www.bilibili.com/video/BV1TEST?id=123")!))
        XCTAssertNil(FocusArticleRouting.extractCVID(from: URL(string: "https://example.com/read/cv123")!))
        XCTAssertNil(FocusArticleRouting.extractCVID(from: URL(string: "https://www.bilibili.com/read/cv123/extra")!))
    }

    func testArticleParserSupportsModernOpsAndStructuredLegacyHTML() {
        let modern = FocusMyDataService.parseArticleContent(
            ##"{"ops":[{"insert":"标题"},{"attributes":{"header":2},"insert":"\n"},{"attributes":{"bold":true,"color":"#fb7299","link":"//www.bilibili.com/video/BV1TEST"},"insert":"链接"},{"insert":"\n"},{"insert":{"native-image":{"url":"//i0.hdslb.com/article.jpg","width":1200,"height":800,"alt":"图注"}}},{"insert":{"native-video":{"title":"相关视频","bvid":"BV1TEST"}}}]}"##
        )

        XCTAssertEqual(modern.count, 4)
        guard case let .heading(headingRuns, level) = modern[0] else { return XCTFail("Expected heading") }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(headingRuns.map(\.plainText).joined(), "标题")
        guard case let .paragraph(runs, _) = modern[1],
              case let .text(value, bold, _, _, _, color, link) = runs[0]
        else { return XCTFail("Expected styled paragraph") }
        XCTAssertEqual(value, "链接")
        XCTAssertTrue(bold)
        XCTAssertEqual(color, "#fb7299")
        XCTAssertEqual(link?.absoluteString, "https://www.bilibili.com/video/BV1TEST")
        guard case let .image(imageURL, width, height, caption) = modern[2] else { return XCTFail("Expected image") }
        XCTAssertEqual(imageURL.absoluteString, "https://i0.hdslb.com/article.jpg")
        XCTAssertEqual(width, 1200)
        XCTAssertEqual(height, 800)
        XCTAssertEqual(caption, "图注")
        guard case let .resource(title, resourceURL) = modern[3] else { return XCTFail("Expected resource") }
        XCTAssertEqual(title, "相关视频")
        XCTAssertEqual(resourceURL.absoluteString, "https://www.bilibili.com/video/BV1TEST")

        let legacy = FocusMyDataService.parseArticleContent(
            #"<h2>旧版标题</h2><p style="text-align:center">普通<strong>粗体</strong><span style="color:#00a1d6">蓝色</span><a href="//www.bilibili.com/read/cv2">链接</a></p><ol><li>第一项</li><li>第二项</li></ol><pre data-lang="swift">let answer = 42</pre><figure><img data-src="//i0.hdslb.com/lazy.webp" width="640" height="360"><figcaption>图片说明</figcaption></figure><hr>"#
        )
        XCTAssertEqual(legacy.count, 6)
        guard case let .paragraph(legacyRuns, alignment) = legacy[1] else { return XCTFail("Expected legacy paragraph") }
        if case .center = alignment {} else { XCTFail("Expected centered paragraph") }
        XCTAssertEqual(legacyRuns.map(\.plainText).joined(), "普通粗体蓝色链接")
        guard case let .list(ordered, items) = legacy[2] else { return XCTFail("Expected ordered list") }
        XCTAssertTrue(ordered)
        XCTAssertEqual(items.count, 2)
        guard case let .image(_, width, height, caption) = legacy[4] else { return XCTFail("Expected lazy image") }
        XCTAssertEqual(width, 640)
        XCTAssertEqual(height, 360)
        XCTAssertEqual(caption, "图片说明")
        guard case .divider = legacy[5] else { return XCTFail("Expected divider") }
    }

    func testOldCallbackStampCannotUpdateNewNavigation() {
        let webView = WKWebView(frame: .zero)
        let oldSession = BrowserSessionID()
        let newSession = BrowserSessionID()
        let oldURL = URL(string: "https://www.bilibili.com/video/BV1OLD/")!
        let newURL = URL(string: "https://www.bilibili.com/video/BV1NEW/")!
        let oldStamp = BrowserCallbackStamp(
            sessionID: oldSession,
            revision: NavigationRevision(rawValue: 8),
            canonicalURL: oldURL,
            webViewIdentifier: ObjectIdentifier(webView)
        )
        let currentStamp = BrowserCallbackStamp(
            sessionID: newSession,
            revision: NavigationRevision(rawValue: 9),
            canonicalURL: newURL,
            webViewIdentifier: ObjectIdentifier(webView)
        )

        XCTAssertFalse(BrowserCallbackGate.accepts(oldStamp, current: currentStamp))
        XCTAssertTrue(BrowserCallbackGate.accepts(currentStamp, current: currentStamp))
    }

    func testThemeChangePreservesRouteWebViewAndPlayerSnapshot() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)
        let browserURL = URL(string: "about:blank")!
        appViewModel.openMyVideo(browserURL)
        guard case let .browser(routeURLBeforeTheme, contextBeforeTheme) = appViewModel.route else {
            return XCTFail("Expected browser route")
        }
        let webView = WKWebView(frame: .zero)
        appViewModel.browserViewModel.attach(webView: webView) { _, _ in }
        let snapshot = PlayerSnapshot(
            hasPlayer: true,
            isPlaying: true,
            playbackRate: 1.5,
            isDanmakuHidden: false,
            hasSubtitles: true,
            isSubtitleHidden: false,
            isFullscreen: false
        )
        appViewModel.browserViewModel.updatePlayerSnapshot(snapshot)
        let routeCount = appViewModel.routeStack.count
        let browserIdentity = ObjectIdentifier(webView)

        store.settings.themeMode = .dark

        XCTAssertEqual(appViewModel.routeStack.count, routeCount)
        guard case let .browser(routeURLAfterTheme, contextAfterTheme) = appViewModel.route else {
            return XCTFail("Theme change must preserve browser route")
        }
        XCTAssertEqual(routeURLAfterTheme, routeURLBeforeTheme)
        XCTAssertEqual(contextAfterTheme, contextBeforeTheme)
        XCTAssertTrue(appViewModel.browserViewModel.webView === webView)
        XCTAssertEqual(ObjectIdentifier(appViewModel.browserViewModel.webView!), browserIdentity)
        XCTAssertEqual(appViewModel.browserViewModel.playerSnapshot, snapshot)
        appViewModel.browserViewModel.detach(webView: webView)
    }

    func testAppGraphReusesOneDependencySetAcrossTheAppViewModel() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appGraph = FocusAppGraph(settingsStore: store)
        let appViewModel = appGraph.makeAppViewModel()

        XCTAssertTrue(appViewModel.settingsStore === store)
        XCTAssertTrue(appViewModel.browserViewModel === appGraph.browserViewModel)
        XCTAssertTrue(appViewModel.dynamicFeedViewModel === appGraph.dynamicFeedViewModel)
        XCTAssertTrue(appViewModel.searchResultsViewModel === appGraph.searchResultsViewModel)
        XCTAssertTrue(appViewModel.myViewModel === appGraph.myViewModel)
        XCTAssertTrue(appViewModel.historyViewModel === appGraph.historyViewModel)
        XCTAssertTrue(appViewModel.favoriteFolderViewModel === appGraph.favoriteFolderViewModel)
    }

    func testPlaybackHistorySubmissionRequiresAuthenticatedPendingWork() async {
        let cookies = await NativeVideoTestCookieProvider().loadCookies()
        XCTAssertNotNil(
            FocusPlaybackHistorySubmissionEligibility.authenticatedAccountScope(
                cookies: cookies
            )
        )
        XCTAssertNil(
            FocusPlaybackHistorySubmissionEligibility.authenticatedAccountScope(
                cookies: cookies.filter {
                    $0.name.caseInsensitiveCompare("SESSDATA") != .orderedSame
                }
            )
        )
        XCTAssertNil(
            FocusPlaybackHistorySubmissionEligibility.authenticatedAccountScope(
                cookies: cookies.filter {
                    $0.name.caseInsensitiveCompare("bili_jct") != .orderedSame
                }
            )
        )

        XCTAssertTrue(
            FocusHistoryBackgroundSchedulingPolicy.shouldSubmit(
                hasAuthenticatedPendingReports: true,
                hasPendingRequest: false
            )
        )
        XCTAssertFalse(
            FocusHistoryBackgroundSchedulingPolicy.shouldSubmit(
                hasAuthenticatedPendingReports: false,
                hasPendingRequest: false
            )
        )
        XCTAssertFalse(
            FocusHistoryBackgroundSchedulingPolicy.shouldSubmit(
                hasAuthenticatedPendingReports: true,
                hasPendingRequest: true
            )
        )
        XCTAssertTrue(
            FocusHistoryBackgroundSchedulingPolicy.shouldReschedule(
                requiresRetry: true,
                remainingCount: 1
            )
        )
        XCTAssertFalse(
            FocusHistoryBackgroundSchedulingPolicy.shouldReschedule(
                requiresRetry: false,
                remainingCount: 1
            )
        )
        XCTAssertFalse(
            FocusHistoryBackgroundSchedulingPolicy.shouldReschedule(
                requiresRetry: true,
                remainingCount: 0
            )
        )
    }

    func testSettingsCategoriesDoNotReloadForNativeOnlyPreferences() {
        let previous = FocusSettings.defaults
        var nativeOnly = previous
        nativeOnly.defaultEntry = .search
        nativeOnly.dynamicVisibleKinds = [.video]
        nativeOnly.perAuthorDynamicFilters = ["mid:1": [.articleLike]]

        XCTAssertEqual(
            FocusWebSettingsUpdate.classify(
                previous: previous,
                current: nativeOnly,
                previousDarkMode: false,
                currentDarkMode: false
            ),
            .none
        )

        var appearance = previous
        appearance.themeMode = .dark
        XCTAssertEqual(
            FocusWebSettingsUpdate.classify(
                previous: previous,
                current: appearance,
                previousDarkMode: false,
                currentDarkMode: true
            ),
            .appearance
        )

        var pageRules = previous
        pageRules.playerMaskEnabled = false
        XCTAssertEqual(
            FocusWebSettingsUpdate.classify(
                previous: previous,
                current: pageRules,
                previousDarkMode: false,
                currentDarkMode: false
            ),
            .pageRules
        )

#if DEBUG
        var debugLogging = previous
        debugLogging.debugMode = true
        XCTAssertEqual(
            FocusWebSettingsUpdate.classify(
                previous: previous,
                current: debugLogging,
                previousDarkMode: false,
                currentDarkMode: false
            ),
            .pageRules
        )
#endif
    }

    func testWebContentRecoveryHasOneAutomaticAttemptAndThenShowsRetry() {
        let url = URL(string: "https://www.bilibili.com/video/BV1RECOVER/")!
        XCTAssertEqual(
            WebContentRecoveryPolicy.decision(
                isSessionActive: true,
                attempts: 0,
                recoveryURL: url
            ),
            .recover(url)
        )

        guard case .showRetry = WebContentRecoveryPolicy.decision(
            isSessionActive: true,
            attempts: 1,
            recoveryURL: url
        ) else {
            return XCTFail("Second process termination must expose manual retry")
        }
        guard case .showRetry = WebContentRecoveryPolicy.decision(
            isSessionActive: true,
            attempts: 0,
            recoveryURL: nil
        ) else {
            return XCTFail("Missing recovery URL must expose manual retry")
        }
        XCTAssertEqual(
            WebContentRecoveryPolicy.decision(
                isSessionActive: false,
                attempts: 0,
                recoveryURL: url
            ),
            .inactive
        )
    }

    func testNestedSameTypeRoutesHaveIndependentStateAndCompleteBackStack() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)
        let firstURL = URL(string: "https://space.bilibili.com/1001")!
        let secondURL = URL(string: "https://space.bilibili.com/1002")!

        appViewModel.openNativeUserSpace(firstURL)
        guard case let .userSpace(firstID, _) = appViewModel.route else {
            return XCTFail("Expected first user-space route")
        }
        let firstViewModel = appViewModel.userSpaceViewModel(for: firstID)

        appViewModel.openNativeUserSpace(secondURL)
        guard case let .userSpace(secondID, _) = appViewModel.route else {
            return XCTFail("Expected nested user-space route")
        }

        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(appViewModel.routeStack.count, 3)
        XCTAssertFalse(firstViewModel.hasActiveLoadTask)
        XCTAssertFalse(firstViewModel === appViewModel.userSpaceViewModel(for: secondID))

        appViewModel.handleTopLevelBack()
        guard case let .userSpace(restoredID, restoredURL) = appViewModel.route else {
            return XCTFail("Expected first user-space route after pop")
        }
        XCTAssertEqual(restoredID, firstID)
        XCTAssertEqual(restoredURL, firstURL)
        XCTAssertTrue(firstViewModel === appViewModel.userSpaceViewModel(for: restoredID))

        appViewModel.handleTopLevelBack()
        XCTAssertEqual(appViewModel.routeStack.count, 1)
        guard case .dynamicFeed = appViewModel.route else {
            return XCTFail("Expected root route after complete pop")
        }
    }

    func testHiddenNativePageCancelsLoadingTask() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)

        appViewModel.openNativeUserSpace(URL(string: "https://space.bilibili.com/2001")!)
        guard case let .userSpace(routeID, _) = appViewModel.route else {
            return XCTFail("Expected user-space route")
        }
        let hiddenViewModel = appViewModel.userSpaceViewModel(for: routeID)

        appViewModel.openNativeUserSpace(URL(string: "https://space.bilibili.com/2002")!)

        XCTAssertFalse(hiddenViewModel.hasActiveLoadTask)
    }

    func testRecognizedVideosUseIndependentNativeRoutesAndCompleteBackStack() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)
        let firstURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        let secondURL = URL(string: "https://www.bilibili.com/video/BV1zz411c7mE/")!

        appViewModel.openNativeVideo(firstURL)
        guard case let .video(firstID, firstRouteURL) = appViewModel.route else {
            return XCTFail("Expected first native-video route")
        }
        let firstViewModel = appViewModel.videoViewModel(for: firstID)
        XCTAssertEqual(firstRouteURL, firstURL)
        XCTAssertFalse(appViewModel.isBrowserActive)

        appViewModel.openNativeVideo(secondURL)
        guard case let .video(secondID, _) = appViewModel.route else {
            return XCTFail("Expected nested native-video route")
        }
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(appViewModel.routeStack.count, 3)
        XCTAssertFalse(firstViewModel.hasActiveLoadTask)
        XCTAssertFalse(firstViewModel === appViewModel.videoViewModel(for: secondID))

        appViewModel.handleTopLevelBack()
        guard case let .video(restoredID, restoredURL) = appViewModel.route else {
            return XCTFail("Expected first native-video route after pop")
        }
        XCTAssertEqual(restoredID, firstID)
        XCTAssertEqual(restoredURL, firstURL)
        XCTAssertTrue(firstViewModel === appViewModel.videoViewModel(for: restoredID))

        appViewModel.handleTopLevelBack()
        XCTAssertEqual(appViewModel.routeStack.count, 1)
        guard case .dynamicFeed = appViewModel.route else {
            return XCTFail("Expected root route after complete native-video pop")
        }
    }

    func testDynamicFeedPresentationStateSurvivesNativeVideoRoundTrip() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)
        let feedViewModel = appViewModel.dynamicFeedViewModel

        XCTAssertTrue(appViewModel.hasDynamicFeedRoot)
        XCTAssertTrue(appViewModel.isDynamicFeedActive)

        feedViewModel.selectFilter(.video)
        feedViewModel.updateScrollOffset(684)

        appViewModel.openNativeVideo(
            URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        guard case .video = appViewModel.route else {
            return XCTFail("Expected native-video route")
        }
        XCTAssertTrue(appViewModel.hasDynamicFeedRoot)
        XCTAssertFalse(appViewModel.isDynamicFeedActive)

        appViewModel.handleTopLevelBack()

        guard case .dynamicFeed = appViewModel.route else {
            return XCTFail("Expected dynamic feed after returning from video")
        }
        XCTAssertTrue(appViewModel.hasDynamicFeedRoot)
        XCTAssertTrue(appViewModel.isDynamicFeedActive)
        XCTAssertTrue(feedViewModel === appViewModel.dynamicFeedViewModel)
        XCTAssertEqual(feedViewModel.selectedFilter, .video)
        XCTAssertEqual(feedViewModel.scrollOffsetY, 684, accuracy: 0.5)
    }

    func testChangingDynamicFilterResetsOnlyScrollPosition() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)
        let feedViewModel = appViewModel.dynamicFeedViewModel
        let initialRevision = feedViewModel.scrollRestorationRevision

        feedViewModel.updateScrollOffset(420)
        feedViewModel.selectFilter(.video)

        XCTAssertEqual(feedViewModel.selectedFilter, .video)
        XCTAssertEqual(feedViewModel.scrollOffsetY, 0)
        XCTAssertEqual(feedViewModel.scrollRestorationRevision, initialRevision + 1)
    }

    func testDynamicFeedScrollRestorationRejectsLayoutOffsetsAndKeepsPendingTarget() {
        XCTAssertFalse(
            FocusDynamicFeedScrollRestorationPolicy.shouldPersistObservedOffset(
                isTracking: false,
                isDragging: false,
                isDecelerating: false,
                isPanActive: false
            )
        )
        XCTAssertTrue(
            FocusDynamicFeedScrollRestorationPolicy.shouldPersistObservedOffset(
                isTracking: false,
                isDragging: false,
                isDecelerating: true,
                isPanActive: false
            )
        )

        XCTAssertEqual(
            FocusDynamicFeedScrollRestorationPolicy.normalizedOffset(
                contentOffsetY: 253,
                minimumY: -47
            ),
            300,
            accuracy: 0.5
        )

        let partialLayout = FocusDynamicFeedScrollRestorationPolicy.placement(
            requestedOffsetY: 684,
            minimumY: -47,
            maximumY: 253
        )
        XCTAssertEqual(partialLayout.contentOffsetY, 253, accuracy: 0.5)
        XCTAssertEqual(partialLayout.normalizedOffsetY, 300, accuracy: 0.5)
        XCTAssertFalse(partialLayout.reachedTarget)

        let completeLayout = FocusDynamicFeedScrollRestorationPolicy.placement(
            requestedOffsetY: 684,
            minimumY: -47,
            maximumY: 900
        )
        XCTAssertEqual(completeLayout.contentOffsetY, 637, accuracy: 0.5)
        XCTAssertEqual(completeLayout.normalizedOffsetY, 684, accuracy: 0.5)
        XCTAssertTrue(completeLayout.reachedTarget)
    }

    func testExplicitWebFallbackStaysOnSameVideoButRoutesOtherVideosNatively() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let browserViewModel = FocusBrowserViewModel(settingsStore: store)
        let videoURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        let previousURL = URL(string: "https://www.bilibili.com/")!

        browserViewModel.allowNextVideoNavigationInWeb(for: videoURL)
        XCTAssertFalse(
            browserViewModel.shouldRouteVideoNavigationToNative(videoURL, currentURL: previousURL)
        )
        XCTAssertFalse(
            browserViewModel.shouldRouteVideoNavigationToNative(videoURL, currentURL: previousURL)
        )
        XCTAssertFalse(
            browserViewModel.shouldRouteVideoNavigationToNative(videoURL, currentURL: videoURL)
        )
        XCTAssertTrue(
            browserViewModel.shouldRouteVideoNavigationToNative(
                URL(string: "https://www.bilibili.com/video/BV1zz411c7mE/")!,
                currentURL: videoURL
            )
        )
    }

    func testNativeVideoDanmakuTogglePersistsAndSeedsNewPlayers() {
        let (store, defaults, suiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appViewModel = FocusAppViewModel(settingsStore: store)

        appViewModel.openNativeVideo(
            URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        guard case let .video(firstRouteID, _) = appViewModel.route else {
            return XCTFail("Expected first native-video route")
        }
        let firstPlayer = appViewModel.videoViewModel(for: firstRouteID)
        XCTAssertTrue(firstPlayer.isDanmakuEnabled)

        firstPlayer.toggleDanmaku()
        XCTAssertFalse(firstPlayer.isDanmakuEnabled)
        XCTAssertFalse(store.settings.nativeDanmakuEnabled)

        appViewModel.openNativeVideo(
            URL(string: "https://www.bilibili.com/video/BV1zz411c7mE/")!
        )
        guard case let .video(secondRouteID, _) = appViewModel.route else {
            return XCTFail("Expected second native-video route")
        }
        XCTAssertFalse(appViewModel.videoViewModel(for: secondRouteID).isDanmakuEnabled)

        store.settings.nativeDanmakuEnabled = true
        appViewModel.applyNativeDanmakuPreference(true)
        XCTAssertTrue(firstPlayer.isDanmakuEnabled)
        XCTAssertTrue(appViewModel.videoViewModel(for: secondRouteID).isDanmakuEnabled)
    }

    func testNativeDanmakuSegmentPrefetchBoundaryAndFallback() {
        XCTAssertEqual(
            FocusDanmakuSegmentScheduler.segmentIndexes(
                playbackPositionMilliseconds: 329_999,
                segmentDurationMilliseconds: 360_000,
                totalSegments: 3
            ),
            [1]
        )
        XCTAssertEqual(
            FocusDanmakuSegmentScheduler.segmentIndexes(
                playbackPositionMilliseconds: 330_000,
                segmentDurationMilliseconds: 360_000,
                totalSegments: 3
            ),
            [1, 2]
        )
        XCTAssertEqual(
            FocusDanmakuSegmentScheduler.segmentIndexes(
                playbackPositionMilliseconds: 330_000,
                segmentDurationMilliseconds: 0,
                totalSegments: 3
            ),
            [1, 2]
        )
        XCTAssertEqual(
            FocusDanmakuSegmentScheduler.segmentIndexes(
                playbackPositionMilliseconds: 350_000,
                segmentDurationMilliseconds: 360_000,
                totalSegments: 1
            ),
            [1]
        )
    }

    func testNativeDanmakuLayoutDropsUnsafeCollisionsAndKeepsModesIndependent() {
        let scrolling = nativeDanmaku(id: 1, progress: 1_000, mode: .scrolling)
        let colliding = nativeDanmaku(id: 2, progress: 2_000, mode: .scrolling)
        let later = nativeDanmaku(id: 3, progress: 6_000, mode: .scrolling)
        let top = nativeDanmaku(id: 4, progress: 2_000, mode: .top)

        let placements = FocusNativeDanmakuLayout.placements(
            for: [scrolling, colliding, top, later],
            laneCount: 1
        )

        XCTAssertEqual(placements.map(\.danmaku.id), [1, 4, 3])
        XCTAssertEqual(FocusNativeDanmakuLayout.displayMilliseconds, 5_000)
    }

    func testNativeVideoFindsCurrentEpisodeInLongSelectionList() {
        let episodes = (1 ... 120).map { index in
            FocusVideoEpisode(
                bvid: String(format: "BV%010d", index),
                aid: Int64(index),
                cid: Int64(10_000 + index),
                title: "第 \(index) 集",
                coverURL: nil,
                badge: ""
            )
        }

        XCTAssertEqual(
            FocusNativeVideoSelection.currentEpisodeIndex(
                in: episodes,
                currentBVID: "BV0000000087",
                currentCID: 10_087
            ),
            86
        )
        XCTAssertEqual(
            FocusNativeVideoSelection.currentEpisodeIndex(
                in: episodes,
                currentBVID: "bv0000000087",
                currentCID: 10_087
            ),
            86
        )
        XCTAssertNil(
            FocusNativeVideoSelection.currentEpisodeIndex(
                in: episodes,
                currentBVID: "BV9999999999"
            )
        )

        var repeatedBVIDEpisodes = episodes
        repeatedBVIDEpisodes[86] = FocusVideoEpisode(
            bvid: "BVREPEATED01",
            aid: 87,
            cid: 20_087,
            title: "第 87 集",
            coverURL: nil,
            badge: ""
        )
        repeatedBVIDEpisodes[87] = FocusVideoEpisode(
            bvid: "BVREPEATED01",
            aid: 88,
            cid: 3_000_000_088,
            title: "第 88 集",
            coverURL: nil,
            badge: ""
        )
        XCTAssertEqual(
            FocusNativeVideoSelection.currentEpisodeIndex(
                in: repeatedBVIDEpisodes,
                currentBVID: "bvrepeated01",
                currentCID: 3_000_000_088
            ),
            87
        )
        XCTAssertEqual(
            FocusNativeVideoSelection.episodeURL(for: repeatedBVIDEpisodes[87])?
                .absoluteString,
            "https://www.bilibili.com/video/BVREPEATED01/?cid=3000000088"
        )
    }

    func testCustomAccentColorNormalizesAndRoundTripsThroughSwiftUI() throws {
        let settings = FocusSettings(accentColorHex: "34c759")
        XCTAssertEqual(settings.accentColorHex, "#34C759")
        XCTAssertEqual(
            FocusAccentColor.hexString(
                from: FocusAccentColor.color(hex: settings.accentColorHex)
            ),
            "#34C759"
        )

        let legacy = Data(#"{"redirectEnabled":false}"#.utf8)
        let restored = try JSONDecoder().decode(FocusSettings.self, from: legacy)
        XCTAssertEqual(restored.accentColorHex, FocusSettings.defaultAccentColorHex)
    }

    func testNativeVideoControlsAndTripleActionsDriveNativeState() async throws {
        let cookieProvider = NativeVideoTestCookieProvider()
        let detailService = FocusVideoDetailService(
            cookieProvider: cookieProvider,
            requestLoader: NativeVideoTestAPI.detailResponse
        )
        let actionService = FocusVideoActionService(
            cookieProvider: cookieProvider,
            requestLoader: NativeVideoTestAPI.actionResponse
        )
        let viewModel = FocusNativeVideoViewModel(
            detailService: detailService,
            actionService: actionService,
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() }
        )
        let videoURL = URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!

        viewModel.activate(url: videoURL)
        await waitUntil {
            viewModel.detail != nil && !viewModel.isLoadingInteractions
        }
        let initialStatistics = try XCTUnwrap(viewModel.detail?.statistics)

        viewModel.cyclePlaybackRate()
        XCTAssertEqual(viewModel.playbackRate, 1.25, accuracy: 0.001)
        viewModel.requestFullscreen()
        XCTAssertTrue(viewModel.isFullscreen)
        viewModel.exitFullscreen()
        await waitUntil { !viewModel.isFullscreen }
        XCTAssertFalse(viewModel.isFullscreen)

        viewModel.toggleLike()
        await waitUntil { !viewModel.actionsInFlight.contains(.like) }
        XCTAssertTrue(viewModel.interactionState.liked)
        XCTAssertEqual(viewModel.detail?.statistics.likes, initialStatistics.likes + 1)

        viewModel.addCoin()
        await waitUntil { !viewModel.actionsInFlight.contains(.coin) }
        XCTAssertTrue(viewModel.interactionState.coined)
        XCTAssertEqual(viewModel.detail?.statistics.coins, initialStatistics.coins + 1)

        viewModel.toggleFavorite()
        await waitUntil { !viewModel.actionsInFlight.contains(.favorite) }
        XCTAssertTrue(viewModel.interactionState.favorited)
        XCTAssertEqual(viewModel.interactionState.favoriteFolderID, 9001)
        XCTAssertEqual(viewModel.detail?.statistics.favorites, initialStatistics.favorites + 1)
        XCTAssertNil(viewModel.actionErrorMessage)

        viewModel.suspend()
    }

    func testNativeVideoChoosesResumePageThenWaitsForReadyAndSeekBeforePublishingPlayer() async {
        var readyContinuation: CheckedContinuation<Void, Never>?
        var playbackEvents: [String] = []
        var seekPositions: [Int64] = []
        var wasPreparedDuringSeek: Bool?
        var wasPlayingDuringSeek: Bool?
        weak var observedViewModel: FocusNativeVideoViewModel?
        let cookieProvider = NativeVideoTestCookieProvider()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.resumableMultiPageResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in
                playbackEvents.append("waiting")
                await withCheckedContinuation { continuation in
                    readyContinuation = continuation
                }
                playbackEvents.append("ready")
            },
            initialPlaybackSeeker: { _, milliseconds in
                playbackEvents.append("seek")
                seekPositions.append(milliseconds)
                wasPreparedDuringSeek = observedViewModel?.hasPreparedPlayer
                wasPlayingDuringSeek = observedViewModel.map { $0.player.rate > 0 }
            }
        )
        observedViewModel = viewModel
        defer {
            readyContinuation?.resume()
            viewModel.suspend()
        }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.selectedPageCID == 4203 && readyContinuation != nil
        }

        XCTAssertTrue(viewModel.isLoadingPlayback)
        XCTAssertFalse(viewModel.hasPreparedPlayer)
        XCTAssertEqual(seekPositions, [])

        let continuation = readyContinuation
        readyContinuation = nil
        continuation?.resume()
        await waitUntil { viewModel.hasPreparedPlayer }

        XCTAssertEqual(playbackEvents, ["waiting", "ready", "seek"])
        XCTAssertEqual(seekPositions, [87_000])
        XCTAssertEqual(viewModel.playbackPositionMilliseconds, 87_000)
        XCTAssertEqual(wasPreparedDuringSeek, false)
        XCTAssertEqual(wasPlayingDuringSeek, false)
        XCTAssertFalse(viewModel.isLoadingPlayback)

        guard let firstPage = viewModel.detail?.pages.first(where: { $0.cid == 4201 }) else {
            return XCTFail("Missing first page")
        }
        viewModel.selectPage(firstPage)
        await waitUntil { readyContinuation != nil }
        XCTAssertEqual(viewModel.selectedPageCID, 4201)

        let manualSelectionContinuation = readyContinuation
        readyContinuation = nil
        manualSelectionContinuation?.resume()
        await waitUntil { !viewModel.hasActivePlaybackPreparationTask }
        XCTAssertEqual(viewModel.selectedPageCID, 4201)
        XCTAssertEqual(seekPositions, [87_000])
        XCTAssertEqual(viewModel.playbackPositionMilliseconds, 0)
    }

    func testNativeVideoPrefersDurableLocalResumeOverOlderServerHistory() async {
        var seekPositions: [Int64] = []
        let persistence = NativeVideoTestPlaybackPersistence()
        let progressStore = FocusPlaybackProgressStore(persistence: persistence)
        let cookieProvider = NativeVideoTestCookieProvider()
        let accountScope = FocusPlaybackAccountScope.resolve(
            cookies: await cookieProvider.loadCookies()
        )
        _ = await progressStore.recordProgressAndEnqueueHistory(
            accountScope: accountScope,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4201,
            positionMilliseconds: 64_000
        )
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.resumableMultiPageResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: progressStore,
            accountScopeProvider: { accountScope },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in },
            initialPlaybackSeeker: { _, milliseconds in
                seekPositions.append(milliseconds)
            }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.hasPreparedPlayer && !viewModel.hasActivePlaybackPreparationTask
        }

        XCTAssertEqual(viewModel.selectedPageCID, 4201)
        XCTAssertEqual(seekPositions, [64_000])
        XCTAssertEqual(viewModel.playbackPositionMilliseconds, 64_000)
    }

    func testNativeVideoImmediateReentryWaitsForPendingLocalProgressWrite() async {
        let progressStore = makeNativeVideoPlaybackStore()
        let writeCoordinator = FocusPlaybackProgressWriteCoordinator()
        let writeGate = NativeVideoAsyncGate()
        let scopeProbe = NativeVideoAccountScopeProbe(scope: .anonymous)
        var reachedReadyWaiter = false
        var seekPositions: [Int64] = []

        // Model the local write synchronously registered by the old route's
        // suspend(). The write itself is intentionally prevented from starting
        // until the replacement route has begun playback preparation.
        writeCoordinator.enqueue {
            await writeGate.wait()
            _ = await progressStore.recordProgress(
                accountScope: .anonymous,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4201,
                positionMilliseconds: 64_000
            )
        }
        await waitUntilAsync { await writeGate.waiterCount == 1 }

        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.detailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: progressStore,
            playbackProgressWriteCoordinator: writeCoordinator,
            accountScopeProvider: { await scopeProbe.resolve() },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in
                reachedReadyWaiter = true
            },
            initialPlaybackSeeker: { _, milliseconds in
                seekPositions.append(milliseconds)
            }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntilAsync { await scopeProbe.callCount >= 2 }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.hasActivePlaybackPreparationTask)
        XCTAssertFalse(viewModel.hasPreparedPlayer)
        XCTAssertFalse(reachedReadyWaiter)
        XCTAssertEqual(seekPositions, [])

        await writeGate.release()
        await waitUntil {
            viewModel.hasPreparedPlayer && !viewModel.hasActivePlaybackPreparationTask
        }

        XCTAssertTrue(reachedReadyWaiter)
        XCTAssertEqual(seekPositions, [64_000])
        XCTAssertEqual(viewModel.playbackPositionMilliseconds, 64_000)
    }

    func testNativeVideoExplicitPageOverridesServerResumePage() async {
        var reachedReadyGate = false
        var seekPositions: [Int64] = []
        let cookieProvider = NativeVideoTestCookieProvider()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.resumableMultiPageResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in
                reachedReadyGate = true
            },
            initialPlaybackSeeker: { _, milliseconds in
                seekPositions.append(milliseconds)
            }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=1")!
        )
        await waitUntil {
            reachedReadyGate && !viewModel.hasActivePlaybackPreparationTask
        }

        XCTAssertEqual(viewModel.selectedPageCID, 4201)
        XCTAssertEqual(viewModel.activePage?.pageNumber, 1)
        XCTAssertEqual(seekPositions, [])
        XCTAssertEqual(viewModel.playbackPositionMilliseconds, 0)
    }

    func testNativeVideoNearTailSelectsLastPageButStartsAtBeginning() async {
        var reachedReadyGate = false
        var seekPositions: [Int64] = []
        let cookieProvider = NativeVideoTestCookieProvider()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.nearTailMultiPageResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in
                reachedReadyGate = true
            },
            initialPlaybackSeeker: { _, milliseconds in
                seekPositions.append(milliseconds)
            }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            reachedReadyGate && !viewModel.hasActivePlaybackPreparationTask
        }

        XCTAssertEqual(viewModel.selectedPageCID, 4203)
        XCTAssertEqual(viewModel.activePage?.pageNumber, 3)
        XCTAssertEqual(seekPositions, [])
        XCTAssertEqual(viewModel.playbackPositionMilliseconds, 0)
    }

    func testCancelledPlaybackTaskCannotClearReplacementTaskHandle() async throws {
        var firstReadyContinuation: CheckedContinuation<Void, Never>?
        var secondReadyContinuation: CheckedContinuation<Void, Never>?
        var readyWaitCount = 0
        var returnedWaitCount = 0
        let cookieProvider = NativeVideoTestCookieProvider()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.multiPageDetailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in
                readyWaitCount += 1
                let waitIndex = readyWaitCount
                await withCheckedContinuation { continuation in
                    if waitIndex == 1 {
                        firstReadyContinuation = continuation
                    } else {
                        secondReadyContinuation = continuation
                    }
                }
                returnedWaitCount += 1
            },
            initialPlaybackSeeker: { _, _ in }
        )
        defer {
            firstReadyContinuation?.resume()
            secondReadyContinuation?.resume()
            viewModel.suspend()
        }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=1")!
        )
        await waitUntil { firstReadyContinuation != nil }
        let secondPage = try XCTUnwrap(viewModel.detail?.pages.first(where: { $0.cid == 4202 }))
        viewModel.selectPage(secondPage)
        await waitUntil { secondReadyContinuation != nil }

        let firstContinuation = firstReadyContinuation
        firstReadyContinuation = nil
        firstContinuation?.resume()
        await waitUntil { returnedWaitCount >= 1 }

        XCTAssertTrue(viewModel.hasActivePlaybackPreparationTask)
        XCTAssertTrue(viewModel.isLoadingPlayback)
        XCTAssertFalse(viewModel.hasPreparedPlayer)

        viewModel.suspend()
        XCTAssertFalse(viewModel.hasActivePlaybackPreparationTask)
        XCTAssertFalse(viewModel.isLoadingPlayback)
        XCTAssertNil(viewModel.player.currentItem)

        let secondContinuation = secondReadyContinuation
        secondReadyContinuation = nil
        secondContinuation?.resume()
        await waitUntil { returnedWaitCount == 2 }
        XCTAssertFalse(viewModel.hasPreparedPlayer)
        XCTAssertFalse(viewModel.hasActivePlaybackPreparationTask)
    }

    func testNativeVideoClearsBoundAccountBeforeSwitchAndReloadPreparation() async {
        let accountScope = await nativeVideoTestAccountScope()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.multiPageDetailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { accountScope },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in },
            initialPlaybackSeeker: { _, _ in }
        )
        defer { viewModel.suspend() }

        let firstPageURL = URL(
            string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=1"
        )!
        let secondPageURL = URL(
            string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=2"
        )!
        viewModel.activate(url: firstPageURL)
        await waitUntil {
            viewModel.hasBoundPlaybackAccountScope && viewModel.hasPreparedPlayer
        }

        viewModel.open(secondPageURL)
        XCTAssertFalse(viewModel.hasBoundPlaybackAccountScope)

        viewModel.loadIfNeeded()
        await waitUntil {
            viewModel.hasBoundPlaybackAccountScope && viewModel.hasPreparedPlayer
        }

        viewModel.reload()
        XCTAssertFalse(viewModel.hasBoundPlaybackAccountScope)
    }

    func testNativeVideoHistoryRetryIsSingleFlightAndClearsCompletedHandle() async {
        let scopeGate = NativeVideoAccountScopeGate()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.detailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await scopeGate.resolve() },
            nativeDanmakuEnabled: false
        )

        await waitUntilAsync { await scopeGate.callCount == 1 }
        XCTAssertTrue(viewModel.hasActiveWatchHistoryRetryTask)

        viewModel.handleAppDidBecomeActive()
        viewModel.handleAppDidBecomeActive()
        viewModel.handleAppDidBecomeActive()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let callCountWhileBlocked = await scopeGate.callCount
        XCTAssertEqual(callCountWhileBlocked, 1)

        await scopeGate.releaseNext(with: .anonymous)
        await waitUntil { !viewModel.hasActiveWatchHistoryRetryTask }

        viewModel.handleAppDidBecomeActive()
        await waitUntilAsync { await scopeGate.callCount == 2 }
        XCTAssertTrue(viewModel.hasActiveWatchHistoryRetryTask)
        await scopeGate.releaseNext(with: .anonymous)
        await waitUntil { !viewModel.hasActiveWatchHistoryRetryTask }
    }

    func testNativeVideoAnonymousHistoryPersistsLocallyWithoutOutbox() async {
        let progressStore = makeNativeVideoPlaybackStore()
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.detailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: progressStore,
            accountScopeProvider: { .anonymous },
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in },
            initialPlaybackSeeker: { _, _ in }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.hasPreparedPlayer && !viewModel.hasActivePlaybackPreparationTask
        }
        await waitUntilAsync {
            await progressStore.recentProgress(
                accountScope: .anonymous,
                aid: 42,
                bvid: "BV1xx411c7mD",
                cid: 4201
            ) != nil
        }

        let localProgress = await progressStore.recentProgress(
            accountScope: .anonymous,
            aid: 42,
            bvid: "BV1xx411c7mD",
            cid: 4201
        )
        let pendingReports = await progressStore.pendingHistoryReports(
            accountScope: .anonymous
        )
        XCTAssertNotNil(localProgress)
        XCTAssertTrue(pendingReports.isEmpty)
    }

    func testNativePlaybackLifecyclePreservesBackgroundPlaybackAndResumesOnlyAllowedInterruptions() {
        XCTAssertEqual(
            FocusNativePlaybackLifecyclePolicy.audiovisualBackgroundPlaybackPolicy,
            .continuesIfPossible
        )
        XCTAssertFalse(
            FocusNativePlaybackLifecyclePolicy.shouldPauseForApplicationBackground(isPlaying: true)
        )
        XCTAssertFalse(
            FocusNativePlaybackLifecyclePolicy.shouldPauseForApplicationBackground(isPlaying: false)
        )
        XCTAssertTrue(
            FocusNativePlaybackLifecyclePolicy.shouldResumeAfterInterruption(
                wasPlaying: true,
                systemAllowsResume: true
            )
        )
        XCTAssertFalse(
            FocusNativePlaybackLifecyclePolicy.shouldResumeAfterInterruption(
                wasPlaying: false,
                systemAllowsResume: true
            )
        )
        XCTAssertFalse(
            FocusNativePlaybackLifecyclePolicy.shouldResumeAfterInterruption(
                wasPlaying: true,
                systemAllowsResume: false
            )
        )
    }

    func testNativeVideoSelectsRequestedPageAndFallsBackToDetailCID() async {
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.multiPageDetailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            nativeDanmakuEnabled: false
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=3")!
        )
        await waitUntil { viewModel.detail != nil && viewModel.selectedPageCID == 4203 }
        XCTAssertEqual(viewModel.selectedPageCID, 4203)
        XCTAssertEqual(viewModel.activePage?.pageNumber, 3)

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/?cid=4201")!
        )
        await waitUntil { viewModel.detail != nil && viewModel.selectedPageCID == 4201 }
        XCTAssertEqual(viewModel.selectedPageCID, 4201)
        XCTAssertEqual(viewModel.activePage?.pageNumber, 1)

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil { viewModel.detail != nil && viewModel.selectedPageCID == 4202 }
        XCTAssertEqual(viewModel.selectedPageCID, 4202)
        XCTAssertEqual(viewModel.activePage?.pageNumber, 2)
    }

    func testNativeVideoAutomaticallySelectsPreferredSubtitleAndLoadsBCC() async {
        let subtitleAPI = NativeVideoSubtitleTestAPI()
        let viewModel = makeSubtitleTestViewModel(
            subtitleAPI: subtitleAPI,
            preferredLanguageCode: "en-US"
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.subtitleLoadState == .ready
                && viewModel.subtitleCues.count == 3
        }

        XCTAssertEqual(viewModel.selectedPageCID, 4201)
        XCTAssertEqual(viewModel.subtitleTracks.map(\.languageCode), ["zh-CN", "en-US"])
        XCTAssertEqual(viewModel.selectedSubtitleTrack?.languageCode, "en-US")
        XCTAssertEqual(viewModel.subtitleControlTitle, "English")
        XCTAssertEqual(
            viewModel.subtitleCues.map(\.content),
            ["P1 English intro", "P1 English next", "P1 English overlap"]
        )
        XCTAssertEqual(viewModel.subtitleText(at: 500), "P1 English intro")
        let trackRequestCIDs = await subtitleAPI.trackRequestCIDs
        let documentPaths = await subtitleAPI.documentPaths
        XCTAssertEqual(trackRequestCIDs, [4201])
        XCTAssertEqual(
            documentPaths,
            ["/bfs/subtitle/4201-en.json"]
        )
    }

    func testNativeVideoSubtitleDisableAndTrackSwitchUpdatePreferenceAndCues() async throws {
        let subtitleAPI = NativeVideoSubtitleTestAPI()
        var preferenceChanges: [(enabled: Bool, languageCode: String)] = []
        let viewModel = makeSubtitleTestViewModel(
            subtitleAPI: subtitleAPI,
            preferredLanguageCode: "en-US",
            subtitlePreferenceChange: { enabled, languageCode in
                preferenceChanges.append((enabled, languageCode))
            }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.subtitleLoadState == .ready
                && viewModel.selectedSubtitleTrack?.languageCode == "en-US"
        }

        viewModel.disableSubtitles()
        XCTAssertFalse(viewModel.isSubtitleEnabled)
        XCTAssertEqual(viewModel.subtitleControlTitle, "关")
        XCTAssertEqual(viewModel.subtitleText(at: 500), "")
        XCTAssertEqual(preferenceChanges.count, 1)
        XCTAssertFalse(preferenceChanges[0].enabled)
        XCTAssertEqual(preferenceChanges[0].languageCode, "en-US")

        let chineseTrack = try XCTUnwrap(
            viewModel.subtitleTracks.first(where: { $0.languageCode == "zh-CN" })
        )
        viewModel.selectSubtitleTrack(chineseTrack)
        await waitUntil {
            viewModel.subtitleLoadState == .ready
                && viewModel.selectedSubtitleTrackID == chineseTrack.id
                && viewModel.subtitleText(at: 500) == "P1 中文字幕"
        }

        XCTAssertTrue(viewModel.isSubtitleEnabled)
        XCTAssertEqual(viewModel.subtitleControlTitle, "中文")
        XCTAssertEqual(viewModel.subtitleCues.map(\.content), ["P1 中文字幕"])
        XCTAssertEqual(preferenceChanges.count, 2)
        XCTAssertTrue(preferenceChanges[1].enabled)
        XCTAssertEqual(preferenceChanges[1].languageCode, "zh-CN")
        let documentPaths = await subtitleAPI.documentPaths
        XCTAssertEqual(
            documentPaths,
            [
                "/bfs/subtitle/4201-en.json",
                "/bfs/subtitle/4201-zh.json",
            ]
        )
    }

    func testNativeVideoSubtitleTimelineUsesStartInclusiveEndExclusiveBoundaries() async {
        let subtitleAPI = NativeVideoSubtitleTestAPI()
        let viewModel = makeSubtitleTestViewModel(
            subtitleAPI: subtitleAPI,
            preferredLanguageCode: "en-US"
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.subtitleLoadState == .ready
                && viewModel.subtitleCues.count == 3
        }

        XCTAssertEqual(viewModel.subtitleText(at: -1), "P1 English intro")
        XCTAssertEqual(viewModel.subtitleText(at: 0), "P1 English intro")
        XCTAssertEqual(viewModel.subtitleText(at: 999), "P1 English intro")
        XCTAssertEqual(viewModel.subtitleText(at: 1_000), "P1 English next")
        XCTAssertEqual(
            viewModel.subtitleText(at: 1_500),
            "P1 English next\nP1 English overlap"
        )
        XCTAssertEqual(viewModel.subtitleText(at: 1_999), "P1 English next\nP1 English overlap")
        XCTAssertEqual(viewModel.subtitleText(at: 2_000), "P1 English overlap")
        XCTAssertEqual(viewModel.subtitleText(at: 2_499), "P1 English overlap")
        XCTAssertEqual(viewModel.subtitleText(at: 2_500), "")
    }

    func testNativeVideoPageSwitchReloadsSubtitlesForSelectedCID() async throws {
        let subtitleAPI = NativeVideoSubtitleTestAPI()
        let viewModel = makeSubtitleTestViewModel(
            subtitleAPI: subtitleAPI,
            detailRequestLoader: NativeVideoTestAPI.multiPageDetailResponse,
            preferredLanguageCode: "en-US"
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(
                string: "https://www.bilibili.com/video/BV1xx411c7mD/?p=1"
            )!
        )
        await waitUntil {
            viewModel.selectedPageCID == 4201
                && viewModel.subtitleLoadState == .ready
                && viewModel.subtitleText(at: 500) == "P1 English intro"
        }

        let secondPage = try XCTUnwrap(
            viewModel.detail?.pages.first(where: { $0.cid == 4202 })
        )
        viewModel.selectPage(secondPage)
        await waitUntil {
            viewModel.selectedPageCID == 4202
                && viewModel.subtitleLoadState == .ready
                && viewModel.subtitleText(at: 500) == "P2 English"
        }

        XCTAssertEqual(viewModel.selectedSubtitleTrack?.languageCode, "en-US")
        let trackRequestCIDs = await subtitleAPI.trackRequestCIDs
        XCTAssertEqual(
            Array(trackRequestCIDs.suffix(2)),
            [4201, 4202]
        )
        let documentPaths = await subtitleAPI.documentPaths
        XCTAssertTrue(documentPaths.contains("/bfs/subtitle/4201-en.json"))
        XCTAssertTrue(documentPaths.contains("/bfs/subtitle/4202-en.json"))
    }

    func testNativeVideoCommentRepliesDeduplicateAndCollapsePreservesCache() async throws {
        let commentAPI = NativeVideoCommentTestAPI()
        let viewModel = makeCommentTestViewModel(commentAPI: commentAPI)
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let rootComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )

        XCTAssertEqual(
            viewModel.replies(for: rootComment).map(\.id),
            [90_001, 90_002]
        )
        XCTAssertNil(viewModel.commentThreadState(for: rootComment.id))

        viewModel.toggleCommentReplies(rootComment)
        XCTAssertTrue(
            viewModel.commentThreadState(for: rootComment.id)?.isExpanded == true
        )
        XCTAssertTrue(
            viewModel.commentThreadState(for: rootComment.id)?.isLoading == true
        )
        await waitUntil {
            guard let thread = viewModel.commentThreadState(for: rootComment.id) else {
                return false
            }
            return thread.hasLoadedFirstPage
                && !thread.isLoading
                && thread.nextCursor != nil
        }

        var thread = try XCTUnwrap(
            viewModel.commentThreadState(for: rootComment.id)
        )
        XCTAssertEqual(thread.replies.map(\.id), [90_001, 90_002])
        XCTAssertEqual(thread.totalCount, 3)
        XCTAssertTrue(thread.isExpanded)

        viewModel.loadMoreCommentReplies(for: rootComment)
        await waitUntil {
            guard let thread = viewModel.commentThreadState(for: rootComment.id) else {
                return false
            }
            return !thread.isLoading
                && thread.nextCursor == nil
                && thread.replies.count == 3
        }

        thread = try XCTUnwrap(
            viewModel.commentThreadState(for: rootComment.id)
        )
        XCTAssertEqual(thread.replies.map(\.id), [90_001, 90_002, 90_003])
        XCTAssertEqual(viewModel.replies(for: rootComment).map(\.id), [90_001, 90_002, 90_003])
        let requestPagesBeforeCollapse = await commentAPI.replyPageNumbers
        XCTAssertEqual(requestPagesBeforeCollapse, [1, 2])

        viewModel.toggleCommentReplies(rootComment)
        thread = try XCTUnwrap(
            viewModel.commentThreadState(for: rootComment.id)
        )
        XCTAssertFalse(thread.isExpanded)
        XCTAssertEqual(thread.replies.map(\.id), [90_001, 90_002, 90_003])
        XCTAssertEqual(
            viewModel.replies(for: rootComment).map(\.id),
            [90_001, 90_002]
        )

        viewModel.toggleCommentReplies(rootComment)
        XCTAssertEqual(
            viewModel.replies(for: rootComment).map(\.id),
            [90_001, 90_002, 90_003]
        )
        let requestPagesAfterReopen = await commentAPI.replyPageNumbers
        XCTAssertEqual(requestPagesAfterReopen, requestPagesBeforeCollapse)
    }

    func testNativeVideoCommentLikeAndUnlikeKeepOptimisticFinalState() async throws {
        let commentAPI = NativeVideoCommentTestAPI()
        let viewModel = makeCommentTestViewModel(commentAPI: commentAPI)
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let rootComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )
        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 10, isLiked: false)
        )

        viewModel.toggleCommentLike(rootComment)
        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 11, isLiked: true)
        )
        XCTAssertTrue(
            viewModel.commentLikeActionsInFlight.contains(rootComment.id)
        )
        await waitUntil {
            !viewModel.commentLikeActionsInFlight.contains(rootComment.id)
        }
        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 11, isLiked: true)
        )
        XCTAssertNil(viewModel.actionErrorMessage)

        viewModel.toggleCommentLike(rootComment)
        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 10, isLiked: false)
        )
        await waitUntil {
            !viewModel.commentLikeActionsInFlight.contains(rootComment.id)
        }
        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 10, isLiked: false)
        )
        XCTAssertNil(viewModel.actionErrorMessage)

        let mutationActions = await commentAPI.mutationActions
        XCTAssertEqual(mutationActions, ["1", "0"])
    }

    func testNativeVideoCommentLikeFailureRollsBackAndShowsError() async throws {
        let commentAPI = NativeVideoCommentTestAPI(
            mutationResult: .apiFailure(code: -500, message: "模拟点赞失败")
        )
        let viewModel = makeCommentTestViewModel(commentAPI: commentAPI)
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let rootComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )

        viewModel.toggleCommentLike(rootComment)
        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 11, isLiked: true)
        )
        await waitUntil {
            !viewModel.commentLikeActionsInFlight.contains(rootComment.id)
        }

        XCTAssertEqual(
            viewModel.commentLikeState(for: rootComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 10, isLiked: false)
        )
        XCTAssertTrue(
            viewModel.actionErrorMessage?.contains("模拟点赞失败") == true
        )
        let mutationActions = await commentAPI.mutationActions
        XCTAssertEqual(mutationActions, ["1"])
    }

    func testNativeVideoCommentLikeRejectsChangedAccountAndReloadsSession() async throws {
        let initialScope = await nativeVideoTestAccountScope()
        let accountScope = NativeVideoMutableAccountScope(initialScope)
        let commentAPI = NativeVideoCommentTestAPI()
        let viewModel = makeCommentTestViewModel(
            commentAPI: commentAPI,
            accountScopeProvider: { await accountScope.resolve() }
        )
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let accountAComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )
        viewModel.toggleCommentReplies(accountAComment)
        await waitUntil {
            viewModel.commentThreadState(for: accountAComment.id)?.isExpanded == true
        }

        await accountScope.update(to: .accountID(2002))
        viewModel.toggleCommentLike(accountAComment)

        await waitUntilAsync {
            await commentAPI.topLevelCommentRequestCount == 2
        }
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
                && viewModel.actionErrorMessage?
                    .contains("登录账号已切换") == true
        }

        let mutationActions = await commentAPI.mutationActions
        XCTAssertTrue(mutationActions.isEmpty)
        XCTAssertNil(viewModel.commentThreadState(for: accountAComment.id))
        XCTAssertTrue(viewModel.commentLikeOverrides.isEmpty)
        XCTAssertFalse(
            viewModel.commentLikeActionsInFlight.contains(accountAComment.id)
        )
    }

    func testNativeVideoOldCommentLikeCompletionCannotClearNewInflightForSameComment() async throws {
        let mutationGate = NativeVideoIndexedAsyncGate()
        let commentAPI = NativeVideoCommentTestAPI(
            mutationGate: mutationGate
        )
        let viewModel = makeCommentTestViewModel(commentAPI: commentAPI)
        defer { viewModel.suspend() }

        viewModel.activate(
            url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!
        )
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let firstSessionComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )

        viewModel.toggleCommentLike(firstSessionComment)
        let oldLikeTask = try XCTUnwrap(
            activeCommentLikeTask(
                for: firstSessionComment.id,
                in: viewModel
            )
        )
        await waitUntilAsync { await mutationGate.waiterCount == 1 }

        viewModel.reload()
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let secondSessionComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )
        viewModel.toggleCommentLike(secondSessionComment)
        await waitUntilAsync { await mutationGate.waiterCount == 2 }
        XCTAssertTrue(
            viewModel.commentLikeActionsInFlight.contains(secondSessionComment.id)
        )

        await mutationGate.release(waiter: 0)
        await oldLikeTask.value

        XCTAssertTrue(
            viewModel.commentLikeActionsInFlight.contains(secondSessionComment.id),
            "The cancelled task's defer must not clear the newer same-rpid action"
        )
        XCTAssertEqual(
            viewModel.commentLikeState(for: secondSessionComment),
            FocusNativeVideoViewModel.CommentLikeState(likes: 11, isLiked: true)
        )

        await mutationGate.release(waiter: 1)
        await waitUntil {
            !viewModel.commentLikeActionsInFlight.contains(secondSessionComment.id)
        }
        let mutationActions = await commentAPI.mutationActions
        XCTAssertEqual(mutationActions, ["1", "1"])
    }

    func testNativeVideoActivateResumesExpandedRepliesCancelledBySuspend() async throws {
        let repliesGate = NativeVideoIndexedAsyncGate()
        let commentAPI = NativeVideoCommentTestAPI(
            repliesGate: repliesGate
        )
        let viewModel = makeCommentTestViewModel(commentAPI: commentAPI)
        defer { viewModel.suspend() }

        let videoURL = URL(
            string: "https://www.bilibili.com/video/BV1xx411c7mD/"
        )!
        viewModel.activate(url: videoURL)
        await waitUntil {
            viewModel.comments.contains(where: { $0.id == 80_001 })
        }
        let rootComment = try XCTUnwrap(
            viewModel.comments.first(where: { $0.id == 80_001 })
        )

        viewModel.toggleCommentReplies(rootComment)
        let suspendedReplyTask = try XCTUnwrap(
            activeCommentReplyTask(for: rootComment.id, in: viewModel)
        )
        await waitUntilAsync { await repliesGate.waiterCount == 1 }
        XCTAssertTrue(
            viewModel.commentThreadState(for: rootComment.id)?.isLoading == true
        )

        viewModel.suspend()
        XCTAssertEqual(
            viewModel.commentThreadState(for: rootComment.id)?.isExpanded,
            true
        )
        XCTAssertEqual(
            viewModel.commentThreadState(for: rootComment.id)?.isLoading,
            false
        )
        XCTAssertEqual(
            viewModel.commentThreadState(for: rootComment.id)?
                .hasLoadedFirstPage,
            false
        )

        viewModel.activate(url: videoURL)
        await waitUntilAsync { await repliesGate.waiterCount == 2 }
        let resumedReplyTask = try XCTUnwrap(
            activeCommentReplyTask(for: rootComment.id, in: viewModel)
        )
        await repliesGate.release(waiter: 1)
        await resumedReplyTask.value

        var thread = try XCTUnwrap(
            viewModel.commentThreadState(for: rootComment.id)
        )
        XCTAssertTrue(thread.isExpanded)
        XCTAssertFalse(thread.isLoading)
        XCTAssertTrue(thread.hasLoadedFirstPage)
        XCTAssertEqual(thread.replies.map(\.id), [90_001, 90_002])

        await repliesGate.release(waiter: 0)
        await suspendedReplyTask.value
        thread = try XCTUnwrap(
            viewModel.commentThreadState(for: rootComment.id)
        )
        XCTAssertTrue(thread.hasLoadedFirstPage)
        XCTAssertEqual(thread.replies.map(\.id), [90_001, 90_002])
        let replyPageNumbers = await commentAPI.replyPageNumbers
        XCTAssertEqual(replyPageNumbers, [1, 1])
    }

    func testNativeVideoKeepsFullscreenPresentedUntilPortraitTransitionCompletes() async {
        var landscapeRequestCount = 0
        var portraitContinuation: CheckedContinuation<Void, Never>?
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.detailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            landscapeRequest: {
                landscapeRequestCount += 1
            },
            portraitTransition: {
                await withCheckedContinuation { continuation in
                    portraitContinuation = continuation
                }
            }
        )
        defer {
            portraitContinuation?.resume()
            viewModel.suspend()
        }

        viewModel.activate(url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        await waitUntil { viewModel.detail != nil }
        viewModel.requestFullscreen()
        XCTAssertEqual(landscapeRequestCount, 1)
        XCTAssertTrue(viewModel.isFullscreen)
        viewModel.exitFullscreen()
        await waitUntil { portraitContinuation != nil }

        XCTAssertTrue(viewModel.isFullscreen)
        XCTAssertTrue(viewModel.isCompletingPortraitExit)

        portraitContinuation?.resume()
        portraitContinuation = nil
        await waitUntil { !viewModel.isFullscreen }

        XCTAssertFalse(viewModel.isFullscreen)
        XCTAssertFalse(viewModel.isCompletingPortraitExit)
    }

    func testNativeVideoFullscreenDirectionFollowsVideoDimensions() async {
        XCTAssertEqual(
            FocusNativeVideoFullscreenPolicy.orientation(
                for: NativeVideoTestAPI.makeDetail(width: 1080, height: 1920)
            ),
            .portrait
        )
        XCTAssertEqual(
            FocusNativeVideoFullscreenPolicy.orientation(
                for: NativeVideoTestAPI.makeDetail(width: 1920, height: 1080)
            ),
            .landscape
        )
        XCTAssertEqual(
            FocusNativeVideoFullscreenPolicy.orientation(
                for: NativeVideoTestAPI.makeDetail(width: 1080, height: 1080)
            ),
            .portrait
        )
        XCTAssertEqual(
            FocusNativeVideoFullscreenPolicy.orientation(
                for: NativeVideoTestAPI.makeDetail(width: 0, height: 0)
            ),
            .landscape
        )

        var landscapeRequestCount = 0
        var portraitRequestCount = 0
        let viewModel = FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.portraitDetailResponse
            ),
            actionService: FocusVideoActionService(
                cookieProvider: NativeVideoTestCookieProvider(),
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            landscapeRequest: {
                landscapeRequestCount += 1
            },
            portraitFullscreenRequest: {
                portraitRequestCount += 1
            },
            portraitTransition: {}
        )
        defer { viewModel.suspend() }

        viewModel.activate(url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        await waitUntil { viewModel.detail != nil }
        viewModel.requestFullscreen()

        XCTAssertTrue(viewModel.isFullscreen)
        XCTAssertEqual(portraitRequestCount, 1)
        XCTAssertEqual(landscapeRequestCount, 0)
    }

    func testFollowingAuthorsPaginationUsesSupportedPageSizeAndLoadsAllPages() {
        XCTAssertEqual(FocusFollowingAuthorsPagination.pageSize, 50)
        XCTAssertTrue(
            FocusFollowingAuthorsPagination.shouldLoadNextPage(
                currentPage: 1,
                receivedCount: 50,
                fetchedCount: 50,
                expectedTotal: 120
            )
        )
        XCTAssertTrue(
            FocusFollowingAuthorsPagination.shouldLoadNextPage(
                currentPage: 2,
                receivedCount: 50,
                fetchedCount: 100,
                expectedTotal: 120
            )
        )
        XCTAssertFalse(
            FocusFollowingAuthorsPagination.shouldLoadNextPage(
                currentPage: 3,
                receivedCount: 20,
                fetchedCount: 120,
                expectedTotal: 120
            )
        )
    }

    func testNativeVideoBilibiliActionIconsAreBundledVectors() throws {
        for name in ["BiliLike", "BiliCoin", "BiliFavorite"] {
            let image = try XCTUnwrap(UIImage(named: name), "Missing native Bilibili action icon: \(name)")
            XCTAssertFalse(image.isSymbolImage)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for native video state")
    }

    private func waitUntilAsync(
        timeout: TimeInterval = 2,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for asynchronous native video state")
    }

    private func makeSubtitleTestViewModel(
        subtitleAPI: NativeVideoSubtitleTestAPI,
        detailRequestLoader: @escaping FocusVideoDetailService.RequestLoader =
            NativeVideoTestAPI.detailResponse,
        preferredLanguageCode: String,
        subtitlePreferenceChange: FocusNativeVideoViewModel.SubtitlePreferenceChange? = nil
    ) -> FocusNativeVideoViewModel {
        let cookieProvider = NativeVideoTestCookieProvider()
        return FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: detailRequestLoader
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            subtitleService: FocusVideoSubtitleService(
                cookieProvider: cookieProvider,
                requestLoader: { request in
                    try await subtitleAPI.response(for: request)
                }
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: { await nativeVideoTestAccountScope() },
            nativeDanmakuEnabled: false,
            nativeSubtitleEnabled: true,
            preferredSubtitleLanguageCode: preferredLanguageCode,
            subtitlePreferenceChange: subtitlePreferenceChange,
            playbackReadyWaiter: { _ in },
            initialPlaybackSeeker: { _, _ in }
        )
    }

    private func makeCommentTestViewModel(
        commentAPI: NativeVideoCommentTestAPI,
        accountScopeProvider: @escaping FocusNativeVideoViewModel.AccountScopeProvider = {
            await nativeVideoTestAccountScope()
        }
    ) -> FocusNativeVideoViewModel {
        let cookieProvider = NativeVideoTestCookieProvider()
        return FocusNativeVideoViewModel(
            detailService: FocusVideoDetailService(
                cookieProvider: cookieProvider,
                requestLoader: { request in
                    try await commentAPI.response(for: request)
                }
            ),
            actionService: FocusVideoActionService(
                cookieProvider: cookieProvider,
                requestLoader: NativeVideoTestAPI.actionResponse
            ),
            commentService: FocusVideoCommentService(
                cookieProvider: cookieProvider,
                requestLoader: { request in
                    try await commentAPI.response(for: request)
                }
            ),
            playbackProgressStore: makeNativeVideoPlaybackStore(),
            accountScopeProvider: accountScopeProvider,
            nativeDanmakuEnabled: false,
            playbackReadyWaiter: { _ in },
            initialPlaybackSeeker: { _, _ in }
        )
    }

    private func activeCommentLikeTask(
        for commentID: Int64,
        in viewModel: FocusNativeVideoViewModel
    ) -> Task<Void, Never>? {
        guard let tasks = Mirror(reflecting: viewModel).children
            .first(where: { $0.label == "commentLikeTasks" })?
            .value as? [Int64: Task<Void, Never>]
        else {
            return nil
        }
        return tasks[commentID]
    }

    private func activeCommentReplyTask(
        for commentID: Int64,
        in viewModel: FocusNativeVideoViewModel
    ) -> Task<Void, Never>? {
        guard let tasks = Mirror(reflecting: viewModel).children
            .first(where: { $0.label == "commentReplyTasks" })?
            .value as? [Int64: Task<Void, Never>]
        else {
            return nil
        }
        return tasks[commentID]
    }

    private func makeSettingsStore() -> (FocusSettingsStore, UserDefaults, String) {
        let suiteName = "BilibiliFocusStabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusSettingsStore(userDefaults: defaults), defaults, suiteName)
    }

    private func nativeDanmaku(
        id: Int64,
        progress: Int64,
        mode: FocusVideoDanmakuMode
    ) -> FocusVideoDanmaku {
        FocusVideoDanmaku(
            id: id,
            progressMilliseconds: progress,
            mode: mode,
            fontSize: 25,
            colorRGB: 0xffffff,
            content: "弹幕 \(id)",
            weight: 0,
            pool: 0
        )
    }
}

private func makeNativeVideoPlaybackStore() -> FocusPlaybackProgressStore {
    FocusPlaybackProgressStore(
        persistence: NativeVideoTestPlaybackPersistence()
    )
}

private func nativeVideoTestAccountScope() async -> FocusPlaybackAccountScope {
    FocusPlaybackAccountScope.resolve(
        cookies: await NativeVideoTestCookieProvider().loadCookies()
    )
}

private actor NativeVideoTestPlaybackPersistence: FocusPlaybackStatePersistence {
    private var data: Data?

    func loadPlaybackState() -> Data? {
        data
    }

    func savePlaybackState(_ data: Data) {
        self.data = data
    }
}

private actor NativeVideoAccountScopeGate {
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<FocusPlaybackAccountScope, Never>] = []

    func resolve() async -> FocusPlaybackAccountScope {
        callCount += 1
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func releaseNext(with scope: FocusPlaybackAccountScope) {
        guard !continuations.isEmpty else {
            return
        }
        continuations.removeFirst().resume(returning: scope)
    }
}

private actor NativeVideoAccountScopeProbe {
    private(set) var callCount = 0
    private let scope: FocusPlaybackAccountScope

    init(scope: FocusPlaybackAccountScope) {
        self.scope = scope
    }

    func resolve() -> FocusPlaybackAccountScope {
        callCount += 1
        return scope
    }
}

private actor NativeVideoMutableAccountScope {
    private var scope: FocusPlaybackAccountScope

    init(_ scope: FocusPlaybackAccountScope) {
        self.scope = scope
    }

    func resolve() -> FocusPlaybackAccountScope {
        scope
    }

    func update(to scope: FocusPlaybackAccountScope) {
        self.scope = scope
    }
}

private actor NativeVideoAsyncGate {
    private(set) var waiterCount = 0
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isReleased else {
            return
        }
        waiterCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func release() {
        guard !isReleased else {
            return
        }
        isReleased = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private actor NativeVideoIndexedAsyncGate {
    private(set) var waiterCount = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    func wait() async {
        let waiter = waiterCount
        waiterCount += 1
        await withCheckedContinuation { continuation in
            continuations[waiter] = continuation
        }
    }

    func release(waiter: Int) {
        continuations.removeValue(forKey: waiter)?.resume()
    }
}

private actor NativeVideoSubtitleTestAPI {
    private(set) var trackRequestCIDs: [Int64] = []
    private(set) var documentPaths: [String] = []

    func response(for request: URLRequest) throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let payload: String
        switch path {
        case "/x/web-interface/nav":
            payload = #"""
            {
              "code": 0,
              "data": {
                "wbi_img": {
                  "img_url": "https://i0.hdslb.com/bfs/wbi/abcdefghijklmnopqrstuvwxyzABCDEF.png",
                  "sub_url": "https://i0.hdslb.com/bfs/wbi/GHIJKLMNOPQRSTUVWXYZ0123456789abcd.png"
                }
              }
            }
            """#
        case "/x/player/wbi/v2":
            guard
                let cid = URLComponents(
                    url: request.url!,
                    resolvingAgainstBaseURL: false
                )?.queryItems?
                .first(where: { $0.name == "cid" })?
                .value
                .flatMap(Int64.init)
            else {
                payload = #"{"code":-400,"message":"missing cid"}"#
                break
            }
            trackRequestCIDs.append(cid)
            payload = Self.tracksPayload(cid: cid)
        default:
            guard path.hasPrefix("/bfs/subtitle/") else {
                payload = #"{"code":-404,"message":"unexpected subtitle endpoint"}"#
                break
            }
            documentPaths.append(path)
            payload = Self.documentPayload(path: path)
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }

    private nonisolated static func tracksPayload(cid: Int64) -> String {
        let chineseID = cid * 10 + 1
        let englishID = cid * 10 + 2
        return """
        {
          "code": 0,
          "data": {
            "subtitle": {
              "subtitles": [
                {
                  "id_str": "\(chineseID)",
                  "lan": "zh-CN",
                  "lan_doc": "中文",
                  "subtitle_url": "//aisubtitle.hdslb.com/bfs/subtitle/\(cid)-zh.json",
                  "type": 0,
                  "ai_type": 0,
                  "ai_status": 0,
                  "is_lock": false
                },
                {
                  "id_str": "\(englishID)",
                  "lan": "en-US",
                  "lan_doc": "English",
                  "subtitle_url": "//aisubtitle.hdslb.com/bfs/subtitle/\(cid)-en.json",
                  "type": 0,
                  "ai_type": 0,
                  "ai_status": 0,
                  "is_lock": false
                }
              ]
            }
          }
        }
        """
    }

    private nonisolated static func documentPayload(path: String) -> String {
        if path.hasSuffix("-zh.json") {
            let cid = path.contains("4202") ? "P2" : "P1"
            return """
            {
              "body": [
                {"from":0,"to":1,"location":2,"content":"\(cid) 中文字幕"}
              ]
            }
            """
        }
        if path.contains("4202-en.json") {
            return """
            {
              "body": [
                {"from":0,"to":1,"location":2,"content":"P2 English"}
              ]
            }
            """
        }
        return #"""
        {
          "body": [
            {"from":0,"to":1,"location":2,"content":"P1 English intro"},
            {"from":1,"to":2,"location":2,"content":"P1 English next"},
            {"from":1.5,"to":2.5,"location":2,"content":"P1 English overlap"}
          ]
        }
        """#
    }
}

private actor NativeVideoCommentTestAPI {
    enum MutationResult: Sendable {
        case success
        case apiFailure(code: Int, message: String)
    }

    private let mutationResult: MutationResult
    private let mutationGate: NativeVideoIndexedAsyncGate?
    private let repliesGate: NativeVideoIndexedAsyncGate?
    private(set) var topLevelCommentRequestCount = 0
    private(set) var replyPageNumbers: [Int] = []
    private(set) var mutationActions: [String] = []

    init(
        mutationResult: MutationResult = .success,
        mutationGate: NativeVideoIndexedAsyncGate? = nil,
        repliesGate: NativeVideoIndexedAsyncGate? = nil
    ) {
        self.mutationResult = mutationResult
        self.mutationGate = mutationGate
        self.repliesGate = repliesGate
    }

    func response(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let payload: String
        switch path {
        case "/x/v2/reply/wbi/main":
            topLevelCommentRequestCount += 1
            payload = Self.topLevelCommentsPayload
        case "/x/v2/reply/reply":
            let pageNumber = Self.queryValue(named: "pn", in: request)
                .flatMap(Int.init) ?? 1
            replyPageNumbers.append(pageNumber)
            if let repliesGate {
                await repliesGate.wait()
            }
            payload = pageNumber == 1
                ? Self.firstRepliesPagePayload
                : Self.secondRepliesPagePayload
        case "/x/v2/reply/action":
            mutationActions.append(
                Self.formValue(named: "action", in: request) ?? ""
            )
            if let mutationGate {
                await mutationGate.wait()
            }
            switch mutationResult {
            case .success:
                payload = #"{"code":0,"message":"0","data":{}}"#
            case let .apiFailure(code, message):
                payload = #"{"code":\#(code),"message":"\#(message)"}"#
            }
        default:
            return try await NativeVideoTestAPI.detailResponse(for: request)
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.bilibili.com/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }

    private nonisolated static func queryValue(
        named name: String,
        in request: URLRequest
    ) -> String? {
        guard let url = request.url else {
            return nil
        }
        return URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == name })?.value
    }

    private nonisolated static func formValue(
        named name: String,
        in request: URLRequest
    ) -> String? {
        guard
            let body = request.httpBody,
            let encoded = String(data: body, encoding: .utf8)
        else {
            return nil
        }
        var components = URLComponents()
        components.percentEncodedQuery = encoded
        return components.queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private nonisolated static let topLevelCommentsPayload = #"""
    {
      "code": 0,
      "data": {
        "cursor": {
          "all_count": 1,
          "pagination_reply": {"next_offset": ""}
        },
        "replies": [{
          "rpid": 80001,
          "mid": 1001,
          "like": 10,
          "action": 0,
          "rcount": 3,
          "ctime": 1710000000,
          "member": {"uname": "主楼", "avatar": "//i0.hdslb.com/root.jpg"},
          "content": {"message": "主楼评论"},
          "replies": [
            {
              "rpid": 90001,
              "mid": 2001,
              "like": 1,
              "action": 0,
              "rcount": 0,
              "ctime": 1710000001,
              "member": {"uname": "回复一", "avatar": ""},
              "content": {"message": "预览回复一"}
            },
            {
              "rpid": 90002,
              "mid": 2002,
              "like": 2,
              "action": 0,
              "rcount": 0,
              "ctime": 1710000002,
              "member": {"uname": "回复二", "avatar": ""},
              "content": {"message": "预览回复二"}
            }
          ]
        }]
      }
    }
    """#

    private nonisolated static let firstRepliesPagePayload = #"""
    {
      "code": 0,
      "data": {
        "page": {"num": 1, "size": 2, "count": 3},
        "replies": [
          {
            "rpid": 90001,
            "mid": 2001,
            "like": 1,
            "action": 0,
            "rcount": 0,
            "ctime": 1710000001,
            "member": {"uname": "回复一", "avatar": ""},
            "content": {"message": "首屏回复一"}
          },
          {
            "rpid": 90002,
            "mid": 2002,
            "like": 2,
            "action": 0,
            "rcount": 0,
            "ctime": 1710000002,
            "member": {"uname": "回复二", "avatar": ""},
            "content": {"message": "首屏回复二"}
          }
        ]
      }
    }
    """#

    private nonisolated static let secondRepliesPagePayload = #"""
    {
      "code": 0,
      "data": {
        "page": {"num": 2, "size": 2, "count": 3},
        "replies": [
          {
            "rpid": 90002,
            "mid": 2002,
            "like": 2,
            "action": 0,
            "rcount": 0,
            "ctime": 1710000002,
            "member": {"uname": "回复二", "avatar": ""},
            "content": {"message": "重复回复二"}
          },
          {
            "rpid": 90003,
            "mid": 2003,
            "like": 3,
            "action": 0,
            "rcount": 0,
            "ctime": 1710000003,
            "member": {"uname": "回复三", "avatar": ""},
            "content": {"message": "更多回复三"}
          }
        ]
      }
    }
    """#
}

private struct NativeVideoTestCookieProvider: CookieSnapshotProvider {
    func loadCookies() async -> [HTTPCookie] {
        [
            cookie(name: "SESSDATA", value: "session-token"),
            cookie(name: "bili_jct", value: "csrf-token"),
        ].compactMap { $0 }
    }

    private func cookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: ".bilibili.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
}

private enum NativeVideoTestAPI {
    static func detailResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let payload: String
        switch path {
        case "/x/web-interface/view":
            payload = detailPayload
        case "/x/web-interface/nav":
            payload = wbiPayload
        case "/x/player/v2", "/x/player/wbi/v2":
            payload = #"{"code":0,"data":{"last_play_cid":0,"last_play_time":0}}"#
        case "/x/player/playurl", "/x/player/wbi/playurl":
            payload = playbackPayload
        case "/x/v2/reply/wbi/main":
            payload = #"{"code":0,"data":{"replies":[]}}"#
        default:
            payload = #"{"code":-404,"message":"unexpected test endpoint"}"#
        }
        return response(payload: payload, request: request)
    }

    static func actionResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let payload: String
        switch path {
        case "/x/web-interface/archive/has/like":
            payload = #"{"code":0,"data":0}"#
        case "/x/web-interface/archive/coins":
            payload = #"{"code":0,"data":{"multiply":0}}"#
        case "/x/v2/fav/video/favoured":
            payload = #"{"code":0,"data":{"favoured":0}}"#
        case "/x/web-interface/nav":
            payload = #"{"code":0,"data":{"isLogin":true,"mid":1001}}"#
        case "/x/v3/fav/folder/created/list-all":
            payload = #"{"code":0,"data":{"list":[{"id":9001,"title":"默认收藏夹","fav_state":0}]}}"#
        case "/x/web-interface/archive/like",
             "/x/web-interface/coin/add",
             "/x/v2/history/report",
             "/x/v3/fav/resource/deal":
            payload = #"{"code":0,"data":{}}"#
        default:
            payload = #"{"code":-404,"message":"unexpected test endpoint"}"#
        }
        return response(payload: payload, request: request)
    }

    static func portraitDetailResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url?.path == "/x/web-interface/view" {
            let payload = detailPayload.replacingOccurrences(
                of: "\"dimension\": {\"width\": 1920, \"height\": 1080}",
                with: "\"dimension\": {\"width\": 1080, \"height\": 1920}"
            )
            return response(payload: payload, request: request)
        }
        return try await detailResponse(for: request)
    }

    static func makeDetail(width: Int, height: Int) -> FocusVideoDetail {
        FocusVideoDetail(
            bvid: "BV1xx411c7mD",
            aid: 42,
            cid: 4201,
            title: "全屏方向测试",
            summary: "",
            coverURL: nil,
            duration: 120,
            publishedAt: 0,
            width: width,
            height: height,
            owner: FocusVideoOwner(mid: 1001, name: "测试 UP", avatarURL: nil),
            statistics: FocusVideoStatistics(
                views: 0,
                danmaku: 0,
                replies: 0,
                favorites: 0,
                coins: 0,
                shares: 0,
                likes: 0
            ),
            pages: [],
            episodeGroups: []
        )
    }

    static func multiPageDetailResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url?.path == "/x/web-interface/view" {
            return response(payload: multiPageDetailPayload, request: request)
        }
        return try await detailResponse(for: request)
    }

    static func resumableMultiPageResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url?.path == "/x/player/v2" || request.url?.path == "/x/player/wbi/v2" {
            return response(
                payload: #"{"code":0,"data":{"last_play_cid":4203,"last_play_time":87000}}"#,
                request: request
            )
        }
        return try await multiPageDetailResponse(for: request)
    }

    static func nearTailMultiPageResponse(for request: URLRequest) async throws -> (Data, URLResponse) {
        if request.url?.path == "/x/player/v2" || request.url?.path == "/x/player/wbi/v2" {
            return response(
                payload: #"{"code":0,"data":{"last_play_cid":4203,"last_play_time":119000}}"#,
                request: request
            )
        }
        return try await multiPageDetailResponse(for: request)
    }

    private static func response(payload: String, request: URLRequest) -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://api.bilibili.com/")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }

    private static let detailPayload = #"""
    {
      "code": 0,
      "data": {
        "bvid": "BV1xx411c7mD",
        "aid": 42,
        "cid": 4201,
        "title": "原生控制测试",
        "desc": "测试简介",
        "pic": "https://i0.hdslb.com/bfs/archive/test.jpg",
        "duration": 120,
        "pubdate": 1710000000,
        "dimension": {"width": 1920, "height": 1080},
        "owner": {"mid": 1001, "name": "测试 UP", "face": ""},
        "stat": {"view":100,"danmaku":2,"reply":3,"favorite":4,"coin":5,"share":6,"like":7},
        "pages": [{"page":1,"cid":4201,"part":"正片","duration":120}]
      }
    }
    """#

    private static let multiPageDetailPayload = #"""
    {
      "code": 0,
      "data": {
        "bvid": "BV1xx411c7mD",
        "aid": 42,
        "cid": 4202,
        "title": "多 P 定位测试",
        "desc": "测试简介",
        "pic": "https://i0.hdslb.com/bfs/archive/test.jpg",
        "duration": 360,
        "pubdate": 1710000000,
        "dimension": {"width": 1920, "height": 1080},
        "owner": {"mid": 1001, "name": "测试 UP", "face": ""},
        "stat": {"view":100,"danmaku":2,"reply":3,"favorite":4,"coin":5,"share":6,"like":7},
        "pages": [
          {"page":1,"cid":4201,"part":"第一集","duration":120},
          {"page":2,"cid":4202,"part":"第二集","duration":120},
          {"page":3,"cid":4203,"part":"第三集","duration":120}
        ]
      }
    }
    """#

    private static let wbiPayload = #"""
    {
      "code": 0,
      "data": {
        "wbi_img": {
          "img_url": "https://i0.hdslb.com/bfs/wbi/abcdefghijklmnopqrstuvwxyzABCDEF.png",
          "sub_url": "https://i0.hdslb.com/bfs/wbi/GHIJKLMNOPQRSTUVWXYZ0123456789abcd.png"
        }
      }
    }
    """#

    private static let playbackPayload = #"""
    {
      "code": 0,
      "data": {
        "quality": 80,
        "durl": [{"url":"https://media.example.invalid/native-video.mp4"}]
      }
    }
    """#
}
