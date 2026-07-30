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
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.runtime.setValue
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
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusPictureInPicturePolicy
import org.bilibilifocus.android.FocusVideoViewModel
import org.bilibilifocus.android.VideoUiState
import org.bilibilifocus.android.playback.FocusPlaybackAccountScopeProvider
import org.bilibilifocus.android.playback.FocusPlaybackConnection
import org.bilibilifocus.android.playback.FocusPlaybackProgressStore
import org.bilibilifocus.android.playback.FocusPlaybackRequest
import org.bilibilifocus.android.playback.FocusPlaybackResumePolicy
import org.bilibilifocus.android.ui.video.AuthorCard
import org.bilibilifocus.android.ui.video.CommentItem
import org.bilibilifocus.android.ui.video.DanmakuFullscreenButton
import org.bilibilifocus.android.ui.video.ExpandableDescription
import org.bilibilifocus.android.ui.video.FocusVideoDeviceType
import org.bilibilifocus.android.ui.video.FocusVideoFullscreenPolicy
import org.bilibilifocus.android.ui.video.FocusVideoRotationPolicy
import org.bilibilifocus.android.ui.video.PhoneFullscreenRotationEffect
import org.bilibilifocus.android.ui.video.PlayerSurface
import org.bilibilifocus.android.ui.video.VideoActionBar
import org.bilibilifocus.android.ui.video.VideoControlDock
import org.bilibilifocus.android.ui.video.VideoDanmakuOverlay
import org.bilibilifocus.android.ui.video.VideoDanmakuStatusBanner
import org.bilibilifocus.android.ui.video.VideoEpisodeSections
import org.bilibilifocus.android.ui.video.VideoPageSection
import org.bilibilifocus.android.ui.video.VideoTitleSection
import org.bilibilifocus.android.ui.video.findActivity
import org.bilibilifocus.android.ui.video.nextSpeed
import org.bilibilifocus.android.ui.video.parseRequestedCid
import org.bilibilifocus.android.ui.video.parseRequestedPage
import org.bilibilifocus.android.ui.video.requestedLandscapeOrientation
import org.bilibilifocus.android.ui.video.resolveActivePage
import org.bilibilifocus.android.ui.video.setSystemBarsHidden
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.VideoActionService
import org.bilibilifocus.core.service.VideoInfoService

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
    viewModel: FocusVideoViewModel? = null,
    scrollState: ScrollState = rememberScrollState(),
    playbackConnection: FocusPlaybackConnection,
    playbackAccountScopeProvider: FocusPlaybackAccountScopeProvider,
    playbackProgressStore: FocusPlaybackProgressStore,
    playerSurfaceRevision: Int,
    isInPictureInPictureMode: Boolean,
) {
    val bvid = remember(url) { VideoInfoService.extractBvid(url) }
    val initialPageNumber = remember(url) { parseRequestedPage(url) }
    val initialPageCid = remember(url) { parseRequestedCid(url) }
    val context = LocalContext.current

    val resolvedViewModel = viewModel ?: remember(url) {
        FocusVideoViewModel(
            service = VideoInfoService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            ),
            actionService = VideoActionService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            ),
        )
    }

    if (bvid != null) {
        LaunchedEffect(bvid) { resolvedViewModel.loadIfNeeded(bvid) }
    }

    val state by resolvedViewModel.state.collectAsState()
    val comments by resolvedViewModel.comments.collectAsState()
    val interactionState by resolvedViewModel.interactionState.collectAsState()
    val isFullscreen by resolvedViewModel.isFullscreen.collectAsState()
    val isCompletingFullscreenExit by resolvedViewModel.isCompletingFullscreenExit.collectAsState()
    val danmakuState by resolvedViewModel.danmakuState.collectAsState()
    val loaded = state as? VideoUiState.Loaded
    val info = loaded?.info
    val configuration = LocalConfiguration.current
    val deviceType = remember(configuration.smallestScreenWidthDp) {
        FocusVideoDeviceType.fromSmallestWidth(configuration.smallestScreenWidthDp)
    }
    val isPhone = deviceType == FocusVideoDeviceType.Phone
    val isNarrowLayout = configuration.screenWidthDp < 840

    val player by playbackConnection.controller.collectAsState()
    val playbackState by playbackConnection.state.collectAsState()
    val playerError = playbackState.errorMessage
    val isPlaying = playbackState.isPlaying
    val playbackSpeed = playbackState.playbackSpeed
    var selectedPageCid by remember(url) { mutableStateOf<Long?>(null) }
    var playbackAccountScope by remember(url) { mutableStateOf<String?>(null) }
    var didResolvePlaybackAccountScope by remember(url) { mutableStateOf(false) }
    var videoAspectRatio by remember { mutableStateOf(playbackState.videoAspectRatio) }
    var playbackPositionMillis by remember { mutableLongStateOf(0L) }
    var fullscreenLandscapeOrientation by remember {
        mutableStateOf(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
    }
    var shouldIgnoreInitialOrientationAfterPictureInPicture by remember {
        mutableStateOf(false)
    }
    val prefersPortraitFullscreen = FocusVideoFullscreenPolicy.isPortrait(videoAspectRatio)

    LaunchedEffect(isInPictureInPictureMode) {
        if (isInPictureInPictureMode) {
            shouldIgnoreInitialOrientationAfterPictureInPicture = true
        }
    }

    LaunchedEffect(info?.bvid, info?.width, info?.height) {
        videoAspectRatio = FocusVideoFullscreenPolicy.aspectRatio(
            width = info?.width ?: 0,
            height = info?.height ?: 0,
        )
    }

    val requestFullscreen = { resolvedViewModel.requestFullscreen() }
    val requestFullscreenExit = {
        if (isPhone) {
            resolvedViewModel.beginFullscreenExit()
        } else {
            resolvedViewModel.completeFullscreenExit()
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

    LaunchedEffect(player) {
        while (true) {
            withFrameNanos { }
            playbackPositionMillis = player?.currentPosition?.coerceAtLeast(0) ?: 0
        }
    }

    LaunchedEffect(info?.aid, activePage?.cid, nativeDanmakuEnabled) {
        val resolvedInfo = info ?: return@LaunchedEffect
        val resolvedPage = activePage ?: return@LaunchedEffect
        resolvedViewModel.configureDanmaku(
            aid = resolvedInfo.aid,
            cid = resolvedPage.cid,
            durationSeconds = resolvedPage.duration,
            enabled = nativeDanmakuEnabled,
            playbackPositionMillis = 0,
        )
    }

    LaunchedEffect(playbackPositionMillis / 1_000, activePage?.cid, nativeDanmakuEnabled) {
        if (nativeDanmakuEnabled) {
            resolvedViewModel.updateDanmakuPosition(playbackPositionMillis)
        }
    }

    LaunchedEffect(
        info?.bvid,
        activePage?.cid,
        playbackAccountScope,
        didResolvePlaybackAccountScope,
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
        val startPositionMillis = FocusPlaybackResumePolicy.resolvePositionMillis(
            localPositionMillis = localProgress,
            serverPositionMillis = serverProgress,
            durationMillis = resolvedPage.duration.coerceAtLeast(0) * 1_000,
        )
        playbackConnection.load(
            FocusPlaybackRequest(
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
                startPositionMillis = startPositionMillis,
                autoPlay = true,
            ),
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
        ),
        ignoreInitialOrientation = shouldIgnoreInitialOrientationAfterPictureInPicture,
        onInitialOrientationConsumed = {
            shouldIgnoreInitialOrientationAfterPictureInPicture = false
        },
        onLandscape = { orientation ->
            val requestedOrientation = orientation.requestedLandscapeOrientation()
            fullscreenLandscapeOrientation = requestedOrientation
            context.findActivity()?.requestedOrientation = requestedOrientation
            resolvedViewModel.requestFullscreen()
        },
        onPortrait = { resolvedViewModel.beginFullscreenExit() },
    )

    LaunchedEffect(
        isPhone,
        isCompletingFullscreenExit,
        configuration.orientation,
        isInPictureInPictureMode,
    ) {
        if (FocusVideoRotationPolicy.shouldCompleteFullscreenExit(
                isPhone = isPhone,
                isCompletingFullscreenExit = isCompletingFullscreenExit,
                configurationOrientation = configuration.orientation,
                isInPictureInPictureMode = isInPictureInPictureMode,
            )
        ) {
            // 与 iOS 一致：界面几何稳定为竖屏后再撤下全屏层，避免先闪回详情页。
            withFrameNanos { }
            withFrameNanos { }
            resolvedViewModel.completeFullscreenExit()
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
    ) {
        val activity = context.findActivity()
        if (FocusVideoRotationPolicy.shouldApplyActivityOrientation(isInPictureInPictureMode)) {
            activity?.requestedOrientation = when {
                deviceType == FocusVideoDeviceType.Tablet -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                isCompletingFullscreenExit -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                isFullscreen && prefersPortraitFullscreen -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                isFullscreen -> fullscreenLandscapeOrientation
                else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            setSystemBarsHidden(activity, isFullscreen)
        }
        onDispose { }
    }
    DisposableEffect(deviceType) {
        onDispose {
            val activity = context.findActivity()
            activity?.requestedOrientation = if (deviceType == FocusVideoDeviceType.Phone) {
                ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            } else {
                ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
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
                        Text(currentState.message, style = MaterialTheme.typography.bodyMedium)
                    }
                }

                is VideoUiState.Loaded -> {
                    BoxWithConstraints(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                    ) {
                        val resolvedAspectRatio = when {
                            videoAspectRatio.isFinite() && videoAspectRatio > 0f -> videoAspectRatio
                            else -> 16f / 9f
                        }
                        val portraitCandidate = resolvedAspectRatio < 1f
                        val playerHeight = when {
                            portraitCandidate -> {
                                minOf(maxWidth / resolvedAspectRatio, maxHeight * 0.74f)
                            }
                            else -> {
                                minOf(maxWidth / resolvedAspectRatio, maxHeight * if (isNarrowLayout) 0.46f else 0.58f)
                            }
                        }
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .verticalScroll(scrollState),
                        ) {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(playerHeight)
                                    .background(Color.Black),
                                contentAlignment = Alignment.Center,
                            ) {
                                if (!isFullscreen) {
                                    if (isPhone) {
                                        PlayerSurface(
                                            player = player,
                                            showController = false,
                                            onToggleFullscreen = requestFullscreen,
                                            attachmentKey = playerSurfaceRevision,
                                            modifier = Modifier.fillMaxSize(),
                                        )
                                    } else {
                                        PlayerSurface(
                                            player = player,
                                            showController = false,
                                            onToggleFullscreen = requestFullscreen,
                                            attachmentKey = playerSurfaceRevision,
                                            modifier = Modifier.fillMaxSize(),
                                        )
                                    }
                                    VideoDanmakuOverlay(
                                        state = danmakuState,
                                        enabled = nativeDanmakuEnabled,
                                        playbackPositionMillis = playbackPositionMillis,
                                        modifier = Modifier.fillMaxSize(),
                                    )
                                    VideoDanmakuStatusBanner(
                                        state = danmakuState,
                                        enabled = nativeDanmakuEnabled,
                                        onRetry = { resolvedViewModel.retryDanmaku(playbackPositionMillis) },
                                        modifier = Modifier.align(Alignment.TopCenter),
                                    )
                                }
                                playerError?.let { message ->
                                    if (!isFullscreen) {
                                        Text(message, color = Color.White, style = MaterialTheme.typography.bodySmall)
                                    }
                                }
                            }

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
                                    onToggleLike = { resolvedViewModel.toggleLike() },
                                    onCoin = { resolvedViewModel.coin() },
                                    onToggleFavorite = { resolvedViewModel.toggleFavorite() },
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

                                if (comments.isNotEmpty()) {
                                    Text(
                                        "评论 (${comments.size})",
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                    comments.forEach { comment ->
                                        CommentItem(comment, onOpenURL = onOpenURL)
                                    }
                                }
                            }

                            Spacer(modifier = Modifier.height(104.dp))
                        }
                    }
                }
            }
        }

        if (!isFullscreen && state is VideoUiState.Loaded) {
            VideoControlDock(
                isPlaying = isPlaying,
                playbackSpeed = playbackSpeed,
                onTogglePlay = {
                    player?.let { if (it.isPlaying) it.pause() else it.play() }
                },
                onChangeSpeed = {
                    val next = nextSpeed(playbackSpeed)
                    player?.setPlaybackSpeed(next)
                },
                danmakuEnabled = nativeDanmakuEnabled,
                onToggleDanmaku = {
                    val enabled = !nativeDanmakuEnabled
                    onNativeDanmakuEnabledChange(enabled)
                    resolvedViewModel.setDanmakuEnabled(enabled, playbackPositionMillis)
                },
                onToggleFullscreen = requestFullscreen,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
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
                        showController = true,
                        onToggleFullscreen = requestFullscreenExit,
                        attachmentKey = playerSurfaceRevision,
                        modifier = fullscreenPlayerModifier,
                    )
                    VideoDanmakuOverlay(
                        state = danmakuState,
                        enabled = nativeDanmakuEnabled,
                        playbackPositionMillis = playbackPositionMillis,
                        modifier = Modifier.fillMaxSize(),
                    )
                    VideoDanmakuStatusBanner(
                        state = danmakuState,
                        enabled = nativeDanmakuEnabled,
                        onRetry = { resolvedViewModel.retryDanmaku(playbackPositionMillis) },
                        modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp),
                    )
                    DanmakuFullscreenButton(
                        enabled = nativeDanmakuEnabled,
                        onClick = {
                            val enabled = !nativeDanmakuEnabled
                            onNativeDanmakuEnabledChange(enabled)
                            resolvedViewModel.setDanmakuEnabled(enabled, playbackPositionMillis)
                        },
                        modifier = Modifier.align(Alignment.TopEnd).padding(18.dp),
                    )
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
                            showController = true,
                            onToggleFullscreen = requestFullscreenExit,
                            attachmentKey = playerSurfaceRevision,
                            modifier = Modifier.fillMaxSize(),
                        )
                        VideoDanmakuOverlay(
                            state = danmakuState,
                            enabled = nativeDanmakuEnabled,
                            playbackPositionMillis = playbackPositionMillis,
                            modifier = Modifier.fillMaxSize(),
                        )
                        VideoDanmakuStatusBanner(
                            state = danmakuState,
                            enabled = nativeDanmakuEnabled,
                            onRetry = { resolvedViewModel.retryDanmaku(playbackPositionMillis) },
                            modifier = Modifier.align(Alignment.TopCenter).padding(top = 18.dp),
                        )
                        DanmakuFullscreenButton(
                            enabled = nativeDanmakuEnabled,
                            onClick = {
                                val enabled = !nativeDanmakuEnabled
                                onNativeDanmakuEnabledChange(enabled)
                                resolvedViewModel.setDanmakuEnabled(enabled, playbackPositionMillis)
                            },
                            modifier = Modifier.align(Alignment.TopEnd).padding(18.dp),
                        )
                    }
                }
            }
        }
    }
}
