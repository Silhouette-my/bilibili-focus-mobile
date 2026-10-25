#if canImport(UIKit)
import Combine
import CryptoKit
import FocusCore
import Foundation
import WebKit

@MainActor
final class FocusBrowserViewModel: ObservableObject {
    enum EntryContext: Equatable {
        case dynamic
        case search
        case my
    }

    enum AppBackAction {
        case close
        case navigate(URL)
    }

    private struct DetectedPageState: Sendable {
        let hasPlayer: Bool
        let pageURLString: String?
        let pageTitle: String?
        let videoTitle: String?
    }

    private struct BrowserCallbackContext: Equatable {
        let sessionID: BrowserSessionID
        let revision: NavigationRevision
        let canonicalURL: URL
        let webViewIdentifier: ObjectIdentifier
    }

    struct PlayerBridgeContext: Equatable, Sendable {
        let sessionID: String
        let revision: UInt64
        let canonicalURL: URL
    }

    @Published private(set) var currentURL: URL?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var hasActiveVideoRoute = false
    @Published private(set) var playerSnapshot = PlayerSnapshot.empty
    @Published private(set) var isLoadingPage = false
    @Published private(set) var entryContext: EntryContext = .dynamic
    @Published private(set) var navigationTitle = "浏览"
    @Published private(set) var nativeVideoAuthorName = ""
    @Published private(set) var nativeVideoAuthorAvatarURL: URL?
    @Published private(set) var nativeVideoAuthorSpaceURL: URL?
    @Published private(set) var nativeVideoAuthorMID: Int64 = 0
    @Published private(set) var nativeVideoAuthorFollowers: Int64 = 0
    @Published private(set) var nativeVideoAuthorIsFollowing = false
    @Published private(set) var webContentFailureMessage: String?
    let settingsStore: FocusSettingsStore

    weak var webView: WKWebView?
    var nativePageAugmentService: (any FocusNativePageAugmentServing)?
    var prepareForURL: ((WKWebView, URL) -> Void)?
    var onEntryRequest: ((FocusEntry) -> Void)?
    var onUserSpaceRequest: ((URL) -> Void)?
    var onVideoRequest: ((URL) -> Void)?
    private var pendingURL: URL?
    private var nativeVideoWebBypassIdentifier: FocusVideoIdentifier?
    private(set) var isSessionActive = false
    private var playerStateObservationTask: Task<Void, Never>?
    private var embeddedPlayerDetectionTask: Task<Void, Never>?
    private var playerCommandTask: Task<Void, Never>?
    private var pageAugmentationTask: Task<Void, Never>?
    private var pageAugmentationApplyTask: Task<Void, Never>?
    private var nativeVideoFollowTask: Task<Void, Never>?
    private var nativeVideoLoadingMaskTask: Task<Void, Never>?
    private var nativeVideoPlaceholderTask: Task<Void, Never>?
    private var pageAugmentationRevision = 0
    private var pageAugmentCache = FocusNativePageAugmentCache()
    private var pageAugmentCacheSessionVersion: UInt64?
    private var scheduledPageAugmentationKey: String?
    private var pageAugmentationFailureCounts: [String: Int] = [:]
    private var pageAugmentationRetryAfter: [String: Date] = [:]
    private var appBackStack: [URL] = []
    private var appBackSourceURL: URL?
    private var pendingAppBackTarget: URL?
    private var isHandlingAppBackNavigation = false

    var activeRouteRequestSessionID: BrowserSessionID? {
        isSessionActive ? browserSessionID : nil
    }
#if DEBUG
    private var lastDebugDetectedPageStateSignature: String?
    private var lastDebugPlayerStateSignature: String?
#endif
    private var isUpdatingNativeVideoFollow = false
    private var lastIssuedLoadURL: URL?
    private var pendingOrientationSyncAfterPlayerReady = false
    private var lastHandledDeviceOrientation: UIDeviceOrientation = .unknown
    private var orientationDebounceTask: Task<Void, Never>?
    private var fullscreenTransitionTask: Task<Void, Never>?
    private var webContentRecoveryTask: Task<Void, Never>?
    private var webContentRecoveryAttempts = 0
    private var requestedInterfaceOrientationMask: UIInterfaceOrientationMask = .portrait
    private var browserSessionID = BrowserSessionID()
    private var navigationRevisionCounter: UInt64 = 0
    private var navigationRevision = NavigationRevision(rawValue: 0)
    private var sessionCanonicalURL: URL?
    private var isAwaitingNavigationStart = false

    var websiteDataStore: WKWebsiteDataStore = FocusTestRuntime.isRunningFixtures ? .nonPersistent() : .default()

    init(settingsStore: FocusSettingsStore) {
        self.settingsStore = settingsStore
    }

    deinit {
        playerStateObservationTask?.cancel()
        embeddedPlayerDetectionTask?.cancel()
        playerCommandTask?.cancel()
        pageAugmentationTask?.cancel()
        pageAugmentationApplyTask?.cancel()
        nativeVideoFollowTask?.cancel()
        nativeVideoLoadingMaskTask?.cancel()
        nativeVideoPlaceholderTask?.cancel()
        orientationDebounceTask?.cancel()
        fullscreenTransitionTask?.cancel()
        webContentRecoveryTask?.cancel()
    }

    var navigationPolicy: FocusNavigationPolicy {
        FocusNavigationPolicy(settings: settingsStore.settings)
    }

    var hasDetectedPlayer: Bool {
        playerSnapshot.hasPlayer
    }

    var isImmersiveVideo: Bool {
        playerSnapshot.isFullscreen
    }

    var isPlaying: Bool {
        playerSnapshot.isPlaying
    }

    var playbackRate: Double {
        playerSnapshot.playbackRate
    }

    var isDanmakuHidden: Bool {
        playerSnapshot.isDanmakuHidden
    }

    var hasSubtitles: Bool {
        playerSnapshot.hasSubtitles
    }

    var isSubtitleHidden: Bool {
        playerSnapshot.isSubtitleHidden
    }

    var isVideoPage: Bool {
        if let currentURL {
            return FocusUserAgent.shouldUseDesktopPlayback(for: currentURL)
        }

        if let pendingURL {
            return FocusUserAgent.shouldUseDesktopPlayback(for: pendingURL)
        }

        return false
    }

    var showsNativeVideoControls: Bool {
        if let pendingURL, FocusUserAgent.shouldUseDesktopPlayback(for: pendingURL) {
            return true
        }

        if let currentURL, FocusUserAgent.shouldUseDesktopPlayback(for: currentURL) {
            return true
        }

        if hasDetectedPlayer || hasActiveVideoRoute {
            return true
        }

        guard let activeURL = currentURL ?? pendingURL else {
            return allowsPlayerControl
        }

        return !isSearchResultURL(activeURL) && allowsPlayerControl
    }

    var playbackRateLabel: String {
        switch playbackRate {
        case 1:
            return "1x"
        case 1.25:
            return "1.25x"
        case 1.5:
            return "1.5x"
        case 2:
            return "2x"
        default:
            return String(format: "%.2gx", playbackRate)
        }
    }

    func openNativeVideoAuthorSpace() {
        guard let nativeVideoAuthorSpaceURL else {
            return
        }
        openNativeUserSpace(nativeVideoAuthorSpaceURL)
    }

    func handleFocusActionURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "focus" else {
            return false
        }

