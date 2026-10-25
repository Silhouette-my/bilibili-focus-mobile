package org.bilibilifocus.android

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.foundation.gestures.stopScroll
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.materials.ExperimentalHazeMaterialsApi
import dev.chrisbanes.haze.materials.HazeMaterials
import org.bilibilifocus.android.ui.FocusArticleScreen
import org.bilibilifocus.android.ui.FocusDynamicFeedScreen
import org.bilibilifocus.android.ui.FocusFavFolderScreen
import org.bilibilifocus.android.ui.FocusHistoryScreen
import org.bilibilifocus.android.ui.FocusLoginScreen
import org.bilibilifocus.android.ui.FocusMyScreen
import org.bilibilifocus.android.ui.FocusOpusScreen
import org.bilibilifocus.android.ui.FocusSearchScreen
import org.bilibilifocus.android.ui.FocusSettingsScreen
import org.bilibilifocus.android.ui.FocusUserScreen
import org.bilibilifocus.android.ui.FocusUserCollectionScreen
import org.bilibilifocus.android.ui.FocusVideoScreen
import org.bilibilifocus.android.ui.FocusWatchLaterScreen
import org.bilibilifocus.android.ui.FocusWebView
import org.bilibilifocus.android.playback.FocusPlaybackConnection
import org.bilibilifocus.core.model.FavFolder
import org.bilibilifocus.core.model.FocusEntry
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.model.FocusSettings
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.UserContentCollection
import org.bilibilifocus.core.routing.ArticleURL
import org.bilibilifocus.core.service.VideoInfoService

