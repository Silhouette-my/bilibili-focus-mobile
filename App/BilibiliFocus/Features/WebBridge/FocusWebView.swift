#if canImport(UIKit)
import FocusCore
import SwiftUI
import UIKit
import WebKit

enum FocusWebSettingsUpdate: Equatable {
    case none
    case appearance
    case pageRules

    static func classify(
        previous: FocusSettings,
        current: FocusSettings,
        previousDarkMode: Bool,
        currentDarkMode: Bool
    ) -> FocusWebSettingsUpdate {
#if DEBUG
        let debugLoggingChanged = previous.debugMode != current.debugMode
#else
        let debugLoggingChanged = false
#endif
        let pageRulesChanged = previous.redirectEnabled != current.redirectEnabled
            || previous.playerMaskEnabled != current.playerMaskEnabled
            || previous.searchMaskEnabled != current.searchMaskEnabled
            || previous.dynamicMaskEnabled != current.dynamicMaskEnabled
            || debugLoggingChanged
        if pageRulesChanged {
            return .pageRules
        }
        if previousDarkMode != currentDarkMode {
            return .appearance
        }
        return .none
    }
}

struct FocusWebView: UIViewRepresentable {
    let viewModel: FocusBrowserViewModel
    var isActive = true
    @ObservedObject var settingsStore: FocusSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private func resolvedDarkMode() -> Bool {
        switch settingsStore.settings.themeMode {
        case .system:
            return colorScheme == .dark
        case .light:
            return false
        case .dark:
            return true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = viewModel.websiteDataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = FocusUserAgent.mobileSafari()
        webView.allowsBackForwardNavigationGestures = false
        let isDarkMode = resolvedDarkMode()
        webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        webView.isOpaque = false
        webView.backgroundColor = isDarkMode ? UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1) : UIColor(red: 0.965, green: 0.969, blue: 0.98, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
#if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
#endif
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.installScripts(
            on: webView,
            settings: settingsStore.settings,
            isDarkMode: isDarkMode
        )
        viewModel.attach(
            webView: webView,
            prepareForURL: { [weak coordinator = context.coordinator] webView, url in
                coordinator?.prepare(webView: webView, for: url)
            }
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let isDarkMode = resolvedDarkMode()
        context.coordinator.updateDocumentActivity(
            on: webView, isActive: isActive, settings: settingsStore.settings, isDarkMode: isDarkMode
        )
        webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        webView.backgroundColor = isDarkMode ? UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1) : UIColor(red: 0.965, green: 0.969, blue: 0.98, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        guard
            let previousSettings = context.coordinator.lastAppliedSettings,
            let previousDarkMode = context.coordinator.lastAppliedDarkMode
        else {
            context.coordinator.installScripts(
                on: webView,
                settings: settingsStore.settings,
                isDarkMode: isDarkMode
            )
            return
        }

        switch FocusWebSettingsUpdate.classify(
            previous: previousSettings,
            current: settingsStore.settings,
            previousDarkMode: previousDarkMode,
            currentDarkMode: isDarkMode
        ) {
        case .none:
            context.coordinator.record(settings: settingsStore.settings, isDarkMode: isDarkMode)
        case .appearance:
            context.coordinator.applyAppearance(
                on: webView,
                settings: settingsStore.settings,
                isDarkMode: isDarkMode
            )
        case .pageRules:
            context.coordinator.installScripts(
                on: webView,
                settings: settingsStore.settings,
                isDarkMode: isDarkMode
            )
            guard viewModel.isSessionActive else {
                return
            }
            context.coordinator.reapplyCurrentPageScripts(on: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.tearDown(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let viewModel: FocusBrowserViewModel
        fileprivate var lastAppliedSettings: FocusSettings?
        fileprivate var lastAppliedDarkMode: Bool?
        fileprivate var lastDocumentStartScript: String?
        fileprivate var lastDocumentEndScript: String?
        fileprivate var lastAppearanceScript: String?
        private var lastPreparedUsesDesktopMode = false
        private var documentActive: Bool?
        private var synchronizedSuspensionRevision: UInt64?

        init(viewModel: FocusBrowserViewModel) {
            self.viewModel = viewModel
        }

#if DEBUG
        private static let debugBridgeScript = """
        (() => {
          window.__FOCUS_DEBUG_SINK__ = (payload) => {
            try {
              window.webkit?.messageHandlers?.logDebug?.postMessage(payload);
            } catch (_) {}
          };
        })();
        """
#endif

        func tearDown(webView: WKWebView) {
            let controller = webView.configuration.userContentController
            webView.evaluateJavaScript("window.__FOCUS_NATIVE_PLAYER_BRIDGE__?.teardown?.(); window.__FOCUS_NATIVE_PLAYER_BRIDGE__ = null;")
            controller.removeScriptMessageHandler(forName: "getConfig")
#if DEBUG
            controller.removeScriptMessageHandler(forName: "logDebug")
#endif
            controller.removeScriptMessageHandler(forName: "playerState")
            controller.removeAllUserScripts()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            viewModel.detach(webView: webView)
        }

        func prepare(webView: WKWebView, for url: URL) {
            let useDesktopMode = FocusUserAgent.shouldUseDesktopMode(for: url)
            lastPreparedUsesDesktopMode = useDesktopMode
            webView.customUserAgent = useDesktopMode ? FocusUserAgent.desktopSafari() : FocusUserAgent.mobileSafari()
            webView.configuration.defaultWebpagePreferences.preferredContentMode = useDesktopMode ? .desktop : .mobile
        }

        func installScripts(on webView: WKWebView, settings: FocusSettings, isDarkMode: Bool) {
            let controller = webView.configuration.userContentController
            controller.removeAllUserScripts()
            controller.removeScriptMessageHandler(forName: "getConfig")
#if DEBUG
            controller.removeScriptMessageHandler(forName: "logDebug")
#endif
            controller.removeScriptMessageHandler(forName: "playerState")
            controller.add(self, name: "getConfig")
#if DEBUG
            controller.add(self, name: "logDebug")
#endif
            controller.add(self, name: "playerState")
            controller.addUserScript(WKUserScript(
                source: "window.__FOCUS_DOCUMENT_ACTIVE__ = \((documentActive ?? viewModel.isSessionActive) ? "true" : "false");",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))

            let bootstrapAppearanceScript = FocusWebAppearance.bootstrapCSS(isDarkMode: isDarkMode)
            let appearanceScript = FocusWebAppearance.script(isDarkMode: isDarkMode)
            let documentStartScript = try? FocusScriptBuilder.makeUserScript(for: .documentStart, settings: settings)
            let documentEndScript = try? FocusScriptBuilder.makeUserScript(for: .documentEnd, settings: settings)
#if DEBUG
            controller.addUserScript(
                WKUserScript(
                    source: Self.debugBridgeScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
#endif
            controller.addUserScript(
                WKUserScript(
                    source: bootstrapAppearanceScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )

            controller.addUserScript(
                WKUserScript(
                    source: appearanceScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )

            if let documentStartScript {
                controller.addUserScript(
                    WKUserScript(
                        source: documentStartScript,
                        injectionTime: .atDocumentStart,
                        forMainFrameOnly: true
                    )
                )
            }

            controller.addUserScript(
                WKUserScript(
                    source: appearanceScript,
                    injectionTime: .atDocumentEnd,
                    forMainFrameOnly: true
                )
            )

            if let documentEndScript {
                controller.addUserScript(
                    WKUserScript(
                        source: documentEndScript,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    )
                )
            }

            lastAppliedSettings = settings
            lastAppliedDarkMode = isDarkMode
            lastAppearanceScript = appearanceScript
            lastDocumentStartScript = documentStartScript
            lastDocumentEndScript = documentEndScript
        }

        func record(settings: FocusSettings, isDarkMode: Bool) {
            lastAppliedSettings = settings
            lastAppliedDarkMode = isDarkMode
        }

        func applyAppearance(on webView: WKWebView, settings: FocusSettings, isDarkMode: Bool) {
            // Update future navigations too. Evaluating only the current page
            // leaves WKUserScripts on the old theme, including video pages that
            // intentionally skip the didFinish feature replay.
            installScripts(on: webView, settings: settings, isDarkMode: isDarkMode)
            let appearanceScript = FocusWebAppearance.script(isDarkMode: isDarkMode)
            webView.evaluateJavaScript(appearanceScript)
        }

        func reapplyCurrentPageScripts(on webView: WKWebView) {
            if let lastAppearanceScript {
                webView.evaluateJavaScript(lastAppearanceScript)
            }
            if let lastDocumentStartScript {
                webView.evaluateJavaScript(lastDocumentStartScript)
            }
            if let lastDocumentEndScript {
                webView.evaluateJavaScript(lastDocumentEndScript)
            }
            installPlayerStateBridge(on: webView)
        }

        func updateDocumentActivity(on webView: WKWebView, isActive: Bool, settings: FocusSettings, isDarkMode: Bool) {
            // A native detail can open and close before SwiftUI delivers its
            // hidden update. Dismissal still suspended JavaScript, so the
            // browser model's suspension revision must participate in resume.
            guard documentActive != isActive
                || (isActive && synchronizedSuspensionRevision != viewModel.documentSuspensionRevision) else { return }
            documentActive = isActive
            synchronizedSuspensionRevision = viewModel.documentSuspensionRevision
            // Future documents inherit visibility too, including a navigation
            // that finishes after this retained web view has been covered.
            installScripts(on: webView, settings: settings, isDarkMode: isDarkMode)
            if isActive {
                // Refresh configuration and bridge revision while the runtime
                // is still suspended; resume performs one rules pass.
                reapplyCurrentPageScripts(on: webView)
            }
            webView.evaluateJavaScript(Self.documentActivityScript(isActive: isActive))
        }

        static func documentActivityScript(isActive: Bool) -> String {
            """
            window.__FOCUS_DOCUMENT_ACTIVE__ = \(isActive ? "true" : "false");
            window.__FOCUS_RUNTIME__?.setDocumentActive?.(window.__FOCUS_DOCUMENT_ACTIVE__);
            window.__FOCUS_NATIVE_PLAYER_BRIDGE__?.setDocumentActive?.(window.__FOCUS_DOCUMENT_ACTIVE__);
            true;
            """
        }

        func installPlayerStateBridge(on webView: WKWebView) {
            guard let context = viewModel.playerBridgeContext(for: webView) else {
                return
            }

            webView.evaluateJavaScript(Self.playerStateBridgeScript(sessionID: context.sessionID, revision: context.revision))
        }

        static func playerStateBridgeScript(sessionID: String, revision: UInt64) -> String {
            """
            (() => {
              const browserSessionID = '\(sessionID)';
              const navigationRevision = \(revision);
              const existing = window.__FOCUS_NATIVE_PLAYER_BRIDGE__;
              if (existing
                && existing.browserSessionID === browserSessionID
                && existing.navigationRevision === navigationRevision) {
                if (window.__FOCUS_DOCUMENT_ACTIVE__ !== false) existing.emit?.();
                return true;
              }

              try {
                existing?.teardown?.();
              } catch (_) {}

              let emitTimer = null;
              let pendingMediaEmit = false;
              let tornDown = false;
              let documentActive = window.__FOCUS_DOCUMENT_ACTIVE__ !== false;
              const previousPlayerStateListener = window.__FOCUS_PLAYER_STATE_LISTENER__;
              const eventNames = [
                'play',
                'pause',
                'playing',
                'ratechange',
                'loadedmetadata',
                'durationchange',
                'volumechange',
                'fullscreenchange',
                'webkitfullscreenchange',
                'webkitbeginfullscreen',
                'webkitendfullscreen',
                'webkitpresentationmodechanged'
              ];

              const fallbackSnapshot = () => {
                const videos = Array.from(document.querySelectorAll('video'));
                const video = window.__FOCUS_ACTIVE_VIDEO__?.isConnected
                  ? window.__FOCUS_ACTIVE_VIDEO__
                  : videos[0] || null;
                const textTracks = video?.textTracks ? Array.from(video.textTracks) : [];
                return {
                  hasPlayer: !!video || !!document.querySelector('#bilibili-player, .bpx-player-container, #playerWrap, .player-container'),
                  pageURL: location.href,
                  pageTitle: document.title || '',
                  videoTitle: '',
                  isPlaying: !!video && !video.paused && !video.ended,
                  playbackRate: Number(video?.playbackRate || 1),
                  isDanmakuHidden: document.documentElement.classList.contains('focus-hide-danmaku'),
                  hasSubtitles: textTracks.length > 0 || !!document.querySelector('[class*="subtitle"]'),
                  isSubtitleHidden: textTracks.length > 0 && textTracks.every((track) => track.mode === 'disabled'),
                  isFullscreen: !!document.fullscreenElement
                    || video?.webkitPresentationMode === 'fullscreen'
                    || video?.webkitDisplayingFullscreen === true
                };
              };

              const emit = (providedSnapshot = null) => {
                if (tornDown) {
                  return;
                }
                if (!providedSnapshot && typeof window.__FOCUS_SNAPSHOT_PLAYER_STATE__ === 'function') {
                  try {
                    window.__FOCUS_SNAPSHOT_PLAYER_STATE__();
                    return;
                  } catch (_) {}
                }
                let snapshot = providedSnapshot || window.__FOCUS_PLAYER_STATE__;
                if (!snapshot || typeof snapshot !== 'object') {
                  snapshot = fallbackSnapshot();
                }
                try {
                  window.webkit.messageHandlers.playerState.postMessage({
                    ...snapshot,
                    browserSessionID,
                    navigationRevision,
                    pageURL: location.href,
                    pageTitle: snapshot.pageTitle || document.title || ''
                  });
                } catch (_) {}
              };

              const scheduleEmit = (delay = 40, isMediaEvent = false) => {
                pendingMediaEmit = pendingMediaEmit || isMediaEvent;
                clearTimeout(emitTimer);
                emitTimer = setTimeout(() => {
                  pendingMediaEmit = false;
                  emit();
                }, delay);
              };
              const eventHandler = (event) => {
                if (event.target instanceof HTMLVideoElement) {
                  window.__FOCUS_ACTIVE_VIDEO__ = event.target;
                }
                scheduleEmit(event.type === 'ratechange' ? 10 : 40, true);
              };
              const clickHandler = (event) => {
                if (!documentActive) return;
                const target = event.target;
                if (!target?.closest?.('.bpx-player-container, #bilibili-player, #playerWrap, [class*="player"]')) {
                  return;
                }
                scheduleEmit(80);
              };

              eventNames.forEach((eventName) => {
                document.addEventListener(eventName, eventHandler, true);
              });
              document.addEventListener('click', clickHandler, true);
              const observer = new MutationObserver(() => scheduleEmit(100));
              const observerOptions = { childList: true, subtree: true };
              if (documentActive) observer.observe(document.documentElement, observerOptions);
              window.__FOCUS_PLAYER_STATE_LISTENER__ = emit;

              const setDocumentActive = (active) => {
                active = !!active;
                if (documentActive === active || tornDown) return;
                documentActive = active;
                clearTimeout(emitTimer);
                observer.disconnect();
                if (active) {
                  observer.observe(document.documentElement, observerOptions);
                  pendingMediaEmit = false;
                  emit();
                } else if (pendingMediaEmit) {
                  // A final pause/PiP transition may precede hiding by only a
                  // few milliseconds. Flush that state, not queued DOM work.
                  pendingMediaEmit = false;
                  emit();
                }
              };

              const teardown = () => {
                if (tornDown) {
                  return;
                }
                tornDown = true;
                clearTimeout(emitTimer);
                observer.disconnect();
                eventNames.forEach((eventName) => {
                  document.removeEventListener(eventName, eventHandler, true);
                });
                document.removeEventListener('click', clickHandler, true);
                if (window.__FOCUS_PLAYER_STATE_LISTENER__ === emit) {
                  window.__FOCUS_PLAYER_STATE_LISTENER__ = previousPlayerStateListener;
                }
              };

              window.__FOCUS_NATIVE_PLAYER_BRIDGE__ = {
                browserSessionID,
                navigationRevision,
                handlesMediaEvents: true,
                emit,
                setDocumentActive,
                teardown
              };
              if (documentActive) scheduleEmit(0);
              return true;
            })();
            """
        }

        private func shouldSkipFinishScriptReplay(for url: URL?) -> Bool {
            guard let url else {
                return false
            }

            return FocusUserAgent.shouldUseDesktopPlayback(for: url)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "getConfig":
                guard let webView = viewModel.webView else { return }
                let data = try? JSONEncoder().encode(
                    viewModel.settingsStore.settings.effectiveRuntimeSettings
                )
                let configJSON = data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                webView.evaluateJavaScript("window.__FOCUS_CONFIG__ = \(configJSON);")
#if DEBUG
            case "logDebug":
                guard viewModel.settingsStore.settings.debugLoggingEnabledForCurrentBuild else {
                    return
                }
                print("[Focus Debug]", message.body)
#endif
            case "playerState":
                viewModel.handlePlayerStateMessage(message.body, from: message.webView)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard viewModel.isSessionActive else {
                webView.evaluateJavaScript(Self.documentActivityScript(isActive: false))
                return
            }
            if !shouldSkipFinishScriptReplay(for: webView.url) {
                reapplyCurrentPageScripts(on: webView)
            }
            viewModel.updateNavigationState(from: webView)
            installPlayerStateBridge(on: webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            viewModel.beginNavigation(to: webView.url)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            viewModel.commitNavigationState(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            viewModel.handleNavigationFailure(failingURL: webView.url)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            viewModel.handleNavigationFailure(failingURL: webView.url)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            viewModel.handleWebContentProcessTermination(webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.targetFrame?.isMainFrame != false,
                let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            if viewModel.handleFocusActionURL(url) {
                decisionHandler(.cancel)
                return
            }

            if viewModel.shouldRouteVideoNavigationToNative(url, currentURL: webView.url) {
                decisionHandler(.cancel)
                viewModel.openNativeVideo(url)
                return
            }

            if viewModel.shouldOpenNativeUserSpace(url) {
                decisionHandler(.cancel)
                viewModel.openNativeUserSpace(url)
                return
            }

            if let entry = viewModel.entryRedirect(for: url) {
                decisionHandler(.cancel)
                viewModel.requestNativeEntry(entry)
                return
            }

            switch viewModel.navigationDecision(for: url, currentURL: webView.url) {
            case .allow:
                viewModel.logNavigationDecision(
                    url: url,
                    currentURL: webView.url,
                    navigationType: navigationAction.navigationType,
                    decision: "allow"
                )
                viewModel.noteUpcomingNavigation(
                    to: url,
                    from: webView.url,
                    navigationType: navigationAction.navigationType
                )
                installPlayerStateBridge(on: webView)
                let desiredDesktopMode = FocusUserAgent.shouldUseDesktopMode(for: url)
                if desiredDesktopMode != lastPreparedUsesDesktopMode {
                    decisionHandler(.cancel)
                    prepare(webView: webView, for: url)
                    webView.load(URLRequest(url: url))
                    return
                }

                decisionHandler(.allow)
            case .cancel:
                viewModel.logNavigationDecision(
                    url: url,
                    currentURL: webView.url,
                    navigationType: navigationAction.navigationType,
                    decision: "cancel"
                )
                decisionHandler(.cancel)
            case let .redirect(target):
                if target == url {
                    viewModel.logNavigationDecision(
                        url: url,
                        currentURL: webView.url,
                        navigationType: navigationAction.navigationType,
                        decision: "allow-same-as-target"
                    )
                    decisionHandler(.allow)
                    return
                }

                viewModel.logNavigationDecision(
                    url: url,
                    currentURL: webView.url,
                    navigationType: navigationAction.navigationType,
                    decision: "redirect:\(target.absoluteString)"
                )
                viewModel.noteUpcomingNavigation(
                    to: target,
                    from: webView.url,
                    navigationType: navigationAction.navigationType
                )
                decisionHandler(.cancel)
                prepare(webView: webView, for: target)
                webView.load(URLRequest(url: target))
            }
        }
    }
}
#endif
