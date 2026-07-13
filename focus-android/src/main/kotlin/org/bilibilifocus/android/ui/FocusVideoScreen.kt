package org.bilibilifocus.android.ui

import android.content.res.Configuration
import android.content.pm.ActivityInfo
import android.view.OrientationEventListener
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.res.painterResource
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.OpenInFull
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.Speed
import androidx.compose.material.icons.outlined.Chat
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusVideoViewModel
import org.bilibilifocus.android.R
import org.bilibilifocus.android.VideoDanmakuLoadStatus
import org.bilibilifocus.android.VideoDanmakuUiState
import org.bilibilifocus.android.VideoUiState
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuMode
import org.bilibilifocus.core.model.VideoEpisode
import org.bilibilifocus.core.model.VideoEpisodeGroup
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState
import org.bilibilifocus.core.model.VideoPage
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.PlayUrlService
import org.bilibilifocus.core.service.VideoActionService
import org.bilibilifocus.core.service.VideoInfoService

private val SPEEDS = floatArrayOf(1f, 1.25f, 1.5f, 2f)
private const val DANMAKU_DISPLAY_MILLIS = 5_000L

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

    val exoPlayer = remember { ExoPlayer.Builder(context).build() }
    val playUrlService = remember {
        PlayUrlService(cookieProvider = AndroidCookieProvider(), httpClient = KtorHttpClient())
    }
    var playerError by remember { mutableStateOf<String?>(null) }
    var isPlaying by remember { mutableStateOf(false) }
    var playbackSpeed by remember { mutableStateOf(1f) }
    var selectedPageCid by remember(url) { mutableStateOf<Long?>(null) }
    var videoAspectRatio by remember { mutableStateOf(16f / 9f) }
    var playbackPositionMillis by remember { mutableLongStateOf(0L) }
    var fullscreenLandscapeOrientation by remember {
        mutableStateOf(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE)
    }
    val prefersPortraitFullscreen = FocusVideoFullscreenPolicy.isPortrait(videoAspectRatio)

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
        if (selectedPageCid != null && resolvedInfo.pages.any { it.cid == selectedPageCid }) return@LaunchedEffect
        selectedPageCid = resolveActivePage(
            info = resolvedInfo,
            selectedCid = null,
            requestedPageNumber = initialPageNumber,
            requestedPageCid = initialPageCid,
        )?.cid
    }

    val activePage = resolveActivePage(
        info = info,
        selectedCid = selectedPageCid,
        requestedPageNumber = initialPageNumber,
        requestedPageCid = initialPageCid,
    )

    val reportCurrentWatchHistory by rememberUpdatedState(
        newValue = { force: Boolean ->
            val currentInfo = info
            val currentPage = activePage
            if (currentInfo != null && currentPage != null) {
                resolvedViewModel.reportWatchHistory(
                    aid = currentInfo.aid,
                    cid = currentPage.cid,
                    progressSeconds = exoPlayer.currentPosition.coerceAtLeast(0) / 1_000,
                    force = force,
                )
            }
        },
    )

    DisposableEffect(info?.aid, activePage?.cid, exoPlayer) {
        val reportAid = info?.aid
        val reportCid = activePage?.cid
        onDispose {
            if (reportAid != null && reportCid != null) {
                resolvedViewModel.reportWatchHistory(
                    aid = reportAid,
                    cid = reportCid,
                    progressSeconds = exoPlayer.currentPosition.coerceAtLeast(0) / 1_000,
                    force = true,
                )
            }
        }
    }

    LaunchedEffect(exoPlayer) {
        while (true) {
            withFrameNanos { }
            playbackPositionMillis = exoPlayer.currentPosition.coerceAtLeast(0)
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

    LaunchedEffect(info?.aid, activePage?.cid, isPlaying) {
        val resolvedInfo = info ?: return@LaunchedEffect
        val resolvedPage = activePage ?: return@LaunchedEffect
        if (!isPlaying) return@LaunchedEffect
        while (true) {
            delay(15_000)
            resolvedViewModel.reportWatchHistory(
                aid = resolvedInfo.aid,
                cid = resolvedPage.cid,
                progressSeconds = exoPlayer.currentPosition.coerceAtLeast(0) / 1_000,
                force = false,
            )
        }
    }

    LaunchedEffect(info?.bvid, activePage?.cid) {
        val resolvedInfo = info ?: return@LaunchedEffect
        val resolvedPage = activePage ?: return@LaunchedEffect
        playerError = null
        try {
            val result = playUrlService.fetchPlayUrl(resolvedInfo.bvid, resolvedPage.cid)
            val headers = buildMap {
                put("Referer", result.referer)
                if (result.cookie.isNotEmpty()) put("Cookie", result.cookie)
            }
            val httpFactory = DefaultHttpDataSource.Factory()
                .setUserAgent(result.userAgent)
                .setAllowCrossProtocolRedirects(true)
                .setDefaultRequestProperties(headers)
            val videoSource = ProgressiveMediaSource.Factory(httpFactory)
                .createMediaSource(MediaItem.fromUri(result.videoUrl))
            val source = result.audioUrl?.let { audioUrl ->
                val audioSource = ProgressiveMediaSource.Factory(httpFactory)
                    .createMediaSource(MediaItem.fromUri(audioUrl))
                MergingMediaSource(videoSource, audioSource)
            } ?: videoSource
            exoPlayer.setMediaSource(source)
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
            exoPlayer.playbackParameters = PlaybackParameters(playbackSpeed)
            resolvedViewModel.reportWatchHistory(
                aid = resolvedInfo.aid,
                cid = resolvedPage.cid,
                progressSeconds = 0,
                force = true,
            )
        } catch (e: Exception) {
            playerError = e.message ?: "视频加载失败"
        }
    }

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
                if (!playing) reportCurrentWatchHistory(true)
            }

            override fun onPlaybackParametersChanged(playbackParameters: PlaybackParameters) {
                playbackSpeed = playbackParameters.speed
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                val width = videoSize.width
                val height = videoSize.height
                if (width > 0 && height > 0) {
                    val ratio = (width * videoSize.pixelWidthHeightRatio) / height.toFloat()
                    if (ratio.isFinite() && ratio > 0f) {
                        videoAspectRatio = ratio
                    }
                }
            }
        }
        exoPlayer.addListener(listener)
        onDispose {
            reportCurrentWatchHistory(true)
            exoPlayer.removeListener(listener)
            exoPlayer.release()
        }
    }

    PhoneFullscreenRotationEffect(
        enabled = isPhone && state is VideoUiState.Loaded && !prefersPortraitFullscreen,
        onLandscape = { orientation ->
            val requestedOrientation = orientation.requestedLandscapeOrientation()
            fullscreenLandscapeOrientation = requestedOrientation
            context.findActivity()?.requestedOrientation = requestedOrientation
            resolvedViewModel.requestFullscreen()
        },
        onPortrait = { resolvedViewModel.beginFullscreenExit() },
    )

    LaunchedEffect(isPhone, isCompletingFullscreenExit, configuration.orientation) {
        if (
            isPhone &&
            isCompletingFullscreenExit &&
            configuration.orientation == Configuration.ORIENTATION_PORTRAIT
        ) {
            // 与 iOS 一致：界面几何稳定为竖屏后再撤下全屏层，避免先闪回详情页。
            withFrameNanos { }
            withFrameNanos { }
            resolvedViewModel.completeFullscreenExit()
        }
    }

    BackHandler(enabled = isFullscreen) { requestFullscreenExit() }
    DisposableEffect(
        deviceType,
        isFullscreen,
        isCompletingFullscreenExit,
        prefersPortraitFullscreen,
        fullscreenLandscapeOrientation,
        configuration.orientation,
    ) {
        val activity = context.findActivity()
        activity?.requestedOrientation = when {
            deviceType == FocusVideoDeviceType.Tablet -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            isCompletingFullscreenExit -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            isFullscreen && prefersPortraitFullscreen -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            isFullscreen -> fullscreenLandscapeOrientation
            else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        setSystemBarsHidden(activity, isFullscreen)
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
                                            player = exoPlayer,
                                            showController = false,
                                            onToggleFullscreen = requestFullscreen,
                                            modifier = Modifier.fillMaxSize(),
                                        )
                                    } else {
                                        PlayerSurface(
                                            player = exoPlayer,
                                            showController = false,
                                            onToggleFullscreen = requestFullscreen,
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
                    if (exoPlayer.isPlaying) exoPlayer.pause() else exoPlayer.play()
                },
                onChangeSpeed = {
                    val next = nextSpeed(playbackSpeed)
                    exoPlayer.playbackParameters = PlaybackParameters(next)
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
                        player = exoPlayer,
                        showController = true,
                        onToggleFullscreen = requestFullscreenExit,
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
                            player = exoPlayer,
                            showController = true,
                            onToggleFullscreen = requestFullscreenExit,
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

@Composable
private fun VideoControlDock(
    isPlaying: Boolean,
    playbackSpeed: Float,
    onTogglePlay: () -> Unit,
    onChangeSpeed: () -> Unit,
    danmakuEnabled: Boolean,
    onToggleDanmaku: () -> Unit,
    onToggleFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isDarkTheme = MaterialTheme.colorScheme.background.luminance() < 0.5f
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(
                brush = Brush.verticalGradient(
                    colors = if (isDarkTheme) {
                        listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.10f),
                            Color.Black.copy(alpha = 0.22f),
                            Color.Black.copy(alpha = 0.34f),
                        )
                    } else {
                        listOf(
                            Color.Transparent,
                            Color.White.copy(alpha = 0.08f),
                            Color.White.copy(alpha = 0.20f),
                            Color.White.copy(alpha = 0.34f),
                        )
                    },
                ),
            )
            .navigationBarsPadding()
            .padding(start = 16.dp, end = 16.dp, top = 2.dp, bottom = 2.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(24.dp))
                .background(
                    if (isDarkTheme) {
                        Color(0xC8262C36)
                    } else {
                        Color.White.copy(alpha = 0.72f)
                    }
                )
                .border(
                    width = 1.dp,
                    color = if (isDarkTheme) {
                        Color.White.copy(alpha = 0.10f)
                    } else {
                        Color(0x241A1D24)
                    },
                    shape = RoundedCornerShape(24.dp),
                )
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            DockButton(
                icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                text = if (isPlaying) "暂停" else "播放",
                onClick = onTogglePlay,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Outlined.Speed,
                text = "${trimSpeed(playbackSpeed)}x",
                onClick = onChangeSpeed,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Outlined.Chat,
                text = if (danmakuEnabled) "开" else "关",
                onClick = onToggleDanmaku,
                active = danmakuEnabled,
                modifier = Modifier.weight(1f),
            )
            DockButton(
                icon = Icons.Filled.OpenInFull,
                text = "全屏",
                onClick = onToggleFullscreen,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun VideoActionBar(
    interactionState: VideoInteractionState,
    info: VideoInfo,
    onToggleLike: () -> Unit,
    onCoin: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(
                    alpha = if (MaterialTheme.colorScheme.background.luminance() < 0.5f) 0.72f else 0.86f,
                )
            )
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_like),
            value = formatCount(info.stats.likes),
            active = interactionState.liked,
            onClick = onToggleLike,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_coin),
            value = formatCount(info.stats.coins),
            active = interactionState.coined,
            onClick = onCoin,
            enabled = !interactionState.loading && !interactionState.coined,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_fav),
            value = formatCount(info.stats.favorites),
            active = interactionState.favorited,
            onClick = onToggleFavorite,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun DockButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    active: Boolean = false,
) {
    val isDarkTheme = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val containerColor = when {
        active -> MaterialTheme.colorScheme.primary.copy(alpha = if (isDarkTheme) 0.22f else 0.18f)
        isDarkTheme -> Color(0xFF343A43)
        else -> Color.White.copy(alpha = 0.90f)
    }
    val contentColor = when {
        active -> MaterialTheme.colorScheme.primary
        isDarkTheme -> Color.White
        else -> Color(0xFF2E3138)
    }

    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(containerColor),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = contentColor,
            disabledContentColor = if (isDarkTheme) Color.White.copy(alpha = 0.42f) else Color(0xFF8E95A1),
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
            Text(
                text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun VideoDanmakuOverlay(
    state: VideoDanmakuUiState,
    enabled: Boolean,
    playbackPositionMillis: Long,
    modifier: Modifier = Modifier,
) {
    if (!enabled || state.danmakus.isEmpty()) return
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current

    BoxWithConstraints(modifier = modifier) {
        val lineHeightPx = with(density) { 32.dp.toPx() }
        val usableHeightPx = with(density) { maxHeight.toPx() } * 0.75f
        val laneCount = (usableHeightPx / lineHeightPx).toInt().coerceAtLeast(1)
        val prepared = remember(state.danmakus, laneCount, textMeasurer) {
            val availableAt = VideoDanmakuMode.entries.associateWith { LongArray(laneCount) }.toMutableMap()
            state.danmakus.mapNotNull { danmaku ->
                val lanes = availableAt.getValue(danmaku.mode)
                val lane = lanes.indexOfFirst { it <= danmaku.progressMillis }
                if (lane < 0) return@mapNotNull null
                lanes[lane] = danmaku.progressMillis + DANMAKU_DISPLAY_MILLIS
                val color = danmakuColor(danmaku.colorRgb)
                val shadowColor = if (color.luminance() < 0.28f) Color.White else Color.Black
                val scale = (danmaku.fontSize / 25f).coerceIn(0.72f, 1.44f)
                val layout = textMeasurer.measure(
                    text = AnnotatedString(danmaku.content),
                    style = TextStyle(
                        color = color.copy(alpha = 0.94f),
                        fontSize = (18f * scale).sp,
                        fontWeight = FontWeight.SemiBold,
                        shadow = Shadow(
                            color = shadowColor.copy(alpha = 0.95f),
                            offset = Offset(1.5f, 1.5f),
                            blurRadius = 2.5f,
                        ),
                    ),
                    maxLines = 1,
                )
                PreparedDanmaku(danmaku, lane, layout)
            }
        }

        Canvas(modifier = Modifier.fillMaxSize()) {
            val time = playbackPositionMillis
            prepared.forEach { preparedDanmaku ->
                val elapsed = time - preparedDanmaku.danmaku.progressMillis
                if (elapsed !in 0L until DANMAKU_DISPLAY_MILLIS) return@forEach
                val textWidth = preparedDanmaku.layout.size.width.toFloat()
                val x = when (preparedDanmaku.danmaku.mode) {
                    VideoDanmakuMode.SCROLLING -> {
                        val progress = elapsed.toFloat() / DANMAKU_DISPLAY_MILLIS
                        size.width - progress * (size.width + textWidth)
                    }
                    VideoDanmakuMode.TOP, VideoDanmakuMode.BOTTOM -> (size.width - textWidth) / 2f
                }
                val y = when (preparedDanmaku.danmaku.mode) {
                    VideoDanmakuMode.BOTTOM -> usableHeightPx - (preparedDanmaku.lane + 1) * lineHeightPx
                    VideoDanmakuMode.SCROLLING, VideoDanmakuMode.TOP -> preparedDanmaku.lane * lineHeightPx
                }
                drawText(
                    textLayoutResult = preparedDanmaku.layout,
                    topLeft = Offset(x, y.coerceAtLeast(0f)),
                )
            }
        }
    }
}

@Composable
private fun VideoDanmakuStatusBanner(
    state: VideoDanmakuUiState,
    enabled: Boolean,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (!enabled) return
    when (state.status) {
        VideoDanmakuLoadStatus.FAILED -> TextButton(
            onClick = onRetry,
            modifier = modifier
                .padding(top = 8.dp)
                .background(Color.Black.copy(alpha = 0.62f), RoundedCornerShape(14.dp)),
        ) {
            Text("弹幕加载失败 · 重试", color = Color.White)
        }
        VideoDanmakuLoadStatus.CLOSED -> Text(
            text = state.message ?: "该视频未开启弹幕",
            color = Color.White,
            style = MaterialTheme.typography.labelMedium,
            modifier = modifier
                .padding(top = 12.dp)
                .background(Color.Black.copy(alpha = 0.62f), RoundedCornerShape(12.dp))
                .padding(horizontal = 12.dp, vertical = 7.dp),
        )
        else -> Unit
    }
}

@Composable
private fun DanmakuFullscreenButton(
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.52f), CircleShape),
    ) {
        Icon(
            imageVector = Icons.Outlined.Chat,
            contentDescription = if (enabled) "关闭弹幕" else "开启弹幕",
            tint = if (enabled) MaterialTheme.colorScheme.primary else Color.White,
        )
    }
}

