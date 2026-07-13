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
            actionService: actionService
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
