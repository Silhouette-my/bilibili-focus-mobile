#if canImport(UIKit)
import Combine
import FocusCore
import Foundation

@MainActor
final class FocusAppViewModel: ObservableObject {
    enum PrimaryTab {
        case dynamic
        case search
        case my
    }

    struct RouteID: Hashable, Sendable {
        let rawValue: UUID

        init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }
    }

    enum AppRoute {
        case dynamicFeed
        case searchResults(SearchQuery)
        case my
        case history
        case favoriteFolder(FocusMyFolder)
        case userSpace(RouteID, URL)
        case userCollection(RouteID, FocusUserSpaceCollection)
        case article(RouteID, URL)
        case opus(RouteID, URL)
        case video(RouteID, URL)
        case browser(URL, FocusBrowserViewModel.EntryContext)
    }

    private static let loginURL = URL(string: "https://passport.bilibili.com/login")!

    @Published private(set) var routeStack: [AppRoute] = [.dynamicFeed]
    @Published private(set) var hasInstantiatedBrowser = false
    @Published var showSettings = false
    @Published var showSearch = false
    @Published var searchKeyword = ""

    let settingsStore: FocusSettingsStore
    let browserViewModel: FocusBrowserViewModel
    let dynamicFeedViewModel: FocusDynamicFeedViewModel
    let searchResultsViewModel: FocusSearchResultsViewModel
    let myViewModel: FocusMyViewModel
    let historyViewModel: FocusHistoryViewModel
    let favoriteFolderViewModel: FocusFavoriteFolderViewModel
    private let cookieProvider: WebViewCookieSnapshotProvider
    private let videoCookieProvider: WebViewCookieSnapshotProvider
    private let nativePageAugmentService: FocusNativePageAugmentService
    private let userSpaceService: FocusUserSpaceService
    private let userCollectionService: FocusUserSpaceService
    private let articleService: FocusArticleService
    private let opusDetailService: FocusOpusDetailService
    private let videoDetailService: FocusVideoDetailService
    private let videoActionService: FocusVideoActionService
    private let videoSubtitleService: FocusVideoSubtitleService
    private let videoCommentService: FocusVideoCommentService
    private let playbackProgressStore: FocusPlaybackProgressStore
    private let playbackProgressWriteCoordinator: FocusPlaybackProgressWriteCoordinator
    private let appGraph: FocusAppGraph
    private var userSpaceViewModels: [RouteID: FocusUserSpaceViewModel] = [:]
    private var userCollectionViewModels: [RouteID: FocusUserCollectionViewModel] = [:]
    private var articleViewModels: [RouteID: FocusArticleViewModel] = [:]
    private var opusDetailViewModels: [RouteID: FocusOpusDetailViewModel] = [:]
    private var videoViewModels: [RouteID: FocusNativeVideoViewModel] = [:]

    private var didHandleLaunchEntry = false
    private var didRefreshOnBecomeActive = false
    private var activeRouteCancellables: Set<AnyCancellable> = []

    var route: AppRoute {
        routeStack.last ?? .dynamicFeed
    }

    init(appGraph: FocusAppGraph) {
        self.appGraph = appGraph
        self.settingsStore = appGraph.settingsStore
        self.browserViewModel = appGraph.browserViewModel
        self.cookieProvider = appGraph.cookieProvider
        self.videoCookieProvider = appGraph.videoCookieProvider
        self.nativePageAugmentService = appGraph.nativePageAugmentService
        self.dynamicFeedViewModel = appGraph.dynamicFeedViewModel
        self.searchResultsViewModel = appGraph.searchResultsViewModel
        self.myViewModel = appGraph.myViewModel
        self.historyViewModel = appGraph.historyViewModel
        self.favoriteFolderViewModel = appGraph.favoriteFolderViewModel
        self.userSpaceService = appGraph.userSpaceService
        self.userCollectionService = appGraph.userCollectionService
        self.articleService = appGraph.articleService
        self.opusDetailService = appGraph.opusDetailService
        self.videoDetailService = appGraph.videoDetailService
        self.videoActionService = appGraph.videoActionService
        self.videoSubtitleService = appGraph.videoSubtitleService
        self.videoCommentService = appGraph.videoCommentService
        self.playbackProgressStore = appGraph.playbackProgressStore
        self.playbackProgressWriteCoordinator = appGraph.playbackProgressWriteCoordinator

        Task { [appGraph] in
            _ = await appGraph.drainPlaybackHistoryOutbox()
        }

        browserViewModel.onEntryRequest = { [weak self] entry in
            Task { @MainActor [weak self] in
                self?.open(entry)
            }
        }

        browserViewModel.onUserSpaceRequest = { [weak self] url in
            Task { @MainActor [weak self] in
                self?.openNativeUserSpace(url)
            }
        }

        browserViewModel.onVideoRequest = { [weak self] url in
            Task { @MainActor [weak self] in
                self?.openNativeVideo(url)
            }
        }

        observeActiveRoute()
    }

    convenience init(settingsStore: FocusSettingsStore) {
        self.init(appGraph: FocusAppGraph(settingsStore: settingsStore))
    }

    func userSpaceViewModel(for routeID: RouteID) -> FocusUserSpaceViewModel {
        if let viewModel = userSpaceViewModels[routeID] {
            return viewModel
        }
        let viewModel = FocusUserSpaceViewModel(service: userSpaceService)
        userSpaceViewModels[routeID] = viewModel
        return viewModel
    }

    func userCollectionViewModel(for routeID: RouteID) -> FocusUserCollectionViewModel {
        if let viewModel = userCollectionViewModels[routeID] {
            return viewModel
        }
        let viewModel = FocusUserCollectionViewModel(service: userCollectionService)
        userCollectionViewModels[routeID] = viewModel
        return viewModel
    }

    func articleViewModel(for routeID: RouteID) -> FocusArticleViewModel {
        if let viewModel = articleViewModels[routeID] {
            return viewModel
        }
        let viewModel = FocusArticleViewModel(service: articleService)
        articleViewModels[routeID] = viewModel
        return viewModel
    }

    func opusDetailViewModel(for routeID: RouteID) -> FocusOpusDetailViewModel {
        if let viewModel = opusDetailViewModels[routeID] {
            return viewModel
        }
        let viewModel = FocusOpusDetailViewModel(
            detailService: opusDetailService,
            augmentService: nativePageAugmentService
        )
        opusDetailViewModels[routeID] = viewModel
        return viewModel
    }

    func videoViewModel(for routeID: RouteID) -> FocusNativeVideoViewModel {
        if let viewModel = videoViewModels[routeID] {
            return viewModel
        }
        let viewModel = FocusNativeVideoViewModel(
            detailService: videoDetailService,
            actionService: videoActionService,
            subtitleService: videoSubtitleService,
            commentService: videoCommentService,
            playbackProgressStore: playbackProgressStore,
            playbackProgressWriteCoordinator: playbackProgressWriteCoordinator,
            accountScopeProvider: { [videoCookieProvider = self.videoCookieProvider] in
                FocusPlaybackAccountScope.resolve(
                    cookies: await videoCookieProvider.loadCookies()
                )
            },
            nativeDanmakuEnabled: settingsStore.settings.nativeDanmakuEnabled,
            danmakuPreferenceChange: { [weak settingsStore] enabled in
                settingsStore?.settings.nativeDanmakuEnabled = enabled
            },
            nativeSubtitleEnabled: settingsStore.settings.nativeSubtitleEnabled,
            preferredSubtitleLanguageCode: settingsStore.settings.nativeSubtitleLanguageCode,
            subtitlePreferenceChange: { [weak settingsStore] enabled, languageCode in
                guard let settingsStore else {
                    return
                }
                var settings = settingsStore.settings
                settings.nativeSubtitleEnabled = enabled
                settings.nativeSubtitleLanguageCode = languageCode
                settingsStore.settings = settings
            }
        )
        videoViewModels[routeID] = viewModel
        return viewModel
    }

    private func observeActiveRoute() {
        activeRouteCancellables.removeAll()

        switch route {
        case .dynamicFeed:
            forwardActiveChanges(from: dynamicFeedViewModel)
        case .searchResults:
            forwardActiveChanges(from: searchResultsViewModel)
        case .my:
            forwardActiveChanges(from: myViewModel)
        case .history:
            forwardActiveChanges(from: historyViewModel)
        case .favoriteFolder:
            forwardActiveChanges(from: favoriteFolderViewModel)
        case let .userSpace(routeID, _):
            forwardActiveChanges(from: userSpaceViewModel(for: routeID))
        case let .userCollection(routeID, _):
            forwardActiveChanges(from: userCollectionViewModel(for: routeID))
        case let .article(routeID, _):
            forwardActiveChanges(from: articleViewModel(for: routeID))
        case let .opus(routeID, _):
            forwardActiveChanges(from: opusDetailViewModel(for: routeID))
        case let .video(routeID, _):
            forwardActiveChanges(from: videoViewModel(for: routeID))
        case .browser:
            let presentationChanges: [AnyPublisher<Void, Never>] = [
                browserViewModel.$navigationTitle.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                browserViewModel.$currentURL.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                browserViewModel.$entryContext.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                browserViewModel.$hasActiveVideoRoute.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                browserViewModel.$playerSnapshot.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                browserViewModel.$isLoadingPage.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
                browserViewModel.$webContentFailureMessage.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
            ]
            Publishers.MergeMany(presentationChanges)
                .dropFirst(presentationChanges.count)
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &activeRouteCancellables)
        }
    }

    private func forwardActiveChanges<Object: ObservableObject>(from object: Object)
    where Object.ObjectWillChangePublisher == ObservableObjectPublisher {
        object.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &activeRouteCancellables)
    }

    var navigationTitle: String {
        switch route {
        case .dynamicFeed:
            return "动态"
        case let .searchResults(query):
            return query.keyword.isEmpty ? "搜索" : query.keyword
        case .my:
            return myViewModel.navigationTitle
        case .history:
            return historyViewModel.navigationTitle
        case .favoriteFolder:
            return favoriteFolderViewModel.navigationTitle
        case let .userSpace(routeID, _):
            return userSpaceViewModel(for: routeID).navigationTitle
        case let .userCollection(routeID, _):
            return userCollectionViewModel(for: routeID).navigationTitle
        case let .article(routeID, _):
            return articleViewModel(for: routeID).navigationTitle
        case let .opus(routeID, _):
            return opusDetailViewModel(for: routeID).navigationTitle
        case let .video(routeID, _):
            return videoViewModel(for: routeID).navigationTitle
        case .browser:
            return browserViewModel.navigationTitle
        }
    }

    var activePrimaryTab: PrimaryTab {
        primaryTab(for: routeStack.first ?? .dynamicFeed)
    }

    var isBrowserActive: Bool {
        if case .browser = route {
            return true
        }
        return false
    }

    var hasDynamicFeedRoot: Bool {
        guard let rootRoute = routeStack.first else {
            return false
        }
        if case .dynamicFeed = rootRoute {
            return true
        }
        return false
    }

    var isDynamicFeedActive: Bool {
        if case .dynamicFeed = route {
            return true
        }
        return false
    }

    var activeNativeVideoViewModel: FocusNativeVideoViewModel? {
        guard case let .video(routeID, _) = route else {
            return nil
        }
        return videoViewModel(for: routeID)
    }

    var isNativeVideoActive: Bool {
        activeNativeVideoViewModel != nil
    }

    func applyNativeDanmakuPreference(_ enabled: Bool) {
        videoViewModels.values.forEach { $0.applyDanmakuPreference(enabled) }
    }

    func applyNativeSubtitlePreference(
        enabled: Bool,
        languageCode: String
    ) {
        videoViewModels.values.forEach {
            $0.applySubtitlePreference(
                enabled: enabled,
                languageCode: languageCode
            )
        }
    }

    var showsBrowserBackButton: Bool {
        isBrowserActive
    }

    var showsBackButton: Bool {
        routeStack.count > 1
    }

    private func setRootRoute(_ newRoute: AppRoute) {
        suspend(route)
        routeStack.dropFirst().forEach(cleanUpRoute)
        routeStack = [newRoute]
        observeActiveRoute()
        activate(newRoute)
    }

    private func pushRoute(_ newRoute: AppRoute) {
        snapshotActiveBrowserURL()
        suspend(route)
        routeStack.append(newRoute)
        observeActiveRoute()
        activate(newRoute)
    }

    @discardableResult
    private func popRoute() -> Bool {
        guard routeStack.count > 1, let removedRoute = routeStack.last else {
            return false
        }
        suspend(removedRoute)
        cleanUpRoute(removedRoute)
        routeStack.removeLast()
        observeActiveRoute()
        activate(route)
        return true
    }

    private func snapshotActiveBrowserURL() {
        guard
            case let .browser(_, context) = route,
            let currentURL = browserViewModel.currentURL.map(FocusNavigationPolicy.canonicalWebURL(for:)),
            !routeStack.isEmpty
        else {
            return
        }
        routeStack[routeStack.count - 1] = .browser(currentURL, context)
    }

    private func suspend(_ route: AppRoute) {
        switch route {
        case .dynamicFeed:
            dynamicFeedViewModel.suspend()
        case .searchResults:
            searchResultsViewModel.suspend()
        case .my:
            myViewModel.suspend()
        case .history:
            historyViewModel.suspend()
        case .favoriteFolder:
            favoriteFolderViewModel.suspend()
        case let .userSpace(routeID, _):
            userSpaceViewModels[routeID]?.suspend()
        case let .userCollection(routeID, _):
            userCollectionViewModels[routeID]?.suspend()
        case let .article(routeID, _):
            articleViewModels[routeID]?.suspend()
        case let .opus(routeID, _):
            opusDetailViewModels[routeID]?.suspend()
        case let .video(routeID, _):
            videoViewModels[routeID]?.suspend()
        case .browser:
            browserViewModel.prepareForDismiss()
        }
    }

    private func activate(_ route: AppRoute) {
        switch route {
        case .dynamicFeed:
            dynamicFeedViewModel.loadIfNeeded()
        case .searchResults:
            searchResultsViewModel.loadIfNeeded()
        case .my:
            myViewModel.refreshForAppearance()
        case .history:
            historyViewModel.refreshForAppearance()
        case .favoriteFolder:
            favoriteFolderViewModel.loadIfNeeded()
        case let .userSpace(routeID, url):
            let viewModel = userSpaceViewModel(for: routeID)
            viewModel.open(url)
            viewModel.loadIfNeeded()
        case let .userCollection(routeID, collection):
            let viewModel = userCollectionViewModel(for: routeID)
            viewModel.open(collection)
            viewModel.loadIfNeeded()
        case let .article(routeID, url):
            let viewModel = articleViewModel(for: routeID)
            viewModel.open(url)
            viewModel.loadIfNeeded()
        case let .opus(routeID, url):
            opusDetailViewModel(for: routeID).open(url)
        case let .video(routeID, url):
            videoViewModel(for: routeID).activate(url: url)
        case let .browser(url, context):
            if !browserViewModel.isSessionActive
                || browserViewModel.currentURL.map(FocusNavigationPolicy.canonicalWebURL(for:)) != url
            {
                browserViewModel.open(url, context: context)
            }
        }
    }

    private func cleanUpRoute(_ route: AppRoute) {
        switch route {
        case let .userSpace(routeID, _):
            userSpaceViewModels[routeID] = nil
        case let .userCollection(routeID, _):
            userCollectionViewModels[routeID] = nil
        case let .article(routeID, _):
            articleViewModels[routeID] = nil
        case let .opus(routeID, _):
            opusDetailViewModels[routeID] = nil
        case let .video(routeID, _):
            videoViewModels[routeID] = nil
        default:
            break
        }
    }

    func handleLaunchEntryIfNeeded() {
        guard !didHandleLaunchEntry else {
            return
        }

        didHandleLaunchEntry = true
        hasInstantiatedBrowser = true
        refreshLoginSensitiveContent(reloadDynamicFeed: true)
        if settingsStore.settings.defaultEntry == .search {
            presentSearchEntry()
        }
    }

    func open(_ entry: FocusEntry) {
        switch entry {
        case .dynamic:
            setRootRoute(.dynamicFeed)
        case .search:
            presentSearchEntry()
        }
    }

    func open(card: DynamicCard) {
        let destinationURL = card.videoURL ?? card.targetURL
        if let host = destinationURL.host?.lowercased(), host == "t.bilibili.com" {
            openOpus(destinationURL)
            return
        }
        if Self.isArticleURL(destinationURL) {
            openArticle(destinationURL)
            return
        }
        if Self.isOpusURL(destinationURL) {
            openOpus(destinationURL)
            return
        }
        if Self.isVideoURL(destinationURL) {
            openVideo(destinationURL)
            return
        }
        openBrowser(destinationURL, context: .dynamic)
    }

    func open(searchItem: SearchResultItem) {
        if Self.isUserSpaceURL(searchItem.targetURL) {
            openUserSpace(searchItem.targetURL)
            return
        }
        if Self.isArticleURL(searchItem.targetURL) {
            openArticle(searchItem.targetURL)
            return
        }
        if Self.isOpusURL(searchItem.targetURL) {
            openOpus(searchItem.targetURL)
            return
        }
        openVideo(searchItem.targetURL)
    }

    func open(searchPreview: SearchResultItem.PreviewVideo) {
        openVideo(searchPreview.targetURL)
    }

    func openMyVideo(_ url: URL) {
        openVideo(url)
    }

    func openOpusRelatedURL(_ url: URL) {
        if Self.isUserSpaceURL(url) {
            openUserSpace(url)
            return
        }
        if Self.isArticleURL(url) {
            openArticle(url)
            return
        }
        if Self.isOpusURL(url) {
            openOpus(url)
            return
        }
        openVideo(url)
    }

    func openUserCollection(_ collection: FocusUserSpaceCollection) {
        let routeID = RouteID()
        _ = userCollectionViewModel(for: routeID)
        pushRoute(.userCollection(routeID, collection))
    }

    func submitSearch() {
        let query = SearchQuery(keyword: searchKeyword)
        guard !query.keyword.isEmpty else {
            return
        }

        showSearch = false
        setRootRoute(.searchResults(query))
        searchResultsViewModel.search(query)
        searchKeyword = ""
    }

    func presentSearchEntry() {
        if case let .searchResults(query) = route {
            searchKeyword = query.keyword
        } else {
            searchKeyword = ""
        }
        showSearch = true
    }

    func openMy() {
        setRootRoute(.my)
    }

    func openHistory() {
        pushRoute(.history)
    }

    func openFavoriteFolder(_ folder: FocusMyFolder) {
        favoriteFolderViewModel.open(folder)
        pushRoute(.favoriteFolder(folder))
    }

    func openLogin() {
        openBrowser(Self.loginURL, context: .my)
    }

    func reloadCurrent() {
        switch route {
        case .dynamicFeed:
            dynamicFeedViewModel.reload()
        case .searchResults(_):
            searchResultsViewModel.reload()
        case .my:
            myViewModel.reload()
        case .history:
            historyViewModel.reload()
        case .favoriteFolder:
            favoriteFolderViewModel.reload()
        case let .userSpace(routeID, _):
            userSpaceViewModel(for: routeID).reload()
        case let .userCollection(routeID, _):
            userCollectionViewModel(for: routeID).reload()
        case let .article(routeID, _):
            articleViewModel(for: routeID).reload()
        case let .opus(routeID, _):
            opusDetailViewModel(for: routeID).reload()
        case let .video(routeID, _):
            videoViewModel(for: routeID).reload()
        case .browser:
            browserViewModel.reload()
        }
    }

    func handleAppDidBecomeActive() {
        activeNativeVideoViewModel?.handleAppDidBecomeActive()
        guard didHandleLaunchEntry else {
            return
        }

        guard !didRefreshOnBecomeActive else {
            return
        }

        didRefreshOnBecomeActive = true
        refreshLoginSensitiveContent(reloadDynamicFeed: false)
    }

    func handleAppDidEnterBackground() {
        activeNativeVideoViewModel?.handleAppDidEnterBackground()
    }

    func goBack() {
        handleTopLevelBack()
    }

    func handleBrowserBack() {
        guard isBrowserActive else {
            return
        }

        switch browserViewModel.resolveAppBackAction() {
        case .close:
            closeBrowser()
        case let .navigate(url):
            browserViewModel.navigateAppBack(to: url)
        }
    }

    func handleTopLevelBack() {
        if isBrowserActive {
            handleBrowserBack()
            return
        }
        _ = popRoute()
    }

    func goForward() {
        guard isBrowserActive else {
            return
        }
        browserViewModel.goForward()
    }

    func closeBrowser() {
        _ = popRoute()
    }

    private func openBrowser(_ url: URL, context: FocusBrowserViewModel.EntryContext) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        hasInstantiatedBrowser = true
        if case .browser = route, !routeStack.isEmpty {
            routeStack[routeStack.count - 1] = .browser(canonicalURL, context)
            observeActiveRoute()
            browserViewModel.open(canonicalURL, context: context)
        } else {
            pushRoute(.browser(canonicalURL, context))
        }
    }

    private func openOpus(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        let routeID = RouteID()
        _ = opusDetailViewModel(for: routeID)
        pushRoute(.opus(routeID, canonicalURL))
    }

    private func openUserSpace(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard Self.extractUserSpaceMID(from: canonicalURL) != nil else {
            openBrowser(canonicalURL, context: entryContext(for: activePrimaryTab))
            return
        }

        let routeID = RouteID()
        _ = userSpaceViewModel(for: routeID)
        pushRoute(.userSpace(routeID, canonicalURL))
    }

    private func openArticle(_ url: URL) {
        guard let canonicalURL = FocusArticleRouting.canonicalURL(for: url) else {
            openBrowser(FocusNavigationPolicy.canonicalWebURL(for: url), context: entryContext(for: activePrimaryTab))
            return
        }

        let routeID = RouteID()
        _ = articleViewModel(for: routeID)
        pushRoute(.article(routeID, canonicalURL))
    }

    private func openVideo(_ url: URL) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard FocusVideoIdentifier.extract(from: canonicalURL) != nil else {
            openBrowser(canonicalURL, context: entryContext(for: activePrimaryTab))
            return
        }

        let routeID = RouteID()
        _ = videoViewModel(for: routeID)
        pushRoute(.video(routeID, canonicalURL))
    }

    func openVideoInBrowser(_ url: URL) {
        browserViewModel.allowNextVideoNavigationInWeb(for: url)
        openBrowser(url, context: entryContext(for: activePrimaryTab))
    }

    func openArticleInBrowser(_ url: URL) {
        openBrowser(FocusArticleRouting.canonicalURL(for: url) ?? url, context: entryContext(for: activePrimaryTab))
    }

    private func refreshLoginSensitiveContent(reloadDynamicFeed: Bool) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            _ = await cookieProvider.refreshSnapshotIfNeeded()
            switch route {
            case .dynamicFeed:
                if reloadDynamicFeed {
                    dynamicFeedViewModel.reload()
                }
            case .searchResults(_):
                searchResultsViewModel.reload()
            case .my:
                myViewModel.reload()
            case .history:
                historyViewModel.reload()
            case .favoriteFolder:
                favoriteFolderViewModel.reload()
            case let .userSpace(routeID, _):
                userSpaceViewModel(for: routeID).reload()
            case let .userCollection(routeID, _):
                userCollectionViewModel(for: routeID).reload()
            case let .article(routeID, _):
                articleViewModel(for: routeID).reload()
            case .opus:
                break
            case .video:
                break
            case .browser:
                break
            }
        }
    }

    private func primaryTab(for route: AppRoute) -> PrimaryTab {
        switch route {
        case .dynamicFeed, .opus:
            return .dynamic
        case .searchResults:
            return .search
        case .my, .history, .favoriteFolder:
            return .my
        case .userSpace, .userCollection, .article, .video:
            return routeStack.first.map(primaryTab(for:)) ?? .dynamic
        case let .browser(_, context):
            switch context {
            case .dynamic:
                return .dynamic
            case .search:
                return .search
            case .my:
                return .my
            }
        }
    }

    private static func isOpusURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()
        if (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com"),
           path.hasPrefix("/opus/")
        {
            return true
        }

        let pathComponents = url.path.split(separator: "/")
        return host == "t.bilibili.com"
            && pathComponents.count == 1
            && pathComponents[0].allSatisfy(\.isNumber)
    }

    private static func isUserSpaceURL(_ url: URL) -> Bool {
        extractUserSpaceMID(from: url) != nil
    }

    private static func isArticleURL(_ url: URL) -> Bool {
        extractArticleCVID(from: url) != nil
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let path = url.path.lowercased()
        return (host == "www.bilibili.com" || host == "bilibili.com" || host == "m.bilibili.com")
            && (path.hasPrefix("/video/") || path.hasPrefix("/bangumi/play/"))
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

    private static func extractArticleCVID(from url: URL) -> Int64? {
        FocusArticleRouting.extractCVID(from: url)
    }

    private func entryContext(for tab: PrimaryTab) -> FocusBrowserViewModel.EntryContext {
        switch tab {
        case .dynamic:
            return .dynamic
        case .search:
            return .search
        case .my:
            return .my
        }
    }

    func shouldOpenNativeUserSpace(_ url: URL) -> Bool {
        Self.isUserSpaceURL(url)
    }

    func openNativeUserSpace(_ url: URL) {
        openUserSpace(url)
    }

    func openNativeVideo(_ url: URL) {
        openVideo(url)
    }
}
#endif
