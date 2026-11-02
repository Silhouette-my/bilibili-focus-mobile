package org.bilibilifocus.android.ui.video

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.util.Rational
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Comment
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.media3.common.Player
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.bilibilifocus.android.VideoSubtitleUiState
import org.bilibilifocus.android.playback.FocusPlaybackState
import org.bilibilifocus.core.model.FocusPlaybackPreferences
import org.bilibilifocus.core.model.VideoSubtitleDocument
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun VideoPlaybackOverlay(
    player: Player?,
    state: FocusPlaybackState,
    positionMillis: () -> Long,
    preferences: FocusPlaybackPreferences,
    onPreferencesChange: (FocusPlaybackPreferences) -> Unit,
    preferredQuality: Int?,
    onQualityChange: (Int?) -> Unit,
    danmakuEnabled: Boolean,
    onDanmakuEnabledChange: (Boolean) -> Unit,
    subtitleState: VideoSubtitleUiState,
    subtitleEnabled: Boolean,
    onSubtitleEnabledChange: (Boolean) -> Unit,
    onSubtitleLanguageChange: (String) -> Unit,
    onRetrySubtitle: () -> Unit,
    onRetryPlayback: () -> Unit,
    onSleepTimer: (Int) -> Unit,
    isFullscreen: Boolean,
    onToggleFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
    title: String = "",
) {
    val context = LocalContext.current
    val activity = context.findActivity()
    val view = LocalView.current
    val playbackWindow = (view.parent as? DialogWindowProvider)?.window ?: activity?.window
    var visible by remember { mutableStateOf(true) }
    var locked by remember { mutableStateOf(false) }
    var scrubbing by remember { mutableStateOf(false) }
    var seekPosition by remember { mutableLongStateOf(0L) }
    var holding by remember { mutableStateOf(false) }
    var settingsOpen by remember { mutableStateOf(false) }
    var speedMenu by remember { mutableStateOf(false) }
    var qualityMenu by remember { mutableStateOf(false) }
    var subtitleMenu by remember { mutableStateOf(false) }
    var sleepMenu by remember { mutableStateOf(false) }
    var gestureMessage by remember { mutableStateOf<String?>(null) }
    val currentPreferences by rememberUpdatedState(preferences)
    val currentPlayer by rememberUpdatedState(player)
    val duration = player?.duration?.coerceAtLeast(0) ?: 0L
    val sliderPosition = (if (scrubbing) seekPosition else positionMillis())
        .toFloat().coerceIn(0f, duration.coerceAtLeast(1).toFloat())
    val sliderColors = SliderDefaults.colors(
        thumbColor = Color.White,
        activeTrackColor = Color.White,
        inactiveTrackColor = Color.White.copy(alpha = 0.45f),
        activeTickColor = Color.Transparent,
        inactiveTickColor = Color.Transparent,
    )
    val originalBrightness = remember(playbackWindow) { playbackWindow?.attributes?.screenBrightness ?: -1f }
    DisposableEffect(playbackWindow) {
        onDispose {
            playbackWindow?.let { window -> window.attributes = window.attributes.apply { screenBrightness = originalBrightness } }
        }
    }
    LaunchedEffect(visible, state.isPlaying, scrubbing, holding, locked, settingsOpen, speedMenu, qualityMenu, subtitleMenu) {
        if (visible && state.isPlaying && !scrubbing && !holding && !locked && !settingsOpen && !speedMenu && !qualityMenu && !subtitleMenu) {
            delay(3_000)
            visible = false
        }
    }
    LaunchedEffect(gestureMessage) { if (gestureMessage != null) { delay(1_800); gestureMessage = null } }
    BoxWithConstraints(modifier = modifier.then(if (isFullscreen) Modifier.windowInsetsPadding(WindowInsets.safeDrawing) else Modifier)) {
        val gestureWidth = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val gestureHeight = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        Box(
            Modifier.fillMaxSize()
                .pointerInput(player, locked) {
                    if (locked) return@pointerInput
                    detectTapGestures(
                        onTap = { visible = !visible },
                        onDoubleTap = { currentPlayer?.let { if (it.playWhenReady) it.pause() else it.play() }; visible = true },
                        onLongPress = {},
                        onPress = {
                            coroutineScope {
                                val activePlayer = currentPlayer
                                val rate = activePlayer?.playbackParameters?.speed ?: currentPreferences.preferredRate
                                val hold = launch {
                                    delay(400)
                                    if (activePlayer?.isPlaying == true) {
                                        holding = true
                                        activePlayer.setPlaybackSpeed(3f)
                                    }
                                }
                                try { tryAwaitRelease() } finally {
                                    hold.cancel()
                                    if (holding) activePlayer?.setPlaybackSpeed(rate)
                                    holding = false
                                }
                            }
                        },
                    )
                }
                .pointerInput(player, locked, duration, isFullscreen) {
                    if (locked || !isFullscreen || duration <= 0) return@pointerInput
                    var dragStart = 0L
                    var drag = 0f
                    detectHorizontalDragGestures(
                        onDragStart = { dragStart = currentPlayer?.currentPosition ?: 0; drag = 0f; scrubbing = true; visible = true; seekPosition = dragStart },
                        onHorizontalDrag = { change, amount ->
                            change.consume(); drag += amount
                            seekPosition = (dragStart + (drag / gestureWidth * 90_000).toLong()).coerceIn(0, duration)
                            gestureMessage = "定位 ${formatPlaybackTime(seekPosition)}"
                        },
                        onDragEnd = { currentPlayer?.seekTo(seekPosition); scrubbing = false },
                        onDragCancel = { scrubbing = false },
                    )
                }
                .pointerInput(player, locked, isFullscreen) {
                    if (locked || !isFullscreen) return@pointerInput
                    var left = true
                    var start = 0f
                    var delta = 0f
                    lateinit var audio: AudioManager
                    detectVerticalDragGestures(
                        onDragStart = { offset ->
                            audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            left = offset.x < gestureWidth / 2; delta = 0f
                            start = if (left) playbackWindow?.attributes?.screenBrightness?.takeIf { it >= 0 } ?: 0.5f
                            else audio.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                        },
                        onVerticalDrag = { change, amount ->
                            change.consume(); delta -= amount / gestureHeight
                            val value = (start + delta).coerceIn(0f, 1f)
                            if (left) playbackWindow?.let { window -> window.attributes = window.attributes.apply { screenBrightness = value.coerceAtLeast(0.01f) } }
                            else audio.setStreamVolume(AudioManager.STREAM_MUSIC, (value * audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)).roundToInt(), 0)
                            gestureMessage = "${if (left) "亮度" else "音量"} ${(value * 100).roundToInt()}%"
                        },
                    )
                },
        )

        val controlsVisible = visible && !locked
        val subtitleTopInset = if (controlsVisible) 52.dp else 0.dp
        val subtitleBottomInset = if (controlsVisible) 96.dp else 18.dp
        val subtitleAvailableHeight = (maxHeight - subtitleTopInset - subtitleBottomInset).coerceAtLeast(0.dp)
        if (controlsVisible) {
            Box(
                Modifier.fillMaxSize().background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = 0.55f), Color.Transparent, Color.Black.copy(alpha = 0.75f)),
                    ),
                ),
            )
        }
        VideoSubtitleOverlay(
            document = subtitleState.document.takeIf { subtitleEnabled },
            positionMillis = positionMillis,
            preferences = preferences,
            maxLines = if (controlsVisible && maxHeight < 220.dp) 1 else 4,
            modifier = Modifier.align(Alignment.BottomCenter)
                .padding(start = 20.dp, end = 20.dp, bottom = subtitleBottomInset)
                .heightIn(max = subtitleAvailableHeight),
        )

        if (locked) {
            IconButton(onClick = { locked = false; visible = true }, modifier = Modifier.align(Alignment.CenterEnd).padding(12.dp).background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(14.dp))) {
                Icon(Icons.Filled.Lock, "解锁播放器", tint = Color.White)
            }
        } else if (visible) {
            Column(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 4.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    if (isFullscreen) IconButton(onClick = onToggleFullscreen) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "退出全屏", tint = Color.White) }
                    if (isFullscreen) Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis, color = Color.White, style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                    else Spacer(Modifier.weight(1f))
                    if (isFullscreen) IconButton(onClick = { locked = true; visible = false }) { Icon(Icons.Filled.LockOpen, "锁定播放器", tint = Color.White) }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
                        IconButton(enabled = state.isConnected && player?.currentMediaItem != null, onClick = {
                            val ratio = state.videoAspectRatio.coerceIn(1f / 2.39f, 2.39f)
                            val entered = activity?.enterPictureInPictureMode(PictureInPictureParams.Builder().setAspectRatio(Rational((ratio * 1000).roundToInt(), 1000)).build()) == true
                            if (!entered) gestureMessage = "无法进入画中画，请检查系统权限"
                        }) { Icon(Icons.Filled.PictureInPictureAlt, "画中画", tint = Color.White) }
                    }
                    IconButton(onClick = { settingsOpen = true }) { Icon(Icons.Filled.Tune, "播放设置", tint = Color.White) }
                    IconButton(onClick = { subtitleMenu = true }) {
                        Icon(Icons.Filled.ClosedCaption, "字幕设置", tint = if (subtitleEnabled) Color.White else Color.White.copy(alpha = 0.58f))
                    }
                    DropdownMenu(expanded = subtitleMenu, onDismissRequest = { subtitleMenu = false }) {
                        DropdownMenuItem(text = { Text(if (!subtitleEnabled) "✓ 关闭字幕" else "关闭字幕") }, onClick = { onSubtitleEnabledChange(false); subtitleMenu = false })
                        subtitleState.tracks.forEach { track -> DropdownMenuItem(
                            text = { Text("${if (subtitleEnabled && subtitleState.selectedTrack?.id == track.id) "✓ " else ""}${track.displayName}${if (track.isLocked) "（不可用）" else ""}") },
                            enabled = !track.isLocked,
                            onClick = { onSubtitleLanguageChange(track.languageCode); onSubtitleEnabledChange(true); subtitleMenu = false },
                        ) }
                        if (subtitleState.isLoading) DropdownMenuItem(text = { Text("正在加载字幕…") }, enabled = false, onClick = {})
                        else if (subtitleState.error != null) DropdownMenuItem(text = { Text("字幕加载失败，重试") }, onClick = { onRetrySubtitle(); subtitleMenu = false })
                        else if (subtitleState.tracks.isEmpty()) DropdownMenuItem(text = { Text("此分 P 暂无字幕") }, enabled = false, onClick = {})
                    }
                }
                Spacer(Modifier.weight(1f))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(formatPlaybackTime(if (scrubbing) sliderPosition.toLong() else positionMillis()), color = Color.White, style = MaterialTheme.typography.labelSmall)
                    Slider(
                        value = sliderPosition,
                        onValueChange = { value ->
                            scrubbing = true
                            seekPosition = value.toLong()
                        },
                        onValueChangeFinished = {
                            if (scrubbing) currentPlayer?.seekTo(seekPosition)
                            scrubbing = false
                        },
                        enabled = duration > 0,
                        valueRange = 0f..duration.coerceAtLeast(1).toFloat(),
                        colors = sliderColors,
                        modifier = Modifier.weight(1f).height(44.dp),
                        thumb = { Box(Modifier.size(10.dp).clip(CircleShape).background(Color.White)) },
                        track = { state -> SliderDefaults.Track(
                            sliderState = state,
                            modifier = Modifier.height(3.dp),
                            colors = sliderColors,
                            thumbTrackGapSize = 0.dp,
                            drawStopIndicator = {},
                        ) },
                    )
                    Text(formatPlaybackTime(duration), color = Color.White, style = MaterialTheme.typography.labelSmall)
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { player?.let { if (state.hasEnded) { it.seekTo(0); it.play() } else if (it.playWhenReady) it.pause() else it.play() } }) {
                        Icon(if (state.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (state.isPlaying) "暂停" else "播放", tint = Color.White)
                    }
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { onDanmakuEnabledChange(!danmakuEnabled); visible = true }) {
                        Icon(Icons.AutoMirrored.Filled.Comment, if (danmakuEnabled) "关闭弹幕" else "开启弹幕", tint = if (danmakuEnabled) Color.White else Color.White.copy(alpha = 0.58f))
                    }
                    Box {
                        TextButton(onClick = { speedMenu = true }, contentPadding = PaddingValues(horizontal = 4.dp)) { Text(formatPlaybackRate(state.playbackSpeed), color = Color.White) }
                        DropdownMenu(expanded = speedMenu, onDismissRequest = { speedMenu = false }) {
                            playbackRates.forEach { rate -> DropdownMenuItem(text = { Text(formatPlaybackRate(rate)) }, onClick = { player?.setPlaybackSpeed(rate); onPreferencesChange(preferences.copy(preferredRate = rate)); speedMenu = false }) }
                        }
                    }
                    Box {
                        TextButton(onClick = { qualityMenu = true }, contentPadding = PaddingValues(horizontal = 4.dp)) {
                            Text(if (preferredQuality == null) "自动" else state.availableQualities.firstOrNull { it.id == preferredQuality }?.title ?: "画质", color = Color.White, maxLines = 1)
                        }
                        DropdownMenu(expanded = qualityMenu, onDismissRequest = { qualityMenu = false }) {
                            if (state.deliveredQuality > 0) DropdownMenuItem(text = { Text("当前播放：${state.availableQualities.firstOrNull { it.id == state.deliveredQuality }?.title ?: state.deliveredQuality}") }, enabled = false, onClick = {})
                            DropdownMenuItem(text = { Text(if (preferredQuality == null) "✓ 自动" else "自动") }, onClick = { onQualityChange(null); qualityMenu = false })
                            state.availableQualities.forEach { quality -> DropdownMenuItem(text = { Text("${if (preferredQuality == quality.id) "✓ " else ""}${quality.title}") }, onClick = { onQualityChange(quality.id); qualityMenu = false }) }
                        }
                    }
                    IconButton(onClick = onToggleFullscreen) { Icon(if (isFullscreen) Icons.Filled.CloseFullscreen else Icons.Filled.OpenInFull, if (isFullscreen) "退出全屏" else "全屏", tint = Color.White) }
                }
            }
        }
        if (state.isRecovering || (state.isBuffering && player?.playWhenReady == true)) {
            Column(Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(12.dp)).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(Modifier.size(24.dp), color = Color.White, strokeWidth = 2.dp)
                Text(if (state.isRecovering) "正在恢复播放…" else "正在缓冲…", color = Color.White, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 6.dp))
            }
        }
        state.errorMessage?.let { message ->
            Column(Modifier.align(Alignment.Center).background(Color.Black.copy(alpha = 0.85f), RoundedCornerShape(12.dp)).padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(message, color = Color.White, textAlign = TextAlign.Center)
                TextButton(onClick = onRetryPlayback) { Text("重试", color = Color.White) }
            }
        }
        val transient = if (holding) "3× 快进中" else gestureMessage
        transient?.let { Text(it, color = Color.White, modifier = Modifier.align(Alignment.TopCenter).padding(top = 52.dp).background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(8.dp)).padding(8.dp)) }
    }
    if (settingsOpen) {
        ModalBottomSheet(onDismissRequest = { settingsOpen = false }) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("播放设置", style = MaterialTheme.typography.titleLarge)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("显示弹幕", modifier = Modifier.weight(1f))
                    Switch(checked = danmakuEnabled, onCheckedChange = onDanmakuEnabledChange)
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("睡眠定时", modifier = Modifier.weight(1f))
                    Box {
                        TextButton(onClick = { sleepMenu = true }) { Text(if (state.sleepDeadlineMillis > 0) "已开启" else "关闭") }
                        DropdownMenu(expanded = sleepMenu, onDismissRequest = { sleepMenu = false }) {
                            listOf(0, 15, 30, 60).forEach { minutes -> DropdownMenuItem(text = { Text(if (minutes == 0) "关闭定时" else "$minutes 分钟后暂停") }, onClick = { onSleepTimer(minutes); sleepMenu = false; gestureMessage = if (minutes == 0) "已关闭定时" else "将在 $minutes 分钟后暂停" }) }
                        }
                    }
                }
                PlaybackPreferencesEditor(preferences, onPreferencesChange)
            }
        }
    }
}

