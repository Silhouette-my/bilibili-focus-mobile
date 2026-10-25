#if canImport(UIKit)
@testable import BilibiliFocus
import WebKit
import XCTest

@MainActor
final class FocusWebAppearancePersistenceTests: XCTestCase {
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
#endif
