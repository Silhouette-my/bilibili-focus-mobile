#if canImport(UIKit)
@testable import BilibiliFocus
import WebKit
import XCTest

@MainActor
final class FocusWebAppearancePersistenceTests: XCTestCase {
    func testQueuedPiPTransitionIsFlushedOnceWhenDocumentHides() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = LifecycleNavigationDelegate()
        webView.navigationDelegate = navigation
        try await navigation.load(webView)
        _ = try await webView.evaluateJavaScript("""
            window.__mediaSnapshots = [];
            window.__FOCUS_SNAPSHOT_PLAYER_STATE__ = () => window.__mediaSnapshots.push(document.title);
            true;
            """)
        _ = try await webView.evaluateJavaScript(FocusWebView.Coordinator.playerStateBridgeScript(sessionID: "fixture", revision: 1))
        try await Task.sleep(for: .milliseconds(50))
        // Dispatch and hide in one JavaScript turn, before its 40 ms timer fires.
        _ = try await webView.evaluateJavaScript("""
            window.__mediaSnapshots = [];
            document.querySelector('video').dispatchEvent(new Event('webkitpresentationmodechanged'));
            document.title = 'latest PiP state';
            \(FocusWebView.Coordinator.documentActivityScript(isActive: false))
            for (let i = 0; i < 100; i++) document.body.appendChild(document.createElement('div'));
            true;
            """)
        try await Task.sleep(for: .milliseconds(200))
        let snapshots = try await webView.evaluateJavaScript("window.__mediaSnapshots") as? [String]
        XCTAssertEqual(snapshots, ["latest PiP state"], "Keep the queued media transition once, without replaying hidden DOM work")
    }

    func testRapidNativeReturnResumesEvenWhenHiddenSwiftUIUpdateWasCoalesced() async throws {
        let suite = "FocusRapidWebReturn-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FocusSettingsStore(userDefaults: defaults)
        let model = FocusBrowserViewModel(settingsStore: store)
        let coordinator = FocusWebView.Coordinator(viewModel: model)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = LifecycleNavigationDelegate()
        webView.navigationDelegate = navigation
        let url = URL(string: "https://search.bilibili.com/all?keyword=local-fixture")!
        model.open(url, context: .search)
        try await navigation.load(webView, baseURL: url)
        model.webView = webView
        model.commitNavigationState(from: webView)
        defer { coordinator.tearDown(webView: webView) }

        coordinator.updateDocumentActivity(on: webView, isActive: true, settings: store.settings, isDarkMode: false)
        _ = try await webView.evaluateJavaScript("""
            window.__runtimeUpdates = 0;
            const originalUpdate = window.__FOCUS_RUNTIME__.update;
            window.__FOCUS_RUNTIME__.update = function(...args) {
              window.__runtimeUpdates++;
              return originalUpdate.apply(this, args);
            };
            true;
            """)
        model.prepareForDismiss()
        // No coordinator isActive=false call: SwiftUI coalesces the round trip.
        let suspended = try await webView.evaluateJavaScript("window.__FOCUS_DOCUMENT_ACTIVE__") as? Bool
        XCTAssertEqual(suspended, false)
        model.resume(url, context: .search)
        coordinator.updateDocumentActivity(on: webView, isActive: true, settings: store.settings, isDarkMode: false)
        let resumed = try await webView.evaluateJavaScript("window.__FOCUS_DOCUMENT_ACTIVE__") as? Bool
        let replayUpdates = try await webView.evaluateJavaScript("window.__runtimeUpdates") as? Int
        let bridgeSession = try await webView.evaluateJavaScript("window.__FOCUS_NATIVE_PLAYER_BRIDGE__.browserSessionID") as? String
        XCTAssertEqual(resumed, true)
        XCTAssertEqual(replayUpdates, 2, "Resume refreshes documentStart and documentEnd configuration once")
        XCTAssertEqual(bridgeSession, model.activeRouteRequestSessionID?.stringValue)

        coordinator.updateDocumentActivity(on: webView, isActive: true, settings: store.settings, isDarkMode: false)
        let ordinaryUpdateReplays = try await webView.evaluateJavaScript("window.__runtimeUpdates") as? Int
        XCTAssertEqual(ordinaryUpdateReplays, replayUpdates, "An ordinary update must not replay again")
    }

    func testHiddenPlayerBridgeStopsDOMWorkButKeepsMediaEvents() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let navigation = LifecycleNavigationDelegate()
        webView.navigationDelegate = navigation
        try await navigation.load(webView)
        _ = try await webView.evaluateJavaScript("""
            window.__lifecycleEmits = 0;
            window.__pauseCalls = 0;
            window.__FOCUS_SNAPSHOT_PLAYER_STATE__ = () => window.__lifecycleEmits++;
            document.querySelector('video').pause = () => window.__pauseCalls++;
            true;
            """)
        _ = try await webView.evaluateJavaScript(FocusWebView.Coordinator.playerStateBridgeScript(sessionID: "fixture", revision: 1))
        try await Task.sleep(for: .milliseconds(50))
        _ = try await webView.evaluateJavaScript("window.__lifecycleEmits = 0; document.body.appendChild(document.createElement('div')); true;")
        try await Task.sleep(for: .milliseconds(10))
        _ = try await webView.evaluateJavaScript(FocusWebView.Coordinator.documentActivityScript(isActive: false))
        _ = try await webView.evaluateJavaScript(FocusWebView.Coordinator.documentActivityScript(isActive: false))
        _ = try await webView.evaluateJavaScript("for (let i = 0; i < 100; i++) document.body.appendChild(document.createElement('div')); true;")
        try await Task.sleep(for: .milliseconds(200))
        let hiddenEmits = try await webView.evaluateJavaScript("window.__lifecycleEmits") as? Int
        XCTAssertEqual(hiddenEmits, 0, "Hidden DOM mutations and an already queued callback must not emit")
        _ = try await webView.evaluateJavaScript("document.querySelector('video').dispatchEvent(new Event('webkitpresentationmodechanged')); true;")
        try await Task.sleep(for: .milliseconds(100))
        let mediaEmits = try await webView.evaluateJavaScript("window.__lifecycleEmits") as? Int
        XCTAssertEqual(mediaEmits, 1, "PiP/media transitions must still reach the bridge")
        _ = try await webView.evaluateJavaScript(FocusWebView.Coordinator.documentActivityScript(isActive: true))
        _ = try await webView.evaluateJavaScript(FocusWebView.Coordinator.documentActivityScript(isActive: true))
        let resumedEmits = try await webView.evaluateJavaScript("window.__lifecycleEmits") as? Int
        let pauseCalls = try await webView.evaluateJavaScript("window.__pauseCalls") as? Int
        XCTAssertEqual(resumedEmits, 2, "Repeated resume synchronizes once")
        XCTAssertEqual(pauseCalls, 0, "Visibility suspension must not stop background/PiP playback")
        _ = try await webView.evaluateJavaScript("document.body.appendChild(document.createElement('div')); true;")
        try await Task.sleep(for: .milliseconds(200))
        let reconnectedEmits = try await webView.evaluateJavaScript("window.__lifecycleEmits") as? Int
        XCTAssertEqual(reconnectedEmits, 3)
    }

    func testAppearanceChangeUpdatesFutureNavigationScripts() {
        let suite = "FocusAppearanceAudit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FocusSettingsStore(userDefaults: defaults)
        let model = FocusBrowserViewModel(settingsStore: store)
        let coordinator = FocusWebView.Coordinator(viewModel: model)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer { coordinator.tearDown(webView: webView) }

        coordinator.installScripts(on: webView, settings: store.settings, isDarkMode: false)
        coordinator.applyAppearance(on: webView, settings: store.settings, isDarkMode: true)

        let sources = webView.configuration.userContentController.userScripts.map(\.source)
        XCTAssertTrue(sources.contains(FocusWebAppearance.script(isDarkMode: true)))
        XCTAssertTrue(sources.contains(FocusWebAppearance.bootstrapCSS(isDarkMode: true)))
        XCTAssertFalse(sources.contains(FocusWebAppearance.script(isDarkMode: false)))
        XCTAssertFalse(sources.contains(FocusWebAppearance.bootstrapCSS(isDarkMode: false)))
    }
}

@MainActor
private final class LifecycleNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ webView: WKWebView, baseURL: URL? = nil) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString("<html><head><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'\"></head><body><video></video></body></html>", baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif
