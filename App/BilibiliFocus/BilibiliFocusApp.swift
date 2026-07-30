#if canImport(UIKit)
import FocusCore
import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = FocusHistoryBackgroundScheduler.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        FocusHistoryBackgroundScheduler.shared.schedule()
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct BilibiliFocusApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsStore = FocusSettingsStore()
    let appGraph: FocusAppGraph

    init() {
        let settingsStore = FocusSettingsStore()
        _settingsStore = StateObject(wrappedValue: settingsStore)
        let appGraph = FocusAppGraph(settingsStore: settingsStore)
        self.appGraph = appGraph
        FocusHistoryBackgroundScheduler.shared.configure(
            hasWork: {
                await appGraph.hasAuthenticatedPendingPlaybackHistory()
            },
            drain: {
                await appGraph.drainPlaybackHistoryOutbox()
            }
        )
        configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            let accentColor = FocusAccentColor.color(hex: settingsStore.settings.accentColorHex)
            FocusBrowserView(appGraph: appGraph)
                .accentColor(accentColor)
                .tint(accentColor)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch settingsStore.settings.themeMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.18)
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.12)
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = appearance
        }
    }
}
#endif