@OptIn(ExperimentalMaterial3Api::class, ExperimentalHazeMaterialsApi::class)
@Composable
fun FocusApp(
    settingsViewModel: FocusSettingsViewModel,
    appGraph: FocusAppGraph,
    playbackConnection: FocusPlaybackConnection,
    playerSurfaceRevision: Int,
    isInPictureInPictureMode: Boolean,
    isInMultiWindowMode: Boolean,
) {
    val widthClass = rememberFocusWindowClass()
    val uriHandler = LocalUriHandler.current
    val isWideLayout = widthClass == FocusWindowClass.Expanded
    val settings by settingsViewModel.settings.collectAsState()
    var accountRevision by remember { mutableIntStateOf(0) }

    var selectedTab by rememberSaveable {
        mutableIntStateOf(if (settings.defaultEntry == FocusEntry.SEARCH) 1 else 0)
    }
    var showLogin by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var pendingSearchQuery by remember { mutableStateOf<String?>(null) }
    var savedFeedFilterName by rememberSaveable {
        mutableStateOf(FocusDynamicFilterKind.ALL.name)
    }
    val overlayStack = remember(accountRevision) { mutableStateListOf<OverlayRoute>() }
    val dynamicDetailStack = remember(accountRevision) { mutableStateListOf<OverlayRoute>() }

    // 顶层持有状态，切 tab / 进出详情页都保留内容与滚动位置。
    val restoredFeedFilter = FocusDynamicFilterKind.entries.firstOrNull {
        it.name == savedFeedFilterName
    } ?: FocusDynamicFilterKind.ALL
    val feedViewModel = remember(accountRevision) {
        FocusFeedViewModel(
            service = appGraph.dynamicFeedService,
            initialSelectedFilter = restoredFeedFilter,
        )
    }
    val feedState by key(accountRevision) { feedViewModel.state.collectAsState() }
    val knownDynamicAuthors = remember(feedState) {
        val cards = (feedState as? FeedUiState.Loaded)?.cards.orEmpty()
        cards.map { it.author }
            .filter { it.mid > 0 || it.name.isNotBlank() }
            .distinctBy(FocusSettingsViewModel::authorFilterKey)
            .sortedBy { it.name.lowercase() }
    }
    val searchViewModel = remember(accountRevision) {
        FocusSearchViewModel(appGraph.searchResultService)
    }
    val myViewModel = remember(accountRevision) {
        FocusMyViewModel(
            accountService = appGraph.accountService,
            userService = appGraph.userService,
            historyService = appGraph.historyService,
            favoriteService = appGraph.favoriteService,
        )
    }
    val watchLaterViewModel = remember(accountRevision) {
        FocusWatchLaterViewModel(appGraph.watchLaterService)
    }
    val feedListState = rememberSaveable(accountRevision, saver = LazyListState.Saver) { LazyListState() }
    val isDynamicFeedVisible = selectedTab == 0 && !showSettings && !showLogin &&
        overlayStack.isEmpty() && (isWideLayout || dynamicDetailStack.isEmpty())
    LaunchedEffect(isDynamicFeedVisible, feedListState) {
        if (!isDynamicFeedVisible) {
            feedListState.stopScroll()
        }
    }
    val myListState = remember(accountRevision) { LazyListState() }
    val videoViewModels = remember(accountRevision) { mutableStateMapOf<String, FocusVideoViewModel>() }
    val videoScrollStates = remember(accountRevision) { mutableStateMapOf<String, ScrollState>() }
    val opusViewModels = remember(accountRevision) { mutableStateMapOf<String, FocusOpusViewModel>() }
    val opusListStates = remember(accountRevision) { mutableStateMapOf<String, LazyListState>() }
    val articleViewModels = remember(accountRevision) { mutableStateMapOf<Long, FocusArticleViewModel>() }
    val userViewModels = remember(accountRevision) { mutableStateMapOf<Long, FocusUserViewModel>() }
    val userGridStates = remember(accountRevision) { mutableStateMapOf<Long, LazyGridState>() }
    val userCollectionViewModels = remember(accountRevision) { mutableStateMapOf<String, FocusUserCollectionViewModel>() }
    val userCollectionGridStates = remember(accountRevision) { mutableStateMapOf<String, LazyGridState>() }
    val favFolderViewModels = remember(accountRevision) { mutableStateMapOf<Long, FocusFavFolderViewModel>() }
    val favFolderGridStates = remember(accountRevision) { mutableStateMapOf<Long, LazyGridState>() }
    val historyViewModels = remember(accountRevision) { mutableStateMapOf<String, FocusHistoryViewModel>() }
    val historyGridStates = remember(accountRevision) { mutableStateMapOf<String, LazyGridState>() }
    val watchLaterGridState = remember(accountRevision) { LazyGridState() }

    fun releaseRouteIfUnused(route: OverlayRoute) {
        val isStillRetained = overlayStack.any { it.key == route.key } ||
            dynamicDetailStack.any { it.key == route.key }
        if (isStillRetained) return

        when (route) {
            is OverlayRoute.Video -> {
                videoViewModels.remove(route.key)?.onCleared()
                videoScrollStates.remove(route.key)
            }
            is OverlayRoute.Opus -> {
                opusViewModels.remove(route.id)?.onCleared()
                opusListStates.remove(route.id)
            }
            is OverlayRoute.Article -> articleViewModels.remove(route.cvid)?.onCleared()
            is OverlayRoute.User -> {
                userViewModels.remove(route.mid)?.onCleared()
                userGridStates.remove(route.mid)
            }
            is OverlayRoute.UserCollection -> {
                userCollectionViewModels.remove(route.collection.id)?.onCleared()
                userCollectionGridStates.remove(route.collection.id)
            }
            is OverlayRoute.Folder -> {
                favFolderViewModels.remove(route.mediaId)?.onCleared()
                favFolderGridStates.remove(route.mediaId)
            }
            is OverlayRoute.History -> {
                historyViewModels.remove(route.key)?.onCleared()
                historyGridStates.remove(route.key)
            }
            OverlayRoute.WatchLater -> Unit
            is OverlayRoute.Web -> Unit
        }
    }

    DisposableEffect(accountRevision) {
        onDispose {
            feedViewModel.onCleared()
            searchViewModel.onCleared()
            myViewModel.onCleared()
            watchLaterViewModel.onCleared()
            videoViewModels.values.forEach(FocusVideoViewModel::onCleared)
            opusViewModels.values.forEach(FocusOpusViewModel::onCleared)
            articleViewModels.values.forEach(FocusArticleViewModel::onCleared)
            userViewModels.values.forEach(FocusUserViewModel::onCleared)
            userCollectionViewModels.values.forEach(FocusUserCollectionViewModel::onCleared)
            favFolderViewModels.values.forEach(FocusFavFolderViewModel::onCleared)
            historyViewModels.values.forEach(FocusHistoryViewModel::onCleared)
        }
    }

    fun selectTab(tab: Int) {
        val hidesDynamicVideo = selectedTab == 0 && tab != 0 &&
            dynamicDetailStack.lastOrNull() is OverlayRoute.Video
        if (FocusPlaybackRoutePolicy.shouldStop(
                isLeavingVideoRoute = hidesDynamicVideo,
                isApplicationBackgrounding = false,
            )
        ) {
            playbackConnection.stop()
        }
        selectedTab = tab
    }

    fun pushOverlay(route: OverlayRoute) {
        if (overlayStack.lastOrNull() == route) return
        if (FocusPlaybackRoutePolicy.shouldStop(
                isLeavingVideoRoute = overlayStack.lastOrNull() is OverlayRoute.Video &&
                    route !is OverlayRoute.Video,
                isApplicationBackgrounding = false,
            )
        ) {
            playbackConnection.stop()
        }
        overlayStack.add(route)
    }

    fun popOverlay() {
        if (overlayStack.isNotEmpty()) {
            val route = overlayStack.last()
            if (FocusPlaybackRoutePolicy.shouldStop(
                    isLeavingVideoRoute = route is OverlayRoute.Video,
                    isApplicationBackgrounding = false,
                )
            ) {
                playbackConnection.stop()
            }
            overlayStack.removeAt(overlayStack.lastIndex)
            releaseRouteIfUnused(route)
        }
    }

    fun pushDynamicDetail(route: OverlayRoute) {
        if (dynamicDetailStack.lastOrNull() == route) return
        if (FocusPlaybackRoutePolicy.shouldStop(
                isLeavingVideoRoute = dynamicDetailStack.lastOrNull() is OverlayRoute.Video &&
                    route !is OverlayRoute.Video,
                isApplicationBackgrounding = false,
            )
        ) {
            playbackConnection.stop()
        }
        dynamicDetailStack.add(route)
    }

    fun popDynamicDetail() {
        if (dynamicDetailStack.isNotEmpty()) {
            val route = dynamicDetailStack.last()
            if (FocusPlaybackRoutePolicy.shouldStop(
                    isLeavingVideoRoute = route is OverlayRoute.Video,
                    isApplicationBackgrounding = false,
                )
            ) {
                playbackConnection.stop()
            }
            dynamicDetailStack.removeAt(dynamicDetailStack.lastIndex)
            releaseRouteIfUnused(route)
        }
    }

    fun routeForUrl(url: String): OverlayRoute {
        if (VideoInfoService.extractBvid(url) != null) {
            return OverlayRoute.Video(url)
        }
        val opusIdExtracted = extractOpusId(url)
        val cvid = extractArticleCvid(url)
        val userMid = extractUserMid(url)
        return when {
            opusIdExtracted != null -> OverlayRoute.Opus(opusIdExtracted)
            cvid != null -> OverlayRoute.Article(cvid)
            userMid != null -> OverlayRoute.User(userMid)
            else -> OverlayRoute.Web(url)
        }
    }

    val openInBrowser: (String) -> Unit = { url -> pushOverlay(routeForUrl(url)) }
    val openDynamicDetailUrl: (String) -> Unit = { url -> pushDynamicDetail(routeForUrl(url)) }
    val openUser: (Long) -> Unit = { mid -> pushOverlay(OverlayRoute.User(mid)) }
    val openDynamicUser: (Long) -> Unit = { mid -> pushDynamicDetail(OverlayRoute.User(mid)) }
    val openSearchItem: (SearchResultItem) -> Unit = { item -> openInBrowser(item.targetURL) }

    BackHandler(enabled = overlayStack.isNotEmpty()) { popOverlay() }
    BackHandler(enabled = overlayStack.isEmpty() && selectedTab == 0 && dynamicDetailStack.isNotEmpty()) {
        popDynamicDetail()
    }
    BackHandler(enabled = showLogin) { showLogin = false }
    BackHandler(enabled = showSettings) { showSettings = false }

    val renderRoute: @Composable (
        OverlayRoute,
        () -> Unit,
        (Long) -> Unit,
        (String) -> Unit,
        (OverlayRoute) -> Unit,
    ) -> Unit = { route, onBack, onOpenUserRoute, onOpenVideoRoute, onOpenChildRoute ->
        when (route) {
            is OverlayRoute.Video -> {
                val routeKey = route.key
                val viewModel = videoViewModels.getOrPut(routeKey) {
                    FocusVideoViewModel(
                        service = appGraph.videoInfoService,
                        actionService = appGraph.videoActionService,
                    )
                }
                val scrollState = videoScrollStates.getOrPut(routeKey) { ScrollState(0) }
                FocusVideoScreen(
                    url = route.url,
                    onBack = onBack,
                    onOpenUser = onOpenUserRoute,
                    onOpenVideo = onOpenVideoRoute,
                    onOpenURL = { url -> onOpenChildRoute(routeForUrl(url)) },
                    nativeDanmakuEnabled = settings.nativeDanmakuEnabled,
                    onNativeDanmakuEnabledChange = { enabled ->
                        settingsViewModel.update { it.copy(nativeDanmakuEnabled = enabled) }
                    },
                    viewModel = viewModel,
                    scrollState = scrollState,
                    playbackConnection = playbackConnection,
                    playbackAccountScopeProvider = appGraph.playbackAccountScopeProvider,
                    playbackProgressStore = appGraph.playbackProgressStore,
                    playerSurfaceRevision = playerSurfaceRevision,
                    isInPictureInPictureMode = isInPictureInPictureMode,
                    isInMultiWindowMode = isInMultiWindowMode,
                )
            }

            is OverlayRoute.Opus -> {
                val viewModel = opusViewModels.getOrPut(route.id) {
                    FocusOpusViewModel(service = appGraph.opusService)
                }
                val listState = opusListStates.getOrPut(route.id) { LazyListState() }
                FocusOpusScreen(
                    opusId = route.id,
                    onBack = onBack,
                    onOpenUser = onOpenUserRoute,
                    onOpenVideo = onOpenVideoRoute,
                    onOpenURL = { url -> onOpenChildRoute(routeForUrl(url)) },
                    viewModel = viewModel,
                    listState = listState,
                )
            }

            is OverlayRoute.Article -> {
                val viewModel = articleViewModels.getOrPut(route.cvid) {
                    FocusArticleViewModel(service = appGraph.articleService)
                }
                FocusArticleScreen(
                    cvid = route.cvid,
                    onBack = onBack,
                    onOpenUser = onOpenUserRoute,
                    onOpenURL = { url -> onOpenChildRoute(routeForUrl(url)) },
                    onOpenWeb = { url -> onOpenChildRoute(OverlayRoute.Web(url)) },
                    viewModel = viewModel,
                )
            }

            is OverlayRoute.User -> {
                val viewModel = userViewModels.getOrPut(route.mid) {
                    FocusUserViewModel(service = appGraph.userService)
                }
                val gridState = userGridStates.getOrPut(route.mid) { LazyGridState() }
                FocusUserScreen(
                    userId = route.mid,
                    onBack = onBack,
                    onOpenVideo = onOpenVideoRoute,
                    onOpenCollection = { collection ->
                        onOpenChildRoute(OverlayRoute.UserCollection(collection))
                    },
                    onOpenArticle = { url -> onOpenChildRoute(routeForUrl(url)) },
                    viewModel = viewModel,
                    gridState = gridState,
                )
            }

            is OverlayRoute.UserCollection -> {
                val viewModel = userCollectionViewModels.getOrPut(route.collection.id) {
                    FocusUserCollectionViewModel(service = appGraph.userService)
                }
                val gridState = userCollectionGridStates.getOrPut(route.collection.id) { LazyGridState() }
                FocusUserCollectionScreen(
                    collection = route.collection,
                    onBack = onBack,
                    onOpenVideo = onOpenVideoRoute,
                    viewModel = viewModel,
                    gridState = gridState,
                )
            }

            is OverlayRoute.Web -> {
                Scaffold(
                    topBar = {
                        CenterAlignedTopAppBar(
                            title = { Text("浏览", maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            navigationIcon = {
                                IconButton(onClick = onBack) {
                                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                                }
                            },
                            colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                                containerColor = MaterialTheme.colorScheme.surface,
                                titleContentColor = MaterialTheme.colorScheme.onSurface,
                            ),
                        )
                    },
                ) { innerPadding ->
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
                        FocusWebView(
                            url = route.url,
                            userScript = FocusScriptBuilder.buildUserScript(route.url, settings),
                            onUrlChanged = {},
                            onPageStarted = {},
                            onPageFinished = {},
                            onError = {},
                            onOpenExternal = { externalURL ->
                                runCatching { uriHandler.openUri(externalURL) }
                                onBack()
                            },
                        )
                    }
                }
            }

            is OverlayRoute.Folder -> {
                val viewModel = favFolderViewModels.getOrPut(route.mediaId) {
                    FocusFavFolderViewModel(service = appGraph.favoriteService)
                }
                val gridState = favFolderGridStates.getOrPut(route.mediaId) { LazyGridState() }
                FocusFavFolderScreen(
                    mediaId = route.mediaId,
                    folderTitle = route.title,
                    onBack = onBack,
                    onOpenVideo = onOpenVideoRoute,
                    viewModel = viewModel,
                    gridState = gridState,
                )
            }

            is OverlayRoute.History -> {
                val viewModel = historyViewModels.getOrPut(route.key) {
                    FocusHistoryViewModel(service = appGraph.historyService)
                }
                val gridState = historyGridStates.getOrPut(route.key) { LazyGridState() }
                FocusHistoryScreen(
                    onBack = onBack,
                    onOpenVideo = onOpenVideoRoute,
                    viewModel = viewModel,
                    gridState = gridState,
                )
            }

            OverlayRoute.WatchLater -> {
                FocusWatchLaterScreen(
                    onBack = onBack,
                    onOpenVideo = onOpenVideoRoute,
                    onOpenLogin = { showLogin = true },
                    viewModel = watchLaterViewModel,
                    gridState = watchLaterGridState,
                )
            }
        }
    }

    // 同一个详情会在横屏分栏和竖屏覆盖层之间移动。保留其 Composition，
    // 避免旋转时销毁并重建 FocusVideoScreen/ExoPlayer。
    val currentRenderRoute by rememberUpdatedState(renderRoute)
    val movableDynamicDetail = remember(accountRevision) {
        movableContentOf<OverlayRoute> { route ->
            currentRenderRoute(
                route,
                { popDynamicDetail() },
                openDynamicUser,
                { url -> pushDynamicDetail(OverlayRoute.Video(url)) },
                { childRoute -> pushDynamicDetail(childRoute) },
            )
        }
    }

    key(accountRevision) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (isWideLayout && selectedTab == 0) {
                FocusDynamicTabletScaffold(
                    widthClass = widthClass,
                    selectedTab = selectedTab,
                    onSelectTab = ::selectTab,
                    onOpenSettings = { showSettings = true },
                    primaryContent = { contentPadding ->
                        FocusDynamicFeedScreen(
                            viewModel = feedViewModel,
                            listState = feedListState,
                            onOpenLogin = { showLogin = true },
                            onOpenCard = { card -> openDynamicDetailUrl(card.videoURL ?: card.targetURL) },
                            onOpenUser = openDynamicUser,
                            onOpenSearch = { query ->
                                pendingSearchQuery = query
                                selectTab(1)
                            },
                            onSelectedFilterChange = { filter ->
                                savedFeedFilterName = filter.name
                            },
                            contentPadding = contentPadding,
                            settings = settings,
                        )
                    },
                    detailContent = {
                        dynamicDetailStack.lastOrNull()?.let { route ->
                            movableDynamicDetail(route)
                        } ?: FocusDynamicDetailPlaceholder()
                    },
                )
            } else if (isWideLayout) {
                FocusTabletScaffold(
                    widthClass = widthClass,
                    selectedTab = selectedTab,
                    onSelectTab = ::selectTab,
                    onOpenSettings = { showSettings = true },
                ) { contentPadding ->
                    FocusPrimaryTabContent(
                        selectedTab = selectedTab,
                        feedViewModel = feedViewModel,
                        feedListState = feedListState,
                        searchViewModel = searchViewModel,
                        myViewModel = myViewModel,
                        watchLaterViewModel = watchLaterViewModel,
                        myListState = myListState,
                        onOpenLogin = { showLogin = true },
                        onOpenRouteFromUrl = openInBrowser,
                        onOpenUser = openUser,
                        onSearchQueryFromFeed = { query ->
                            pendingSearchQuery = query
                            selectTab(1)
                        },
                        onFeedFilterChange = { filter ->
                            savedFeedFilterName = filter.name
                        },
                        onOpenSearchItem = openSearchItem,
                        initialQuery = pendingSearchQuery,
                        onInitialQueryConsumed = { pendingSearchQuery = null },
                        onOpenMyVideo = { pushOverlay(OverlayRoute.Video(it)) },
                        onOpenWatchLater = { pushOverlay(OverlayRoute.WatchLater) },
                        onOpenHistory = { pushOverlay(OverlayRoute.History) },
                        onOpenFolder = { pushOverlay(OverlayRoute.Folder(it.id, it.title)) },
                        contentPadding = contentPadding,
                        searchGridColumns = searchColumnsFor(widthClass),
                        settings = settings,
                    )
                }
            } else {
                FocusCompactScaffold(
                    selectedTab = selectedTab,
                    onSelectTab = ::selectTab,
                    onOpenSettings = { showSettings = true },
                ) { contentPadding ->
                    FocusPrimaryTabContent(
                        selectedTab = selectedTab,
                        feedViewModel = feedViewModel,
                        feedListState = feedListState,
                        searchViewModel = searchViewModel,
                        myViewModel = myViewModel,
                        watchLaterViewModel = watchLaterViewModel,
                        myListState = myListState,
                        onOpenLogin = { showLogin = true },
                        onOpenRouteFromUrl = openInBrowser,
                        onOpenUser = openUser,
                        onSearchQueryFromFeed = { query ->
                            pendingSearchQuery = query
                            selectTab(1)
                        },
                        onFeedFilterChange = { filter ->
                            savedFeedFilterName = filter.name
                        },
                        onOpenSearchItem = openSearchItem,
                        initialQuery = pendingSearchQuery,
                        onInitialQueryConsumed = { pendingSearchQuery = null },
                        onOpenMyVideo = { pushOverlay(OverlayRoute.Video(it)) },
                        onOpenWatchLater = { pushOverlay(OverlayRoute.WatchLater) },
                        onOpenHistory = { pushOverlay(OverlayRoute.History) },
                        onOpenFolder = { pushOverlay(OverlayRoute.Folder(it.id, it.title)) },
                        contentPadding = contentPadding,
                        searchGridColumns = searchColumnsFor(widthClass),
                        settings = settings,
                    )
                }
            }

            if (!isWideLayout && selectedTab == 0) {
                dynamicDetailStack.lastOrNull()?.let { route ->
                    movableDynamicDetail(route)
                }
            }

            overlayStack.lastOrNull()?.let { route ->
                renderRoute(
                    route,
                    { popOverlay() },
                    openUser,
                    { url -> pushOverlay(OverlayRoute.Video(url)) },
                    { childRoute -> pushOverlay(childRoute) },
                )
            }

            AnimatedVisibility(
                visible = showSettings,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                FocusSettingsScreen(
                    settings = settings,
                    knownAuthors = knownDynamicAuthors,
                    followingAuthorsService = appGraph.followingAuthorsService,
                    loginHealthService = appGraph.loginHealthService,
                    networkEvents = appGraph.networkEvents,
                    onBack = { showSettings = false },
                    onUpdate = settingsViewModel::update,
                    onSetAuthorKind = settingsViewModel::setDynamicKindEnabled,
                    authorKinds = settingsViewModel::dynamicKindsFor,
                    onReset = settingsViewModel::reset,
                )
            }

            AnimatedVisibility(
                visible = showLogin,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                FocusLoginScreen(
                    onBack = { showLogin = false },
                    onLoginComplete = {
                        // Authentication can replace the account. Dispose retained
                        // content and route state before any old account is shown again.
                        playbackConnection.stop()
                        pendingSearchQuery = null
                        accountRevision += 1
                        showLogin = false
                    },
                )
            }
        }
    }
}

