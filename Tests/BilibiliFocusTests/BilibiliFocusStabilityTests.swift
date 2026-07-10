import FocusCore
import UIKit
import WebKit
import XCTest
@testable import BilibiliFocus

@MainActor
final class BilibiliFocusStabilityTests: XCTestCase {
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

    private func makeSettingsStore() -> (FocusSettingsStore, UserDefaults, String) {
        let suiteName = "BilibiliFocusStabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (FocusSettingsStore(userDefaults: defaults), defaults, suiteName)
    }
}
