import FocusCore
import Foundation
import WebKit

@main
@MainActor
struct FocusVerifier {
    static func main() async {
        do {
            try verifySettingsRoundTrip()
            try verifyRouterRules()
            try verifyNavigationPolicy()
            try verifySearchQuery()
            try verifyDynamicCardDecoding()
            try await verifyFixture(
                name: "dynamic",
                url: URL(string: "https://t.bilibili.com/")!,
                html: dynamicHTML,
                checks: [
                    ("dynamic sidebar hidden", "getComputedStyle(document.querySelector('.bili-dyn-sidebar')).display", "none"),
                    ("dynamic overflow hidden", "getComputedStyle(document.documentElement).overflowX", "hidden"),
                ]
            )
            try await verifyFixture(
                name: "search",
                url: URL(string: "https://search.bilibili.com/all")!,
                html: searchHTML,
                checks: [
                    ("search recommendation hidden", "getComputedStyle(document.querySelector('.search-recommend')).display", "none"),
                    ("search result preserved", "document.querySelector('.search-list').textContent.includes('Core Search Results') ? 'true' : 'false'", "true"),
                    ("search video href canonicalized", "document.querySelector('.video-link').href", "https://www.bilibili.com/video/BV1xx411c7mD/"),
                ]
            )
            try await verifyFixture(
                name: "video",
                url: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD/")!,
                html: videoHTML,
                checks: [
                    ("video title hidden", "getComputedStyle(document.querySelector('#viewbox_report')).display", "none"),
                    ("video player preserved", "document.querySelector('.player-container').textContent.trim()", "Core Player"),
                    (
                        "video toolbar reduced",
                        """
                        Array.from(document.querySelectorAll('#arc_toolbar_report .video-toolbar-left > *'))
                          .filter((node) => getComputedStyle(node).display !== 'none')
                          .map((node) => node.textContent.trim())
                          .join('|')
                        """,
                        "Like|Coin|Favorite|Share"
                    ),
                    ("video coin visible", "getComputedStyle(document.querySelector('.toolbar-left-item-wrap')).display", "block"),
                    ("video parts preserved", "Array.from(document.querySelectorAll('.video-pod__item')).map((node) => node.textContent.trim()).join('|')", "P1|P2"),
                    ("video recommendation hidden", "getComputedStyle(document.querySelector('.rec-list')).display", "none"),
                    ("video no horizontal overflow", "(document.documentElement.scrollWidth <= document.documentElement.clientWidth) ? 'true' : 'false'", "true"),
                ]
            )
            print("FocusVerifier passed")
        } catch {
            fputs("FocusVerifier failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func verifySettingsRoundTrip() throws {
        let suiteName = "FocusVerifier.settings"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = FocusSettings(
            redirectEnabled: false,
            playerMaskEnabled: false,
            searchMaskEnabled: true,
            dynamicMaskEnabled: false,
            debugMode: true,
            defaultEntry: .search
        )

        settings.save(to: defaults)
        let loaded = FocusSettings.load(from: defaults)
        guard loaded == settings else {
            throw VerificationError("settings round-trip mismatch")
        }
        print("pass: settings round-trip")
    }

    private static func verifyRouterRules() throws {
        let router = FocusRouter(
            settings: FocusSettings(
                redirectEnabled: true,
                defaultEntry: .search
            )
        )

        guard router.redirectTarget(for: URL(string: "https://www.bilibili.com/")!) == .search else {
            throw VerificationError("homepage redirect mismatch")
        }

        guard router.redirectTarget(for: URL(string: "https://t.bilibili.com/")!) == nil else {
            throw VerificationError("non-homepage should not redirect")
        }

        print("pass: router rules")
    }

    private static func verifyNavigationPolicy() throws {
        let policy = FocusNavigationPolicy(settings: .defaults)

        guard policy.decision(for: URL(string: "bilibili://video/123")!) == .cancel else {
            throw VerificationError("custom scheme should be blocked")
        }

        guard
            policy.decision(for: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!)
            == .allow
        else {
            throw VerificationError("desktop video URL should stay on desktop playback page")
        }

        guard
            policy.decision(for: URL(string: "https://m.bilibili.com/video/BV1xx411c7mD")!)
            == .redirect(URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!)
        else {
            throw VerificationError("mobile video URL should canonicalize to desktop playback page")
        }

        guard
            policy.decision(
                for: URL(string: "https://app.bilibili.com/download")!,
                currentURL: URL(string: "https://www.bilibili.com/video/BV1xx411c7mD")!
            ) == .cancel
        else {
            throw VerificationError("download page should be blocked from video flow")
        }

        print("pass: navigation policy")
    }

    private static func verifySearchQuery() throws {
        let query = SearchQuery(keyword: "  测试搜索  ")
        guard query.keyword == "测试搜索" else {
            throw VerificationError("search query should trim keyword")
        }

        guard query.resultURL.absoluteString == "https://search.bilibili.com/all?keyword=%E6%B5%8B%E8%AF%95%E6%90%9C%E7%B4%A2" else {
            throw VerificationError("search query should build desktop result URL")
        }

        print("pass: search query")
    }

    private static func verifyDynamicCardDecoding() throws {
        let cards = try DynamicFeedService.decodeCards(from: Data(dynamicPayload.utf8))
        guard cards.count == 2 else {
            throw VerificationError("dynamic card decode count mismatch")
        }

        guard cards[0].kind == .video, cards[0].videoURL?.host == "www.bilibili.com" else {
            throw VerificationError("video dynamic should canonicalize to desktop playback URL")
        }

        guard cards[1].kind == .image, cards[1].targetURL.absoluteString == "https://t.bilibili.com/456" else {
            throw VerificationError("image dynamic should fall back to dynamic detail URL")
        }

        print("pass: dynamic card decoding")
    }

    private static func verifyFixture(
        name: String,
        url: URL,
        html: String,
        checks: [(String, String, String)]
    ) async throws {
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

        for (label, script, expectedValue) in checks {
            let value = try await evaluate(script, in: webView)
            guard value == expectedValue else {
                throw VerificationError("\(name) check failed: \(label) expected \(expectedValue) got \(value)")
            }
        }

        print("pass: \(name) fixture")
    }

    private static func evaluate(_ script: String, in webView: WKWebView) async throws -> String {
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

private struct VerificationError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private let dynamicHTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Dynamic Fixture</title>
  </head>
  <body>
    <div id="app">
      <header id="bili-header-container">
        <div class="bili-header">
          <div class="bili-header__bar">
            <div class="left-entry">Left Entry</div>
            <div class="center-search-container"><input value="search" /></div>
            <div class="right-entry">Right Entry</div>
          </div>
        </div>
        <div class="bili-header__channel">Channel</div>
      </header>
      <div class="bili-layout bili-dyn-home--member">
        <aside class="left">Left Sidebar</aside>
        <main class="bili-dyn-content">
          <section class="bili-dyn-item">Core Dynamic Content</section>
        </main>
        <aside class="right bili-dyn-sidebar">Right Sidebar</aside>
      </div>
    </div>
  </body>
</html>
"""

private let searchHTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Search Fixture</title>
  </head>
  <body>
    <div class="search-list">
      Core Search Results
      <a class="video-link" href="https://m.bilibili.com/video/BV1xx411c7mD">Video Result</a>
    </div>
    <div class="search-recommend">Recommendation</div>
    <div class="m-bottom-app-download">Download App</div>
    <div class="m-nav-bottom">Bottom Navigation</div>
  </body>
</html>
"""

private let videoHTML = """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Video Fixture</title>
  </head>
  <body>
    <div id="app">
      <header id="biliMainHeader">
        <div class="download-entry download-client-trigger">Download</div>
      </header>
      <main style="width: 1280px;">
        <div id="mirror-vdcon" class="video-container-v1" style="display: flex; min-width: 1280px;">
          <section class="left-container scroll-sticky" style="width: 920px;">
            <div id="viewbox_report" class="video-info-container mac">Video Title</div>
            <div id="playerWrap" class="player-wrap">
              <div id="bilibili-player">
                <div class="player-container">Core Player</div>
              </div>
              <div class="bpx-player-sending-area">Danmaku Input</div>
            </div>
            <div id="arc_toolbar_report" class="video-toolbar-container">
              <div class="video-toolbar-left">
                <div class="video-like-info">Like</div>
                <div class="toolbar-left-item-wrap">
                  <div class="video-coin">Coin</div>
                </div>
                <div class="video-fav">Favorite</div>
                <div class="video-share-wrap">Share</div>
              </div>
              <div class="video-toolbar-right">Complaint</div>
            </div>
            <div id="v_desc" class="video-desc-container">Description</div>
            <div class="video-tag-container">Tags</div>
            <div class="left-banner">Banner</div>
            <div id="commentapp">Comments</div>
          </section>
          <aside class="right-container" style="width: 360px;">
            <div class="panel-shell">
              <div class="video-pod video-pod">
                <div class="video-pod__header">Parts</div>
                <div class="video-pod__body">
                  <div class="video-pod__slide">
                    <div class="video-pod__list multip list">
                      <div class="video-pod__item">P1</div>
                      <div class="video-pod__item">P2</div>
                    </div>
                  </div>
                </div>
              </div>
              <div class="rec-list">Recommendations</div>
            </div>
          </aside>
        </div>
        <div class="m-video-related">Related Cards</div>
        <button class="launch-app-btn">Open App</button>
      </main>
    </div>
  </body>
</html>
"""

private let dynamicPayload = """
{
  "code": 0,
  "message": "0",
  "data": {
    "items": [
      {
        "id_str": "123",
        "type": "DYNAMIC_TYPE_AV",
        "basic": {
          "comment_id_str": "123",
          "jump_url": "//www.bilibili.com/video/BV1xx411c7mD"
        },
        "modules": {
          "module_author": {
            "name": "Tech UP",
            "face": "https://i0.hdslb.com/bfs/face/video.jpg",
            "pub_time": "5分钟前"
          },
          "module_dynamic": {
            "desc": {
              "text": "视频动态正文"
            },
            "major": {
              "type": "MAJOR_TYPE_ARCHIVE",
              "archive": {
                "title": "视频标题",
                "cover": "https://i0.hdslb.com/bfs/archive/cover.jpg",
                "jump_url": "https://www.bilibili.com/video/BV1xx411c7mD"
              }
            }
          }
        }
      },
      {
        "id_str": "456",
        "type": "DYNAMIC_TYPE_DRAW",
        "basic": {
          "comment_id_str": "456"
        },
        "modules": {
          "module_author": {
            "name": "Drawer",
            "face": "//i0.hdslb.com/bfs/face/draw.jpg",
            "pub_time": "昨天"
          },
          "module_dynamic": {
            "desc": {
              "text": "图文动态正文"
            },
            "major": {
              "type": "MAJOR_TYPE_OPUS",
              "opus": {
                "summary": {
                  "text": "图文动态正文"
                },
                "pics": [
                  {
                    "url": "https://i0.hdslb.com/bfs/new_dyn/pic1.jpg"
                  }
                ]
              }
            }
          }
        }
      }
    ]
  }
}
"""
