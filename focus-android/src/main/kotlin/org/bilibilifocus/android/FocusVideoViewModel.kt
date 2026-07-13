package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuSegmentScheduler
import org.bilibilifocus.core.model.VideoDanmakuView
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState
import org.bilibilifocus.core.service.VideoActionService
import org.bilibilifocus.core.service.VideoInfoService

class FocusVideoViewModel(
    private val service: VideoInfoService,
    private val actionService: VideoActionService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = VideoUiState.Error(e.message ?: "加载失败")
    })

    private val _state = MutableStateFlow<VideoUiState>(VideoUiState.Loading)
    val state: StateFlow<VideoUiState> = _state.asStateFlow()

    private val _comments = MutableStateFlow<List<VideoComment>>(emptyList())
    val comments: StateFlow<List<VideoComment>> = _comments.asStateFlow()
    private val _interactionState = MutableStateFlow(VideoInteractionState())
    val interactionState: StateFlow<VideoInteractionState> = _interactionState.asStateFlow()
    private val _isFullscreen = MutableStateFlow(false)
    val isFullscreen: StateFlow<Boolean> = _isFullscreen.asStateFlow()
    private val _isCompletingFullscreenExit = MutableStateFlow(false)
    val isCompletingFullscreenExit: StateFlow<Boolean> = _isCompletingFullscreenExit.asStateFlow()
    private val _danmakuState = MutableStateFlow(VideoDanmakuUiState())
    val danmakuState: StateFlow<VideoDanmakuUiState> = _danmakuState.asStateFlow()
    private var loadedBvid: String? = null
    private var loadedInfo: VideoInfo? = null
    private val watchHistoryMutex = Mutex()
    private var lastQueuedWatchHistoryReport: WatchHistoryReport? = null
    private var danmakuContext: DanmakuContext? = null
    private var danmakuView: VideoDanmakuView? = null
    private var danmakuEnabled = true
    private var danmakuRevision = 0
    private var danmakuViewJob: Job? = null
    private val danmakuSegmentJobs = mutableMapOf<Int, Job>()
    private val danmakuSegmentCache = mutableMapOf<Int, List<VideoDanmaku>>()

    fun requestFullscreen() {
        _isCompletingFullscreenExit.value = false
        _isFullscreen.value = true
    }

    fun beginFullscreenExit() {
        if (!_isFullscreen.value || _isCompletingFullscreenExit.value) return
        _isCompletingFullscreenExit.value = true
    }

    fun completeFullscreenExit() {
        _isFullscreen.value = false
        _isCompletingFullscreenExit.value = false
    }

    fun loadIfNeeded(bvid: String) {
        if (loadedBvid == bvid && _state.value is VideoUiState.Loaded) return
        load(bvid)
    }

    fun load(bvid: String) {
        scope.launch {
            resetDanmakuSession()
            _state.value = VideoUiState.Loading
            _comments.value = emptyList()
            _interactionState.value = VideoInteractionState()
            try {
                val info = service.fetchVideoInfo(bvid)
                loadedBvid = bvid
                loadedInfo = info
                _state.value = VideoUiState.Loaded(info)
                loadComments(info.aid)
                loadInteractions(info.aid)
            } catch (e: VideoInfoService.ServiceError) {
                _state.value = when (e) {
                    VideoInfoService.ServiceError.LoginRequired -> VideoUiState.Error("需要登录")
                    is VideoInfoService.ServiceError.Api -> VideoUiState.Error("API错误 ${e.code}: ${e.message}")
                    VideoInfoService.ServiceError.InvalidResponse -> VideoUiState.Error("接口数据异常")
                }
            } catch (e: Exception) {
                _state.value = VideoUiState.Error(e.message ?: "加载失败")
            }
        }
    }

    fun configureDanmaku(
        aid: Long,
        cid: Long,
        durationSeconds: Long,
        enabled: Boolean,
        playbackPositionMillis: Long,
    ) {
        val next = DanmakuContext(aid, cid, durationSeconds.coerceAtLeast(0) * 1_000)
        val contextChanged = danmakuContext != next
        val wasEnabled = danmakuEnabled
        danmakuEnabled = enabled
        if (contextChanged) {
            resetDanmakuSession()
            danmakuContext = next
        }
        if (!enabled) {
            if (!contextChanged && wasEnabled) suspendDanmakuRequests()
            return
        }
        if (danmakuView == null && danmakuViewJob == null) {
            loadDanmakuView(playbackPositionMillis)
        } else {
            updateDanmakuPosition(playbackPositionMillis)
        }
    }

    fun setDanmakuEnabled(enabled: Boolean, playbackPositionMillis: Long) {
        val changed = danmakuEnabled != enabled
        danmakuEnabled = enabled
        if (!enabled) {
            if (changed) suspendDanmakuRequests()
            return
        }
        val context = danmakuContext ?: return
        configureDanmaku(
            aid = context.aid,
            cid = context.cid,
            durationSeconds = context.durationMillis / 1_000,
            enabled = true,
            playbackPositionMillis = playbackPositionMillis,
        )
    }

    fun updateDanmakuPosition(playbackPositionMillis: Long) {
        if (!danmakuEnabled) return
        val view = danmakuView ?: return
        if (view.isClosed) return
        VideoDanmakuSegmentScheduler.segmentIndexes(
            playbackPositionMillis = playbackPositionMillis,
            segmentDurationMillis = view.segmentDurationMillis,
            totalSegments = view.totalSegments,
        ).forEach(::ensureDanmakuSegment)
    }

    fun retryDanmaku(playbackPositionMillis: Long) {
        danmakuViewJob?.cancel()
        danmakuSegmentJobs.values.forEach(Job::cancel)
        danmakuSegmentJobs.clear()
        _danmakuState.value = _danmakuState.value.copy(
            status = VideoDanmakuLoadStatus.LOADING,
            message = null,
        )
        if (danmakuView == null) {
            loadDanmakuView(playbackPositionMillis)
        } else {
            updateDanmakuPosition(playbackPositionMillis)
        }
    }

    private fun loadDanmakuView(playbackPositionMillis: Long) {
        val context = danmakuContext ?: return
        val revision = danmakuRevision
        _danmakuState.value = _danmakuState.value.copy(
            status = VideoDanmakuLoadStatus.LOADING,
            message = null,
        )
        danmakuViewJob = scope.launch {
            val view = try {
                service.fetchDanmakuView(context.aid, context.cid)
            } catch (_: Exception) {
                val total = if (context.durationMillis > 0) {
                    ((context.durationMillis + DEFAULT_DANMAKU_SEGMENT_MILLIS - 1) /
                        DEFAULT_DANMAKU_SEGMENT_MILLIS).toInt()
                } else {
                    0
                }
                VideoDanmakuView(
                    state = 0,
                    segmentDurationMillis = DEFAULT_DANMAKU_SEGMENT_MILLIS,
                    totalSegments = total,
                    count = 0,
                )
            }
            if (revision != danmakuRevision || context != danmakuContext) return@launch
            danmakuViewJob = null
            danmakuView = view
            if (view.isClosed) {
                _danmakuState.value = VideoDanmakuUiState(
                    status = VideoDanmakuLoadStatus.CLOSED,
                    message = "该视频未开启弹幕",
                )
                return@launch
            }
            updateDanmakuPosition(playbackPositionMillis)
        }
    }

    private fun ensureDanmakuSegment(segmentIndex: Int) {
        val context = danmakuContext ?: return
        val view = danmakuView ?: return
        if (segmentIndex <= 0 || (view.totalSegments > 0 && segmentIndex > view.totalSegments)) return
        if (danmakuSegmentCache.containsKey(segmentIndex) || danmakuSegmentJobs.containsKey(segmentIndex)) return

        val revision = danmakuRevision
        val job = scope.launch {
            try {
                val segment = service.fetchDanmakuSegment(context.aid, context.cid, segmentIndex)
                if (revision != danmakuRevision || context != danmakuContext) return@launch
                if (segment.isClosed) {
                    markDanmakuClosed()
                    return@launch
                }
                danmakuSegmentCache[segmentIndex] = segment.danmakus
                _danmakuState.value = VideoDanmakuUiState(
                    status = VideoDanmakuLoadStatus.READY,
                    danmakus = danmakuSegmentCache.toSortedMap().values
                        .flatten()
                        .sortedWith(compareBy<VideoDanmaku> { it.progressMillis }.thenByDescending { it.weight }),
                )
            } catch (_: Exception) {
                if (revision != danmakuRevision || context != danmakuContext) return@launch
                if (danmakuSegmentCache.isEmpty()) {
                    _danmakuState.value = VideoDanmakuUiState(
                        status = VideoDanmakuLoadStatus.FAILED,
                        message = "弹幕加载失败",
                    )
                }
            } finally {
                if (revision == danmakuRevision) danmakuSegmentJobs.remove(segmentIndex)
            }
        }
        danmakuSegmentJobs[segmentIndex] = job
    }

    private fun resetDanmakuSession() {
        danmakuRevision += 1
        danmakuViewJob?.cancel()
        danmakuViewJob = null
        danmakuSegmentJobs.values.forEach(Job::cancel)
        danmakuSegmentJobs.clear()
        danmakuSegmentCache.clear()
        danmakuView = null
        danmakuContext = null
        _danmakuState.value = VideoDanmakuUiState()
    }

    private fun suspendDanmakuRequests() {
        danmakuRevision += 1
        danmakuViewJob?.cancel()
        danmakuViewJob = null
        danmakuSegmentJobs.values.forEach(Job::cancel)
        danmakuSegmentJobs.clear()
    }

    private fun markDanmakuClosed() {
        danmakuView = danmakuView?.copy(state = 1)
        danmakuSegmentCache.clear()
        suspendDanmakuRequests()
        _danmakuState.value = VideoDanmakuUiState(
            status = VideoDanmakuLoadStatus.CLOSED,
            message = "该视频未开启弹幕",
        )
    }

    fun toggleLike() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        scope.launch {
            try {
                actionService.toggleLike(info.aid, !current.liked)
                _interactionState.value = current.copy(liked = !current.liked, loading = false)
                updateStats { stats ->
                    stats.copy(likes = (stats.likes + if (!current.liked) 1 else -1).coerceAtLeast(0))
                }
            } catch (_: Exception) {
            }
        }
    }

    fun coin() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        if (current.coined) return
        scope.launch {
            try {
                actionService.coin(info.aid)
                _interactionState.value = current.copy(coined = true, loading = false)
                updateStats { stats -> stats.copy(coins = stats.coins + 1) }
            } catch (_: Exception) {
            }
        }
    }

    fun toggleFavorite() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        scope.launch {
            try {
                val folderId = actionService.toggleFavorite(
                    aid = info.aid,
                    favorited = !current.favorited,
                    folderId = current.favoriteFolderId,
                )
                _interactionState.value = current.copy(
                    favorited = !current.favorited,
                    favoriteFolderId = folderId,
                    loading = false,
                )
                updateStats { stats ->
                    stats.copy(favorites = (stats.favorites + if (!current.favorited) 1 else -1).coerceAtLeast(0))
                }
            } catch (_: Exception) {
            }
        }
    }

    fun reportWatchHistory(
        aid: Long,
        cid: Long,
        progressSeconds: Long,
        force: Boolean,
    ) {
        val report = WatchHistoryReport(
            aid = aid,
            cid = cid,
            progressSeconds = progressSeconds.coerceAtLeast(0),
        )
        val previous = lastQueuedWatchHistoryReport
        if (previous?.aid == report.aid && previous.cid == report.cid) {
            if (previous.progressSeconds == report.progressSeconds) return
            if (!force && kotlin.math.abs(previous.progressSeconds - report.progressSeconds) < 15) return
        }

        lastQueuedWatchHistoryReport = report
        scope.launch {
            watchHistoryMutex.withLock {
                try {
                    actionService.reportWatchHistory(
                        aid = report.aid,
                        cid = report.cid,
                        progressSeconds = report.progressSeconds,
                    )
                } catch (_: Exception) {
                    // Playback must remain uninterrupted when the account is signed out
                    // or the optional history endpoint is temporarily unavailable.
                }
            }
        }
    }

    private fun loadComments(oid: Long) {
        scope.launch {
            try {
                val (comments, _) = service.fetchComments(oid)
                _comments.value = comments
            } catch (_: Exception) {
            }
        }
    }

    private fun loadInteractions(aid: Long) {
        scope.launch {
            _interactionState.value = _interactionState.value.copy(loading = true)
            try {
                _interactionState.value = actionService.fetchInteractionState(aid)
            } catch (_: Exception) {
                _interactionState.value = _interactionState.value.copy(loading = false)
            }
        }
    }

    private fun updateStats(transform: (org.bilibilifocus.core.model.VideoStats) -> org.bilibilifocus.core.model.VideoStats) {
        val current = _state.value as? VideoUiState.Loaded ?: return
        val updatedInfo = current.info.copy(stats = transform(current.info.stats))
        loadedInfo = updatedInfo
        _state.value = VideoUiState.Loaded(updatedInfo)
    }

    fun onCleared() {
        resetDanmakuSession()
        scope.cancel()
    }

    private data class DanmakuContext(
        val aid: Long,
        val cid: Long,
        val durationMillis: Long,
    )

    private data class WatchHistoryReport(
        val aid: Long,
        val cid: Long,
        val progressSeconds: Long,
    )

    companion object {
        private const val DEFAULT_DANMAKU_SEGMENT_MILLIS = 360_000L
    }
}

sealed class VideoUiState {
    data object Loading : VideoUiState()
    data class Loaded(val info: VideoInfo) : VideoUiState()
    data class Error(val message: String) : VideoUiState()
}

enum class VideoDanmakuLoadStatus {
    IDLE,
    LOADING,
    READY,
    CLOSED,
    FAILED,
}

data class VideoDanmakuUiState(
    val status: VideoDanmakuLoadStatus = VideoDanmakuLoadStatus.IDLE,
    val danmakus: List<VideoDanmaku> = emptyList(),
    val message: String? = null,
)