private data class PreparedDanmaku(
    val danmaku: VideoDanmaku,
    val lane: Int,
    val layout: TextLayoutResult,
)

private fun danmakuColor(rgb: Int?): Color {
    val value = rgb ?: 0xffffff
    return Color(
        red = ((value shr 16) and 0xff) / 255f,
        green = ((value shr 8) and 0xff) / 255f,
        blue = (value and 0xff) / 255f,
        alpha = 1f,
    )
}

@Composable
private fun ActionMetricButton(
    painter: Painter,
    value: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            disabledContentColor = MaterialTheme.colorScheme.outline,
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                painter = painter,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
            Text(
                value,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun VerticalDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(20.dp)
            .background(MaterialTheme.colorScheme.outlineVariant),
    )
}

@Composable
private fun VideoPageSection(
    pages: List<VideoPage>,
    selectedCid: Long?,
    onSelect: (VideoPage) -> Unit,
) {
    val selectedIndex = pages.indexOfFirst { it.cid == selectedCid }.coerceAtLeast(0)
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = selectedIndex)

    LaunchedEffect(pages, selectedCid) {
        val currentIndex = pages.indexOfFirst { it.cid == selectedCid }
        if (currentIndex >= 0) {
            listState.scrollToItem(currentIndex)
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("分 P", style = MaterialTheme.typography.titleMedium)
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(pages, key = { it.cid }) { page ->
                val selected = page.cid == selectedCid
                val chipShape = RoundedCornerShape(10.dp)
                FilterChip(
                    selected = selected,
                    onClick = { onSelect(page) },
                    label = {
                        val label = buildString {
                            append("P${page.pageNumber}")
                            if (page.title.isNotBlank()) append(" ${page.title}")
                        }
                        Text(
                            label,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ),
                    shape = chipShape,
                    modifier = Modifier.then(
                        if (selected) {
                            Modifier.border(2.dp, MaterialTheme.colorScheme.primary, chipShape)
                        } else {
                            Modifier
                        }
                    ),
                )
            }
        }
    }
}