internal val playbackRates = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f, 2.5f, 3f)

@Composable
internal fun PlaybackPreferencesEditor(preferences: FocusPlaybackPreferences, onChange: (FocusPlaybackPreferences) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("自动播放下一 P", modifier = Modifier.weight(1f))
        Switch(checked = preferences.autoPlayNextPart, onCheckedChange = { onChange(preferences.copy(autoPlayNextPart = it)) })
    }
    PreferenceChoices("常用倍速", playbackRates, preferences.preferredRate, ::formatPlaybackRate) { onChange(preferences.copy(preferredRate = it)) }
    PreferenceChoices("弹幕透明度", listOf(0.4f, 0.7f, 0.94f, 1f), preferences.danmakuOpacity, { "${(it * 100).roundToInt()}%" }) { onChange(preferences.copy(danmakuOpacity = it)) }
    PreferenceChoices("弹幕字号", listOf(0.75f, 1f, 1.25f, 1.5f), preferences.danmakuFontScale, { "${(it * 100).roundToInt()}%" }) { onChange(preferences.copy(danmakuFontScale = it)) }
    PreferenceChoices("弹幕区域", listOf(0.25f, 0.5f, 1f), preferences.danmakuArea, { when (it) { 0.25f -> "顶部 1/4"; 0.5f -> "上半屏"; else -> "全屏" } }) { onChange(preferences.copy(danmakuArea = it)) }
    PreferenceChoices("弹幕密度", listOf(0.25f, 0.5f, 1f), preferences.danmakuDensity, { "${(it * 100).roundToInt()}%" }) { onChange(preferences.copy(danmakuDensity = it)) }
    PreferenceChoices("字幕字号", listOf(0.75f, 1f, 1.25f, 1.5f), preferences.subtitleFontScale, { "${(it * 100).roundToInt()}%" }) { onChange(preferences.copy(subtitleFontScale = it)) }
    PreferenceChoices("字幕背景", listOf(0f, 0.4f, 0.72f, 1f), preferences.subtitleBackgroundOpacity, { if (it == 0f) "无背景" else "${(it * 100).roundToInt()}%" }) { onChange(preferences.copy(subtitleBackgroundOpacity = it)) }
}

