#if canImport(UIKit)
import FocusCore
import Foundation

enum FocusPlaybackHistorySubmissionEligibility {
    private static let endpoint = BiliAPIContractCatalog.require(
        "video.operate.report_history"
    ).url

    static func authenticatedAccountScope(
        cookies: [HTTPCookie]
    ) -> FocusPlaybackAccountScope? {
        let matchingCookies = CookieRequestPolicy.cookies(
            cookies,
            matching: endpoint
        )
        let hasSession = matchingCookies.contains {
            $0.name.caseInsensitiveCompare("SESSDATA") == .orderedSame
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasCSRF = matchingCookies.contains {
            $0.name.caseInsensitiveCompare("bili_jct") == .orderedSame
                && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard hasSession, hasCSRF else {
            return nil
        }

        let accountScope = FocusPlaybackAccountScope.resolve(cookies: matchingCookies)
        return accountScope == .anonymous ? nil : accountScope
    }
}

/// The app's composition root. Long-lived services and their account-aware
/// cookie providers are created exactly once here and shared by every feature.
@MainActor
final class FocusAppGraph {
    let settingsStore: FocusSettingsStore
    let browserViewModel: FocusBrowserViewModel
    let cookieProvider: WebViewCookieSnapshotProvider
    let videoCookieProvider: WebViewCookieSnapshotProvider
    let nativePageAugmentService: FocusNativePageAugmentService
    let dynamicFeedViewModel: FocusDynamicFeedViewModel
    let searchResultsViewModel: FocusSearchResultsViewModel
    let myViewModel: FocusMyViewModel
    let historyViewModel: FocusHistoryViewModel
    let favoriteFolderViewModel: FocusFavoriteFolderViewModel
    let userSpaceService: FocusUserSpaceService
    let userCollectionService: FocusUserSpaceService
    let articleService: FocusArticleService
    let opusDetailService: FocusOpusDetailService
    let videoDetailService: FocusVideoDetailService
    let videoActionService: FocusVideoActionService
    let videoSubtitleService: FocusVideoSubtitleService
    let videoCommentService: FocusVideoCommentService
    let loginHealthService: LoginHealthService
    let playbackProgressStore: FocusPlaybackProgressStore
    let playbackProgressWriteCoordinator: FocusPlaybackProgressWriteCoordinator

    init(
        settingsStore: FocusSettingsStore,
        playbackProgressStore: FocusPlaybackProgressStore = .shared
    ) {
        let browserViewModel = FocusBrowserViewModel(settingsStore: settingsStore)
        let cookieProvider = WebViewCookieSnapshotProvider()
        let videoCookieProvider = WebViewCookieSnapshotProvider(performsLoginWarmup: false)
        let nativePageAugmentService = FocusNativePageAugmentService(
            cookieProvider: cookieProvider
        )
        let myDataService = FocusMyDataService(cookieProvider: cookieProvider)
        let watchLaterService = FocusWatchLaterService(cookieProvider: cookieProvider)

        self.settingsStore = settingsStore
        self.browserViewModel = browserViewModel
        self.cookieProvider = cookieProvider
        self.videoCookieProvider = videoCookieProvider
        self.nativePageAugmentService = nativePageAugmentService
        self.dynamicFeedViewModel = FocusDynamicFeedViewModel(
            service: DynamicFeedService(cookieProvider: cookieProvider)
        )
        self.searchResultsViewModel = FocusSearchResultsViewModel(
            service: SearchResultService(cookieProvider: cookieProvider)
        )
        self.myViewModel = FocusMyViewModel(
            service: myDataService,
            watchLaterService: watchLaterService
        )
        self.historyViewModel = FocusHistoryViewModel(service: myDataService)
        self.favoriteFolderViewModel = FocusFavoriteFolderViewModel(service: myDataService)
        self.userSpaceService = FocusUserSpaceService(cookieProvider: cookieProvider)
        self.userCollectionService = FocusUserSpaceService(cookieProvider: cookieProvider)
        self.articleService = FocusArticleService(cookieProvider: cookieProvider)
        self.opusDetailService = FocusOpusDetailService(cookieProvider: cookieProvider)
        self.videoDetailService = FocusVideoDetailService(cookieProvider: videoCookieProvider)
        self.videoActionService = FocusVideoActionService(cookieProvider: videoCookieProvider)
        self.videoSubtitleService = FocusVideoSubtitleService(cookieProvider: videoCookieProvider)
        self.videoCommentService = FocusVideoCommentService(cookieProvider: videoCookieProvider)
        self.loginHealthService = LoginHealthService(cookieProvider: cookieProvider)
        self.playbackProgressStore = playbackProgressStore
        self.playbackProgressWriteCoordinator = FocusPlaybackProgressWriteCoordinator()

        browserViewModel.nativePageAugmentService = nativePageAugmentService
    }

    func makeAppViewModel() -> FocusAppViewModel {
        FocusAppViewModel(appGraph: self)
    }

    func hasAuthenticatedPendingPlaybackHistory() async -> Bool {
        guard let accountScope = await authenticatedPlaybackHistoryAccountScope() else {
            return false
        }
        let pendingReports = await playbackProgressStore.pendingHistoryReports(
            accountScope: accountScope
        )
        return !pendingReports.isEmpty
    }

    /// Drains only the currently authenticated account's durable outbox.
    /// Signed-out state is deliberately left untouched until that account
    /// becomes active again.
    func drainPlaybackHistoryOutbox() async -> FocusHistoryOutboxDrainOutcome {
        guard let accountScope = await authenticatedPlaybackHistoryAccountScope() else {
            return .noWork
        }
        let pendingReports = await playbackProgressStore.pendingHistoryReports(
            accountScope: accountScope
        )
        guard !pendingReports.isEmpty else {
            return .noWork
        }

        return await playbackProgressStore.drainPendingHistory(
            accountScope: accountScope
        ) { [videoActionService] report in
            await videoActionService.attemptWatchHistory(report)
        }
    }

    private func authenticatedPlaybackHistoryAccountScope() async
        -> FocusPlaybackAccountScope?
    {
        FocusPlaybackHistorySubmissionEligibility.authenticatedAccountScope(
            cookies: await videoCookieProvider.loadCookies()
        )
    }
}
#endif
