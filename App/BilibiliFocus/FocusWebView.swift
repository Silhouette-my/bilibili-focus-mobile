#if canImport(UIKit)
import FocusCore
import SwiftUI
import UIKit
import WebKit

struct FocusWebView: UIViewRepresentable {
    @ObservedObject var viewModel: FocusBrowserViewModel
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
        configuration.websiteDataStore = .default()
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
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
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
        webView.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
        webView.backgroundColor = isDarkMode ? UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1) : UIColor(red: 0.965, green: 0.969, blue: 0.98, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        if context.coordinator.lastAppliedSettings != settingsStore.settings
            || context.coordinator.lastAppliedDarkMode != isDarkMode
        {
            context.coordinator.installScripts(
                on: webView,
                settings: settingsStore.settings,
                isDarkMode: isDarkMode
            )
            if viewModel.isSessionActive {
                context.coordinator.reapplyCurrentPageScripts(on: webView)
            }
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

        init(viewModel: FocusBrowserViewModel) {
            self.viewModel = viewModel
        }

        func tearDown(webView: WKWebView) {
            let controller = webView.configuration.userContentController
            controller.removeScriptMessageHandler(forName: "getConfig")
            controller.removeScriptMessageHandler(forName: "logDebug")
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
            controller.removeScriptMessageHandler(forName: "logDebug")
            controller.add(self, name: "getConfig")
            controller.add(self, name: "logDebug")

            let bootstrapAppearanceScript = FocusWebAppearance.bootstrapCSS(isDarkMode: isDarkMode)
            let appearanceScript = FocusWebAppearance.script(isDarkMode: isDarkMode)
            let documentStartScript = try? FocusScriptBuilder.makeUserScript(for: .documentStart, settings: settings)
            let documentEndScript = try? FocusScriptBuilder.makeUserScript(for: .documentEnd, settings: settings)
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
                let data = try? JSONEncoder().encode(viewModel.settingsStore.settings)
                let configJSON = data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                webView.evaluateJavaScript("window.__FOCUS_CONFIG__ = \(configJSON);")
            case "logDebug":
                print("[Focus Debug]", message.body)
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if !shouldSkipFinishScriptReplay(for: webView.url) {
                reapplyCurrentPageScripts(on: webView)
            }
            viewModel.updateNavigationState(from: webView)
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