@Composable
private fun FocusPrimaryTabContent(
    selectedTab: Int,
    feedViewModel: FocusFeedViewModel,
    feedListState: LazyListState,
    searchViewModel: FocusSearchViewModel,
    myViewModel: FocusMyViewModel,
    watchLaterViewModel: FocusWatchLaterViewModel,
    myListState: LazyListState,
    onOpenLogin: () -> Unit,
    onOpenRouteFromUrl: (String) -> Unit,
    onOpenUser: (Long) -> Unit,
    onSearchQueryFromFeed: (String) -> Unit,
    onFeedFilterChange: (FocusDynamicFilterKind) -> Unit,
    onOpenSearchItem: (SearchResultItem) -> Unit,
    initialQuery: String?,
    onInitialQueryConsumed: () -> Unit,
    onOpenMyVideo: (String) -> Unit,
    onOpenWatchLater: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenFolder: (FavFolder) -> Unit,
    contentPadding: PaddingValues,
    searchGridColumns: Int,
    settings: FocusSettings,
) {
    when (selectedTab) {
        0 -> FocusDynamicFeedScreen(
            viewModel = feedViewModel,
            listState = feedListState,
            onOpenLogin = onOpenLogin,
            onOpenCard = { card -> onOpenRouteFromUrl(card.videoURL ?: card.targetURL) },
            onOpenUser = onOpenUser,
            onOpenSearch = onSearchQueryFromFeed,
            onSelectedFilterChange = onFeedFilterChange,
            contentPadding = contentPadding,
            settings = settings,
        )

        1 -> FocusSearchScreen(
            viewModel = searchViewModel,
            onOpenItem = onOpenSearchItem,
            onOpenLogin = onOpenLogin,
            initialQuery = initialQuery,
            onInitialQueryConsumed = onInitialQueryConsumed,
            contentPadding = contentPadding,
            resultColumns = searchGridColumns,
        )

        2 -> FocusMyScreen(
            viewModel = myViewModel,
            watchLaterViewModel = watchLaterViewModel,
            listState = myListState,
            onOpenLogin = onOpenLogin,
            onOpenVideo = onOpenMyVideo,
            onOpenWatchLater = onOpenWatchLater,
            onOpenHistory = onOpenHistory,
            onOpenFolder = onOpenFolder,
            contentPadding = contentPadding,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalHazeMaterialsApi::class)
@Composable
private fun FocusCompactScaffold(
    selectedTab: Int,
    onSelectTab: (Int) -> Unit,
    onOpenSettings: () -> Unit,
    content: @Composable (PaddingValues) -> Unit,
) {
    val hazeState = remember { HazeState() }
    val hazeStyle = HazeMaterials.thin(MaterialTheme.colorScheme.surface)

    Scaffold(
        topBar = {
            Column(modifier = Modifier.hazeEffect(state = hazeState, style = hazeStyle)) {
                CenterAlignedTopAppBar(
                    title = {
                        Text(
                            primaryDestinations.getOrNull(selectedTab)?.label ?: "Bilibili Focus",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    actions = {
                        IconButton(onClick = onOpenSettings) {
                            Icon(Icons.Outlined.Settings, contentDescription = "设置")
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = Color.Transparent,
                        titleContentColor = MaterialTheme.colorScheme.onSurface,
                        actionIconContentColor = MaterialTheme.colorScheme.onSurface,
                    ),
                )
                HorizontalDivider(thickness = 0.5.dp, color = Color.Black.copy(alpha = 0.06f))
            }
        },
        bottomBar = {
            Column(modifier = Modifier.hazeEffect(state = hazeState, style = hazeStyle)) {
                HorizontalDivider(thickness = 0.5.dp, color = Color.Black.copy(alpha = 0.06f))
                NavigationBar(
                    containerColor = Color.Transparent,
                    tonalElevation = 0.dp,
                ) {
                    primaryDestinations.forEachIndexed { index, destination ->
                        NavigationBarItem(
                            icon = {
                                Icon(
                                    imageVector = if (selectedTab == index) destination.filledIcon else destination.outlinedIcon,
                                    contentDescription = destination.label,
                                )
                            },
                            label = { Text(destination.label) },
                            selected = selectedTab == index,
                            onClick = { onSelectTab(index) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = MaterialTheme.colorScheme.primary,
                                selectedTextColor = MaterialTheme.colorScheme.primary,
                                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                            ),
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        Box(modifier = Modifier.fillMaxSize().hazeSource(state = hazeState)) {
            content(innerPadding)
        }
    }
}

@Composable
private fun FocusTabletScaffold(
    widthClass: FocusWindowClass,
    selectedTab: Int,
    onSelectTab: (Int) -> Unit,
    onOpenSettings: () -> Unit,
    content: @Composable (PaddingValues) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsTopHeight(WindowInsets.statusBars),
        )
        Row(modifier = Modifier.fillMaxSize()) {
            FocusPrimaryNavigationRail(
                selectedTab = selectedTab,
                onSelectTab = onSelectTab,
                onOpenSettings = onOpenSettings,
                modifier = Modifier.fillMaxHeight(),
            )

            VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f))

            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(),
                contentAlignment = androidx.compose.ui.Alignment.TopCenter,
            ) {
                Box(
                    modifier = Modifier
                        .widthIn(max = tabletContentWidthFor(widthClass, selectedTab))
                        .fillMaxWidth()
                        .fillMaxHeight(),
                ) {
                    content(PaddingValues(bottom = 18.dp))
                }
            }
        }
    }
}

@Composable
private fun FocusDynamicTabletScaffold(
    widthClass: FocusWindowClass,
    selectedTab: Int,
    onSelectTab: (Int) -> Unit,
    onOpenSettings: () -> Unit,
    primaryContent: @Composable (PaddingValues) -> Unit,
    detailContent: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .windowInsetsTopHeight(WindowInsets.statusBars),
        )
        Row(modifier = Modifier.fillMaxSize()) {
            FocusPrimaryNavigationRail(
                selectedTab = selectedTab,
                onSelectTab = onSelectTab,
                onOpenSettings = onOpenSettings,
                modifier = Modifier.fillMaxHeight(),
            )

            VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f))

            Box(
                modifier = Modifier
                    .width(dynamicListWidthFor(widthClass))
                    .fillMaxHeight(),
            ) {
                primaryContent(PaddingValues(bottom = 18.dp))
            }

            VerticalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.65f))

            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.surface),
            ) {
                detailContent()
            }
        }
    }
}

