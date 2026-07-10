#if canImport(WebKit)
import FocusCore
import Foundation
import Testing
import WebKit

@MainActor
struct FocusDOMIntegrationTests {
    @Test
    func dynamicFixtureAppliesPruneAndRepairRules() async throws {
        let webView = try await loadFixture(named: "dynamic", url: URL(string: "https://t.bilibili.com/")!)

        let sidebarDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.bili-dyn-sidebar')).display",
            in: webView
        )
        let overflowX = try await evaluate(
            "getComputedStyle(document.documentElement).overflowX",
            in: webView
        )
        let mainWidth = try await evaluate(
            "getComputedStyle(document.querySelector('main')).width",
            in: webView
        )

        #expect(sidebarDisplay == "none")
        #expect(overflowX == "hidden")
        #expect(!mainWidth.isEmpty)
    }

    @Test
    func searchFixtureHidesRecommendationsButKeepsResults() async throws {
        let webView = try await loadFixture(named: "search", url: URL(string: "https://search.bilibili.com/all")!)

        let recommendationDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.search-recommend')).display",
            in: webView
        )
        let resultText = try await evaluate(
            "document.querySelector('.search-list').textContent.trim()",
            in: webView
        )
        let rewrittenHref = try await evaluate(
            "document.querySelector('.video-link').href",
            in: webView
        )
        let videoGridDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.video-list')).display",
            in: webView
        )
        let videoGridColumns = try await evaluate(
            "getComputedStyle(document.querySelector('.video-list')).gridTemplateColumns",
            in: webView
        )
        let markedVideoCards = try await evaluate(
            "document.querySelectorAll('[data-focus-search-video-card=\"true\"]').length",
            in: webView
        )
        let contentRootTag = try await evaluate(
            "document.querySelector('[data-focus-search-video-content-root=\"true\"]').tagName",
            in: webView
        )
        let coverClassName = try await evaluate(
            "document.querySelector('[data-focus-search-video-cover=\"true\"]').className",
            in: webView
        )
        let titleText = try await evaluate(
            "document.querySelector('[data-focus-search-video-title=\"true\"]').textContent.trim()",
            in: webView
        )
        #expect(recommendationDisplay == "none")
        #expect(resultText.contains("Core Search Results"))
        #expect(rewrittenHref == "https://www.bilibili.com/video/BV1xx411c7mD/")
        #expect(videoGridDisplay == "grid")
        #expect(videoGridColumns.contains(" "))
        #expect(markedVideoCards == "2")
        #expect(contentRootTag == "A")
        #expect(coverClassName.contains("video-cover"))
        #expect(titleText == "Video Result One")
    }

    @Test
    func searchRichFixtureBuildsProfileStripAndLiveGrid() async throws {
        let webView = try await loadFixture(named: "search-rich", url: URL(string: "https://search.bilibili.com/all")!)

        let inputShellExists = try await evaluate(
            "document.querySelector('[data-focus-search-input-shell=\"true\"]') ? 'true' : 'false'",
            in: webView
        )
        let filterShellExists = try await evaluate(
            "document.querySelector('[data-focus-search-filter-shell=\"true\"]') ? 'true' : 'false'",
            in: webView
        )
        let upCardCount = try await evaluate(
            "document.querySelectorAll('[data-focus-search-up-card=\"true\"]').length",
            in: webView
        )
        let upVideoCount = try await evaluate(
            "document.querySelectorAll('[data-focus-search-up-video=\"true\"]').length",
            in: webView
        )
        let liveGridDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.live-list')).display",
            in: webView
        )
        let reserveButtonDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.reserve-btn')).display",
            in: webView
        )

        #expect(inputShellExists == "true")
        #expect(filterShellExists == "true")
        #expect(upCardCount == "1")
        #expect(upVideoCount == "2")
        #expect(liveGridDisplay == "grid")
        #expect(reserveButtonDisplay == "none")
    }

    @Test
    func videoFixtureReflowsDesktopPlaybackPage() async throws {
        let webView = try await loadFixture(named: "video", url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)

        let titleDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('#viewbox_report')).display",
            in: webView
        )
        let playerText = try await evaluate(
            "document.querySelector('.player-container').textContent.trim()",
            in: webView
        )
        let toolbarItems = try await evaluate(
            """
            Array.from(document.querySelectorAll('#arc_toolbar_report .video-toolbar-left > *'))
              .filter((node) => getComputedStyle(node).display !== 'none')
              .map((node) => node.textContent.trim())
              .join('|')
            """,
            in: webView
        )
        let coinDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.toolbar-left-item-wrap')).display",
            in: webView
        )
        let partText = try await evaluate(
            "Array.from(document.querySelectorAll('.video-pod__item')).map((node) => node.textContent.trim()).join('|')",
            in: webView
        )
        let recommendationDisplay = try await evaluate(
            "getComputedStyle(document.querySelector('.rec-list')).display",
            in: webView
        )
        let autoplayEnabled = try await evaluate(
            "document.querySelector('.continuous-btn .switch-btn').classList.contains('on') ? 'true' : 'false'",
            in: webView
        )
        let overflowFree = try await evaluate(
            "(document.documentElement.scrollWidth <= document.documentElement.clientWidth) ? 'true' : 'false'",
            in: webView
        )

        #expect(titleDisplay == "none")
        #expect(playerText == "Core Player")
        #expect(toolbarItems == "Like|Coin|Favorite|Share")
        #expect(coinDisplay == "block")
        #expect(partText == "P1|P2")
        #expect(recommendationDisplay == "none")
        #expect(autoplayEnabled == "false")
        #expect(overflowFree == "true")
    }

    @Test
    func playerEventsEmitCompleteSnapshots() async throws {
        let webView = try await loadFixture(named: "video", url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        _ = try await evaluate(
            """
            window.__focusPlayerMessages = [];
            window.__FOCUS_PLAYER_STATE_LISTENER__ = (payload) => {
              window.__focusPlayerMessages.push(payload);
            };
            const video = document.querySelector('video');
            video.playbackRate = 1.5;
            ['loadedmetadata', 'play', 'pause', 'ratechange'].forEach((name) => {
              video.dispatchEvent(new Event(name));
            });
            document.dispatchEvent(new Event('fullscreenchange'));
            'ready';
            """,
            in: webView
        )
        try await Task.sleep(nanoseconds: 220_000_000)

        let payload = try await evaluate(
            "JSON.stringify(window.__focusPlayerMessages.at(-1) || {})",
            in: webView
        )
        #expect(payload.contains("\"hasPlayer\""))
        #expect(payload.contains("\"isPlaying\""))
        #expect(payload.contains("\"playbackRate\":1.5"))
        #expect(payload.contains("\"isDanmakuHidden\""))
        #expect(payload.contains("\"hasSubtitles\""))
        #expect(payload.contains("\"isSubtitleHidden\""))
        #expect(payload.contains("\"isFullscreen\""))
    }

    @Test
    func repeatedVideoRuleMountKeepsSingleStylePerFeature() async throws {
        let webView = try await loadFixture(named: "video", url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        let documentEndScript = try FocusScriptBuilder.makeUserScript(for: .documentEnd, settings: .defaults)
        _ = try await evaluate(documentEndScript, in: webView)
        _ = try await evaluate(documentEndScript, in: webView)

        let counts = try await evaluate(
            """
            (() => {
              const styles = Array.from(document.querySelectorAll('style[id^="bili-focus-style-"]'));
              return `${styles.length}|${new Set(styles.map((style) => style.id)).size}`;
            })();
            """,
            in: webView
        )
        let parts = counts.split(separator: "|")
        #expect(parts.count == 2)
        #expect(parts.first == parts.last)
    }

    @Test
    func rapidVideoSwitchPublishesLatestPageURL() async throws {
        let webView = try await loadFixture(named: "video", url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!)
        _ = try await evaluate(
            """
            window.__focusPlayerMessages = [];
            window.__FOCUS_PLAYER_STATE_LISTENER__ = (payload) => {
              window.__focusPlayerMessages.push(payload);
            };
            history.replaceState({}, '', '/video/BV1FIRST/');
            window.__FOCUS_SNAPSHOT_PLAYER_STATE__?.();
            history.replaceState({}, '', '/video/BV1LATEST/');
            document.querySelector('video')?.dispatchEvent(new Event('loadedmetadata'));
            window.__FOCUS_SNAPSHOT_PLAYER_STATE__?.();
            'switched';
            """,
            in: webView
        )
        try await Task.sleep(nanoseconds: 180_000_000)

        let latestURL = try await evaluate(
            "window.__focusPlayerMessages.at(-1)?.pageURL || ''",
            in: webView
        )
        #expect(latestURL.contains("/video/BV1LATEST/"))
    }

    private func loadFixture(named name: String, url: URL) async throws -> WKWebView {
        let htmlURL = try #require(Bundle.module.url(forResource: name, withExtension: "html"))
        let html = try String(contentsOf: htmlURL, encoding: .utf8)

        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: try FocusScriptBuilder.makeUserScript(for: .documentStart, settings: .defaults),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: try FocusScriptBuilder.makeUserScript(for: .documentEnd, settings: .defaults),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        try await delegate.load {
            webView.loadHTMLString(html, baseURL: url)
        }

        return webView
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: value.map(String.init(describing:)) ?? "")
            }
        }
    }
}

@MainActor
private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ action: () -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            action()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
#endif
