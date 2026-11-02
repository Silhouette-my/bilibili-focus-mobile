package org.bilibilifocus.android

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import org.bilibilifocus.android.playback.FocusPlaybackState
import org.bilibilifocus.android.ui.video.PlayerSurface
import org.bilibilifocus.android.ui.video.VideoDanmakuOverlay
import org.bilibilifocus.android.ui.video.VideoPlaybackOverlay
import org.bilibilifocus.android.ui.video.FocusVideoDetailLayout
import org.bilibilifocus.android.ui.theme.BilibiliFocusTheme
import org.bilibilifocus.android.ui.video.setSystemBarsHidden
import org.bilibilifocus.core.model.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

/** Debug-only UI fixture. It never constructs an account graph or playback service. */
class FocusPlayerFixtureActivity : ComponentActivity() {
    private var inPictureInPicture by mutableStateOf(false)

    @OptIn(ExperimentalMaterial3Api::class)
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            BilibiliFocusTheme(themeMode = FocusThemeMode.LIGHT) {
                var fullscreen by remember { mutableStateOf(intent.getBooleanExtra("fullscreen", false)) }
                var compact by remember { mutableStateOf(intent.getBooleanExtra("compact", true)) }
                var preferences by remember { mutableStateOf(FocusPlaybackPreferences()) }
                var quality by remember { mutableStateOf<Int?>(null) }
                var danmakuEnabled by remember { mutableStateOf(intent.getBooleanExtra("danmaku", true)) }
                var subtitleEnabled by remember { mutableStateOf(true) }
                var language by remember { mutableStateOf("zh-CN") }
                var state by remember { mutableStateOf(FocusPlaybackState(isConnected = true, isNativeVideoActive = true, mediaId = "fixture", deliveredQuality = 32, availableQualities = listOf(VideoQuality(32, "360P")))) }
                val fixtureScope = rememberCoroutineScope()
                var sleepJob by remember { mutableStateOf<Job?>(null) }
                val position = remember { mutableLongStateOf(0L) }
                val player = remember {
                    ExoPlayer.Builder(this).build().apply {
                        setMediaItem(MediaItem.Builder().setMediaId("fixture").setUri(Uri.parse("android.resource://$packageName/${R.raw.focus_player_fixture}")).build(), intent.getLongExtra("position_ms", 3_000L))
                        playWhenReady = !intent.getBooleanExtra("paused", false)
                    }
                }
                val subtitleTracks = remember { listOf(
                    VideoSubtitleTrack(1, "zh-CN", "中文", "fixture:zh"),
                    VideoSubtitleTrack(2, "en", "English", "fixture:en"),
                ) }
                val subtitleDocument = remember(language) { VideoSubtitleDocument(listOf(
                    VideoSubtitleCue(0, 10_000, if (intent.getBooleanExtra("long_subtitle", false)) "这是一段用于检查紧凑播放器字幕的长句，应当避开顶部按钮和底部进度条，不缩小文字。" else if (language == "en") "Offline subtitle · seek to another position" else "离线字幕 · 可以拖动进度条"),
                    VideoSubtitleCue(10_000, 20_000, if (language == "en") "Change font size and background in playback settings" else "在播放设置中调整字号和背景"),
                    VideoSubtitleCue(20_000, 30_000, if (language == "en") "All media in this fixture is local" else "此页面的媒体和内容均来自本地"),
                )) }
                val danmakus = remember { VideoDanmakuUiState(
                    status = VideoDanmakuLoadStatus.READY,
                    segments = listOf(VideoDanmakuRenderSegment(1, (0 until 120).map { index ->
                        VideoDanmaku(index + 1L, index * 250L, VideoDanmakuMode.SCROLLING, 25,
                            if (index % 4 == 0) 0xFB7299 else 0xffffff,
                            listOf("离线弹幕", "全屏查看控件", "长按临时 3×", "进度可以点按和拖动")[index % 4], 5, 0)
                    })),
                ) }
                DisposableEffect(player) {
                    var captured = false
                    val listener = object : Player.Listener {
                        override fun onEvents(player: Player, events: Player.Events) {
                            state = state.copy(isPlaying = player.isPlaying, isBuffering = player.playbackState == Player.STATE_BUFFERING,
                                hasEnded = player.playbackState == Player.STATE_ENDED, playbackSpeed = player.playbackParameters.speed,
                                errorMessage = player.playerError?.localizedMessage)
                        }
                        override fun onRenderedFirstFrame() {
                            if (!captured) {
                                captured = true
                                captureFixtureScreenshotIfRequested()
                            }
                        }
                    }
                    player.addListener(listener)
                    player.prepare()
                    onDispose { player.removeListener(listener); player.release() }
                }
                LaunchedEffect(player) { while (true) { withFrameNanos { }; position.longValue = player.currentPosition.coerceAtLeast(0) } }
                LaunchedEffect(fullscreen) {
                    requestedOrientation = if (fullscreen || intent.getBooleanExtra("landscape", false)) ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                    setSystemBarsHidden(this@FocusPlayerFixtureActivity, fullscreen)
                }
                BackHandler(fullscreen) { fullscreen = false }
                val content: @Composable () -> Unit = {
                    Box(Modifier.fillMaxSize().background(Color.Black)) {
                        PlayerSurface(player, false, { fullscreen = !fullscreen }, 0, Modifier.fillMaxSize())
                        VideoDanmakuOverlay(danmakus, danmakuEnabled, { position.longValue }, Modifier.fillMaxSize(), preferences)
                        if (!inPictureInPicture) VideoPlaybackOverlay(
                            player, state, { position.longValue }, preferences,
                            onPreferencesChange = { preferences = it; player.setPlaybackSpeed(it.preferredRate) },
                            preferredQuality = quality, onQualityChange = { quality = it },
                            danmakuEnabled = danmakuEnabled, onDanmakuEnabledChange = { danmakuEnabled = it },
                            subtitleState = VideoSubtitleUiState(subtitleTracks, subtitleTracks.first { it.languageCode == language }, subtitleDocument),
                            subtitleEnabled = subtitleEnabled, onSubtitleEnabledChange = { subtitleEnabled = it },
                            onSubtitleLanguageChange = { language = it }, onRetrySubtitle = {},
                            onRetryPlayback = { player.seekTo(position.longValue); player.prepare(); player.play() },
                            onSleepTimer = { minutes ->
                                sleepJob?.cancel()
                                state = state.copy(sleepDeadlineMillis = if (minutes == 0) 0 else System.currentTimeMillis() + minutes * 60_000L)
                                if (minutes > 0) sleepJob = fixtureScope.launch { delay(minutes * 60_000L); player.pause(); state = state.copy(sleepDeadlineMillis = 0) }
                            },
                            isFullscreen = fullscreen, onToggleFullscreen = { fullscreen = !fullscreen }, modifier = Modifier.fillMaxSize(),
                            title = "从零理解光线追踪：让画面真正亮起来",
                        )
                    }
                }
                if (fullscreen || inPictureInPicture) content()
                else if (intent.getBooleanExtra("detail", false)) {
                    val detailScrollState = rememberScrollState()
                    LaunchedEffect(detailScrollState) {
                        detailScrollState.scrollTo(intent.getIntExtra("detail_scroll", 0))
                    }
                    Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("视频") }) }) { padding ->
                        FocusVideoDetailLayout(
                            videoAspectRatio = 16f / 9f,
                            scrollState = detailScrollState,
                            modifier = Modifier.padding(padding),
                            playerContent = content,
                            detailContent = {
                                Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                    Text("从零理解光线追踪：让画面真正亮起来", style = MaterialTheme.typography.titleLarge)
                                    Text("1.8万播放 · 120条弹幕", style = MaterialTheme.typography.bodySmall)
                                    Text("图形学实验室", style = MaterialTheme.typography.titleMedium)
                                    Text("分 P", style = MaterialTheme.typography.titleMedium)
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        FilterChip(true, {}, label = { Text("1 · 光的路径") })
                                        FilterChip(false, {}, label = { Text("2 · 材质") })
                                    }
                                    Text("简介", style = MaterialTheme.typography.titleMedium)
                                    Text("通过离线视频演示光线与材质。右侧内容独立滚动，左侧视频保持可见。")
                                    Text("评论", style = MaterialTheme.typography.titleMedium)
                                    repeat(12) { index ->
                                        Text("观众 ${index + 1}", style = MaterialTheme.typography.labelLarge)
                                        Text("从光照到材质一步步讲解，很容易理解。")
                                        HorizontalDivider()
                                    }
                                }
                            },
                        )
                    }
                } else Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("离线播放器验收") }) }) { padding ->
                    Column(Modifier.fillMaxSize().padding(padding), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilterChip(compact, { compact = true }, label = { Text("320dp") })
                            FilterChip(!compact, { compact = false }, label = { Text("全宽") })
                            TextButton(onClick = { fullscreen = true }) { Text("横屏全屏") }
                        }
                        Box(if (compact) Modifier.width(320.dp).height(180.dp) else Modifier.fillMaxWidth().aspectRatio(16f / 9f)) { content() }
                        Text("点按显示控件，双击播放/暂停，长按临时 3×。\n菜单、字幕、弹幕和视频均可离线检查。", modifier = Modifier.padding(horizontal = 20.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        inPictureInPicture = isInPictureInPictureMode
    }
}

private fun ComponentActivity.captureFixtureScreenshotIfRequested() {
    val name = intent.getStringExtra("capture") ?: return
    require(name.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { "Invalid fixture capture name" }
    window.decorView.postDelayed({
        val bitmap = Bitmap.createBitmap(window.decorView.width.coerceAtLeast(1), window.decorView.height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        PixelCopy.request(window, bitmap, { result ->
            if (result == PixelCopy.SUCCESS) {
                val directory = File(filesDir, "fixture-captures").apply { mkdirs() }
                val pending = File(directory, "$name.tmp")
                FileOutputStream(pending).use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                check(pending.renameTo(File(directory, "$name.png")))
            }
            bitmap.recycle()
        }, Handler(Looper.getMainLooper()))
    }, 1800)
}