@Composable
private fun FocusPrimaryNavigationRail(
    selectedTab: Int,
    onSelectTab: (Int) -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    NavigationRail(
        modifier = modifier.width(94.dp),
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Spacer(modifier = Modifier.height(18.dp))
        primaryDestinations.forEachIndexed { index, destination ->
            NavigationRailItem(
                selected = selectedTab == index,
                onClick = { onSelectTab(index) },
                icon = {
                    Icon(
                        imageVector = if (selectedTab == index) destination.filledIcon else destination.outlinedIcon,
                        contentDescription = destination.label,
                        modifier = Modifier
                            .padding(bottom = 2.dp)
                            .size(30.dp),
                    )
                },
                label = {
                    Text(
                        destination.label,
                        style = MaterialTheme.typography.labelLarge.copy(fontSize = 17.sp),
                    )
                },
                alwaysShowLabel = true,
                colors = NavigationRailItemDefaults.colors(
                    selectedIconColor = MaterialTheme.colorScheme.primary,
                    selectedTextColor = MaterialTheme.colorScheme.primary,
                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                ),
            )
            Spacer(modifier = Modifier.height(12.dp))
        }
        Spacer(modifier = Modifier.weight(1f))
        NavigationRailItem(
            selected = false,
            onClick = onOpenSettings,
            icon = {
                Icon(
                    imageVector = Icons.Outlined.Settings,
                    contentDescription = "设置",
                    modifier = Modifier.size(28.dp),
                )
            },
            label = { Text("设置", style = MaterialTheme.typography.labelLarge) },
            alwaysShowLabel = true,
            colors = NavigationRailItemDefaults.colors(
                unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
            ),
        )
        Spacer(modifier = Modifier.height(18.dp))
    }
}

