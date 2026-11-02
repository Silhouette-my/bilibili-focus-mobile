package org.bilibilifocus.android.ui

import android.content.pm.ActivityInfo
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.util.UnstableApi
import org.bilibilifocus.android.FocusPictureInPicturePolicy
import org.bilibilifocus.android.FocusVideoViewModel
import org.bilibilifocus.android.VideoUiState
import org.bilibilifocus.android.playback.FocusPlaybackAccountScopeProvider
import org.bilibilifocus.android.playback.FocusPlaybackConnection
import org.bilibilifocus.android.playback.FocusPlaybackProgressStore
import org.bilibilifocus.android.playback.FocusPlaybackRequest
import org.bilibilifocus.android.playback.FocusPlaybackResumePolicy
import org.bilibilifocus.android.ui.video.AuthorCard
import org.bilibilifocus.android.ui.video.commentImageGalleryRequest
import org.bilibilifocus.android.ui.video.ExpandableDescription
import org.bilibilifocus.android.ui.video.FocusVideoDeviceType
import org.bilibilifocus.android.ui.video.FocusVideoDetailLayout
import org.bilibilifocus.android.ui.video.FocusVideoFullscreenPolicy
import org.bilibilifocus.android.ui.video.FocusVideoRotationPolicy
import org.bilibilifocus.android.ui.video.PhoneFullscreenRotationEffect
import org.bilibilifocus.android.ui.video.PlayerSurface
import org.bilibilifocus.android.ui.video.VideoActionBar
import org.bilibilifocus.android.ui.video.VideoDanmakuOverlay
import org.bilibilifocus.android.ui.video.VideoDanmakuStatusBanner
import org.bilibilifocus.android.ui.video.VideoEpisodeSections
import org.bilibilifocus.android.ui.video.VideoPageSection
import org.bilibilifocus.android.ui.video.VideoTitleSection
import org.bilibilifocus.android.ui.video.findActivity
import org.bilibilifocus.android.ui.video.historyPositionForRequestedPage
import org.bilibilifocus.android.ui.video.parseRequestedCid
import org.bilibilifocus.android.ui.video.parseRequestedHistoryPositionMillis
import org.bilibilifocus.android.ui.video.parseRequestedPage
import org.bilibilifocus.android.ui.video.requestedLandscapeOrientation
import org.bilibilifocus.android.ui.video.resolveActivePage
import org.bilibilifocus.android.ui.video.setSystemBarsHidden
import org.bilibilifocus.android.ui.video.VideoPlaybackOverlay
import org.bilibilifocus.android.ui.video.VideoCommentsSection
import org.bilibilifocus.core.model.FocusPlaybackPreferences
import org.bilibilifocus.core.service.VideoInfoService
import kotlinx.coroutines.flow.distinctUntilChanged