        switch url.host?.lowercased() {
        case "toggle-follow":
            toggleNativeVideoAuthorFollow()
            return true
        default:
            return false
        }
    }

    func triggerNativeVideoAction(_ action: String) {
        guard let webView else {
            return
        }
        let escapedAction = action.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (() => {
          const action = '\(escapedAction)';
          const selectorMap = {
            like: [
              '#arc_toolbar_report .video-like-info',
              '.video-toolbar-container .video-like-info',
              '.video-like-info',
              '[class*="like-info"]',
              '[class*="toolbar"] [class*="like"]'
            ],
            coin: [
              '#arc_toolbar_report .video-coin',
              '.video-toolbar-container .video-coin',
              '.video-coin',
              '[class*="video-coin"]',
              '[class*="toolbar"] [class*="coin"]'
            ],
            favorite: [
              '#arc_toolbar_report .video-fav',
              '.video-toolbar-container .video-fav',
              '.video-fav',
              '[class*="video-fav"]',
              '[class*="toolbar"] [class*="fav"]'
            ]
          };
          const selectors = selectorMap[action] || [];
          const target = selectors
            .flatMap((selector) => Array.from(document.querySelectorAll(selector)))
            .find((node) => {
              const rect = node.getBoundingClientRect?.();
              return !!rect && rect.width > 8 && rect.height > 8;
            });
          if (!target) {
            return false;
          }
          const clickable = target.querySelector('button, [role="button"], a') || target;
          clickable.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func attach(
        webView: WKWebView,
        prepareForURL: @escaping (WKWebView, URL) -> Void
    ) {
        self.webView = webView
        self.prepareForURL = prepareForURL

        if let pendingURL {
            loadURLIfNeeded(pendingURL, on: webView, reason: "attach")
        }
    }

    func playerBridgeContext(for candidateWebView: WKWebView) -> PlayerBridgeContext? {
        guard
            webView === candidateWebView,
            let context = makeBrowserCallbackContext(for: candidateWebView)
        else {
            return nil
        }

        return PlayerBridgeContext(
            sessionID: context.sessionID.stringValue,
            revision: context.revision.rawValue,
            canonicalURL: context.canonicalURL
        )
    }

    func handlePlayerStateMessage(_ body: Any, from sourceWebView: WKWebView?) {
        guard
            let sourceWebView,
            let payload = body as? [String: Any],
            let context = makeBrowserCallbackContext(for: sourceWebView),
            payload["browserSessionID"] as? String == context.sessionID.stringValue,
            Self.uint64Value(payload["navigationRevision"]) == context.revision.rawValue,
            let payloadURLString = payload["pageURL"] as? String,
            let payloadURL = URL(string: payloadURLString).map(FocusNavigationPolicy.canonicalWebURL(for:)),
            payloadURL == context.canonicalURL,
            isCurrent(context, webView: sourceWebView)
        else {
            debugLog(
                "playerStateMessage.discarded",
                fields: debugStateFields([
                    "messageSessionID": (body as? [String: Any])?["browserSessionID"] as? String,
                    "messageRevision": Self.uint64Value((body as? [String: Any])?["navigationRevision"]).map(String.init),
                    "messageURL": (body as? [String: Any])?["pageURL"] as? String
                ])
            )
            return
        }

        applyPlayerStatePayload(payload, context: context, webView: sourceWebView, source: "playerStateMessage")
    }

    private func prepareNavigationSession(to url: URL, force: Bool = false) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard force || !isAwaitingNavigationStart || sessionCanonicalURL != canonicalURL else {
            return
        }

        advanceNavigationSession(to: canonicalURL, awaitingStart: true)
    }

    private func markNavigationStarted(at url: URL?) {
        let canonicalURL = url.map(FocusNavigationPolicy.canonicalWebURL(for:))
        if isAwaitingNavigationStart, sessionCanonicalURL == canonicalURL {
            isAwaitingNavigationStart = false
            return
        }

        advanceNavigationSession(to: canonicalURL, awaitingStart: false)
    }

    private func alignNavigationSessionIfNeeded(to url: URL?) {
        guard let canonicalURL = url.map(FocusNavigationPolicy.canonicalWebURL(for:)) else {
            return
        }
        guard sessionCanonicalURL != canonicalURL else {
            isAwaitingNavigationStart = false
            return
        }

        advanceNavigationSession(to: canonicalURL, awaitingStart: false)
    }

    private func advanceNavigationSession(to canonicalURL: URL?, awaitingStart: Bool) {
        nativeVideoFollowTask?.cancel()
        nativeVideoFollowTask = nil
        isUpdatingNativeVideoFollow = false
        navigationRevisionCounter &+= 1
        navigationRevision = NavigationRevision(rawValue: navigationRevisionCounter)
        browserSessionID = BrowserSessionID()
        sessionCanonicalURL = canonicalURL
        isAwaitingNavigationStart = awaitingStart
        playerStateObservationTask?.cancel()
        playerStateObservationTask = nil
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = nil
        playerCommandTask?.cancel()
        playerCommandTask = nil
        pageAugmentationApplyTask?.cancel()
        pageAugmentationApplyTask = nil
        updatePlayerSnapshot(.empty)
    }

    private func invalidateBrowserCallbacks() {
        advanceNavigationSession(to: nil, awaitingStart: false)
    }

    private func makeBrowserCallbackContext(for candidateWebView: WKWebView) -> BrowserCallbackContext? {
        guard webView === candidateWebView else {
            return nil
        }
        guard let canonicalURL = (candidateWebView.url ?? sessionCanonicalURL ?? currentURL ?? pendingURL)
            .map(FocusNavigationPolicy.canonicalWebURL(for:))
        else {
            return nil
        }
        guard sessionCanonicalURL == canonicalURL else {
            return nil
        }

        return BrowserCallbackContext(
            sessionID: browserSessionID,
            revision: navigationRevision,
            canonicalURL: canonicalURL,
            webViewIdentifier: ObjectIdentifier(candidateWebView)
        )
    }

    private func isCurrent(_ context: BrowserCallbackContext, webView candidateWebView: WKWebView) -> Bool {
        guard webView === candidateWebView else {
            return false
        }

        let callbackStamp = BrowserCallbackStamp(
            sessionID: context.sessionID,
            revision: context.revision,
            canonicalURL: context.canonicalURL,
            webViewIdentifier: context.webViewIdentifier
        )
        let currentStamp = BrowserCallbackStamp(
            sessionID: browserSessionID,
            revision: navigationRevision,
            canonicalURL: sessionCanonicalURL ?? context.canonicalURL,
            webViewIdentifier: ObjectIdentifier(candidateWebView)
        )
        guard
            sessionCanonicalURL != nil,
            BrowserCallbackGate.accepts(callbackStamp, current: currentStamp)
        else {
            return false
        }

        let activeURL = (candidateWebView.url ?? currentURL ?? pendingURL)
            .map(FocusNavigationPolicy.canonicalWebURL(for:))
        return activeURL == context.canonicalURL
    }

    func open(_ url: URL, context: EntryContext) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        if FocusVideoIdentifier.extract(from: canonicalURL) != nativeVideoWebBypassIdentifier {
            nativeVideoWebBypassIdentifier = nil
        }
        isSessionActive = true
        webContentRecoveryTask?.cancel()
        webContentRecoveryTask = nil
        webContentRecoveryAttempts = 0
        webContentFailureMessage = nil
        resetAppBackStack()
        invalidatePageAugmentation()
        prepareNavigationSession(to: canonicalURL, force: true)
        if let webView {
            suspendActivePlayback(in: webView)
            webView.stopLoading()
        }
        resetPlayerState()
        entryContext = context
        pendingURL = canonicalURL
        isLoadingPage = true
        hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: canonicalURL)
        updateNavigationMetadata(for: canonicalURL, pageTitle: nil, context: context)
        if let webView {
            loadURLIfNeeded(canonicalURL, on: webView, reason: "open")
        }

        debugLog(
            "open",
            fields: debugStateFields([
                "inputURL": canonicalURL.absoluteString,
                "context": entryContextLabel(context)
            ])
        )
    }

    func resume(_ url: URL, context: EntryContext) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard let webView,
              currentURL == canonicalURL,
              webView.url.map(FocusNavigationPolicy.canonicalWebURL(for:)) == canonicalURL else {
            open(url, context: context)
            return
        }

        // Returning from a native detail restores this route's committed
        // document, not a new browser entry. No didCommit follows this path.
        isSessionActive = true
        entryContext = context
        prepareNavigationSession(to: canonicalURL, force: true)
        updateNavigationState(from: webView)
    }

    func reload() {
        if let webView {
            let targetURL = (webView.url ?? currentURL ?? pendingURL)
                .map(FocusNavigationPolicy.canonicalWebURL(for:))
            if let targetURL {
                prepareNavigationSession(to: targetURL, force: true)
            }
            webView.reload()
            return
        }

        guard let pendingURL else {
            return
        }

        if let webView {
            prepareForURL?(webView, pendingURL)
        }
        webView?.load(URLRequest(url: pendingURL))
    }

    func goBack() {
        guard canGoBack else { return }
        if let targetURL = webView?.backForwardList.backItem?.url {
            prepareNavigationSession(to: targetURL, force: true)
        }
        webView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        if let targetURL = webView?.backForwardList.forwardItem?.url {
            prepareNavigationSession(to: targetURL, force: true)
        }
        webView?.goForward()
    }

    func noteUpcomingNavigation(to url: URL, from currentURL: URL?, navigationType: WKNavigationType) {
        let canonicalTargetURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        let canonicalCurrentURL = currentURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
        let shouldPushAppBack = shouldPushAppBackEntry(
            from: canonicalCurrentURL,
            to: canonicalTargetURL,
            navigationType: navigationType
        )

        prepareNavigationSession(to: canonicalTargetURL)

        pendingURL = canonicalTargetURL
        updateNavigationMetadata(for: canonicalTargetURL)
        if canonicalCurrentURL != canonicalTargetURL {
            isLoadingPage = true
        }
        hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: canonicalTargetURL)

        if isHandlingAppBackNavigation {
            debugLog(
                "noteUpcomingNavigation",
                fields: debugStateFields([
                    "fromURL": canonicalCurrentURL?.absoluteString,
                    "targetURL": canonicalTargetURL.absoluteString,
                    "navigationType": navigationTypeLabel(navigationType),
                    "handlingAppBack": debugBool(isHandlingAppBackNavigation),
                    "shouldPushAppBack": debugBool(shouldPushAppBack)
                ])
            )
            return
        }

        guard shouldPushAppBack,
              let canonicalCurrentURL,
              appBackStack.last != canonicalCurrentURL
        else {
            debugLog(
                "noteUpcomingNavigation",
                fields: debugStateFields([
                    "fromURL": canonicalCurrentURL?.absoluteString,
                    "targetURL": canonicalTargetURL.absoluteString,
                    "navigationType": navigationTypeLabel(navigationType),
                    "handlingAppBack": debugBool(isHandlingAppBackNavigation),
                    "shouldPushAppBack": debugBool(shouldPushAppBack)
                ])
            )
            return
        }

        appBackStack.append(canonicalCurrentURL)
        debugLog(
            "noteUpcomingNavigation",
            fields: debugStateFields([
                "fromURL": canonicalCurrentURL.absoluteString,
                "targetURL": canonicalTargetURL.absoluteString,
                "navigationType": navigationTypeLabel(navigationType),
                "handlingAppBack": debugBool(isHandlingAppBackNavigation),
                "shouldPushAppBack": debugBool(shouldPushAppBack),
                "appBackDepth": String(appBackStack.count)
            ])
        )
    }

    func updateNavigationState(from webView: WKWebView) {
        guard self.webView === webView else {
            return
        }
        let resolvedURL = webView.url.map(FocusNavigationPolicy.canonicalWebURL(for:))
        alignNavigationSessionIfNeeded(to: resolvedURL)
        currentURL = resolvedURL
        appBackSourceURL = resolvedURL
        pendingURL = currentURL
        isLoadingPage = false
        webContentRecoveryTask?.cancel()
        webContentRecoveryTask = nil
        webContentRecoveryAttempts = 0
        webContentFailureMessage = nil
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        updateNavigationMetadata(for: currentURL, pageTitle: webView.title)
        playerStateObservationTask?.cancel()
        embeddedPlayerDetectionTask?.cancel()
        lastIssuedLoadURL = currentURL

        if isHandlingAppBackNavigation,
           let resolvedURL = currentURL,
           let pendingAppBackTarget,
           resolvedURL == pendingAppBackTarget
        {
            isHandlingAppBackNavigation = false
            self.pendingAppBackTarget = nil
        }

        if let currentURL {
            hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: currentURL)
        }

        if hasActiveVideoRoute {
            debugLog(
                "updateNavigationState",
                fields: debugStateFields([
                    "webViewURL": webView.url?.absoluteString,
                    "webViewTitle": webView.title,
                    "canGoBack": debugBool(webView.canGoBack),
                    "canGoForward": debugBool(webView.canGoForward),
                    "mode": "video-route"
                ])
            )
            schedulePageAugmentationRefresh()
            startPlayerStateObservation()
            return
        }

        resetPlayerState()
        debugLog(
            "updateNavigationState",
            fields: debugStateFields([
                "webViewURL": webView.url?.absoluteString,
                "webViewTitle": webView.title,
                "canGoBack": debugBool(webView.canGoBack),
                "canGoForward": debugBool(webView.canGoForward),
                "mode": "page"
            ])
        )
        schedulePageAugmentationRefresh()
        if webView.url != nil {
            startEmbeddedPlayerDetection(on: webView)
        }
    }

    func commitNavigationState(from webView: WKWebView) {
        guard self.webView === webView else {
            return
        }
        let resolvedURL = webView.url.map(FocusNavigationPolicy.canonicalWebURL(for:))
        alignNavigationSessionIfNeeded(to: resolvedURL)
        currentURL = resolvedURL
        appBackSourceURL = resolvedURL
        pendingURL = resolvedURL
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        updateNavigationMetadata(for: resolvedURL, pageTitle: webView.title)
        lastIssuedLoadURL = resolvedURL

        if isHandlingAppBackNavigation,
           let resolvedURL,
           let pendingAppBackTarget,
           resolvedURL == pendingAppBackTarget
        {
            isHandlingAppBackNavigation = false
            self.pendingAppBackTarget = nil
        }

        let isCommittedVideoRoute = resolvedURL.map(FocusUserAgent.shouldUseDesktopPlayback(for:)) ?? false
        if isCommittedVideoRoute {
            isLoadingPage = false
            hasActiveVideoRoute = true
            schedulePageAugmentationRefresh()
            if let resolvedURL {
                installNativeVideoOriginalSectionSuppression(for: resolvedURL)
            }
            startPlayerStateObservation()
        } else {
            nativeVideoLoadingMaskTask?.cancel()
            nativeVideoLoadingMaskTask = nil
            resetPlayerState()
        }

        debugLog(
            "commitNavigationState",
            fields: debugStateFields([
                "webViewURL": resolvedURL?.absoluteString,
                "webViewTitle": webView.title,
                "canGoBack": debugBool(webView.canGoBack),
                "canGoForward": debugBool(webView.canGoForward),
                "isVideoRoute": debugBool(isCommittedVideoRoute)
            ])
        )
    }

    func beginNavigation(to url: URL?) {
        var isStaleStartURL = false
        let targetURL = (pendingURL ?? url).map(FocusNavigationPolicy.canonicalWebURL(for:))
        markNavigationStarted(at: targetURL)
        if let targetURL {
            let canonicalCurrentURL = currentURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
            let canonicalPendingURL = pendingURL.map(FocusNavigationPolicy.canonicalWebURL(for:))
            isStaleStartURL = canonicalCurrentURL == targetURL
                && canonicalPendingURL != nil
                && canonicalPendingURL != targetURL

            if !isStaleStartURL {
                invalidatePageAugmentation()
                pendingURL = targetURL
                updateNavigationMetadata(for: targetURL)
            }
        }
        nativeVideoLoadingMaskTask?.cancel()
        nativeVideoLoadingMaskTask = nil
        if let targetURL, FocusUserAgent.shouldUseDesktopPlayback(for: targetURL) {
            dismissNativeVideoPlaceholder(for: targetURL)
        }
        isLoadingPage = true
        debugLog(
            "beginNavigation",
            fields: debugStateFields([
                "inputURL": url?.absoluteString,
                "targetURL": targetURL?.absoluteString,
                "isStaleStartURL": debugBool(isStaleStartURL)
            ])
        )
    }

    func handleNavigationFailure(failingURL: URL?) {
        if let failingURL {
            pendingURL = FocusNavigationPolicy.canonicalWebURL(for: failingURL)
            updateNavigationMetadata(for: pendingURL)
        }
        nativeVideoLoadingMaskTask?.cancel()
        nativeVideoLoadingMaskTask = nil
        isLoadingPage = false
        lastIssuedLoadURL = nil
        invalidateBrowserCallbacks()
        debugLog(
            "handleNavigationFailure",
            fields: debugStateFields([
                "failingURL": failingURL?.absoluteString
            ])
        )
    }

    func handleWebContentProcessTermination(_ terminatedWebView: WKWebView) {
        guard webView === terminatedWebView else {
            return
        }

        invalidateBrowserCallbacks()
        invalidatePageAugmentation()
        resetPlayerState()
        webContentRecoveryTask?.cancel()
        webContentRecoveryTask = nil

        let candidateRecoveryURL = (terminatedWebView.url ?? currentURL ?? pendingURL)
            .map(FocusNavigationPolicy.canonicalWebURL(for:))
        let recoveryURL: URL
        switch WebContentRecoveryPolicy.decision(
            isSessionActive: isSessionActive,
            attempts: webContentRecoveryAttempts,
            recoveryURL: candidateRecoveryURL
        ) {
        case .inactive:
            isLoadingPage = false
            return
        case let .showRetry(message):
            isLoadingPage = false
            webContentFailureMessage = message
            return
        case let .recover(url):
            recoveryURL = url
        }

        webContentRecoveryAttempts += 1
        webContentFailureMessage = nil
        pendingURL = recoveryURL
        isLoadingPage = true
        prepareNavigationSession(to: recoveryURL, force: true)

        webContentRecoveryTask = Task { @MainActor [weak self, weak terminatedWebView] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard
                let self,
                !Task.isCancelled,
                let terminatedWebView,
                self.webView === terminatedWebView,
                self.isSessionActive
            else {
                return
            }

            self.prepareForURL?(terminatedWebView, recoveryURL)
            self.lastIssuedLoadURL = recoveryURL
            terminatedWebView.load(
                URLRequest(
                    url: recoveryURL,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 30
                )
            )
            self.webContentRecoveryTask = nil
        }
    }

    func retryAfterWebContentFailure() {
        guard let recoveryURL = currentURL ?? pendingURL else {
            return
        }

        webContentRecoveryAttempts = 0
        webContentFailureMessage = nil
        isLoadingPage = true
        if let webView {
            loadURLIfNeeded(recoveryURL, on: webView, reason: "manualWebContentRecovery", force: true)
        }
    }

    func entryRedirect(for url: URL) -> FocusEntry? {
        FocusKMPRouterAdapter.redirectTarget(
            for: url,
            settings: settingsStore.settings
        )
    }

    func requestNativeEntry(_ entry: FocusEntry) {
        onEntryRequest?(entry)
    }

    func shouldOpenNativeUserSpace(_ url: URL) -> Bool {
        Self.extractUserSpaceMID(from: url) != nil
    }

    func openNativeUserSpace(_ url: URL) {
        onUserSpaceRequest?(FocusNavigationPolicy.canonicalWebURL(for: url))
    }

    func shouldRouteVideoNavigationToNative(_ url: URL, currentURL: URL?) -> Bool {
        guard FocusVideoIdentifier.extract(from: url) != nil else {
            return false
        }

        let identifier = FocusVideoIdentifier.extract(from: url)
        if nativeVideoWebBypassIdentifier == identifier {
            return false
        }
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        if let currentURL,
           FocusNavigationPolicy.canonicalWebURL(for: currentURL) == canonicalURL
        {
            return false
        }
        return true
    }

    func openNativeVideo(_ url: URL) {
        onVideoRequest?(FocusNavigationPolicy.canonicalWebURL(for: url))
    }

    func allowNextVideoNavigationInWeb(for url: URL) {
        nativeVideoWebBypassIdentifier = FocusVideoIdentifier.extract(from: url)
    }

    func resolveAppBackAction() -> AppBackAction {
        guard let targetURL = appBackStack.popLast() else {
            return .close
        }

        return .navigate(targetURL)
    }

    func navigateAppBack(to url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        invalidatePageAugmentation()
        isHandlingAppBackNavigation = true
        pendingAppBackTarget = canonicalURL
        pendingURL = canonicalURL
        isLoadingPage = true
        hasActiveVideoRoute = FocusUserAgent.shouldUseDesktopPlayback(for: canonicalURL)
        updateNavigationMetadata(for: canonicalURL)

        if !hasActiveVideoRoute {
            resetPlayerState()
        }

        if let webView {
            if let historyItem = historyItem(for: canonicalURL, in: webView) {
                prepareNavigationSession(to: canonicalURL, force: true)
                debugLog(
                    "navigateAppBack",
                    fields: debugStateFields([
                        "targetURL": canonicalURL.absoluteString,
                        "usedHistoryItem": debugBool(true),
                        "appBackDepth": String(appBackStack.count)
                    ])
                )
                webView.go(to: historyItem)
                return
            }

            loadURLIfNeeded(canonicalURL, on: webView, reason: "navigateAppBack")
        }

        debugLog(
            "navigateAppBack",
            fields: debugStateFields([
                "targetURL": canonicalURL.absoluteString,
                "usedHistoryItem": debugBool(false),
                "appBackDepth": String(appBackStack.count)
            ])
        )
    }

    func navigationDecision(for url: URL, currentURL: URL? = nil) -> FocusNavigationPolicy.Decision {
        navigationPolicy.decision(for: url, currentURL: currentURL)
    }

    func logNavigationDecision(
        url: URL,
        currentURL: URL?,
        navigationType: WKNavigationType,
        decision: String
    ) {
        debugLog(
            "navigationDecision",
            fields: debugStateFields([
                "requestURL": url.absoluteString,
                "currentURL": currentURL?.absoluteString,
                "navigationType": navigationTypeLabel(navigationType),
                "decision": decision
            ])
        )
    }

    func cyclePlaybackRate() {
        let rates: [Double] = [1.0, 1.25, 1.5, 2.0]
        let nextIndex = rates.firstIndex(of: playbackRate).map { ($0 + 1) % rates.count } ?? 0
        let nextRate = rates[nextIndex]

        runPlayerCommand(
            """
            (() => {
              const rate = \(nextRate);
              const videos = Array.from(document.querySelectorAll('video'));
              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const rankedVideos = videos
                .map((video) => {
                  const rect = video.getBoundingClientRect();
                  const style = window.getComputedStyle(video);
                  const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                  const visible = rect.width > 120
                    && rect.height > 70
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                  const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
                  const score = (insidePlayer ? 1000000 : 0) + (visible ? 100000 : 0) + area + (video.readyState > 0 ? 5000 : 0);
                  return { video, score };
                })
                .sort((left, right) => right.score - left.score);
              const primaryVideo = trackedVideo && trackedVideo.isConnected ? trackedVideo : (rankedVideos[0]?.video || null);
              const targetVideos = primaryVideo ? [primaryVideo] : videos;
              if (primaryVideo) {
                window.__FOCUS_ACTIVE_VIDEO__ = primaryVideo;
              }

              targetVideos.forEach((video) => {
                video.playbackRate = rate;
                video.defaultPlaybackRate = rate;
                video.dispatchEvent(new Event('ratechange'));
              });
              if (typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function') {
                window.__FOCUS_SNAPSHOT_PLAYER_STATE__();
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 80);
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 260);
              }
              return targetVideos.length > 0;
            })();
            """
        )
    }

    func togglePlayback() {
        runPlayerCommand(
            """
            (() => {
              const videos = Array.from(document.querySelectorAll('video'));
              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const rankedVideos = videos
                .map((video) => {
                  const rect = video.getBoundingClientRect();
                  const style = window.getComputedStyle(video);
                  const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                  const visible = rect.width > 120
                    && rect.height > 70
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                  const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
                  const score = (insidePlayer ? 1000000 : 0) + (visible ? 100000 : 0) + area + (video.readyState > 0 ? 5000 : 0) + (!video.paused && !video.ended ? 1000 : 0);
                  return { video, score };
                })
                .sort((left, right) => right.score - left.score);
              const primaryVideo = trackedVideo && trackedVideo.isConnected ? trackedVideo : (rankedVideos[0]?.video || null);
              const playButton = document.querySelector('.bpx-player-ctrl-play, .bilibili-player-video-btn-start, [class*="ctrl-play"]');
              const hasPlayingVideo = primaryVideo
                ? (!primaryVideo.paused && !primaryVideo.ended)
                : videos.some((video) => !video.paused && !video.ended);
              let didIssueCommand = false;

              if (primaryVideo) {
                window.__FOCUS_ACTIVE_VIDEO__ = primaryVideo;
                if (hasPlayingVideo) {
                  primaryVideo.pause?.();
                } else {
                  const playTask = primaryVideo.play?.();
                  if (playTask && typeof playTask.catch === 'function') {
                    playTask.catch(() => {});
                  }
                }
                primaryVideo.dispatchEvent(new Event(hasPlayingVideo ? 'pause' : 'play'));
                didIssueCommand = true;
              } else if (playButton) {
                playButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                didIssueCommand = true;
              }

              if (typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function' && didIssueCommand) {
                window.__FOCUS_SNAPSHOT_PLAYER_STATE__();
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 90);
                setTimeout(() => window.__FOCUS_SNAPSHOT_PLAYER_STATE__(), 280);
              }

              return didIssueCommand;
            })();
            """
        )
    }

    func toggleDanmaku() {
        runPlayerCommand(
            """
            (() => {
              const toggle = document.querySelector('.bpx-player-ctrl-dm, .bpx-player-dm-switch, [class*="dm-switch"], [class*="ctrl-dm"]');
              if (toggle) {
                toggle.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              const hidden = !document.documentElement.classList.contains('focus-hide-danmaku');
              document.documentElement.classList.toggle('focus-hide-danmaku', hidden);
              return !!document.querySelector('video');
            })();
            """
        )
    }

    func requestFullscreen() {
        runPlayerCommand(
            """
            (() => {
              if (typeof window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__ === 'function') {
                window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__('expanded');
              }
              if (typeof window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__ === 'function') {
                window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__(1400, 'expanded');
              } else if (typeof window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__ === 'function') {
                window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__();
              }

              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const videos = Array.from(document.querySelectorAll('video'));
              const rankedVideos = videos
                .map((video) => {
                  const rect = video.getBoundingClientRect();
                  const style = window.getComputedStyle(video);
                  const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                  const visible = rect.width > 120
                    && rect.height > 70
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                  const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
                  const score = (insidePlayer ? 1000000 : 0) + (visible ? 100000 : 0) + area + (video.readyState > 0 ? 5000 : 0);
                  return { video, score };
                })
                .sort((left, right) => right.score - left.score);
              const video = trackedVideo && trackedVideo.isConnected ? trackedVideo : (rankedVideos[0]?.video || null);
              if (video) {
                window.__FOCUS_ACTIVE_VIDEO__ = video;
              }

              if (video && typeof video.webkitEnterFullscreen === 'function') {
                try {
                  video.webkitEnterFullscreen();
                  return true;
                } catch (_) {}
              }

              if (video && typeof video.webkitSetPresentationMode === 'function') {
                try {
                  video.webkitSetPresentationMode('fullscreen');
                  return true;
                } catch (_) {}
              }

              if (video && typeof video.requestFullscreen === 'function') {
                try {
                  video.requestFullscreen();
                  return true;
                } catch (_) {}
              }

              const fullscreenButton = document.querySelector('.bpx-player-ctrl-full, [class*="ctrl-full"], [class*="fullscreen"]');
              if (fullscreenButton) {
                fullscreenButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              const webFullscreenButton = document.querySelector('.bpx-player-ctrl-web, [class*="web-fullscreen"]');
              if (webFullscreenButton) {
                webFullscreenButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              return false;
            })();
            """
        )
    }

    func exitFullscreen() {
        let shouldResumePlayback = isPlaying
        runPlayerCommand(
            """
            (() => {
              if (typeof window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__ === 'function') {
                window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__('automatic');
              }
              if (typeof window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__ === 'function') {
                window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__(900, 'automatic');
              } else if (typeof window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__ === 'function') {
                window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__();
              }

              const trackedVideo = window.__FOCUS_ACTIVE_VIDEO__;
              const videos = Array.from(document.querySelectorAll('video'));
              const rankedVideos = videos
                .map((video) => {
                  const rect = video.getBoundingClientRect();
                  const style = window.getComputedStyle(video);
                  const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
                  const visible = rect.width > 120
                    && rect.height > 70
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                  const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
                  const score = (insidePlayer ? 1000000 : 0) + (visible ? 100000 : 0) + area + (video.readyState > 0 ? 5000 : 0);
                  return { video, score };
                })
                .sort((left, right) => right.score - left.score);
              const video = trackedVideo && trackedVideo.isConnected ? trackedVideo : (rankedVideos[0]?.video || null);
              const shouldResumePlayback = \(shouldResumePlayback ? "true" : "false");
              if (video) {
                window.__FOCUS_ACTIVE_VIDEO__ = video;
              }

              let exited = false;
              const isNativeFullscreen = !!video && (
                video.webkitDisplayingFullscreen === true
                || video.webkitPresentationMode === 'fullscreen'
              );

              if (isNativeFullscreen && video && typeof video.webkitSetPresentationMode === 'function') {
                try {
                  video.webkitSetPresentationMode('inline');
                  exited = true;
                } catch (_) {}
              }

              if (!exited && isNativeFullscreen && video && typeof video.webkitExitFullscreen === 'function') {
                try {
                  video.webkitExitFullscreen();
                  exited = true;
                } catch (_) {}
              }

              if (!exited && document.fullscreenElement && typeof document.exitFullscreen === 'function') {
                try {
                  document.exitFullscreen();
                  exited = true;
                } catch (_) {}
              }

              if (!exited) {
                const exitButton = document.querySelector('.bpx-player-ctrl-web, .bpx-player-ctrl-full, [class*="web-fullscreen"], [class*="exit-fullscreen"]');
                if (exitButton) {
                  exitButton.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                  exited = true;
                }
              }

              if (shouldResumePlayback && video && !video.ended) {
                const resume = () => {
                  try {
                    const playTask = video.play?.();
                    if (playTask && typeof playTask.catch === 'function') {
                      playTask.catch(() => {});
                    }
                  } catch (_) {}
                };

                if (video.paused) {
                  resume();
                }
                setTimeout(() => {
                  if (video.paused && !video.ended) {
                    resume();
                  }
                }, 80);
                setTimeout(() => {
                  if (video.paused && !video.ended) {
                    resume();
                  }
                }, 260);
                setTimeout(() => {
                  if (video.paused && !video.ended) {
                    resume();
                  }
                }, 520);
              }

              return exited;
            })();
            """
        )
    }

    @MainActor
    private func enterLandscapeFullscreen() {
        let targetMask: UIInterfaceOrientationMask = .landscape
        let requiresNativeRotation = requestedInterfaceOrientationMask != targetMask

        runPlayerCommand(
            """
            (() => {
              window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__?.('expanded');
              window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__?.(1800, 'expanded');
              return true;
            })();
            """
        )

        if requiresNativeRotation {
            requestedInterfaceOrientationMask = targetMask
            updateSupportedOrientations(to: targetMask)
        }

        fullscreenTransitionTask?.cancel()
        fullscreenTransitionTask = Task { @MainActor [weak self] in
            let delay: UInt64 = requiresNativeRotation ? 160_000_000 : 40_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else {
                return
            }
            if !self.isImmersiveVideo {
                self.requestFullscreen()
            }
        }
    }

    @MainActor
    private func exitLandscapeFullscreen() {
        let needsPortraitRestore = requestedInterfaceOrientationMask != .portrait
        let needsFullscreenExit = isImmersiveVideo
        guard needsFullscreenExit || needsPortraitRestore else {
            return
        }

        fullscreenTransitionTask?.cancel()
        if needsPortraitRestore {
            runPlayerCommand(
                """
                (() => {
                  window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__?.('automatic');
                  window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__?.(900, 'automatic');
                  return true;
                })();
                """
            )
            requestedInterfaceOrientationMask = .portrait
            updateSupportedOrientations(to: .portrait)
        }

        guard needsFullscreenExit else {
            return
        }

        fullscreenTransitionTask = Task { @MainActor [weak self] in
            let delay: UInt64 = needsPortraitRestore ? 40_000_000 : 0
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else {
                return
            }
            if self.isImmersiveVideo {
                self.exitFullscreen()
            }
        }
    }

    @MainActor
    private func updateSupportedOrientations(to mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask

        guard let rootViewController = activeRootViewController else {
            return
        }

        rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        rootViewController.navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        rootViewController.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private var activeRootViewController: UIViewController? {
        let activeWindowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { scene in
                scene.activationState == .foregroundActive
            }
        return activeWindowScene?
            .windows.first(where: \.isKeyWindow)?
            .rootViewController
    }

    func toggleSubtitles() {
        runPlayerCommand(
            """
            (() => {
              const subtitleToggle = document.querySelector('.bpx-player-ctrl-subtitle, .bpx-player-subtitle-btn, [class*="subtitle-switch"], [class*="subtitle-btn"], [class*="subtitle"] button');
              if (subtitleToggle) {
                subtitleToggle.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                return true;
              }

              const video = document.querySelector('video');
              if (!video || !video.textTracks) {
                return false;
              }

              const tracks = Array.from(video.textTracks);
              if (tracks.length === 0) {
                return false;
              }

              const hasVisibleTrack = tracks.some((track) => track.mode !== 'disabled');
              tracks.forEach((track) => {
                track.mode = hasVisibleTrack ? 'disabled' : 'showing';
              });

              document.documentElement.classList.toggle('focus-hide-subtitles', hasVisibleTrack);
              return true;
            })();
            """
        )
    }

    func handleDeviceOrientationChange(_ orientation: UIDeviceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        guard orientation.isLandscape || orientation == .portrait else {
            return
        }

        if lastHandledDeviceOrientation == orientation {
            return
        }
        lastHandledDeviceOrientation = orientation

        orientationDebounceTask?.cancel()
        orientationDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, !Task.isCancelled else {
                return
            }
            self.handleStableDeviceOrientationChange(orientation)
        }
    }

    @MainActor
    private func handleStableDeviceOrientationChange(_ orientation: UIDeviceOrientation) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }

        let activeTargetURL = (isLoadingPage ? (pendingURL ?? currentURL) : (currentURL ?? pendingURL))
            .map(FocusNavigationPolicy.canonicalWebURL(for:))

        guard let activeTargetURL, FocusUserAgent.shouldUseDesktopPlayback(for: activeTargetURL) else {
            pendingOrientationSyncAfterPlayerReady = false
            return
        }

        guard !isLoadingPage, hasDetectedPlayer else {
            pendingOrientationSyncAfterPlayerReady = orientation.isLandscape || orientation == .portrait
            return
        }

        pendingOrientationSyncAfterPlayerReady = false
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            if !isImmersiveVideo {
                enterLandscapeFullscreen()
            }
        case .portrait:
            exitLandscapeFullscreen()
        default:
            break
        }
    }

    func prepareForDismiss() {
        isSessionActive = false
        invalidateBrowserCallbacks()
        webContentRecoveryTask?.cancel()
        webContentRecoveryTask = nil
        webContentFailureMessage = nil
        if let webView {
            suspendActivePlayback(in: webView)
            webView.stopLoading()
        }
        invalidatePageAugmentation()
        resetPlayerState()
        isLoadingPage = false
        requestedInterfaceOrientationMask = .portrait
        updateSupportedOrientations(to: .portrait)
        navigationTitle = "浏览"
        entryContext = .dynamic
        lastIssuedLoadURL = nil
        pendingOrientationSyncAfterPlayerReady = false
        lastHandledDeviceOrientation = .unknown
        orientationDebounceTask?.cancel()
        orientationDebounceTask = nil
        fullscreenTransitionTask?.cancel()
        fullscreenTransitionTask = nil
        resetAppBackStack()
    }

    func detach(webView detachedWebView: WKWebView) {
        guard webView === detachedWebView else {
            return
        }

        isSessionActive = false
        invalidateBrowserCallbacks()
        webContentRecoveryTask?.cancel()
        webContentRecoveryTask = nil
        if let webView {
            suspendActivePlayback(in: webView)
            webView.stopLoading()
        }
        invalidatePageAugmentation()
        resetPlayerState()
        prepareForURL = nil
        self.webView = nil
        webContentFailureMessage = nil
        isLoadingPage = false
    }

    private func suspendActivePlayback(in webView: WKWebView) {
        let script = """
        (() => {
          try {
            if (document.fullscreenElement && typeof document.exitFullscreen === 'function') {
              document.exitFullscreen();
            }
          } catch (_) {}

          if (window.__FOCUS_LOADING_MASK_OBSERVER__) {
            try {
              window.__FOCUS_LOADING_MASK_OBSERVER__.disconnect();
            } catch (_) {}
            window.__FOCUS_LOADING_MASK_OBSERVER__ = null;
          }

          if (window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__?.teardown) {
            try {
              window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__.teardown();
            } catch (_) {}
          }
          window.__FOCUS_NATIVE_VIDEO_AUGMENT_HELPERS__ = null;

          document.documentElement.classList.remove('focus-native-video-ready', 'focus-hide-danmaku', 'focus-hide-subtitles');
          document.documentElement.classList.remove('focus-native-video-fallback');
          document.documentElement.removeAttribute('data-focus-player-layout');
          document.body?.classList?.remove?.('focus-native-video-ready');
          document.getElementById('focus-native-video-prehide-style')?.remove?.();

          try {
            window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__?.();
          } catch (_) {}
          window.__FOCUS_CLEAR_IOS_PLAYER_SIZING__ = null;
          window.__FOCUS_SUPPRESS_IOS_PLAYER_SIZING__ = null;
          window.__FOCUS_SET_IOS_PLAYER_LAYOUT_MODE__ = null;

          [
            'focus-native-video-augment',
            'focus-native-video-loading-mask'
          ].forEach((id) => {
            document.getElementById(id)?.remove?.();
          });

          Array.from(document.querySelectorAll('video')).forEach((video) => {
            try {
              video.pause();
            } catch (_) {}

            try {
              if (typeof video.webkitSetPresentationMode === 'function'
                && video.webkitPresentationMode
                && video.webkitPresentationMode !== 'inline') {
                video.webkitSetPresentationMode('inline');
              }
            } catch (_) {}

            try {
              video.removeAttribute('autoplay');
            } catch (_) {}
          });

          window.__FOCUS_ACTIVE_VIDEO__ = null;
          window.__FOCUS_PLAYER_STATE__ = null;
          return true;
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func runPlayerCommand(_ script: String) {
        guard
            allowsPlayerControl,
            let webView,
            let context = makeBrowserCallbackContext(for: webView)
        else {
            return
        }

        playerCommandTask?.cancel()
        playerCommandTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else {
                return
            }

            do {
                _ = try await webView.evaluateJavaScript(script)
            } catch {
                self.debugLog(
                    "playerCommand.error",
                    fields: self.debugStateFields(["error": String(describing: error)])
                )
            }

            guard !Task.isCancelled, self.isCurrent(context, webView: webView) else {
                return
            }

            _ = await self.refreshPlayerState(on: webView, context: context)
        }
    }

    private func startEmbeddedPlayerDetection(on webView: WKWebView) {
        guard let context = makeBrowserCallbackContext(for: webView) else {
            return
        }
        let expectedURL = context.canonicalURL
        debugLog(
            "startEmbeddedPlayerDetection",
            fields: debugStateFields([
                "expectedURL": expectedURL.absoluteString,
                "continuous": debugBool(false)
            ])
        )
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = Task { @MainActor [weak self, weak webView] in
            let initialDelays: [UInt64] = [0, 300_000_000, 700_000_000, 1_400_000_000, 2_500_000_000]
            for (attempt, delay) in initialDelays.enumerated() {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard
                    !Task.isCancelled,
                    let self,
                    let webView,
                    self.isCurrent(context, webView: webView)
                else {
                    return
                }

                if let state = await self.detectEmbeddedPlayerState(
                    on: webView,
                    context: context,
                    fallbackURL: expectedURL
                ) {
                    guard self.isCurrent(context, webView: webView) else {
                        return
                    }
                    let hasPlayer = state.hasPlayer
                    self.applyDetectedPageState(state, fallbackURL: webView.url ?? expectedURL)
                    self.logDetectedPageState(state, source: "detectEmbeddedPlayerState")
                    self.debugLog(
                        "embeddedPlayerDetectionAttempt",
                        fields: self.debugStateFields([
                            "attempt": String(attempt),
                            "expectedURL": expectedURL.absoluteString,
                            "detectedHasPlayer": self.debugBool(hasPlayer)
                        ])
                    )

                    if self.hasActiveVideoRoute || hasPlayer {
                        self.hasActiveVideoRoute = true
                        var snapshot = self.playerSnapshot
                        snapshot.hasPlayer = true
                        self.updatePlayerSnapshot(snapshot)
                        self.startPlayerStateObservation()
                        return
                    }
                }
            }

            guard
                let self,
                !Task.isCancelled,
                let webView,
                self.isCurrent(context, webView: webView)
            else {
                return
            }
        }
    }

    private func detectEmbeddedPlayerState(
        on webView: WKWebView,
        context: BrowserCallbackContext,
        fallbackURL: URL?
    ) async -> DetectedPageState? {
        let script = """
        (() => {
          const cachedState = window.__FOCUS_PLAYER_STATE__;
          const titleSelectors = [
            '#viewbox_report',
            'h1.video-title',
            'h1[class*="video-title"]',
            '.video-title',
            '[class*="video-title"]',
            '[class*="archive-title"]',
            '.media-title'
          ];
          const extractVideoTitle = () => {
            for (const selector of titleSelectors) {
              const node = Array.from(document.querySelectorAll(selector)).find((candidate) => {
                const text = String(candidate?.textContent || '').trim();
                const rect = candidate?.getBoundingClientRect?.();
                return !!text && text.length >= 4 && text.length <= 160 && !!rect && rect.width > 40;
              });
              if (node) {
                return String(node.textContent || '').trim();
              }
            }
            return '';
          };
          if (cachedState && cachedState.hasPlayer) {
            return {
              ...cachedState,
              hasPlayer: true,
              pageURL: location.href,
              pageTitle: document.title || '',
              videoTitle: extractVideoTitle()
            };
          }

          const videos = Array.from(document.querySelectorAll('video'));
          const shells = document.querySelectorAll('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
          const hasVisibleVideo = videos.some((video) => {
            const rect = video.getBoundingClientRect();
            const style = window.getComputedStyle(video);
            const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
            return rect.width > 120
              && rect.height > 70
              && (rect.width >= Math.max(window.innerWidth * 0.62, 240) || rect.height >= 180 || area >= 65000)
              && style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0';
          });

          return {
            hasPlayer: shells.length > 0 || hasVisibleVideo,
            pageURL: location.href,
            pageTitle: document.title || '',
            videoTitle: extractVideoTitle()
          };
        })();
        """

        do {
            let value = try await webView.evaluateJavaScript(script)
            guard !Task.isCancelled, isCurrent(context, webView: webView) else {
                return nil
            }
            guard let payload = value as? [String: Any] else {
                debugLog(
                    "detectEmbeddedPlayerState.missingPayload",
                    fields: debugStateFields([
                        "fallbackURL": fallbackURL?.absoluteString,
                        "valueType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
                return nil
            }
            return makeDetectedPageState(from: payload)
        } catch {
            guard isCurrent(context, webView: webView) else {
                return nil
            }
            debugLog(
                "detectEmbeddedPlayerState.error",
                fields: debugStateFields([
                    "fallbackURL": fallbackURL?.absoluteString,
                    "error": String(describing: error)
                ])
            )
            return nil
        }
    }

    private func makeDetectedPageState(from payload: [String: Any]) -> DetectedPageState {
        DetectedPageState(
            hasPlayer: payload["hasPlayer"] as? Bool ?? false,
            pageURLString: payload["pageURL"] as? String,
            pageTitle: payload["pageTitle"] as? String,
            videoTitle: payload["videoTitle"] as? String
        )
    }

    private func applyDetectedPageState(_ state: DetectedPageState, fallbackURL: URL?) {
        let resolvedURL = (state.pageURLString.flatMap(URL.init(string:)) ?? fallbackURL)
            .map(FocusNavigationPolicy.canonicalWebURL(for:))
        let preferredTitle = sanitizedPageTitle(state.videoTitle)
            ?? sanitizedPageTitle(state.pageTitle)
            ?? sanitizedPageTitle(webView?.title)
        let hasPlayer = state.hasPlayer

        if let resolvedURL {
            currentURL = resolvedURL
            pendingURL = resolvedURL
            hasActiveVideoRoute = hasActiveVideoRoute || hasPlayer || FocusUserAgent.shouldUseDesktopPlayback(for: resolvedURL)
            updateNavigationMetadata(for: resolvedURL, pageTitle: preferredTitle)
            return
        }

        if preferredTitle != nil {
            updateNavigationMetadata(for: currentURL ?? pendingURL, pageTitle: preferredTitle)
        }
    }

    private var allowsPlayerControl: Bool {
        isVideoPage || hasActiveVideoRoute
    }

    private func resetAppBackStack() {
        appBackStack.removeAll()
        appBackSourceURL = nil
        pendingAppBackTarget = nil
        isHandlingAppBackNavigation = false
    }

    private func historyItem(for targetURL: URL, in webView: WKWebView) -> WKBackForwardListItem? {
        let canonicalTargetURL = FocusNavigationPolicy.canonicalWebURL(for: targetURL)
        return webView.backForwardList.backList.last { item in
            FocusNavigationPolicy.canonicalWebURL(for: item.url) == canonicalTargetURL
        }
    }

    private func shouldPushAppBackEntry(from currentURL: URL?, to targetURL: URL, navigationType: WKNavigationType) -> Bool {
        // A retained WKWebView still exposes the previous session's URL until
        // its new entry commits. That URL is history, not this route's parent.
        guard isSessionActive, let currentURL,
              currentURL == appBackSourceURL, currentURL != targetURL else {
            return false
        }

        if navigationType == .backForward || navigationType == .reload {
            return false
        }

        return isSearchResultURL(currentURL) && !isSearchResultURL(targetURL)
    }

    private func isSearchResultURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        if host == "search.bilibili.com" {
            return true
        }

        let path = url.path.lowercased()
        return (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com")
            && path.hasPrefix("/search")
    }

    private static func extractUserSpaceMID(from url: URL) -> Int64? {
        guard url.host?.lowercased() == "space.bilibili.com" else {
            return nil
        }

        guard let first = url.path.split(separator: "/").first else {
            return nil
        }

        let candidate = String(first)
        guard candidate.allSatisfy(\.isNumber) else {
            return nil
        }

        return Int64(candidate)
    }

    private func updateNavigationMetadata(for url: URL?, pageTitle: String? = nil, context: EntryContext? = nil) {
        let resolvedURL = url.map(FocusNavigationPolicy.canonicalWebURL(for:))

        if let context {
            entryContext = context
        } else if let resolvedURL {
            entryContext = inferredEntryContext(for: resolvedURL)
        }

        navigationTitle = resolvedNavigationTitle(for: resolvedURL, pageTitle: pageTitle)
    }

    private func inferredEntryContext(for url: URL) -> EntryContext {
        if Self.isLoginURL(url) {
            return .my
        }

        if isSearchResultURL(url) || entryContext == .search {
            return .search
        }

        return .dynamic
    }

    private func resolvedNavigationTitle(for url: URL?, pageTitle: String?) -> String {
        guard let url else {
            switch entryContext {
            case .dynamic:
                return "浏览"
            case .search:
                return "搜索"
            case .my:
                return "我的"
            }
        }

        if isOpusDetailURL(url) {
            return "图文动态"
        }

        if isSearchResultURL(url) {
            if (hasDetectedPlayer || hasActiveVideoRoute),
               let sanitizedTitle = sanitizedPageTitle(pageTitle),
               !sanitizedTitle.isEmpty,
               sanitizedTitle != searchKeyword(from: url)
            {
                return sanitizedTitle
            }
            return searchKeyword(from: url) ?? "搜索"
        }

        if Self.isLoginURL(url) {
            return "登录"
        }

        if FocusUserAgent.shouldUseDesktopPlayback(for: url),
           let sanitizedTitle = sanitizedPageTitle(pageTitle),
           !sanitizedTitle.isEmpty
        {
            return sanitizedTitle
        }

        if let sanitizedTitle = sanitizedPageTitle(pageTitle),
           !sanitizedTitle.isEmpty,
           sanitizedTitle != "哔哩哔哩"
        {
            return sanitizedTitle
        }

        if FocusUserAgent.shouldUseDesktopPlayback(for: url) {
            return "视频"
        }

        switch entryContext {
        case .dynamic:
            return "浏览"
        case .search:
            return searchKeyword(from: url) ?? "搜索"
        case .my:
            return "我的"
        }
    }

    private func sanitizedPageTitle(_ rawTitle: String?) -> String? {
        guard let rawTitle else {
            return nil
        }

        let separators = [
            "_哔哩哔哩_bilibili",
            "_哔哩哔哩",
            " - 哔哩哔哩",
            " - bilibili",
            " - Bilibili",
            "丨哔哩哔哩",
            "| 哔哩哔哩",
        ]

        let normalizedTitle = separators.reduce(rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)) { title, separator in
            guard let range = title.range(of: separator, options: .caseInsensitive) else {
                return title
            }

            return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalizedTitle.isEmpty ? nil : normalizedTitle
    }

    private func searchKeyword(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        return components.queryItems?
            .first(where: { $0.name.caseInsensitiveCompare("keyword") == .orderedSame })?
            .value?
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isOpusDetailURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()
        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com")
            && path.hasPrefix("/opus/")
        {
            return true
        }

        let pathComponents = url.path.split(separator: "/")
        return host == "t.bilibili.com"
            && pathComponents.count == 1
            && pathComponents[0].allSatisfy(\.isNumber)
    }

    private static func isLoginURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        return host == "passport.bilibili.com"
    }

    private func resetPlayerState() {
        if let activeURL = webView?.url ?? currentURL ?? pendingURL {
            clearNativeVideoOriginalSectionSuppression(for: FocusNavigationPolicy.canonicalWebURL(for: activeURL))
        }
        playerStateObservationTask?.cancel()
        playerStateObservationTask = nil
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = nil
        nativeVideoLoadingMaskTask?.cancel()
        nativeVideoLoadingMaskTask = nil
        pendingOrientationSyncAfterPlayerReady = false
        orientationDebounceTask?.cancel()
        orientationDebounceTask = nil
        fullscreenTransitionTask?.cancel()
        fullscreenTransitionTask = nil
        playerCommandTask?.cancel()
        playerCommandTask = nil
        lastHandledDeviceOrientation = .unknown
        requestedInterfaceOrientationMask = .portrait
        updateSupportedOrientations(to: .portrait)
        hasActiveVideoRoute = false
        updatePlayerSnapshot(.empty)
        nativeVideoAuthorName = ""
        nativeVideoAuthorAvatarURL = nil
        nativeVideoAuthorSpaceURL = nil
        nativeVideoAuthorMID = 0
        nativeVideoAuthorFollowers = 0
        nativeVideoAuthorIsFollowing = false
        isUpdatingNativeVideoFollow = false
#if DEBUG
        lastDebugDetectedPageStateSignature = nil
        lastDebugPlayerStateSignature = nil
#endif
    }

    private func invalidatePageAugmentation() {
        pageAugmentationRevision &+= 1
        pageAugmentationTask?.cancel()
        pageAugmentationTask = nil
        pageAugmentationApplyTask?.cancel()
        pageAugmentationApplyTask = nil
        nativeVideoLoadingMaskTask?.cancel()
        nativeVideoLoadingMaskTask = nil
        nativeVideoPlaceholderTask?.cancel()
        nativeVideoPlaceholderTask = nil
        scheduledPageAugmentationKey = nil
        pageAugmentationFailureCounts.removeAll()
        pageAugmentationRetryAfter.removeAll()
    }

    func resetForSessionChange() {
        invalidatePageAugmentation()
        invalidateBrowserCallbacks()
        pageAugmentCache.removeAll()
        pageAugmentCacheSessionVersion = nil
        resetPlayerState()
    }

    func reconcileSessionVersion(_ version: UInt64) {
        guard nativePageAugmentService?.sessionVersion == version else { return }
        invalidatePageAugmentation()
        nativeVideoFollowTask?.cancel()
        nativeVideoFollowTask = nil
        isUpdatingNativeVideoFollow = false
        pageAugmentCache.removeAll()
        pageAugmentCacheSessionVersion = version
        if isSessionActive { schedulePageAugmentationRefresh() }
    }

    private func loadURLIfNeeded(_ url: URL, on webView: WKWebView, reason: String, force: Bool = false) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        let activeURL = webView.url.map(FocusNavigationPolicy.canonicalWebURL(for:))

        if !force {
            if webView.isLoading, lastIssuedLoadURL == canonicalURL {
                debugLog(
                    "loadURLIfNeeded.skip",
                    fields: debugStateFields([
                        "reason": reason,
                        "targetURL": canonicalURL.absoluteString,
                        "skipReason": "already-loading"
                    ])
                )
                return
            }

            if activeURL == canonicalURL,
               pendingURL == canonicalURL,
               !isLoadingPage
            {
                debugLog(
                    "loadURLIfNeeded.skip",
                    fields: debugStateFields([
                        "reason": reason,
                        "targetURL": canonicalURL.absoluteString,
                        "skipReason": "already-visible"
                    ])
                )
                return
            }
        }

        prepareNavigationSession(to: canonicalURL)
        prepareForURL?(webView, canonicalURL)
        lastIssuedLoadURL = canonicalURL
        webView.load(URLRequest(url: canonicalURL))
        debugLog(
            "loadURLIfNeeded.load",
            fields: debugStateFields([
                "reason": reason,
                "targetURL": canonicalURL.absoluteString,
                "force": debugBool(force)
            ])
        )
    }

    private func schedulePageAugmentationRefresh() {
        guard
            let service = nativePageAugmentService,
            let activeURL = currentURL ?? pendingURL,
            let kind = nativePageKind(for: activeURL)
        else {
            return
        }

        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: activeURL)
        let scheduleKey = "\(revisionKeyPrefix(for: kind, url: canonicalURL))::rev=\(pageAugmentationRevision)"
        if let retryAfter = pageAugmentationRetryAfter[scheduleKey], retryAfter > Date() {
            debugLog(
                "nativePageAugmentation.skipRetryCooldown",
                fields: debugStateFields([
                    "pageKind": kind.rawValue,
                    "pageURL": canonicalURL.absoluteString,
                    "retryAfter": ISO8601DateFormatter().string(from: retryAfter)
                ])
            )
            return
        }
        pageAugmentationRetryAfter[scheduleKey] = nil
        if scheduledPageAugmentationKey == scheduleKey {
            debugLog(
                "nativePageAugmentation.skipDuplicateSchedule",
                fields: debugStateFields([
                    "pageKind": kind.rawValue,
                    "pageURL": canonicalURL.absoluteString
                ])
            )
            return
        }
        scheduledPageAugmentationKey = scheduleKey
        let sessionVersion = service.sessionVersion
        if pageAugmentCacheSessionVersion != sessionVersion {
            pageAugmentCache.removeAll()
            pageAugmentCacheSessionVersion = sessionVersion
        }
        let cacheKey = kind.cacheKey(for: canonicalURL)
        let revision = pageAugmentationRevision

        if let cachedPayload = pageAugmentCache.payload(for: cacheKey) {
            nativeVideoLoadingMaskTask?.cancel()
            nativeVideoLoadingMaskTask = nil
            nativeVideoPlaceholderTask?.cancel()
            nativeVideoPlaceholderTask = nil
            pageAugmentationFailureCounts[scheduleKey] = nil
            pageAugmentationRetryAfter[scheduleKey] = nil
            syncNativeVideoMetadata(from: cachedPayload)
            applyPageAugmentation(cachedPayload, for: canonicalURL, revision: revision)
            return
        }

        if kind == .video && (pageAugmentationFailureCounts[scheduleKey] ?? 0) < 3 {
            scheduleNativeVideoPlaceholderInstall(for: canonicalURL, revision: revision)
        }

        pageAugmentationTask?.cancel()
        pageAugmentationTask = Task { [weak self] in
            guard let self else {
                return
            }

            let payload = await service.loadPayload(for: canonicalURL, kind: kind)
            guard !Task.isCancelled, service.sessionVersion == sessionVersion else {
                return
            }

            guard let payload else {
                await MainActor.run {
                    guard self.pageAugmentationRevision == revision else {
                        return
                    }

                    let failureCount = (self.pageAugmentationFailureCounts[scheduleKey] ?? 0) + 1
                    self.pageAugmentationFailureCounts[scheduleKey] = failureCount
                    let retryDelay = min(3.0, pow(2.0, Double(max(failureCount - 1, 0))) * 0.35)
                    self.pageAugmentationRetryAfter[scheduleKey] = Date().addingTimeInterval(retryDelay)
                    self.scheduledPageAugmentationKey = nil
                    self.debugLog(
                        "nativePageAugmentation.missingPayload",
                        fields: self.debugStateFields([
                            "pageKind": kind.rawValue,
                            "pageURL": canonicalURL.absoluteString,
                            "failures": String(failureCount),
                            "retryDelayMS": String(Int(retryDelay * 1000))
                        ])
                    )

                    if kind == .video, failureCount >= 3 {
                        self.nativeVideoPlaceholderTask?.cancel()
                        self.nativeVideoPlaceholderTask = nil
                        self.clearNativeVideoOriginalSectionSuppression(for: canonicalURL)
                        self.dismissNativeVideoPlaceholder(for: canonicalURL)
                    }
                }
                return
            }

            await MainActor.run {
                guard self.pageAugmentationRevision == revision else {
                    return
                }

                self.nativeVideoLoadingMaskTask?.cancel()
                self.nativeVideoLoadingMaskTask = nil
                self.nativeVideoPlaceholderTask?.cancel()
                self.nativeVideoPlaceholderTask = nil
                self.pageAugmentationFailureCounts[scheduleKey] = nil
                self.pageAugmentationRetryAfter[scheduleKey] = nil
                self.pageAugmentCache.store(payload, for: cacheKey)
                self.syncNativeVideoMetadata(from: payload)
                self.applyPageAugmentation(payload, for: canonicalURL, revision: revision)
            }
        }
    }

    private func revisionKeyPrefix(for kind: FocusNativePageKind, url: URL) -> String {
        "\(kind.rawValue)::\(url.absoluteString)"
    }

    private func scheduleNativeVideoLoadingMaskInstall(for canonicalURL: URL, revision: Int) {
        nativeVideoLoadingMaskTask?.cancel()
        debugLog(
            "nativeLoadingMask.scheduled",
            fields: debugStateFields([
                "pageURL": canonicalURL.absoluteString,
                "delayMS": "360",
                "revision": String(revision)
            ])
        )
        nativeVideoLoadingMaskTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard
                let self,
                !Task.isCancelled,
                self.pageAugmentationRevision == revision
            else {
                return
            }

            self.installNativeVideoLoadingMaskIfNeeded(for: canonicalURL)
            self.nativeVideoLoadingMaskTask = nil
        }
    }

    private func installNativeVideoOriginalSectionSuppression(for canonicalURL: URL) {
        guard let webView else {
            return
        }

        webView.evaluateJavaScript(
            """
            (() => {
              const activeURL = location.href ? new URL(location.href, document.baseURI).href : '';
              const targetURL = '\(canonicalURL.absoluteString.replacingOccurrences(of: "'", with: "\\'"))';
              if (activeURL && activeURL !== targetURL && !activeURL.startsWith(targetURL)) {
                return { applied: false, reason: 'url-mismatch' };
              }

              const id = 'focus-native-video-prehide-style';
              document.documentElement.classList.remove('focus-native-video-fallback');
              let style = document.getElementById(id);
              if (!style) {
                style = document.createElement('style');
                style.id = id;
                document.head.appendChild(style);
              }

              style.textContent = `
                .video-pod,
                .video-pod__head,
                .video-pod__header,
                .video-pod__body,
                .video-pod__list,
                .right-container,
                .right-container-inner,
                .side-toolbar,
                .right-entry,
                #viewbox_report,
                .multi-page,
                [class*="multi-page"],
                [class*="episode-list"],
                [class*="part-list"],
                [class*="page-list"],
                #commentapp,
                #commentapp > *,
                bili-comments,
                .comment-container,
                .bb-comment {
                  opacity: 0 !important;
                  pointer-events: none !important;
                }
              `;

              return { applied: true, reason: 'installed' };
            })();
            """,
            completionHandler: { [weak self] value, error in
                guard let self else {
                    return
                }

                if let error {
                    self.debugLog(
                        "nativeOriginalSectionSuppression.error",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "error": String(describing: error)
                        ])
                    )
                    return
                }

                let payload = value as? [String: Any]
                let applied = payload?["applied"] as? Bool
                let reason = payload?["reason"] as? String
                self.debugLog(
                    "nativeOriginalSectionSuppression.install",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "applied": applied == true ? "true" : "false",
                        "reason": reason,
                        "resultType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
            }
        )
    }

    private func clearNativeVideoOriginalSectionSuppression(for canonicalURL: URL) {
        guard let webView else {
            return
        }

        webView.evaluateJavaScript(
            """
            (() => {
              const activeURL = location.href ? new URL(location.href, document.baseURI).href : '';
              const targetURL = '\(canonicalURL.absoluteString.replacingOccurrences(of: "'", with: "\\'"))';
              if (activeURL && activeURL !== targetURL && !activeURL.startsWith(targetURL)) {
                return { cleared: false, reason: 'url-mismatch' };
              }

              document.getElementById('focus-native-video-prehide-style')?.remove?.();
              document.documentElement.classList.add('focus-native-video-fallback');
              return { cleared: true, reason: 'removed' };
            })();
            """,
            completionHandler: { [weak self] value, error in
                guard let self else {
                    return
                }

                if let error {
                    self.debugLog(
                        "nativeOriginalSectionSuppression.clear.error",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "error": String(describing: error)
                        ])
                    )
                    return
                }

                let payload = value as? [String: Any]
                let cleared = payload?["cleared"] as? Bool
                let reason = payload?["reason"] as? String
                self.debugLog(
                    "nativeOriginalSectionSuppression.clear",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "cleared": cleared == true ? "true" : "false",
                        "reason": reason,
                        "resultType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
            }
        )
    }

    private func installNativeVideoLoadingMaskIfNeeded(for canonicalURL: URL) {
        guard let webView else {
            return
        }

        webView.evaluateJavaScript(
            """
            (() => {
              const activeURL = location.href ? new URL(location.href, document.baseURI).href : '';
              const targetURL = '\(canonicalURL.absoluteString.replacingOccurrences(of: "'", with: "\\'"))';
              if (activeURL && activeURL !== targetURL && !activeURL.startsWith(targetURL)) {
                return false;
              }

              const root = document.getElementById('focus-native-video-augment');
              const hasSettledAugment = (() => {
                if (!(root instanceof HTMLElement)) {
                  return false;
                }

                const renderKey = root.getAttribute('data-focus-render-key');
                const version = root.getAttribute('data-focus-version');
                return !!renderKey && !!version && root.children.length > 0 && !root.hasAttribute('data-focus-placeholder');
              })();
              const hasPlaceholder = root instanceof HTMLElement
                && root.hasAttribute('data-focus-placeholder')
                && root.children.length > 0;
              const isReady = document.documentElement.classList.contains('focus-native-video-ready')
                || document.body?.classList?.contains?.('focus-native-video-ready');

              if (hasSettledAugment || hasPlaceholder || isReady) {
                if (window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__) {
                  try {
                    window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__(true);
                  } catch (_) {}
                }
                return false;
              }

              const id = 'focus-native-video-loading-mask';
              if (window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__) {
                try {
                  window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__(true);
                } catch (_) {}
              }
              let mask = document.getElementById(id);
              if (!mask) {
                mask = document.createElement('div');
                mask.id = id;
                (document.body || document.documentElement).appendChild(mask);
              }
              mask.style.position = 'fixed';
              mask.style.left = '0';
              mask.style.right = '0';
              mask.style.top = 'calc(100vw / 1.5 + 88px)';
              mask.style.bottom = '0';
              mask.style.background = document.documentElement.getAttribute('data-focus-theme') === 'dark' ? '#0F1115' : '#F6F7FA';
              mask.style.pointerEvents = 'none';
              mask.style.zIndex = '20';
              mask.style.opacity = '1';

              if (window.__FOCUS_LOADING_MASK_OBSERVER__) {
                try {
                  window.__FOCUS_LOADING_MASK_OBSERVER__.disconnect();
                } catch (_) {}
              }

              const clearMask = () => {
                const current = document.getElementById(id);
                if (!current) {
                  return;
                }
                current.style.transition = 'opacity 0.18s ease';
                current.style.opacity = '0';
                setTimeout(() => current.remove?.(), 220);
                if (window.__FOCUS_LOADING_MASK_OBSERVER__) {
                  try {
                    window.__FOCUS_LOADING_MASK_OBSERVER__.disconnect();
                  } catch (_) {}
                  window.__FOCUS_LOADING_MASK_OBSERVER__ = null;
                }
              };
              window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__ = clearMask;

              const hasVisiblePlayerLoadingOverlay = () => {
                return Array.from(document.querySelectorAll([
                  '#bilibili-player [class*="loading"]',
                  '#playerWrap [class*="loading"]',
                  '.bpx-player-container [class*="loading"]',
                  '#bilibili-player [class*="skeleton"]',
                  '#playerWrap [class*="skeleton"]',
                  '.bpx-player-container [class*="skeleton"]'
                ].join(','))).some((node) => {
                  if (!(node instanceof HTMLElement)) {
                    return false;
                  }

                  const rect = node.getBoundingClientRect();
                  const style = window.getComputedStyle(node);
                  return rect.width > 40
                    && rect.height > 40
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                });
              };

              const shouldClearMask = () => {
                const liveRoot = document.getElementById('focus-native-video-augment');
                const playerLoadingVisible = hasVisiblePlayerLoadingOverlay();
                if (liveRoot instanceof HTMLElement) {
                  const renderKey = liveRoot.getAttribute('data-focus-render-key');
                  const version = liveRoot.getAttribute('data-focus-version');
                  const hasRenderableAugment = !!renderKey && !!version && liveRoot.children.length > 0 && !liveRoot.hasAttribute('data-focus-placeholder');
                  const hasLivePlaceholder = liveRoot.hasAttribute('data-focus-placeholder') && liveRoot.children.length > 0;
                  if ((hasRenderableAugment || hasLivePlaceholder) && !playerLoadingVisible) {
                    return true;
                  }
                }

                return (
                  document.documentElement.classList.contains('focus-native-video-ready')
                  || document.body?.classList?.contains?.('focus-native-video-ready')
                ) && !playerLoadingVisible;
              };

              if (shouldClearMask()) {
                clearMask();
                return false;
              }

              const observer = new MutationObserver(() => {
                if (shouldClearMask()) {
                  clearMask();
                }
              });
              observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
              window.__FOCUS_LOADING_MASK_OBSERVER__ = observer;

              setTimeout(clearMask, 3200);
              return true;
            })();
            """,
            completionHandler: { [weak self] value, error in
                guard let self else {
                    return
                }

                if let error {
                    self.debugLog(
                        "nativeLoadingMask.error",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "error": String(describing: error)
                        ])
                    )
                    return
                }

                let result = value as? Bool
                self.debugLog(
                    "nativeLoadingMask.installAttempt",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "installed": result == true ? "true" : "false",
                        "resultType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
            }
        )
    }

    private func scheduleNativeVideoPlaceholderInstall(for canonicalURL: URL, revision: Int) {
        nativeVideoPlaceholderTask?.cancel()
        debugLog(
            "nativePlaceholder.scheduled",
            fields: debugStateFields([
                "pageURL": canonicalURL.absoluteString,
                "delayMS": "650",
                "revision": String(revision)
            ])
        )
        nativeVideoPlaceholderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard
                let self,
                !Task.isCancelled,
                self.pageAugmentationRevision == revision
            else {
                return
            }

            self.installNativeVideoPlaceholderIfNeeded(for: canonicalURL)
            self.nativeVideoPlaceholderTask = nil
        }
    }

    private func installNativeVideoPlaceholderIfNeeded(for canonicalURL: URL) {
        guard let webView else {
            return
        }

        webView.evaluateJavaScript(
            """
            (() => {
              const activeURL = location.href ? new URL(location.href, document.baseURI).href : '';
              const targetURL = '\(canonicalURL.absoluteString.replacingOccurrences(of: "'", with: "\\'"))';
              if (activeURL && activeURL !== targetURL && !activeURL.startsWith(targetURL)) {
                return { installed: false, reason: 'url-mismatch' };
              }

              const rootId = 'focus-native-video-augment';
              const styleId = 'focus-native-video-augment-style';
              \(focusNativeVideoAugmentMountHelpersJavaScript)
              const hasVisibleLoadingMask = () => {
                const mask = document.getElementById('focus-native-video-loading-mask');
                if (!(mask instanceof HTMLElement)) {
                  return false;
                }
                const opacity = Number.parseFloat(mask.style.opacity || '1');
                return mask.isConnected && opacity > 0.01;
              };
              const hasVisiblePlayerLoadingOverlay = () => {
                return Array.from(document.querySelectorAll([
                  '#bilibili-player [class*="loading"]',
                  '#playerWrap [class*="loading"]',
                  '.bpx-player-container [class*="loading"]',
                  '#bilibili-player [class*="skeleton"]',
                  '#playerWrap [class*="skeleton"]',
                  '.bpx-player-container [class*="skeleton"]'
                ].join(','))).some((node) => {
                  if (!(node instanceof HTMLElement)) {
                    return false;
                  }
                  const rect = node.getBoundingClientRect?.();
                  if (!rect) {
                    return false;
                  }
                  const style = window.getComputedStyle(node);
                  return rect.width > 40
                    && rect.height > 40
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                });
              };
              const hasVisiblePlayer = () => {
                const playerShell = document.querySelector('#playerWrap, .player-wrap, #bilibili-player, .bpx-player-container, .player-container, .bpx-player-video-wrap');
                if (!playerShell) {
                  return false;
                }

                const video = Array.from(document.querySelectorAll('video')).find((node) => {
                  if (!(node instanceof HTMLVideoElement)) {
                    return false;
                  }
                  const rect = node.getBoundingClientRect?.();
                  if (!rect) {
                    return false;
                  }
                  const style = window.getComputedStyle(node);
                  return rect.width > 120
                    && rect.height > 68
                    && style.display !== 'none'
                    && style.visibility !== 'hidden'
                    && style.opacity !== '0';
                });

                return !!video;
              };
              const hasSettledAugment = () => {
                const existingRoot = document.getElementById(rootId);
                if (!(existingRoot instanceof HTMLElement)) {
                  return false;
                }

                const renderKey = existingRoot.getAttribute('data-focus-render-key');
                const version = existingRoot.getAttribute('data-focus-version');
                return !!renderKey && !!version && existingRoot.children.length > 0 && !existingRoot.hasAttribute('data-focus-placeholder');
              };

              if (hasSettledAugment()) {
                return { installed: false, reason: 'augment-ready' };
              }

              if (!hasVisiblePlayer()) {
                return { installed: false, reason: 'player-not-visible' };
              }

              const ensureStyle = () => {
                let style = document.getElementById(styleId);
                if (!style) {
                  style = document.createElement('style');
                  style.id = styleId;
                  document.head.appendChild(style);
                }
                if (style.getAttribute('data-focus-placeholder') === 'true') {
                  return style;
                }
                style.setAttribute('data-focus-placeholder', 'true');
                style.textContent = `
                  #${rootId} {
                    display: block !important;
                    width: 100% !important;
                    box-sizing: border-box !important;
                    padding: 8px 16px 24px !important;
                    position: relative !important;
                    z-index: 21 !important;
                    order: 2 !important;
                    flex: 0 0 auto !important;
                  }
                  #${rootId} .focus-native-section {
                    margin-top: 8px !important;
                    padding: 16px !important;
                    border-radius: 20px !important;
                    background: rgba(248, 250, 252, 0.96) !important;
                    border: 1px solid rgba(15, 23, 42, 0.06) !important;
                    box-shadow: 0 14px 32px rgba(15, 23, 42, 0.05) !important;
                    box-sizing: border-box !important;
                  }
                  html[data-focus-theme='dark'] #${rootId} .focus-native-section {
                    background: rgba(17, 24, 39, 0.96) !important;
                    border-color: rgba(255, 255, 255, 0.08) !important;
                    box-shadow: 0 12px 24px rgba(0, 0, 0, 0.22) !important;
                  }
                  #${rootId} .focus-native-skeleton-row,
                  #${rootId} .focus-native-skeleton-pill,
                  #${rootId} .focus-native-skeleton-card {
                    background: linear-gradient(90deg, rgba(148,163,184,0.18) 0%, rgba(148,163,184,0.28) 50%, rgba(148,163,184,0.18) 100%) !important;
                    background-size: 240px 100% !important;
                    animation: focus-native-skeleton-shimmer 1.2s linear infinite !important;
                  }
                  #${rootId} .focus-native-skeleton-header {
                    display: flex !important;
                    align-items: center !important;
                    gap: 12px !important;
                  }
                  #${rootId} .focus-native-skeleton-avatar {
                    width: 42px !important;
                    height: 42px !important;
                    border-radius: 999px !important;
                    flex: 0 0 42px !important;
                  }
                  #${rootId} .focus-native-skeleton-copy {
                    flex: 1 1 auto !important;
                    min-width: 0 !important;
                  }
                  #${rootId} .focus-native-skeleton-row {
                    border-radius: 999px !important;
                    height: 12px !important;
                    width: 100% !important;
                    margin-top: 8px !important;
                  }
                  #${rootId} .focus-native-skeleton-row:first-child {
                    margin-top: 0 !important;
                    width: 54% !important;
                    height: 14px !important;
                  }
                  #${rootId} .focus-native-skeleton-pills {
                    display: flex !important;
                    gap: 10px !important;
                    overflow: hidden !important;
                  }
                  #${rootId} .focus-native-skeleton-pill {
                    border-radius: 16px !important;
                    width: 168px !important;
                    height: 82px !important;
                    flex: 0 0 168px !important;
                  }
                  #${rootId} .focus-native-skeleton-comments {
                    display: grid !important;
                    gap: 12px !important;
                  }
                  #${rootId} .focus-native-skeleton-card {
                    border-radius: 16px !important;
                    height: 84px !important;
                    width: 100% !important;
                  }
                  @keyframes focus-native-skeleton-shimmer {
                    0% { background-position: -240px 0; }
                    100% { background-position: 240px 0; }
                  }
                `;
                return style;
              };

              ensureStyle();
              const root = document.getElementById(rootId) || document.createElement('section');
              root.id = rootId;
              root.setAttribute('data-focus-placeholder', 'true');
              root.style.setProperty('display', 'block', 'important');
              root.style.setProperty('width', '100%', 'important');
              root.style.setProperty('visibility', 'visible', 'important');
              root.style.setProperty('opacity', '1', 'important');
              root.style.setProperty('position', 'relative', 'important');
              root.style.setProperty('z-index', '21', 'important');
              root.style.setProperty('order', '2', 'important');
              root.style.setProperty('flex', '0 0 auto', 'important');
              if (hasVisibleLoadingMask()) {
                return { installed: false, reason: 'loading-mask-visible' };
              }
              root.style.setProperty('opacity', '1', 'important');
              root.style.removeProperty('pointer-events');

              if (!root.querySelector('.focus-native-skeleton-header')) {
                root.innerHTML = `
                  <section class="focus-native-section">
                    <div class="focus-native-skeleton-header">
                      <div class="focus-native-skeleton-avatar focus-native-skeleton-row"></div>
                      <div class="focus-native-skeleton-copy">
                        <div class="focus-native-skeleton-row"></div>
                        <div class="focus-native-skeleton-row" style="width: 34% !important;"></div>
                      </div>
                    </div>
                  </section>
                  <section class="focus-native-section">
                    <div class="focus-native-skeleton-pills">
                      <div class="focus-native-skeleton-pill"></div>
                      <div class="focus-native-skeleton-pill"></div>
                      <div class="focus-native-skeleton-pill"></div>
                    </div>
                  </section>
                  <section class="focus-native-section">
                    <div class="focus-native-skeleton-comments">
                      <div class="focus-native-skeleton-card"></div>
                      <div class="focus-native-skeleton-card"></div>
                    </div>
                  </section>
                `;
              }

              mountNativeVideoAugmentRoot(root);
              return { installed: true, reason: 'installed' };
            })();
            """,
            completionHandler: { [weak self] value, error in
                guard let self else {
                    return
                }

                if let error {
                    self.debugLog(
                        "nativePlaceholder.error",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "error": String(describing: error)
                        ])
                    )
                    return
                }

                let payload = value as? [String: Any]
                let result = payload?["installed"] as? Bool
                let reason = payload?["reason"] as? String
                self.debugLog(
                    "nativePlaceholder.installAttempt",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "installed": result == true ? "true" : "false",
                        "reason": reason,
                        "resultType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
            }
        )
    }

    private func dismissNativeVideoPlaceholder(for canonicalURL: URL) {
        guard let webView else {
            return
        }

        webView.evaluateJavaScript(
            """
            (() => {
              const activeURL = location.href ? new URL(location.href, document.baseURI).href : '';
              const targetURL = '\(canonicalURL.absoluteString.replacingOccurrences(of: "'", with: "\\'"))';
              if (activeURL && activeURL !== targetURL && !activeURL.startsWith(targetURL)) {
                return false;
              }

              const root = document.getElementById('focus-native-video-augment');
              if (root instanceof HTMLElement && (root.hasAttribute('data-focus-placeholder') || root.children.length === 0)) {
                root.remove();
              }

              document.documentElement.classList.remove('focus-native-video-ready');
              document.body?.classList?.remove?.('focus-native-video-ready');

              if (window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__) {
                try {
                  window.__FOCUS_CLEAR_VIDEO_LOADING_MASK__(true);
                } catch (_) {}
              }

              return true;
            })();
            """,
            completionHandler: { [weak self] value, error in
                guard let self else {
                    return
                }

                if let error {
                    self.debugLog(
                        "nativePlaceholder.dismiss.error",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "error": String(describing: error)
                        ])
                    )
                    return
                }

                let result = value as? Bool
                self.debugLog(
                    "nativePlaceholder.dismiss",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "dismissed": result == true ? "true" : "false",
                        "resultType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
            }
        )
    }

    private func syncNativeVideoMetadata(from payload: FocusNativePageAugmentPayload) {
        guard case let .video(videoPayload) = payload else {
            nativeVideoAuthorName = ""
            nativeVideoAuthorAvatarURL = nil
            nativeVideoAuthorSpaceURL = nil
            nativeVideoAuthorMID = 0
            nativeVideoAuthorFollowers = 0
            nativeVideoAuthorIsFollowing = false
            return
        }

        nativeVideoAuthorName = videoPayload.authorName
        nativeVideoAuthorAvatarURL = URL(string: videoPayload.authorAvatarURL)
        nativeVideoAuthorSpaceURL = URL(string: videoPayload.authorSpaceURL)
        nativeVideoAuthorMID = videoPayload.authorMID
        nativeVideoAuthorFollowers = videoPayload.authorFollowers
        nativeVideoAuthorIsFollowing = videoPayload.authorIsFollowing
    }

    private func toggleNativeVideoAuthorFollow() {
        guard !isUpdatingNativeVideoFollow else {
            return
        }
        guard nativeVideoAuthorMID > 0, let service = nativePageAugmentService else {
            return
        }

        let targetMID = nativeVideoAuthorMID
        let shouldFollow = !nativeVideoAuthorIsFollowing
        let sessionID = browserSessionID
        let sessionVersion = service.sessionVersion
        isUpdatingNativeVideoFollow = true

        nativeVideoFollowTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let result = try await service.updateFollowState(mid: targetMID, shouldFollow: shouldFollow, expectedSessionVersion: sessionVersion)
                await MainActor.run {
                    guard !Task.isCancelled, self.browserSessionID == sessionID,
                          service.sessionVersion == sessionVersion,
                          self.nativeVideoAuthorMID == targetMID else { return }
                    self.nativeVideoFollowTask = nil
                    self.isUpdatingNativeVideoFollow = false
                    self.applyNativeVideoAuthorFollowState(
                        mid: targetMID,
                        isFollowing: result.isFollowing,
                        followers: result.followers
                    )
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled, self.browserSessionID == sessionID,
                          service.sessionVersion == sessionVersion else { return }
                    self.nativeVideoFollowTask = nil
                    self.isUpdatingNativeVideoFollow = false
                    self.debugLog(
                        "nativeVideoAuthorFollow.failed",
                        fields: self.debugStateFields([
                            "mid": String(targetMID),
                            "requestedFollowing": self.debugBool(shouldFollow),
                            "error": error.localizedDescription
                        ])
                    )
                }
            }
        }
    }

    private func applyNativeVideoAuthorFollowState(mid: Int64, isFollowing: Bool, followers: Int64) {
        nativeVideoAuthorMID = mid
        nativeVideoAuthorIsFollowing = isFollowing
        nativeVideoAuthorFollowers = followers

        if let currentURL = currentURL ?? pendingURL,
           let kind = nativePageKind(for: currentURL),
           kind == .video
        {
            let cacheKey = kind.cacheKey(for: FocusNavigationPolicy.canonicalWebURL(for: currentURL))
            if case let .video(existingPayload)? = pageAugmentCache.payload(for: cacheKey), existingPayload.authorMID == mid {
                pageAugmentCache.store(.video(
                    FocusNativeVideoAugmentPayload(
                        title: existingPayload.title,
                        authorName: existingPayload.authorName,
                        authorAvatarURL: existingPayload.authorAvatarURL,
                        authorSpaceURL: existingPayload.authorSpaceURL,
                        authorMID: existingPayload.authorMID,
                        authorFollowers: followers,
                        authorFollowersText: Self.formatSocialCount(followers),
                        authorIsFollowing: isFollowing,
                        groups: existingPayload.groups,
                        comments: existingPayload.comments
                    )
                ), for: cacheKey)
            }
        }

        guard let webView else {
            return
        }

        let followText = isFollowing ? "已关注" : "关注"
        let followersText = "\(Self.formatSocialCount(followers)) 粉丝"
        let escapedFollowText = followText.replacingOccurrences(of: "'", with: "\\'")
        let escapedFollowersText = followersText.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript(
            """
            (() => {
              const root = document.getElementById('focus-native-video-augment');
              if (!root) {
                return;
              }
              const followNode = root.querySelector('.focus-native-owner-follow');
              const followersNode = root.querySelector('.focus-native-owner-followers');
              if (followNode) {
                followNode.textContent = '\(escapedFollowText)';
                followNode.setAttribute('data-following', '\(isFollowing ? "true" : "false")');
              }
              if (followersNode) {
                followersNode.textContent = '\(escapedFollowersText)';
              }
            })();
            """,
            completionHandler: nil
        )
    }

    private static func formatSocialCount(_ value: Int64) -> String {
        switch value {
        case 100_000_000...:
            return String(format: "%.1f亿", Double(value) / 100_000_000).replacingOccurrences(of: ".0", with: "")
        case 10_000...:
            return String(format: "%.1f万", Double(value) / 10_000).replacingOccurrences(of: ".0", with: "")
        default:
            return "\(value)"
        }
    }

    private func applyPageAugmentation(
        _ payload: FocusNativePageAugmentPayload,
        for canonicalURL: URL,
        revision: Int
    ) {
        let delays: [UInt64] = [0, 150_000_000, 500_000_000, 1_200_000_000, 3_000_000_000, 6_000_000_000]
        let expectedRenderKey = payload.renderKey

        pageAugmentationApplyTask?.cancel()
        pageAugmentationApplyTask = Task { @MainActor [weak self] in
            for (index, delay) in delays.enumerated() {
                guard let self else {
                    return
                }

                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }

                guard
                    !Task.isCancelled,
                    self.pageAugmentationRevision == revision,
                    let webView = self.webView,
                    let callbackContext = self.makeBrowserCallbackContext(for: webView),
                    callbackContext.canonicalURL == canonicalURL
                else {
                    return
                }

                let activeURL = (webView.url ?? self.currentURL ?? self.pendingURL)
                    .map(FocusNavigationPolicy.canonicalWebURL(for:))
                guard activeURL == canonicalURL else {
                    return
                }

                if let expectedRenderKey, index > 0 {
                    let existingRenderKey = await withCheckedContinuation { continuation in
                        webView.evaluateJavaScript(
                            "document.getElementById('focus-native-video-augment')?.getAttribute('data-focus-render-key')"
                        ) { value, _ in
                            continuation.resume(returning: value as? String)
                        }
                    }

                    guard
                        !Task.isCancelled,
                        self.pageAugmentationRevision == revision,
                        self.isCurrent(callbackContext, webView: webView)
                    else {
                        return
                    }

                    if existingRenderKey == expectedRenderKey {
                        self.debugLog(
                            "nativePageAugmentation.skipStableReplay",
                            fields: self.debugStateFields([
                                "pageURL": canonicalURL.absoluteString,
                                "pageKind": payload.kind.rawValue,
                                "attempt": String(index),
                                "delayMS": String(delay / 1_000_000)
                            ])
                        )
                        return
                    }
                }

                let preflightScript = """
                (() => {
                  const hasVisiblePlayerLoadingOverlay = () => {
                    return Array.from(document.querySelectorAll([
                      '#bilibili-player [class*="loading"]',
                      '#playerWrap [class*="loading"]',
                      '.bpx-player-container [class*="loading"]',
                      '#bilibili-player [class*="skeleton"]',
                      '#playerWrap [class*="skeleton"]',
                      '.bpx-player-container [class*="skeleton"]'
                    ].join(','))).some((node) => {
                      if (!(node instanceof HTMLElement)) {
                        return false;
                      }
                      const rect = node.getBoundingClientRect?.();
                      if (!rect) {
                        return false;
                      }
                      const style = window.getComputedStyle(node);
                      return rect.width > 40
                        && rect.height > 40
                        && style.display !== 'none'
                        && style.visibility !== 'hidden'
                        && style.opacity !== '0';
                    });
                  };
                  const hasVisiblePlayer = () => {
                    const playerShell = document.querySelector('#playerWrap, .player-wrap, #bilibili-player, .bpx-player-container, .player-container, .bpx-player-video-wrap');
                    if (!(playerShell instanceof HTMLElement)) {
                      return false;
                    }

                    const playerRect = playerShell.getBoundingClientRect?.();
                    if (!playerRect || playerRect.width < 120 || playerRect.height < 68) {
                      return false;
                    }

                    return Array.from(document.querySelectorAll('video')).some((node) => {
                      if (!(node instanceof HTMLVideoElement)) {
                        return false;
                      }
                      const rect = node.getBoundingClientRect?.();
                      if (!rect) {
                        return false;
                      }
                      const style = window.getComputedStyle(node);
                      return rect.width > 120
                        && rect.height > 68
                        && style.display !== 'none'
                        && style.visibility !== 'hidden'
                        && style.opacity !== '0';
                    });
                  };
                  const checkTargets = () => {
                    let score = 0;
                    const hasPlayer = !!document.querySelector('#playerWrap, .player-wrap, #bilibili-player');
                    const hasContainer = !!document.querySelector('.left-container, main');
                    const hasToolbar = !!document.querySelector('.video-toolbar-container, #arc_toolbar_report');
                    const hasCommentAnchor = !!document.querySelector('#commentapp, .comment-container, .bb-comment');
                    const hasEpisodeAnchor = !!document.querySelector('.video-pod, .multi-page, [class*="episode-list"], [class*="part-list"], [class*="page-list"]');
                    const hasViewbox = !!document.querySelector('#viewbox_report');
                    const playerLoadingVisible = hasVisiblePlayerLoadingOverlay();
                    const visiblePlayer = hasVisiblePlayer();

                    if (hasPlayer) score += 25;
                    if (hasContainer) score += 20;
                    if (hasToolbar) score += 20;
                    if (hasCommentAnchor) score += 15;
                    if (hasEpisodeAnchor) score += 15;
                    if (hasViewbox) score += 5;

                    return {
                      score: score,
                      ready: hasPlayer && hasContainer && visiblePlayer,
                      details: {
                        hasPlayer: hasPlayer,
                        hasContainer: hasContainer,
                        hasToolbar: hasToolbar,
                        hasCommentAnchor: hasCommentAnchor,
                        hasEpisodeAnchor: hasEpisodeAnchor,
                        hasViewbox: hasViewbox,
                        playerLoadingVisible: playerLoadingVisible,
                        visiblePlayer: visiblePlayer
                      }
                    };
                  };

                  return checkTargets();
                })();
                """

                let (isReady, score, playerLoadingVisible, visiblePlayer) = await withCheckedContinuation { continuation in
                    webView.evaluateJavaScript(preflightScript) { value, error in
                        if let dict = value as? [String: Any],
                           let ready = dict["ready"] as? Bool,
                           let score = dict["score"] as? Int {
                            let details = dict["details"] as? [String: Any]
                            let playerLoadingVisible = details?["playerLoadingVisible"] as? Bool ?? false
                            let visiblePlayer = details?["visiblePlayer"] as? Bool ?? false
                            continuation.resume(returning: (ready, score, playerLoadingVisible, visiblePlayer))
                        } else {
                            continuation.resume(returning: (false, 0, false, false))
                        }
                    }
                }

                guard
                    !Task.isCancelled,
                    self.pageAugmentationRevision == revision,
                    self.isCurrent(callbackContext, webView: webView)
                else {
                    return
                }

                self.debugLog(
                    "nativePageAugmentation.preflight",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "pageKind": payload.kind.rawValue,
                        "attempt": String(index),
                        "delayMS": String(delay / 1_000_000),
                        "ready": isReady ? "true" : "false",
                        "score": String(score),
                        "visiblePlayer": visiblePlayer ? "true" : "false",
                        "playerLoadingVisible": playerLoadingVisible ? "true" : "false"
                    ])
                )

                if !isReady {
                    self.debugLog(
                        index == delays.count - 1
                            ? "nativePageAugmentation.preflightFinalFallback"
                            : "nativePageAugmentation.skipPreflight",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "pageKind": payload.kind.rawValue,
                            "attempt": String(index),
                            "delayMS": String(delay / 1_000_000),
                            "visiblePlayer": visiblePlayer ? "true" : "false",
                            "playerLoadingVisible": playerLoadingVisible ? "true" : "false",
                            "reason": visiblePlayer ? "dom-not-ready" : "player-not-visible"
                        ])
                    )
                }

                guard isReady || index == delays.count - 1 else {
                    continue
                }

                let script = payload.javaScript
                do {
                    _ = try await webView.evaluateJavaScript(script)
                } catch {
                    self.debugLog(
                        "nativePageAugmentation.error",
                        fields: self.debugStateFields([
                            "pageURL": canonicalURL.absoluteString,
                            "pageKind": payload.kind.rawValue,
                            "attempt": String(index),
                            "error": String(describing: error)
                        ])
                    )
                    continue
                }

                guard
                    !Task.isCancelled,
                    self.pageAugmentationRevision == revision,
                    self.isCurrent(callbackContext, webView: webView)
                else {
                    return
                }

#if DEBUG
                if self.settingsStore.settings.debugLoggingEnabledForCurrentBuild {
                    let probeScript = """
                    (() => {
                      const root = document.getElementById('focus-native-video-augment') || document.getElementById('focus-native-opus-comments');
                      if (!root) {
                        return { exists: false };
                      }
                      const rect = root.getBoundingClientRect();
                      return {
                        exists: true,
                        top: Math.round(rect.top),
                        height: Math.round(rect.height),
                        childCount: root.children.length,
                        mountCount: root.getAttribute ? (root.getAttribute('data-focus-mount-count') || '') : '',
                        mountPhase: root.getAttribute ? (root.getAttribute('data-focus-mount-phase') || '') : '',
                        isPlaceholder: root.hasAttribute ? root.hasAttribute('data-focus-placeholder') : false,
                        renderKey: root.getAttribute ? (root.getAttribute('data-focus-render-key') || '') : '',
                        version: root.getAttribute ? (root.getAttribute('data-focus-version') || '') : '',
                        loadingMaskPresent: !!document.getElementById('focus-native-video-loading-mask'),
                        readyClass: document.documentElement.classList.contains('focus-native-video-ready') || !!document.body?.classList?.contains?.('focus-native-video-ready'),
                        textSample: String(root.textContent || '').trim().slice(0, 120),
                        parentTag: root.parentElement?.tagName || '',
                        previousTag: root.previousElementSibling?.tagName || '',
                        previousClass: root.previousElementSibling?.className || '',
                        domProbe: (() => {
                          const sample = (selector) => {
                            const node = document.querySelector(selector);
                            if (!(node instanceof HTMLElement)) {
                              return '0';
                            }
                            const rect = node.getBoundingClientRect();
                            const style = window.getComputedStyle(node);
                            return [
                              '1',
                              Math.round(rect.height),
                              style.display,
                              style.visibility,
                              style.opacity
                            ].join(':');
                          };
                          return {
                            rightContainer: sample('.right-container'),
                            rightContainerInner: sample('.right-container-inner'),
                            sideToolbar: sample('.side-toolbar, .right-entry, [class*="side-toolbar"], [class*="right-entry"]'),
                            toolbar: sample('.video-toolbar-container, #arc_toolbar_report'),
                            playerLoading: sample('#bilibili-player [class*="loading"], #playerWrap [class*="loading"], .bpx-player-container [class*="loading"], #bilibili-player [class*="skeleton"], #playerWrap [class*="skeleton"], .bpx-player-container [class*="skeleton"]'),
                            viewbox: sample('#viewbox_report'),
                            videoPod: sample('.video-pod, .video-pod__body'),
                            commentApp: sample('#commentapp, bili-comments, .comment-container'),
                            skeleton: sample('[class*="skeleton"]'),
                            loading: sample('[class*="loading"]'),
                            scrollY: Math.round(window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0)
                          };
                        })()
                      };
                    })();
                    """
                    let traceScript = """
                    (() => {
                      const root = document.getElementById('focus-native-video-augment');
                      if (!(root instanceof HTMLElement)) {
                        return { stage: 'missing-root' };
                      }
                      const trace = (label) => {
                        const y = Math.round(window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0);
                        const rect = root.getBoundingClientRect();
                        return {
                          stage: label,
                          scrollY: y,
                          rootTop: Math.round(rect.top),
                          rootHeight: Math.round(rect.height),
                          mountCount: root.getAttribute('data-focus-mount-count') || '',
                          mountPhase: root.getAttribute('data-focus-mount-phase') || '',
                          readyClass: document.documentElement.classList.contains('focus-native-video-ready') || !!document.body?.classList?.contains?.('focus-native-video-ready'),
                          toolbarHeight: (() => {
                            const node = document.querySelector('.video-toolbar-container, #arc_toolbar_report');
                            if (!(node instanceof HTMLElement)) {
                              return 0;
                            }
                            return Math.round(node.getBoundingClientRect().height);
                          })(),
                          sideToolbarHeight: (() => {
                            const node = document.querySelector('.side-toolbar, .right-entry, [class*="side-toolbar"], [class*="right-entry"]');
                            if (!(node instanceof HTMLElement)) {
                              return 0;
                            }
                            return Math.round(node.getBoundingClientRect().height);
                          })()
                        };
                      };
                      window.__FOCUS_TRACE_NATIVE_AUGMENT__ = trace;
                      return trace('trace-installed');
                    })();
                    """
                    Task { @MainActor in
                        do {
                            let value = try await webView.evaluateJavaScript(traceScript)
                            guard
                                self.pageAugmentationRevision == revision,
                                self.isCurrent(callbackContext, webView: webView)
                            else {
                                return
                            }
                            self.debugLog(
                                "nativePageAugmentation.traceInstalled",
                                fields: self.debugStateFields([
                                    "pageURL": canonicalURL.absoluteString,
                                    "pageKind": payload.kind.rawValue,
                                    "attempt": String(index),
                                    "trace": String(describing: value)
                                ])
                            )
                        } catch {
                            guard self.isCurrent(callbackContext, webView: webView) else {
                                return
                            }
                            self.debugLog(
                                "nativePageAugmentation.traceInstallError",
                                fields: self.debugStateFields([
                                    "pageURL": canonicalURL.absoluteString,
                                    "pageKind": payload.kind.rawValue,
                                    "attempt": String(index),
                                    "error": String(describing: error)
                                ])
                            )
                        }
                    }
                    Task { @MainActor in
                        do {
                            let value = try await webView.evaluateJavaScript(probeScript)
                            guard
                                self.pageAugmentationRevision == revision,
                                self.isCurrent(callbackContext, webView: webView)
                            else {
                                return
                            }
                            self.debugLog(
                                "nativePageAugmentation.probeCaptured",
                                fields: self.debugStateFields([
                                    "pageURL": canonicalURL.absoluteString,
                                    "pageKind": payload.kind.rawValue,
                                    "attempt": String(index),
                                    "probeType": value.map { String(describing: type(of: $0)) } ?? "nil"
                                ])
                            )
                        } catch {}
                    }
                    let traceSampleDelays: [UInt64] = [0, 120_000_000, 260_000_000]
                    for (sampleIndex, sampleDelay) in traceSampleDelays.enumerated() {
                        Task { @MainActor [weak self] in
                            guard let self else {
                                return
                            }
                            if sampleDelay > 0 {
                                try? await Task.sleep(nanoseconds: sampleDelay)
                            }
                            guard
                                self.pageAugmentationRevision == revision,
                                let activeWebView = self.webView,
                                (activeWebView.url ?? self.currentURL ?? self.pendingURL).map(FocusNavigationPolicy.canonicalWebURL(for:)) == canonicalURL
                            else {
                                return
                            }

                            do {
                                let value = try await activeWebView.evaluateJavaScript(
                                    "window.__FOCUS_TRACE_NATIVE_AUGMENT__ ? window.__FOCUS_TRACE_NATIVE_AUGMENT__('sample-\(sampleIndex)') : { stage: 'trace-missing' }"
                                )
                                guard
                                    self.pageAugmentationRevision == revision,
                                    self.isCurrent(callbackContext, webView: activeWebView)
                                else {
                                    return
                                }
                                self.debugLog(
                                    "nativePageAugmentation.traceSample",
                                    fields: self.debugStateFields([
                                        "pageURL": canonicalURL.absoluteString,
                                        "pageKind": payload.kind.rawValue,
                                        "attempt": String(index),
                                        "sampleIndex": String(sampleIndex),
                                        "sampleDelayMS": String(sampleDelay / 1_000_000),
                                        "trace": String(describing: value)
                                    ])
                                )
                            } catch {
                                self.debugLog(
                                    "nativePageAugmentation.traceSampleError",
                                    fields: self.debugStateFields([
                                        "pageURL": canonicalURL.absoluteString,
                                        "pageKind": payload.kind.rawValue,
                                        "attempt": String(index),
                                        "sampleIndex": String(sampleIndex),
                                        "sampleDelayMS": String(sampleDelay / 1_000_000),
                                        "error": String(describing: error)
                                    ])
                                )
                            }
                        }
                    }
                }
#endif

                self.debugLog(
                    "nativePageAugmentation.applied",
                    fields: self.debugStateFields([
                        "pageURL": canonicalURL.absoluteString,
                        "pageKind": payload.kind.rawValue,
                        "attempt": String(index),
                        "delayMS": String(delay / 1_000_000),
                        "summary": payload.summary
                    ])
                )
            }
        }
    }

    private func nativePageKind(for url: URL) -> FocusNativePageKind? {
        if isOpusDetailURL(url) {
            return .opus
        }

        guard let host = url.host?.lowercased() else {
            return nil
        }

        let path = url.path.lowercased()
        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           path.hasPrefix("/video/")
        {
            return .video
        }

        return nil
    }

    private func startPlayerStateObservation() {
        embeddedPlayerDetectionTask?.cancel()
        embeddedPlayerDetectionTask = nil
        playerStateObservationTask?.cancel()
        guard
            allowsPlayerControl,
            let webView,
            let context = makeBrowserCallbackContext(for: webView)
        else {
            return
        }

        playerStateObservationTask = Task { @MainActor [weak self, weak webView] in
            let delays: [UInt64] = [0, 300_000_000, 700_000_000, 1_400_000_000, 2_500_000_000]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard
                    let self,
                    let webView,
                    !Task.isCancelled,
                    self.allowsPlayerControl,
                    self.isCurrent(context, webView: webView)
                else {
                    return
                }

                if await self.refreshPlayerState(on: webView, context: context) {
                    return
                }
            }
        }
    }

    @discardableResult
    private func refreshPlayerState(
        on webView: WKWebView,
        context: BrowserCallbackContext
    ) async -> Bool {
        guard allowsPlayerControl, isCurrent(context, webView: webView) else {
            playerStateObservationTask?.cancel()
            playerStateObservationTask = nil
            return false
        }

        let script = """
        (() => {
          const titleSelectors = [
            '#viewbox_report',
            'h1.video-title',
            'h1[class*="video-title"]',
            '.video-title',
            '[class*="video-title"]',
            '[class*="archive-title"]',
            '.media-title'
          ];
          const extractVideoTitle = () => {
            for (const selector of titleSelectors) {
              const node = Array.from(document.querySelectorAll(selector)).find((candidate) => {
                const text = String(candidate?.textContent || '').trim();
                const rect = candidate?.getBoundingClientRect?.();
                return !!text && text.length >= 4 && text.length <= 160 && !!rect && rect.width > 40;
              });
              if (node) {
                return String(node.textContent || '').trim();
              }
            }
            return '';
          };
          const snapshot = typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function'
            ? window.__FOCUS_SNAPSHOT_PLAYER_STATE__()
            : null;
          const cachedState = snapshot || window.__FOCUS_PLAYER_STATE__;
          if (cachedState && typeof cachedState === 'object' && cachedState.hasPlayer) {
            return {
              ...cachedState,
              pageURL: cachedState.pageURL || location.href,
              pageTitle: cachedState.pageTitle || document.title || '',
              videoTitle: cachedState.videoTitle || extractVideoTitle()
            };
          }

          const videos = Array.from(document.querySelectorAll('video'));
          const rankedVideos = videos
            .map((video) => {
              const rect = video.getBoundingClientRect();
              const style = window.getComputedStyle(video);
              const area = Math.max(rect.width, 0) * Math.max(rect.height, 0);
              const visible = rect.width > 120
                && rect.height > 70
                && style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0';
              const insidePlayer = !!video.closest('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
              const largePlaybackCandidate = rect.width >= Math.max(window.innerWidth * 0.62, 240)
                || rect.height >= 180
                || area >= 65000;
              const score = (insidePlayer ? 1000000 : 0)
                + (largePlaybackCandidate ? 250000 : 0)
                + (visible ? 100000 : 0)
                + area
                + (video.readyState > 0 ? 5000 : 0)
                + (!video.paused && !video.ended ? 1000 : 0);
              return { video, score, insidePlayer, largePlaybackCandidate };
            })
            .sort((left, right) => right.score - left.score);
          const hasPlayerShell = !!document.querySelector('#bilibili-player, .bpx-player-container, #playerWrap, .player-container, .bpx-player-video-wrap');
          const primaryRankedVideo = rankedVideos[0] || null;
          const activeVideo = primaryRankedVideo?.video || null;
          const hasPlaybackVideo = !!(primaryRankedVideo && (primaryRankedVideo.insidePlayer || primaryRankedVideo.largePlaybackCandidate))
            || !!document.querySelector('#bilibili-player video, .bpx-player-container video, #playerWrap video, .player-container video, .bpx-player-video-wrap video');
          const playButton = document.querySelector('.bpx-player-ctrl-play, .bilibili-player-video-btn-start, [class*="ctrl-play"]');
          const danmakuToggle = document.querySelector('.bpx-player-ctrl-dm, .bpx-player-dm-switch, [class*="dm-switch"], [class*="ctrl-dm"]');
          const playbackRateNode = document.querySelector('.bpx-player-ctrl-playbackrate-result, .bpx-player-ctrl-playbackrate [class*="name"], .bpx-player-ctrl-playbackrate [class*="text"], .bpx-player-ctrl-playbackrate-menu .active, [class*="playbackrate"] [class*="name"], [class*="playbackrate"] [class*="text"], [class*="playbackrate"], [class*="speed"] .active, [class*="speed"] [aria-checked="true"]');
          const subtitleToggle = document.querySelector('.bpx-player-ctrl-subtitle, .bpx-player-subtitle-btn, [class*="subtitle-switch"], [class*="subtitle-btn"], [class*="subtitle"] button');
          const isDanmakuOff = document.documentElement.classList.contains('focus-hide-danmaku')
            || danmakuToggle?.getAttribute('aria-checked') === 'false'
            || danmakuToggle?.getAttribute('aria-pressed') === 'false'
            || danmakuToggle?.classList.contains('off')
            || danmakuToggle?.classList.contains('disabled');
          const textTracks = activeVideo && activeVideo.textTracks ? Array.from(activeVideo.textTracks) : [];
          const playerRoot = document.querySelector('.bpx-player-container, #bilibili-player, #playerWrap');
          const playerClassName = String(playerRoot?.className || '');
          const playButtonDescriptor = [playButton?.getAttribute('aria-label'), playButton?.getAttribute('title'), playButton?.textContent, playButton?.className].filter(Boolean).join(' ').toLowerCase();
          const uiSuggestsPlaying = /pause|暂停|icon-pause|state-pause|video-state-pause/.test(playButtonDescriptor);
          const uiSuggestsPaused = /play|播放|icon-play|state-play|video-state-play/.test(playButtonDescriptor);
          const videoSuggestsPlaying = !!activeVideo && !activeVideo.paused && !activeVideo.ended;
          const isFullscreen = !!document.fullscreenElement
            || activeVideo?.webkitPresentationMode === 'fullscreen'
            || activeVideo?.webkitPresentationMode === 'fullScreen'
            || /(^|\\s)(?:web-)?fullscreen(?:\\s|$)/.test(playerClassName);
          const hasSubtitleLayer = !!document.querySelector('.bpx-player-subtitle-wrap, [class*="subtitle-panel"], [class*="subtitle-item"], [class*="subtitle-wrap"]');
          const hasSubtitleTrack = !!subtitleToggle || hasSubtitleLayer || textTracks.length > 0;
          const isSubtitleOff = document.documentElement.classList.contains('focus-hide-subtitles')
            || (textTracks.length > 0 && textTracks.every((track) => track.mode === 'disabled'))
            || subtitleToggle?.getAttribute('aria-checked') === 'false'
            || subtitleToggle?.getAttribute('aria-pressed') === 'false'
            || subtitleToggle?.classList.contains('off')
            || subtitleToggle?.classList.contains('disabled');
          const rateText = String(playbackRateNode?.textContent || '').trim();
          const rateMatch = rateText.match(/(\\d+(?:\\.\\d+)?)\\s*x/i);
          const parsedRate = rateMatch ? Number(rateMatch[1]) : NaN;
          const rawPlaybackRate = Number(activeVideo?.playbackRate || 0);
          const isPlaying = activeVideo
            ? videoSuggestsPlaying
            : uiSuggestsPlaying && !uiSuggestsPaused;
          const playbackRate = Number.isFinite(rawPlaybackRate) && rawPlaybackRate > 0
            ? rawPlaybackRate
            : Number.isFinite(parsedRate) && parsedRate > 0
                ? parsedRate
                : 1;

          return {
            hasPlayer: hasPlayerShell || hasPlaybackVideo,
            pageURL: location.href,
            pageTitle: document.title || '',
            videoTitle: extractVideoTitle(),
            isPlaying: !!isPlaying,
            playbackRate,
            isDanmakuHidden: !!isDanmakuOff,
            hasSubtitles: !!hasSubtitleTrack,
            isSubtitleHidden: !!isSubtitleOff,
            isFullscreen: !!isFullscreen
          };
        })();
        """

        do {
            let value = try await webView.evaluateJavaScript(script)
            guard !Task.isCancelled, isCurrent(context, webView: webView) else {
                return false
            }
            guard let payload = value as? [String: Any] else {
                debugLog(
                    "refreshPlayerState.missingPayload",
                    fields: debugStateFields([
                        "valueType": value.map { String(describing: type(of: $0)) } ?? "nil"
                    ])
                )
                return false
            }
            applyPlayerStatePayload(payload, context: context, webView: webView, source: "refreshPlayerState")
            return payload["hasPlayer"] as? Bool ?? false
        } catch {
            guard isCurrent(context, webView: webView) else {
                return false
            }
            debugLog(
                "refreshPlayerState.error",
                fields: debugStateFields(["error": String(describing: error)])
            )
            return false
        }
    }

    private func applyPlayerStatePayload(
        _ payload: [String: Any],
        context: BrowserCallbackContext,
        webView: WKWebView,
        source: String
    ) {
        guard isCurrent(context, webView: webView) else {
            return
        }

        let snapshot = PlayerSnapshot(
            hasPlayer: payload["hasPlayer"] as? Bool ?? false,
            isPlaying: payload["isPlaying"] as? Bool ?? false,
            playbackRate: max(Self.doubleValue(payload["playbackRate"]) ?? 1, 0.1),
            isDanmakuHidden: payload["isDanmakuHidden"] as? Bool ?? false,
            hasSubtitles: payload["hasSubtitles"] as? Bool ?? false,
            isSubtitleHidden: payload["isSubtitleHidden"] as? Bool ?? false,
            isFullscreen: payload["isFullscreen"] as? Bool ?? false
        )

        let detectedState = makeDetectedPageState(from: payload)
        applyDetectedPageState(detectedState, fallbackURL: context.canonicalURL)
        if snapshot.hasPlayer {
            hasActiveVideoRoute = true
            isLoadingPage = false
            if nativePageKind(for: context.canonicalURL) == .video,
               nativeVideoPlaceholderTask != nil
            {
                nativeVideoPlaceholderTask?.cancel()
                nativeVideoPlaceholderTask = nil
                installNativeVideoPlaceholderIfNeeded(for: context.canonicalURL)
            }
            if scheduledPageAugmentationKey == nil {
                schedulePageAugmentationRefresh()
            }
        }

        updatePlayerSnapshot(snapshot)
        if pendingOrientationSyncAfterPlayerReady, snapshot.hasPlayer {
            handleDeviceOrientationChange(UIDevice.current.orientation)
        }
        logDetectedPageState(detectedState, source: source)
        logPlayerStatePayload(payload)
    }

    func updatePlayerSnapshot(_ snapshot: PlayerSnapshot) {
        guard playerSnapshot != snapshot else {
            return
        }
        playerSnapshot = snapshot
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        return (value as? NSNumber)?.doubleValue
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 {
            return value
        }
        if let value = value as? Int, value >= 0 {
            return UInt64(value)
        }
        return (value as? NSNumber)?.uint64Value
    }

    private func debugLog(
        _ event: @autoclosure () -> String,
        fields: @autoclosure () -> [String: String?] = [:]
    ) {
#if DEBUG
        guard settingsStore.settings.debugLoggingEnabledForCurrentBuild else {
            return
        }

        let resolvedEvent = event()
        let payload = fields()
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value ?? "nil")"
            }
            .joined(separator: " ")

        if payload.isEmpty {
            print("[Focus Native Debug] \(resolvedEvent)")
        } else {
            print("[Focus Native Debug] \(resolvedEvent) \(payload)")
        }
#endif
    }

    private func debugStateFields(_ extra: [String: String?] = [:]) -> [String: String?] {
#if DEBUG
        var fields: [String: String?] = [
            "context": entryContextLabel(entryContext),
            "currentURL": currentURL?.absoluteString,
            "pendingURL": pendingURL?.absoluteString,
            "webViewURL": webView?.url?.absoluteString,
            "webViewTitle": webView?.title,
            "navigationTitle": navigationTitle,
            "hasActiveVideoRoute": debugBool(hasActiveVideoRoute),
            "hasDetectedPlayer": debugBool(hasDetectedPlayer),
            "isVideoPage": debugBool(isVideoPage),
            "showsNativeVideoControls": debugBool(showsNativeVideoControls),
            "isLoadingPage": debugBool(isLoadingPage)
        ]

        extra.forEach { key, value in
            fields[key] = value
        }
        return fields
#else
        return [:]
#endif
    }

    private func logDetectedPageState(_ state: DetectedPageState, source: String) {
#if DEBUG
        let signature = [
            source,
            debugBool(state.hasPlayer),
            state.pageURLString ?? "",
            sanitizedPageTitle(state.videoTitle) ?? "",
            sanitizedPageTitle(state.pageTitle) ?? ""
        ].joined(separator: "|")

        guard signature != lastDebugDetectedPageStateSignature else {
            return
        }

        lastDebugDetectedPageStateSignature = signature
        debugLog(
            source,
            fields: debugStateFields([
                "detectedHasPlayer": debugBool(state.hasPlayer),
                "detectedPageURL": state.pageURLString,
                "detectedPageTitle": sanitizedPageTitle(state.pageTitle),
                "detectedVideoTitle": sanitizedPageTitle(state.videoTitle)
            ])
        )
#endif
    }

    private func logPlayerStatePayload(_ payload: [String: Any]) {
#if DEBUG
        let playbackRateValue = payload["playbackRate"] as? Double ?? 1.0
        let hasPlayerValue = payload["hasPlayer"] as? Bool ?? false
        let isPlayingValue = payload["isPlaying"] as? Bool ?? false
        let isFullscreenValue = payload["isFullscreen"] as? Bool ?? false
        let signature = [
            debugBool(hasPlayerValue),
            debugBool(isPlayingValue),
            String(format: "%.2f", playbackRateValue),
            debugBool(isFullscreenValue),
            String(payload["playerWidth"] as? Int ?? 0),
            String(payload["playerHeight"] as? Int ?? 0),
            sanitizedPageTitle(payload["videoTitle"] as? String) ?? "",
            payload["pageURL"] as? String ?? ""
        ].joined(separator: "|")

        guard signature != lastDebugPlayerStateSignature else {
            return
        }

        lastDebugPlayerStateSignature = signature
        debugLog(
            "refreshPlayerState",
            fields: debugStateFields([
                "payloadHasPlayer": debugBool(hasPlayerValue),
                "payloadIsPlaying": debugBool(isPlayingValue),
                "payloadPlaybackRate": String(format: "%.2f", playbackRateValue),
                "payloadIsFullscreen": debugBool(isFullscreenValue),
                "payloadPageURL": payload["pageURL"] as? String,
                "payloadPageTitle": sanitizedPageTitle(payload["pageTitle"] as? String),
                "payloadVideoTitle": sanitizedPageTitle(payload["videoTitle"] as? String),
                "payloadPlayerWidth": String(payload["playerWidth"] as? Int ?? 0),
                "payloadPlayerHeight": String(payload["playerHeight"] as? Int ?? 0),
                "payloadHasSubtitles": debugBool(payload["hasSubtitles"] as? Bool ?? false),
                "payloadIsSubtitleHidden": debugBool(payload["isSubtitleHidden"] as? Bool ?? false),
                "payloadIsDanmakuHidden": debugBool(payload["isDanmakuHidden"] as? Bool ?? false)
            ])
        )
#endif
    }

    private func debugBool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    private func entryContextLabel(_ context: EntryContext) -> String {
        switch context {
        case .dynamic:
            return "dynamic"
        case .search:
            return "search"
        case .my:
            return "my"
        }
    }

    private func navigationTypeLabel(_ navigationType: WKNavigationType) -> String {
        switch navigationType {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .formResubmitted:
            return "formResubmitted"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}

extension Notification.Name {
    static let focusSessionDidChange = Notification.Name("FocusSessionDidChange")
}

final class WebViewCookieSnapshotProvider: NSObject, @unchecked Sendable, CookieSnapshotProvider {
    let websiteDataStore: WKWebsiteDataStore
    private let cookieStore: WKHTTPCookieStore
    private let coordinator: CookieSessionCoordinator
    private let observer: StoreObserver
    private let transitionLock = NSLock()
    private var pendingAccountReset = false

    @MainActor
    private final class StoreObserver: NSObject, WKHTTPCookieStoreObserver {
        weak var owner: WebViewCookieSnapshotProvider?
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard let owner else { return }
            owner.coordinator.invalidate()
            Task { _ = await owner.coordinator.loadSnapshot() }
        }
    }

    @MainActor
    init(
        websiteDataStore: WKWebsiteDataStore = .default(),
        performsLoginWarmup: Bool = true
    ) {
        self.websiteDataStore = websiteDataStore
        let store = websiteDataStore.httpCookieStore
        self.cookieStore = store
        self.coordinator = CookieSessionCoordinator(
            reader: { @MainActor in
                await withCheckedContinuation { continuation in
                    store.getAllCookies { continuation.resume(returning: $0) }
                }
            },
            warmupDelays: performsLoginWarmup ? [180_000_000, 350_000_000, 700_000_000, 1_100_000_000] : []
        )
        self.observer = StoreObserver()
        super.init()
        observer.owner = self
        store.add(observer)
        coordinator.setTransitionHandler { [weak self] transition in
            // A newer tracking-cookie event can overtake the account-change
            // notification. Preserve its reset obligation until a current event
            // is delivered instead of losing it to the generation guard.
            self?.transitionLock.withLock {
                if transition.requiresAccountReset { self?.pendingAccountReset = true }
            }
            Task { @MainActor [weak self] in
                guard let self, self.sessionVersion == transition.version else { return }
                let requiresReset = self.transitionLock.withLock {
                    let reset = self.pendingAccountReset
                    self.pendingAccountReset = false
                    return reset
                }
                NotificationCenter.default.post(
                    name: .focusSessionDidChange, object: self,
                    userInfo: ["version": transition.version, "readiness": transition.readiness.rawValue,
                               "requiresAccountReset": requiresReset]
                )
            }
        }
    }

    deinit {
        let store = cookieStore
        let observer = observer
        Task { @MainActor in store.remove(observer) }
    }

    var sessionVersion: UInt64 { coordinator.sessionVersion }
    var sessionReadiness: CookieSessionReadiness { coordinator.sessionReadiness }
    func loadCookies() async -> [HTTPCookie] { await coordinator.loadCookies() }
    func loadSnapshot() async -> CookieSessionSnapshot { await coordinator.loadSnapshot() }
    func refreshSnapshotIfNeeded() async -> [HTTPCookie] { await loadCookies() }
    func noteServerSessionExpired(version: UInt64) { coordinator.noteServerSessionExpired(version: version) }
    func attachCookies(to request: URLRequest) -> URLRequest { coordinator.attachCookies(to: request) }
    static func containsUsableLoginSession(in cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        CookieSessionCoordinator.hasUsableSession(cookies, now: now)
    }
}

extension Encodable {
    var focusJSONString: String {
        let encoder = JSONEncoder()
        guard
            let data = try? encoder.encode(self),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }
}

extension Dictionary where Key == String, Value == Any {
    func value(at keys: String...) -> Any? {
        value(at: Array(keys))
    }

    func dictionaryValue(at keys: String...) -> [String: Any]? {
        value(at: keys) as? [String: Any]
    }

    func arrayValue(at keys: String...) -> [[String: Any]]? {
        (value(at: keys) as? [Any])?.compactMap { $0 as? [String: Any] }
    }

    func stringValue(at keys: String...) -> String? {
        if let value = value(at: keys) as? String {
            return value
        }
        if let number = value(at: keys) as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func intValue(at keys: String...) -> Int? {
        if let number = value(at: keys) as? NSNumber {
            return number.intValue
        }
        if let string = value(at: keys) as? String {
            return Int(string)
        }
        return nil
    }

    func int64Value(at keys: String...) -> Int64? {
        if let number = value(at: keys) as? NSNumber {
            return number.int64Value
        }
        if let string = value(at: keys) as? String {
            return Int64(string)
        }
        return nil
    }

    func boolValue(at keys: String...) -> Bool? {
        if let value = value(at: keys) as? Bool {
            return value
        }
        if let number = value(at: keys) as? NSNumber {
            return number.boolValue
        }
        if let string = value(at: keys) as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func value(at keys: [String]) -> Any? {
        var current: Any = self
        for key in keys {
            guard let dictionary = current as? [String: Any] else {
                return nil
            }
            guard let next = dictionary[key], !(next is NSNull) else {
                return nil
            }
            current = next
        }
        return current
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func substringAfterLast(_ separator: Character) -> String {
        guard let index = lastIndex(of: separator) else {
            return self
        }
        return String(self[self.index(after: index)...])
    }

    func substringBefore(_ separator: Character) -> String {
        guard let index = firstIndex(of: separator) else {
            return self
        }
        return String(self[..<index])
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
#endif