@Composable
private fun FocusDynamicDetailPlaceholder() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.surface),
    ) {
        Column(
            modifier = Modifier
                .padding(horizontal = 32.dp)
                .align(androidx.compose.ui.Alignment.Center),
        ) {
            Text("选择一条动态", style = MaterialTheme.typography.headlineSmall, color = MaterialTheme.colorScheme.onSurface)
            Text(
                "右侧会显示视频、图文动态或专栏详情。",
                modifier = Modifier.padding(top = 10.dp),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun rememberFocusWindowClass(): FocusWindowClass {
    val widthDp = LocalConfiguration.current.screenWidthDp
    return when {
        widthDp < 600 -> FocusWindowClass.Compact
        widthDp < 1000 -> FocusWindowClass.Medium
        else -> FocusWindowClass.Expanded
    }
}

private fun tabletContentWidthFor(widthClass: FocusWindowClass, selectedTab: Int): Dp = when (selectedTab) {
    1 -> when (widthClass) {
        FocusWindowClass.Compact -> 720.dp
        FocusWindowClass.Medium -> 940.dp
        FocusWindowClass.Expanded -> 1160.dp
    }
    2 -> when (widthClass) {
        FocusWindowClass.Compact -> 720.dp
        FocusWindowClass.Medium -> 920.dp
        FocusWindowClass.Expanded -> 1080.dp
    }
    else -> when (widthClass) {
        FocusWindowClass.Compact -> 640.dp
        FocusWindowClass.Medium -> 660.dp
        FocusWindowClass.Expanded -> 700.dp
    }
}

internal object FocusPlaybackRoutePolicy {
    fun shouldStop(
        isLeavingVideoRoute: Boolean,
        isApplicationBackgrounding: Boolean,
    ): Boolean = isLeavingVideoRoute && !isApplicationBackgrounding
}

private fun dynamicListWidthFor(widthClass: FocusWindowClass): Dp = when (widthClass) {
    FocusWindowClass.Compact -> 420.dp
    FocusWindowClass.Medium -> 440.dp
    FocusWindowClass.Expanded -> 480.dp
}

private fun searchColumnsFor(widthClass: FocusWindowClass): Int = when (widthClass) {
    FocusWindowClass.Compact -> 2
    FocusWindowClass.Medium -> 3
    FocusWindowClass.Expanded -> 4
}

private enum class FocusWindowClass {
    Compact,
    Medium,
    Expanded,
}

private data class PrimaryDestination(
    val label: String,
    val filledIcon: ImageVector,
    val outlinedIcon: ImageVector,
)

private val primaryDestinations = listOf(
    PrimaryDestination(
        label = "动态",
        filledIcon = Icons.Filled.Home,
        outlinedIcon = Icons.Outlined.Home,
    ),
    PrimaryDestination(
        label = "搜索",
        filledIcon = Icons.Filled.Search,
        outlinedIcon = Icons.Outlined.Search,
    ),
    PrimaryDestination(
        label = "我的",
        filledIcon = Icons.Filled.Person,
        outlinedIcon = Icons.Outlined.Person,
    ),
)

private fun extractOpusId(url: String): String? {
    Regex("""bilibili\.com/opus/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.let { return it }
    Regex("""t\.bilibili\.com/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.let { return it }
    Regex("""opus/detail/(\d+)""").find(url)?.groupValues?.getOrNull(1)?.let { return it }
    return null
}

private fun extractArticleCvid(url: String): Long? {
    return ArticleURL.extractCvid(url)
}

private fun extractUserMid(url: String): Long? {
    Regex("""(?:https?:)?//space\.bilibili\.com/(\d+)""", RegexOption.IGNORE_CASE)
        .find(url)
        ?.groupValues
        ?.getOrNull(1)
        ?.toLongOrNull()
        ?.let { return it }
    Regex("""bilibili://space/(\d+)""", RegexOption.IGNORE_CASE)
        .find(url)
        ?.groupValues
        ?.getOrNull(1)
        ?.toLongOrNull()
        ?.let { return it }
    return null
}

private sealed interface OverlayRoute {
    val key: String

    data class Video(val url: String) : OverlayRoute {
        override val key: String = "video:$url"
    }

    data class Opus(val id: String) : OverlayRoute {
        override val key: String = "opus:$id"
    }

    data class Article(val cvid: Long) : OverlayRoute {
        override val key: String = "article:$cvid"
    }

    data class User(val mid: Long) : OverlayRoute {
        override val key: String = "user:$mid"
    }

    data class UserCollection(val collection: UserContentCollection) : OverlayRoute {
        override val key: String = "user-collection:${collection.id}"
    }

    data class Web(val url: String) : OverlayRoute {
        override val key: String = "web:$url"
    }

    data class Folder(val mediaId: Long, val title: String) : OverlayRoute {
        override val key: String = "folder:$mediaId"
    }

    data object History : OverlayRoute {
        override val key: String = "history"
    }

    data object WatchLater : OverlayRoute {
        override val key: String = "watch-later"
    }
}