@Composable
private fun PreferenceChoices(title: String, choices: List<Float>, selected: Float, label: (Float) -> String, onSelect: (Float) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            choices.forEach { value -> FilterChip(selected = kotlin.math.abs(value - selected) < 0.01f, onClick = { onSelect(value) }, label = { Text(label(value)) }) }
        }
    }
}

@Composable
private fun VideoSubtitleOverlay(document: VideoSubtitleDocument?, positionMillis: () -> Long, preferences: FocusPlaybackPreferences, maxLines: Int, modifier: Modifier) {
    val text = document?.textAt(positionMillis()).orEmpty()
    if (text.isNotEmpty()) Text(
        text, color = Color.White, fontSize = (18 * preferences.subtitleFontScale).sp,
        textAlign = TextAlign.Center, maxLines = maxLines, overflow = TextOverflow.Ellipsis,
        modifier = modifier.background(Color.Black.copy(alpha = preferences.subtitleBackgroundOpacity), RoundedCornerShape(6.dp)).padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

internal fun formatPlaybackTime(milliseconds: Long): String {
    val seconds = milliseconds.coerceAtLeast(0) / 1000
    return if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60) else "%02d:%02d".format(seconds / 60, seconds % 60)
}

private fun formatPlaybackRate(rate: Float): String = if (rate % 1f == 0f) "${rate.toInt()}×" else "${rate}×"

@Preview(name = "Compact player controls", widthDp = 320, heightDp = 180)
@Preview(name = "Wide player controls", widthDp = 740, heightDp = 360)
@Composable
private fun VideoPlaybackControlsPreview() {
    MaterialTheme {
        var preferences by remember { mutableStateOf(FocusPlaybackPreferences()) }
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            VideoPlaybackOverlay(
                player = null, state = FocusPlaybackState(isConnected = true, isNativeVideoActive = true),
                positionMillis = { 0L }, title = "视频标题",
                preferences = preferences, onPreferencesChange = { preferences = it },
                preferredQuality = null, onQualityChange = {}, danmakuEnabled = true, onDanmakuEnabledChange = {},
                subtitleState = VideoSubtitleUiState(), subtitleEnabled = true, onSubtitleEnabledChange = {},
                onSubtitleLanguageChange = {}, onRetrySubtitle = {}, onRetryPlayback = {}, onSleepTimer = {},
                isFullscreen = false, onToggleFullscreen = {}, modifier = Modifier.fillMaxSize(),
            )
        }
    }
}