@Composable
private fun VideoEpisodeSections(
    groups: List<VideoEpisodeGroup>,
    currentBvid: String,
    currentCid: Long,
    onOpenVideo: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        groups.forEach { group ->
            VideoEpisodeGroupRow(
                group = group,
                currentBvid = currentBvid,
                currentCid = currentCid,
                onOpenVideo = onOpenVideo,
            )
        }
    }
}

@Composable
private fun VideoEpisodeGroupRow(
    group: VideoEpisodeGroup,
    currentBvid: String,
    currentCid: Long,
    onOpenVideo: (String) -> Unit,
) {
    val currentIndex = currentVideoEpisodeIndex(group.episodes, currentBvid, currentCid)
    val listState = remember(group, currentBvid, currentCid) {
        LazyListState(firstVisibleItemIndex = currentIndex.coerceAtLeast(0))
    }

    LaunchedEffect(group.episodes, currentBvid, currentCid, currentIndex) {
        if (currentIndex >= 0) {
            withFrameNanos { }
            listState.scrollToItem(currentIndex)
            withFrameNanos { }
            if (listState.layoutInfo.visibleItemsInfo.none { it.index == currentIndex }) {
                listState.scrollToItem(currentIndex)
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(group.title, style = MaterialTheme.typography.titleMedium)
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            itemsIndexed(
                items = group.episodes,
                key = { _, episode -> "${group.title}-${episode.bvid}-${episode.cid}" },
            ) { index, episode ->
                val selected = index == currentIndex
                EpisodeCard(
                    episode = episode,
                    selected = selected,
                    onClick = {
                        if (!selected) {
                            onOpenVideo(videoEpisodeURL(episode))
                        }
                    },
                )
            }
        }
    }
}

internal fun currentVideoEpisodeIndex(
    episodes: List<VideoEpisode>,
    currentBvid: String,
    currentCid: Long? = null,
): Int {
    if (currentCid != null && currentCid > 0) {
        val exactMatch = episodes.indexOfFirst {
            it.bvid == currentBvid && it.cid == currentCid
        }
        if (exactMatch >= 0) return exactMatch

        val caseInsensitiveMatch = episodes.indexOfFirst {
            it.cid == currentCid && it.bvid.equals(currentBvid, ignoreCase = true)
        }
        if (caseInsensitiveMatch >= 0) return caseInsensitiveMatch

        val cidMatch = episodes.indexOfFirst { it.cid == currentCid }
        if (cidMatch >= 0) return cidMatch
    }

    val exactIndex = episodes.indexOfFirst { it.bvid == currentBvid }
    return if (exactIndex >= 0) {
        exactIndex
    } else {
        episodes.indexOfFirst { it.bvid.equals(currentBvid, ignoreCase = true) }
    }
}

internal fun videoEpisodeURL(episode: VideoEpisode): String = buildString {
    append("https://www.bilibili.com/video/")
    append(episode.bvid)
    append('/')
    if (episode.cid > 0) {
        append("?cid=")
        append(episode.cid)
    }
}

@Composable
private fun EpisodeCard(
    episode: VideoEpisode,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val cardShape = RoundedCornerShape(14.dp)
    ElevatedCard(
        onClick = onClick,
        shape = cardShape,
        colors = CardDefaults.elevatedCardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surface
            }
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        modifier = Modifier
            .size(width = 156.dp, height = 88.dp)
            .then(
                if (selected) {
                    Modifier.border(2.dp, MaterialTheme.colorScheme.primary, cardShape)
                } else {
                    Modifier
                }
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                episode.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            if (episode.badgeText.isNotBlank()) {
                Text(
                    episode.badgeText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
@Composable
private fun PlayerSurface(
    player: ExoPlayer,
    showController: Boolean,
    onToggleFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                useController = showController
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                setShowNextButton(false)
                setShowPreviousButton(false)
                setBackgroundColor(android.graphics.Color.BLACK)
                setFullscreenButtonClickListener { onToggleFullscreen() }
            }
        },
        update = { view ->
            view.useController = showController
            view.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
            view.player = player
            view.setFullscreenButtonClickListener { onToggleFullscreen() }
        },
        onRelease = { view ->
            view.player = null
        },
        modifier = modifier,
    )
}

@Composable
private fun PhoneFullscreenRotationEffect(
    enabled: Boolean,
    onLandscape: (FocusPhysicalOrientation) -> Unit,
    onPortrait: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val currentOnLandscape by rememberUpdatedState(onLandscape)
    val currentOnPortrait by rememberUpdatedState(onPortrait)

    DisposableEffect(context, enabled) {
        if (!enabled) return@DisposableEffect onDispose { }

        var lastOrientation: FocusPhysicalOrientation? = null
        var debounceJob: Job? = null
        val listener = object : OrientationEventListener(context.applicationContext) {
            override fun onOrientationChanged(orientation: Int) {
                val resolvedOrientation = FocusPhysicalOrientation.fromDegrees(orientation) ?: return
                if (resolvedOrientation == lastOrientation) return
                val isInitialOrientation = lastOrientation == null
                lastOrientation = resolvedOrientation

                // OrientationEventListener 启用后会立即上报当前方向；初始竖屏不是一次旋转动作。
                if (isInitialOrientation && resolvedOrientation == FocusPhysicalOrientation.Portrait) return

                debounceJob?.cancel()
                debounceJob = scope.launch {
                    delay(180)
                    when (resolvedOrientation) {
                        FocusPhysicalOrientation.LandscapeClockwise,
                        FocusPhysicalOrientation.LandscapeCounterClockwise
                        -> currentOnLandscape(resolvedOrientation)
                        FocusPhysicalOrientation.Portrait -> currentOnPortrait()
                    }
                }
            }
        }

        if (listener.canDetectOrientation()) listener.enable()
        onDispose {
            debounceJob?.cancel()
            listener.disable()
        }
    }
}

private enum class FocusVideoDeviceType {
    Phone,
    Tablet;

    companion object {
        fun fromSmallestWidth(smallestScreenWidthDp: Int): FocusVideoDeviceType =
            if (smallestScreenWidthDp < 600) Phone else Tablet
    }
}

internal object FocusVideoFullscreenPolicy {
    private const val DEFAULT_ASPECT_RATIO = 16f / 9f

    fun aspectRatio(width: Int, height: Int): Float =
        if (width > 0 && height > 0) width.toFloat() / height else DEFAULT_ASPECT_RATIO

    fun isPortrait(aspectRatio: Float): Boolean =
        aspectRatio.isFinite() && aspectRatio > 0f && aspectRatio <= 1f

    fun shouldFitToWidth(containerAspectRatio: Float, videoAspectRatio: Float): Boolean =
        containerAspectRatio.isFinite() &&
            videoAspectRatio.isFinite() &&
            containerAspectRatio > 0f &&
            videoAspectRatio > 0f &&
            containerAspectRatio <= videoAspectRatio
}

internal enum class FocusPhysicalOrientation {
    Portrait,
    LandscapeClockwise,
    LandscapeCounterClockwise;

    companion object {
        fun fromDegrees(degrees: Int): FocusPhysicalOrientation? = when {
            degrees == OrientationEventListener.ORIENTATION_UNKNOWN -> null
            degrees in 315..359 || degrees in 0..44 -> Portrait
            degrees in 45..134 -> LandscapeClockwise
            degrees in 225..314 -> LandscapeCounterClockwise
            // 与 iOS 保持一致：倒置和设备平放时不触发全屏切换。
            else -> null
        }
    }
}

internal fun FocusPhysicalOrientation.requestedLandscapeOrientation(): Int = when (this) {
    FocusPhysicalOrientation.LandscapeClockwise -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
    FocusPhysicalOrientation.LandscapeCounterClockwise -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    FocusPhysicalOrientation.Portrait -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
}

private fun android.content.Context.findActivity(): android.app.Activity? {
    var ctx: android.content.Context? = this
    while (ctx is android.content.ContextWrapper) {
        if (ctx is android.app.Activity) return ctx
        ctx = ctx.baseContext
    }
    return null
}

private fun setSystemBarsHidden(activity: android.app.Activity?, hidden: Boolean) {
    val window = activity?.window ?: return
    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
        val controller = window.insetsController
        val bars = android.view.WindowInsets.Type.statusBars() or android.view.WindowInsets.Type.navigationBars()
        if (hidden) {
            controller?.hide(bars)
            controller?.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            controller?.show(bars)
        }
    } else {
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (hidden) {
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        } else {
            View.SYSTEM_UI_FLAG_VISIBLE
        }
    }
}

@Composable
private fun StatItem(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurface)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun VideoTitleSection(info: VideoInfo) {
    val titleStyle = MaterialTheme.typography.titleMedium
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = info.title,
            style = titleStyle.copy(fontSize = titleStyle.fontSize * 1.2f),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "${formatCount(info.stats.views)}播放",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "${formatCount(info.stats.danmaku)}弹幕",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (info.publishDate > 0) {
                Text(
                    text = formatPublishDate(info.publishDate),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun AuthorCard(info: VideoInfo, onClick: () -> Unit = {}) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(info.author.avatarURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier.size(44.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(info.author.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("UID: ${info.author.mid}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ExpandableDescription(desc: String) {
    var expanded by remember(desc) { mutableStateOf(true) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = desc,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
        )
        if (desc.length > 120) {
            Text(
                text = if (expanded) "收起" else "展开",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable { expanded = !expanded },
            )
        }
    }
}

@Composable
private fun CommentItem(comment: VideoComment, onOpenURL: (String) -> Unit) {
    val contentStyle = MaterialTheme.typography.bodyMedium.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    val replyStyle = MaterialTheme.typography.bodySmall.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    val authorStyle = MaterialTheme.typography.labelMedium.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(comment.avatarURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.size(28.dp).clip(CircleShape),
                contentScale = ContentScale.Crop,
            )
            Text(comment.authorName, style = authorStyle, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.weight(1f))
            Text(
                formatTimeAgo(comment.publishTime),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text("${comment.likeCount}赞", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        FocusRichText(comment.contentRuns, style = contentStyle, onOpenURL = onOpenURL)

        comment.replies.take(3).forEach { reply ->
            Row(modifier = Modifier.padding(start = 36.dp, top = 4.dp)) {
                Text("${reply.authorName}: ", style = replyStyle, color = MaterialTheme.colorScheme.primary)
                FocusRichText(
                    reply.contentRuns,
                    style = replyStyle.copy(color = MaterialTheme.colorScheme.onSurfaceVariant),
                    modifier = Modifier.weight(1f),
                    onOpenURL = onOpenURL,
                )
            }
        }
    }
}

private fun resolveActivePage(
    info: VideoInfo?,
    selectedCid: Long?,
    requestedPageNumber: Int?,
    requestedPageCid: Long?,
): VideoPage? {
    if (info == null) return null
    return info.pages.firstOrNull { it.cid == selectedCid }
        ?: requestedPageNumber?.let { pageNumber ->
            info.pages.firstOrNull { it.pageNumber == pageNumber }
        }
        ?: requestedPageCid?.let { cid ->
            info.pages.firstOrNull { it.cid == cid }
        }
        ?: info.pages.firstOrNull { it.cid == info.cid }
        ?: info.pages.firstOrNull()
        ?: VideoPage(
            pageNumber = 1,
            cid = info.cid,
            title = "正片",
            duration = info.duration,
        )
}

private fun parseRequestedPage(url: String): Int? {
    return Regex("""[?&]p=(\d+)""", RegexOption.IGNORE_CASE)
        .find(url.replace("&amp;", "&", ignoreCase = true))
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
        ?.takeIf { it > 0 }
}

internal fun parseRequestedCid(url: String): Long? {
    return Regex("""[?&]cid=(\d+)""", RegexOption.IGNORE_CASE)
        .find(url.replace("&amp;", "&", ignoreCase = true))
        ?.groupValues
        ?.getOrNull(1)
        ?.toLongOrNull()
        ?.takeIf { it > 0 }
}

private fun nextSpeed(current: Float): Float {
    val currentIndex = SPEEDS.indexOfFirst { kotlin.math.abs(it - current) < 0.01f }
    return if (currentIndex == -1 || currentIndex == SPEEDS.lastIndex) SPEEDS.first() else SPEEDS[currentIndex + 1]
}

private fun trimSpeed(speed: Float): String {
    return if (speed % 1f == 0f) speed.toInt().toString() else speed.toString()
}

private fun formatCount(count: Long): String = when {
    count >= 100_000_000L -> {
        "%.1f亿".format(count / 100_000_000.0).replace(".0亿", "亿")
    }
    count >= 10000L -> {
        "%.1f万".format(count / 10_000.0).replace(".0万", "万")
    }
    else -> count.toString()
}

private fun formatPublishDate(timestamp: Long): String =
    java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.CHINA)
        .format(java.util.Date(timestamp * 1000))

private fun formatTimeAgo(ts: Long): String {
    val now = System.currentTimeMillis() / 1000
    val diff = now - ts
    return when {
        diff < 60 -> "刚刚"
        diff < 3600 -> "${diff / 60}分钟前"
        diff < 86400 -> "${diff / 3600}小时前"
        diff < 2592000 -> "${diff / 86400}天前"
        else -> java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
            .format(java.util.Date(ts * 1000))
    }
}
