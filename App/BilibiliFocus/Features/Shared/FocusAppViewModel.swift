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
    private var isLoginFlowActive = false
    private var pendingDynamicReturnID: UUID?
    private var activeRouteCancellables: Set<AnyCancellable> = []
    private var sessionCancellable: AnyCancellable?

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
        sessionCancellable = NotificationCenter.default.publisher(for: .focusSessionDidChange, object: cookieProvider)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in self?.handleSessionTransition(notification) }

        Task { [appGraph] in
            _ = await appGraph.drainPlaybackHistoryOutbox()
        }

        browserViewModel.onEntryRequest = { [weak self] entry in
            self?.scheduleBrowserRouteRequest { $0.open(entry) }
        }

        browserViewModel.onUserSpaceRequest = { [weak self] url in
            self?.scheduleBrowserRouteRequest { $0.openNativeUserSpace(url) }
        }

        browserViewModel.onVideoRequest = { [weak self] url in
            self?.scheduleBrowserRouteRequest { $0.openNativeVideo(url) }
        }

        observeActiveRoute()
    }

    convenience init(settingsStore: FocusSettingsStore) {
        self.init(appGraph: FocusAppGraph(settingsStore: settingsStore))
    }

    private func scheduleBrowserRouteRequest(_ action: @escaping @MainActor (FocusAppViewModel) -> Void) {
        guard isBrowserActive, let sessionID = browserViewModel.activeRouteRequestSessionID else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isBrowserActive,
                  self.browserViewModel.activeRouteRequestSessionID == sessionID else { return }
            action(self)
        }
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
            // Only detail/title and dock visibility affect the shell. Progress,
            // subtitles, danmaku and playback buttons observe their own subtree.
            videoViewModel(for: routeID).$state
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &activeRouteCancellables)
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

    private func handleSessionTransition(_ notification: Notification) {
        guard let version = notification.userInfo?["version"] as? UInt64,
              version == cookieProvider.sessionVersion else { return }
        let requiresReset = notification.userInfo?["requiresAccountReset"] as? Bool ?? false
        guard requiresReset else {
            browserViewModel.reconcileSessionVersion(version)
            if cookieProvider.sessionReadiness == .authenticated || cookieProvider.sessionReadiness == .anonymous {
                myViewModel.reconcileSessionVersion(version)
                dynamicFeedViewModel.reconcileSessionVersion(version)
                if case let .video(routeID, _) = route {
                    videoViewModel(for: routeID).reconcileSessionVersion(version)
                }
            }
            return
        }
        cancelPendingDynamicReturn()
        let primary = activePrimaryTab
        let loginBrowser: AppRoute? = isLoginFlowActive && isBrowserActive ? route : nil
        routeStack.forEach(suspend)
        browserViewModel.resetForSessionChange()
        dynamicFeedViewModel.resetForSessionChange()
        myViewModel.resetForSessionChange()
        historyViewModel.resetForSessionChange()
        favoriteFolderViewModel.resetForSessionChange()
        userSpaceViewModels.values.forEach { $0.suspend() }
        userCollectionViewModels.values.forEach { $0.suspend() }
        articleViewModels.values.forEach { $0.suspend() }
        opusDetailViewModels.values.forEach { $0.suspend() }
        videoViewModels.values.forEach { $0.suspend() }
        userSpaceViewModels.removeAll(); userCollectionViewModels.removeAll()
        articleViewModels.removeAll(); opusDetailViewModels.removeAll(); videoViewModels.removeAll()
        let root: AppRoute = primary == .my ? .my : .dynamicFeed
        routeStack = loginBrowser.map { [root, $0] } ?? [root]
        observeActiveRoute()
        activate(route)
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

    private func cancelPendingDynamicReturn() {
        // Revoke the old completion before cancelling its layout work.
        pendingDynamicReturnID = nil
        dynamicFeedViewModel.cancelDetailReturn()
    }

    private func setRootRoute(_ newRoute: AppRoute) {
        cancelPendingDynamicReturn()
        if case .dynamicFeed = newRoute, hasDynamicFeedRoot, routeStack.count > 1 {
            let requestID = UUID()
            pendingDynamicReturnID = requestID
            dynamicFeedViewModel.prepareForDetailReturn { [weak self] _ in
                guard let self, self.pendingDynamicReturnID == requestID else { return }
                self.pendingDynamicReturnID = nil
                self.completeSetRootRoute(newRoute)
            }
            return
        }
        completeSetRootRoute(newRoute)
    }

    private func completeSetRootRoute(_ newRoute: AppRoute) {
        suspend(route)
        routeStack.dropFirst().forEach(cleanUpRoute)
        routeStack = [newRoute]
        observeActiveRoute()
        activate(newRoute)
        finishLoginFlowIfNeeded()
    }

    private func pushRoute(_ newRoute: AppRoute) {
        cancelPendingDynamicReturn()
        if case .dynamicFeed = route { dynamicFeedViewModel.freezeForDetails() }
        snapshotActiveBrowserURL()
        suspend(route)
        routeStack.append(newRoute)
        observeActiveRoute()
        activate(newRoute)
    }

    @discardableResult
    private func popRoute() -> Bool {
        guard routeStack.count > 1 else { return false }
        if pendingDynamicReturnID != nil {
            // Finish the pending transition at its current legal position;
            // never expose it and then resume conflicting corrections.
            dynamicFeedViewModel.finishDetailReturnNow()
            if pendingDynamicReturnID != nil {
                cancelPendingDynamicReturn()
                return completePopRoute()
            }
            return true
        }
        if routeStack.count == 2, case .dynamicFeed = routeStack[0] {
            let requestID = UUID()
            pendingDynamicReturnID = requestID
            dynamicFeedViewModel.prepareForDetailReturn { [weak self] _ in
                guard let self, self.pendingDynamicReturnID == requestID else { return }
                self.pendingDynamicReturnID = nil
                _ = self.completePopRoute()
            }
            return true
        }
        return completePopRoute()
    }

    @discardableResult
    private func completePopRoute() -> Bool {
        guard routeStack.count > 1, let removedRoute = routeStack.last else {
            return false
        }
        suspend(removedRoute)
        cleanUpRoute(removedRoute)
        routeStack.removeLast()
        observeActiveRoute()
        activate(route, restoringRetainedBrowser: true)
        if case .browser = removedRoute {
            finishLoginFlowIfNeeded()
        }
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

    private func activate(_ route: AppRoute, restoringRetainedBrowser: Bool = false) {
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
            if restoringRetainedBrowser {
                browserViewModel.resume(url, context: context)
            } else if !browserViewModel.isSessionActive
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
        // The feed view owns its initial load, which already awaits cookies.
        // Late startup warmup must not refresh an already visible/returned feed.
        refreshLoginSensitiveContent(reloadDynamicFeed: false)
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
            // Dynamic text may be commentary rather than the video's title.
            openVideo(destinationURL, preview: .init(title: "", coverURL: card.coverURLs.first))
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
        openVideo(searchItem.targetURL, preview: .init(title: searchItem.title, coverURL: searchItem.coverURL))
    }

    func open(searchPreview: SearchResultItem.PreviewVideo) {
        openVideo(searchPreview.targetURL, preview: .init(title: searchPreview.title, coverURL: searchPreview.coverURL))
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
        isLoginFlowActive = true
        openBrowser(Self.loginURL, context: .my)
    }

    private func finishLoginFlowIfNeeded() {
        guard isLoginFlowActive else { return }
        isLoginFlowActive = false
        refreshLoginSensitiveContent(reloadDynamicFeed: true)
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
        dynamicFeedViewModel.setApplicationActive(true)
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
        didRefreshOnBecomeActive = false
        activeNativeVideoViewModel?.handleAppDidEnterBackground()
        dynamicFeedViewModel.setApplicationActive(false)
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

    private func openVideo(_ url: URL, preview: FocusNativeVideoViewModel.RoutePreview? = nil) {
        let canonicalURL = FocusNavigationPolicy.canonicalWebURL(for: url)
        guard FocusVideoIdentifier.extract(from: canonicalURL) != nil else {
            openBrowser(canonicalURL, context: entryContext(for: activePrimaryTab))
            return
        }

        let routeID = RouteID()
        videoViewModel(for: routeID).seedRoutePreview(preview, for: canonicalURL)
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
            // Returning from the background must not discard loaded pages or
            // scroll positions. Only retry screens blocked by authentication.
            guard reloadDynamicFeed else {
                switch route {
                case .dynamicFeed:
                    if case .loginRequired = dynamicFeedViewModel.state { dynamicFeedViewModel.reload() }
                case .my:
                    if case .loginRequired = myViewModel.state { myViewModel.reload() }
                case .history:
                    if case .loginRequired = historyViewModel.state { historyViewModel.reload() }
                case .favoriteFolder:
                    if case .loginRequired = favoriteFolderViewModel.state { favoriteFolderViewModel.reload() }
                case let .article(routeID, _):
                    let viewModel = articleViewModel(for: routeID)
                    if case .loginRequired = viewModel.state { viewModel.reload() }
                case let .opus(routeID, _):
                    let viewModel = opusDetailViewModel(for: routeID)
                    if case .loginRequired = viewModel.state { viewModel.reload() }
                default:
                    break
                }
                return
            }
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