@androidx.annotation.OptIn(UnstableApi::class)
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusVideoScreen(
    url: String,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
    onOpenURL: (String) -> Unit = {},
    nativeDanmakuEnabled: Boolean = true,
    onNativeDanmakuEnabledChange: (Boolean) -> Unit = {},
    nativeSubtitleEnabled: Boolean = true,
    nativeSubtitleLanguageCode: String = "",
    onNativeSubtitleEnabledChange: (Boolean) -> Unit = {},
    onNativeSubtitleLanguageCodeChange: (String) -> Unit = {},
    playbackPreferences: FocusPlaybackPreferences = FocusPlaybackPreferences(),
    onPlaybackPreferencesChange: (FocusPlaybackPreferences) -> Unit = {},
    viewModel: FocusVideoViewModel,
    scrollState: ScrollState = rememberScrollState(),
    playbackConnection: FocusPlaybackConnection,
    playbackAccountScopeProvider: FocusPlaybackAccountScopeProvider,
    playbackProgressStore: FocusPlaybackProgressStore,
    playerSurfaceRevision: Int,
    isInPictureInPictureMode: Boolean,
    isInMultiWindowMode: Boolean = false,
) {
    val bvid = remember(url) { VideoInfoService.extractBvid(url) }
    val initialPageNumber = remember(url) { parseRequestedPage(url) }
    val initialPageCid = remember(url) { parseRequestedCid(url) }
    val initialHistoryPositionMillis = remember(url) { parseRequestedHistoryPositionMillis(url) }
    val context = LocalContext.current

    if (bvid != null) {
        LaunchedEffect(viewModel, bvid) { viewModel.loadIfNeeded(bvid) }
    }

    val state by viewModel.state.collectAsState()
    val comments by viewModel.comments.collectAsState()
    val commentState by viewModel.commentState.collectAsState()
    val subtitleState by viewModel.subtitleState.collectAsState()
    val actionError by viewModel.actionError.collectAsState()
    var galleryRequest by remember(url) { mutableStateOf<FocusImageGalleryRequest?>(null) }
    val interactionState by viewModel.interactionState.collectAsState()
    val isFullscreen by viewModel.isFullscreen.collectAsState()
    val isCompletingFullscreenExit by viewModel.isCompletingFullscreenExit.collectAsState()
    val danmakuState by viewModel.danmakuState.collectAsState()
    val loaded = state as? VideoUiState.Loaded
    val info = loaded?.info
    val configuration = LocalConfiguration.current
    val deviceType = remember(configuration.smallestScreenWidthDp) {
        FocusVideoDeviceType.fromSmallestWidth(configuration.smallestScreenWidthDp)
    }
    val isPhone = deviceType == FocusVideoDeviceType.Phone
    val isInMultiWindowModeUpdated by rememberUpdatedState(isInMultiWindowMode)
    val isInPictureInPictureModeUpdated by rememberUpdatedState(isInPictureInPictureMode)
    val deviceTypeUpdated by rememberUpdatedState(deviceType)

    val player by playbackConnection.controller.collectAsState()
    val playbackState by playbackConnection.state.collectAsState()
    var selectedPageCid by remember(url) { mutableStateOf<Long?>(null) }
    var preferredQuality by remember(url) { mutableStateOf<Int?>(null) }
    var lastPlaybackRequest by remember(url) { mutableStateOf<FocusPlaybackRequest?>(null) }
    var startNextPartFromBeginning by remember(url) { mutableStateOf<Long?>(null) }
    var playbackAccountScope by remember(url) { mutableStateOf<String?>(null) }
    var didResolvePlaybackAccountScope by remember(url) { mutableStateOf(false) }
    var videoAspectRatio by remember { mutableStateOf(playbackState.videoAspectRatio) }
    // Read this in Canvas/coroutines, not composition, so a playback frame does
    // not invalidate the entire metadata/comment screen.
    val playbackPositionMillis = remember { mutableLongStateOf(0L) }
    var fullscreenLandscapeOrientation by remember {
        mutableStateOf(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
    }
    var shouldIgnoreNextInitialOrientationAfterWindowMode by remember {
        mutableStateOf(false)
    }
    val prefersPortraitFullscreen = FocusVideoFullscreenPolicy.isPortrait(videoAspectRatio)

    LaunchedEffect(isInPictureInPictureMode, isInMultiWindowMode) {
        if (FocusVideoRotationPolicy.shouldArmInitialOrientationIgnore(
                isInPictureInPictureMode = isInPictureInPictureMode,
                isInMultiWindowMode = isInMultiWindowMode,
            )
        ) {
            shouldIgnoreNextInitialOrientationAfterWindowMode = true
        }
    }

    LaunchedEffect(info?.bvid, info?.width, info?.height) {
        videoAspectRatio = FocusVideoFullscreenPolicy.aspectRatio(
            width = info?.width ?: 0,
            height = info?.height ?: 0,
        )
    }

    val requestFullscreen = { viewModel.requestFullscreen() }
    val requestFullscreenExit = {
        if (isPhone) {
            viewModel.beginFullscreenExit()
        } else {
            viewModel.completeFullscreenExit()
        }
    }
    LaunchedEffect(info, initialPageNumber, initialPageCid) {
        val resolvedInfo = info ?: return@LaunchedEffect
        val accountScope = playbackAccountScopeProvider.currentSnapshot()?.scope
        playbackAccountScope = accountScope
        didResolvePlaybackAccountScope = true
        if (selectedPageCid != null && resolvedInfo.pages.any { it.cid == selectedPageCid }) return@LaunchedEffect
        val localResumeCid = accountScope?.let { scope ->
            playbackProgressStore.latestProgress(scope, resolvedInfo.bvid)?.cid
        }
        selectedPageCid = resolveActivePage(
            info = resolvedInfo,
            selectedCid = null,
            requestedPageNumber = initialPageNumber,
            requestedPageCid = initialPageCid,
            resumeCid = localResumeCid ?: resolvedInfo.lastPlaybackCid,
        )?.cid
    }

    val activePage = resolveActivePage(
        info = info,
        selectedCid = selectedPageCid,
        requestedPageNumber = initialPageNumber,
        requestedPageCid = initialPageCid,
        resumeCid = playbackAccountScope?.let { scope ->
            playbackProgressStore.latestProgress(scope, info?.bvid.orEmpty())?.cid
        }
            ?: info?.lastPlaybackCid,
    )
    val requestedHistoryPositionMillis = historyPositionForRequestedPage(
        positionMillis = initialHistoryPositionMillis,
        requestedPageNumber = initialPageNumber,
        requestedPageCid = initialPageCid,
        activePageNumber = activePage?.pageNumber ?: 0,
        activePageCid = activePage?.cid ?: 0L,
    )

    LaunchedEffect(player) {
        while (true) {
            withFrameNanos { }
            playbackPositionMillis.longValue = player?.currentPosition?.coerceAtLeast(0) ?: 0
        }
    }

    LaunchedEffect(info?.aid, activePage?.cid, nativeDanmakuEnabled) {
        val resolvedInfo = info ?: return@LaunchedEffect
        val resolvedPage = activePage ?: return@LaunchedEffect
        viewModel.configureDanmaku(
            aid = resolvedInfo.aid,
            cid = resolvedPage.cid,
            durationSeconds = resolvedPage.duration,
            enabled = nativeDanmakuEnabled,
            playbackPositionMillis = 0,
        )
    }

    LaunchedEffect(viewModel, activePage?.cid, nativeDanmakuEnabled) {
        if (nativeDanmakuEnabled) {
            snapshotFlow { playbackPositionMillis.longValue / 1_000 }
                .distinctUntilChanged()
                .collect { viewModel.updateDanmakuPosition(playbackPositionMillis.longValue) }
        }
    }

    LaunchedEffect(player, playbackPreferences.preferredRate) { player?.setPlaybackSpeed(playbackPreferences.preferredRate) }
    LaunchedEffect(info?.aid, activePage?.cid, nativeSubtitleEnabled, nativeSubtitleLanguageCode) {
        val aid = info?.aid ?: return@LaunchedEffect
        val cid = activePage?.cid ?: return@LaunchedEffect
        viewModel.configureSubtitles(aid, cid, nativeSubtitleEnabled, nativeSubtitleLanguageCode)
    }
    LaunchedEffect(playbackState.hasEnded, playbackState.mediaId, playbackPreferences.autoPlayNextPart) {
        val video = info ?: return@LaunchedEffect
        val page = activePage ?: return@LaunchedEffect
        if (playbackState.hasEnded && playbackPreferences.autoPlayNextPart &&
            playbackState.mediaId == "${video.bvid}:${page.cid}:${playbackAccountScope.orEmpty()}") {
            val next = video.pages.getOrNull(video.pages.indexOfFirst { it.cid == page.cid } + 1)
            if (next != null && next.cid != page.cid) {
                startNextPartFromBeginning = next.cid
                selectedPageCid = next.cid
            }
        }
    }

    LaunchedEffect(
        info?.bvid,
        activePage?.cid,
        playbackAccountScope,
        didResolvePlaybackAccountScope,
        preferredQuality,
    ) {
        if (!didResolvePlaybackAccountScope) return@LaunchedEffect
        val resolvedInfo = info ?: return@LaunchedEffect
        val resolvedPage = activePage ?: return@LaunchedEffect
        val localProgress = playbackAccountScope?.let { scope ->
            playbackProgressStore
                .progress(scope, resolvedInfo.bvid, resolvedPage.cid)
                ?.positionMillis
        }
        val serverProgress = resolvedInfo.lastPlaybackPositionMillis
            .takeIf { resolvedInfo.lastPlaybackCid == resolvedPage.cid }
        val resumedPositionMillis = FocusPlaybackResumePolicy.resolvePositionMillis(
            localPositionMillis = localProgress,
            serverPositionMillis = requestedHistoryPositionMillis ?: serverProgress,
            durationMillis = resolvedPage.duration.coerceAtLeast(0) * 1_000,
        )
        val sameContent = playbackState.mediaId == "${resolvedInfo.bvid}:${resolvedPage.cid}:${playbackAccountScope.orEmpty()}"
        val request = FocusPlaybackRequest(
                bvid = resolvedInfo.bvid,
                aid = resolvedInfo.aid,
                cid = resolvedPage.cid,
                title = if (resolvedInfo.pages.size > 1 && resolvedPage.title.isNotBlank()) {
                    "${resolvedInfo.title} · ${resolvedPage.title}"
                } else {
                    resolvedInfo.title
                },
                author = resolvedInfo.author.name,
                artworkUrl = resolvedInfo.coverURL,
                durationSeconds = resolvedPage.duration,
                accountScope = playbackAccountScope,
                startPositionMillis = when { sameContent -> player?.currentPosition ?: resumedPositionMillis; startNextPartFromBeginning == resolvedPage.cid -> 0L; else -> resumedPositionMillis },
                autoPlay = if (sameContent) player?.playWhenReady ?: true else true,
                preferredQuality = preferredQuality,
                playbackSpeed = player?.playbackParameters?.speed ?: playbackPreferences.preferredRate,
            )
        lastPlaybackRequest = request
        playbackConnection.load(request)
        if (startNextPartFromBeginning == resolvedPage.cid) startNextPartFromBeginning = null
    }

    val renderPlaybackControls: @Composable () -> Unit = {
        VideoPlaybackOverlay(
            player = player, state = playbackState, positionMillis = { playbackPositionMillis.longValue },
            title = info?.title.orEmpty(),
            preferences = playbackPreferences, onPreferencesChange = onPlaybackPreferencesChange,
            preferredQuality = preferredQuality, onQualityChange = { if (it != preferredQuality) preferredQuality = it },
            danmakuEnabled = nativeDanmakuEnabled, onDanmakuEnabledChange = { enabled ->
                onNativeDanmakuEnabledChange(enabled); viewModel.setDanmakuEnabled(enabled, playbackPositionMillis.longValue)
            },
            subtitleState = subtitleState, subtitleEnabled = nativeSubtitleEnabled,
            onSubtitleEnabledChange = onNativeSubtitleEnabledChange, onSubtitleLanguageChange = onNativeSubtitleLanguageCodeChange,
            onRetrySubtitle = { if (info != null && activePage != null) viewModel.configureSubtitles(info.aid, activePage.cid, nativeSubtitleEnabled, nativeSubtitleLanguageCode) },
            onRetryPlayback = {
                lastPlaybackRequest?.let { request ->
                    playbackConnection.load(request.copy(startPositionMillis = player?.currentPosition ?: request.startPositionMillis,
                        autoPlay = player?.playWhenReady ?: request.autoPlay, playbackSpeed = player?.playbackParameters?.speed ?: playbackPreferences.preferredRate, forceReload = true))
                }
            },
            onSleepTimer = playbackConnection::setSleepTimer,
            isFullscreen = isFullscreen, onToggleFullscreen = if (isFullscreen) requestFullscreenExit else requestFullscreen,
            modifier = Modifier.fillMaxSize(),
        )
    }

    LaunchedEffect(playbackState.videoAspectRatio, info?.width, info?.height) {
        videoAspectRatio = playbackState.videoAspectRatio
            .takeIf { it.isFinite() && it > 0f }
            ?: FocusVideoFullscreenPolicy.aspectRatio(
                width = info?.width ?: 0,
                height = info?.height ?: 0,
            )
    }

    PhoneFullscreenRotationEffect(
        enabled = FocusVideoRotationPolicy.shouldObservePhysicalOrientation(
            isPhone = isPhone,
            isVideoLoaded = state is VideoUiState.Loaded,
            prefersPortraitFullscreen = prefersPortraitFullscreen,
            isInPictureInPictureMode = isInPictureInPictureMode,
            isInMultiWindowMode = isInMultiWindowMode,
        ),
        ignoreInitialOrientation = shouldIgnoreNextInitialOrientationAfterWindowMode,
        onInitialOrientationConsumed = {
            shouldIgnoreNextInitialOrientationAfterWindowMode = false
        },
        onLandscape = { orientation ->
            if (!isInMultiWindowMode) {
                val requestedOrientation = orientation.requestedLandscapeOrientation()
                fullscreenLandscapeOrientation = requestedOrientation
                context.findActivity()?.requestedOrientation = requestedOrientation
                viewModel.requestFullscreen()
            }
        },
        onPortrait = {
            if (!isInMultiWindowMode) viewModel.beginFullscreenExit()
        },
    )

    LaunchedEffect(
        isPhone,
        isCompletingFullscreenExit,
        configuration.orientation,
        isInPictureInPictureMode,
        isInMultiWindowMode,
    ) {
        if (FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = isPhone,
                isCompletingFullscreenExit = isCompletingFullscreenExit,
                configurationOrientation = configuration.orientation,
                isInPictureInPictureMode = isInPictureInPictureMode,
                isInMultiWindowMode = isInMultiWindowMode,
            )
        ) {
            // 与 iOS 一致：界面几何稳定为竖屏后再撤下全屏层，避免先闪回详情页。
            withFrameNanos { }
            withFrameNanos { }
            viewModel.completeFullscreenExit()
        }
    }

    BackHandler(enabled = isFullscreen && !isInPictureInPictureMode) { requestFullscreenExit() }
    DisposableEffect(
        deviceType,
        isFullscreen,
        isCompletingFullscreenExit,
        prefersPortraitFullscreen,
        fullscreenLandscapeOrientation,
        configuration.orientation,
        isInPictureInPictureMode,
        isInMultiWindowMode,
    ) {
        val activity = context.findActivity()
        if (FocusVideoRotationPolicy.shouldApplyActivityOrientation(
                isInPictureInPictureMode = isInPictureInPictureMode,
                isInMultiWindowMode = isInMultiWindowMode,
            )
        ) {
            activity?.requestedOrientation = when {
                deviceType == FocusVideoDeviceType.Tablet -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                isCompletingFullscreenExit -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                isFullscreen && prefersPortraitFullscreen -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                isFullscreen -> fullscreenLandscapeOrientation
                else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            setSystemBarsHidden(activity, isFullscreen)
        } else if (isInMultiWindowMode) {
            setSystemBarsHidden(activity, false)
        }
        onDispose { }
    }
    DisposableEffect(Unit) {
        onDispose {
            val activity = context.findActivity()
            if (!isInMultiWindowModeUpdated && !isInPictureInPictureModeUpdated) {
                activity?.requestedOrientation = if (deviceTypeUpdated == FocusVideoDeviceType.Phone) {
                    ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                } else {
                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
            }
            setSystemBarsHidden(activity, false)
        }
    }

    if (!FocusPictureInPicturePolicy.shouldRenderEmbeddedPlayerSurface(isInPictureInPictureMode)) {
        // MainActivity owns the only PlayerView while in PiP. Keeping the inline
        // or fullscreen SurfaceView alive here makes large-screen window scaling
        // display the old page-sized surface in the center of the PiP window.
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black),
        )
        return
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = {
                        Text(
                            info?.title ?: "视频",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleMedium,
                        )
                    },
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
            if (bvid == null) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("无法识别视频链接", style = MaterialTheme.typography.bodyMedium)
                        Text(url, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else when (val currentState = state) {
                VideoUiState.Loading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                }

                is VideoUiState.Error -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text(currentState.message, style = MaterialTheme.typography.bodyMedium)
                            androidx.compose.material3.TextButton(onClick = { viewModel.load(bvid) }) { Text("重试") }
                        }
                    }
                }

                is VideoUiState.Loaded -> {
                    FocusVideoDetailLayout(
                        videoAspectRatio = videoAspectRatio.takeIf { it.isFinite() && it > 0f } ?: (16f / 9f),
                        scrollState = scrollState,
                        modifier = Modifier.padding(innerPadding),
                        playerContent = {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .background(Color.Black),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (!isFullscreen) {
                                    PlayerSurface(
                                        player = player,
                                        showController = false,
                                        onToggleFullscreen = requestFullscreen,
                                        attachmentKey = playerSurfaceRevision,
                                        modifier = Modifier.fillMaxSize(),
                                    )
                                    VideoDanmakuOverlay(
                                        state = danmakuState,
                                        enabled = nativeDanmakuEnabled,
                                        playbackPositionMillis = { playbackPositionMillis.longValue },
                                        modifier = Modifier.fillMaxSize(),
                                        preferences = playbackPreferences,
                                    )
                                    VideoDanmakuStatusBanner(
                                        state = danmakuState,
                                        enabled = nativeDanmakuEnabled,
                                        onRetry = { viewModel.retryDanmaku(playbackPositionMillis.longValue) },
                                        modifier = Modifier.align(Alignment.TopCenter),
                                    )
                                    renderPlaybackControls()
                                }
                            }
                        },
                        detailContent = {
                            Column(
                                modifier = Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp),
                                verticalArrangement = Arrangement.spacedBy(16.dp),
                            ) {
                                VideoTitleSection(currentState.info)

                                if (currentState.info.tags.isNotEmpty()) {
                                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        items(currentState.info.tags, key = { it }) { tag ->
                                            FilterChip(
                                                selected = false,
                                                onClick = {},
                                                label = { Text(tag, style = MaterialTheme.typography.labelSmall) },
                                                shape = RoundedCornerShape(8.dp),
                                                colors = FilterChipDefaults.filterChipColors(
                                                    containerColor = MaterialTheme.colorScheme.secondaryContainer,
                                                    labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                                                ),
                                            )
                                        }
                                    }
                                }

                                VideoActionBar(
                                    interactionState = interactionState,
                                    info = currentState.info,
                                    onToggleLike = { viewModel.toggleLike() },
                                    onCoin = { viewModel.coin() },
                                    onToggleFavorite = { viewModel.toggleFavorite() },
                                )

                                if (currentState.info.author.mid > 0) {
                                    AuthorCard(
                                        info = currentState.info,
                                        onClick = { onOpenUser(currentState.info.author.mid) },
                                    )
                                }

                                if (currentState.info.pages.size > 1) {
                                    VideoPageSection(
                                        pages = currentState.info.pages,
                                        selectedCid = activePage?.cid,
                                        onSelect = { page -> selectedPageCid = page.cid },
                                    )
                                }

                                if (currentState.info.episodeGroups.isNotEmpty()) {
                                    VideoEpisodeSections(
                                        groups = currentState.info.episodeGroups,
                                        currentBvid = currentState.info.bvid,
                                        currentCid = activePage?.cid ?: currentState.info.cid,
                                        onOpenVideo = onOpenVideo,
                                    )
                                }

                                if (currentState.info.description.isNotBlank()) {
                                    ExpandableDescription(currentState.info.description)
                                }

                                VideoCommentsSection(viewModel, comments, commentState, onOpenURL) { images, index ->
                                    galleryRequest = commentImageGalleryRequest(images, index, "https://www.bilibili.com/video/${currentState.info.bvid}")
                                }
                            }

                            Spacer(modifier = Modifier.height(104.dp))
                        },
                    )
                }
            }
        }

        if (isFullscreen) {
            if (isPhone) {
                BoxWithConstraints(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    val containerAspectRatio = maxWidth.value / maxHeight.value
                    val fullscreenPlayerModifier = if (
                        FocusVideoFullscreenPolicy.shouldFitToWidth(
                            containerAspectRatio = containerAspectRatio,
                            videoAspectRatio = videoAspectRatio,
                        )
                    ) {
                        Modifier
                            .fillMaxWidth()
                            .aspectRatio(videoAspectRatio)
                    } else {
                        Modifier
                            .fillMaxHeight()
                            .aspectRatio(videoAspectRatio)
                    }
                    PlayerSurface(
                        player = player,
                        showController = false,
                        onToggleFullscreen = requestFullscreenExit,
                        attachmentKey = playerSurfaceRevision,
                        modifier = fullscreenPlayerModifier,
                    )
                    VideoDanmakuOverlay(
                        state = danmakuState,
                        enabled = nativeDanmakuEnabled,
                        playbackPositionMillis = { playbackPositionMillis.longValue },
                        modifier = Modifier.fillMaxSize(),
                        preferences = playbackPreferences,
                    )
                    VideoDanmakuStatusBanner(
                        state = danmakuState,
                        enabled = nativeDanmakuEnabled,
                        onRetry = { viewModel.retryDanmaku(playbackPositionMillis.longValue) },
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp),
                    )
                    renderPlaybackControls()
                }
            } else {
                Dialog(
                    onDismissRequest = requestFullscreenExit,
                    properties = DialogProperties(
                        usePlatformDefaultWidth = false,
                        dismissOnBackPress = true,
                        dismissOnClickOutside = false,
                        decorFitsSystemWindows = false,
                    ),
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black),
                        contentAlignment = Alignment.Center,
                    ) {
                        PlayerSurface(
                            player = player,
                            showController = false,
                            onToggleFullscreen = requestFullscreenExit,
                            attachmentKey = playerSurfaceRevision,
                            modifier = Modifier.fillMaxSize(),
                        )
                        VideoDanmakuOverlay(
                            state = danmakuState,
                            enabled = nativeDanmakuEnabled,
                            playbackPositionMillis = { playbackPositionMillis.longValue },
                            modifier = Modifier.fillMaxSize(),
                            preferences = playbackPreferences,
                        )
                        VideoDanmakuStatusBanner(
                            state = danmakuState,
                            enabled = nativeDanmakuEnabled,
                            onRetry = { viewModel.retryDanmaku(playbackPositionMillis.longValue) },
                            modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp),
                        )
                        renderPlaybackControls()
                    }
                }
            }
        }

        galleryRequest?.let { request ->
            FocusImageGallery(request = request, onDismiss = { galleryRequest = null })
        }
        actionError?.let { message ->
            androidx.compose.material3.AlertDialog(
                onDismissRequest = viewModel::dismissActionError,
                title = { Text("操作未完成") }, text = { Text(message) },
                confirmButton = { androidx.compose.material3.TextButton(onClick = viewModel::dismissActionError) { Text("知道了") } },
            )
        }
    }
}
