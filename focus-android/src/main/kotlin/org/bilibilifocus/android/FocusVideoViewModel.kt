package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuSegmentScheduler
import org.bilibilifocus.core.model.VideoDanmakuView
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState
import org.bilibilifocus.core.model.CommentCursor
import org.bilibilifocus.core.model.VideoSubtitleTrack
import org.bilibilifocus.core.model.VideoSubtitleDocument
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
    private val _commentState = MutableStateFlow(VideoCommentsUiState())
    val commentState = _commentState.asStateFlow()
    private val _subtitleState = MutableStateFlow(VideoSubtitleUiState())
    val subtitleState = _subtitleState.asStateFlow()
    private val _actionError = MutableStateFlow<String?>(null)
    val actionError = _actionError.asStateFlow()
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
    private var loadedAccountMid: Long? = null
    private var loadJob: Job? = null
    private var generation = 0L
    private var commentsJob: Job? = null
    private var nextCommentCursor: CommentCursor? = null
    private val seenCommentCursors = mutableSetOf<CommentCursor>()
    private var subtitleJob: Job? = null
    private var subtitleContext: Pair<Long, Long>? = null
    private var subtitleTracksLoaded = false
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
        loadJob?.cancel()
        commentsJob?.cancel()
        subtitleJob?.cancel()
        generation += 1
        val revision = generation
        loadJob = scope.launch {
            resetDanmakuSession()
            subtitleContext = null
            subtitleTracksLoaded = false
            _subtitleState.value = VideoSubtitleUiState()
            _state.value = VideoUiState.Loading
            _comments.value = emptyList()
            nextCommentCursor = null
            seenCommentCursors.clear()
            _commentState.value = VideoCommentsUiState()
            _actionError.value = null
            _interactionState.value = VideoInteractionState()
            try {
                val info = service.fetchVideoInfo(bvid)
                loadedAccountMid = service.currentAccountMid()
                if (revision != generation) return@launch
                loadedBvid = bvid
                loadedInfo = info
                _state.value = VideoUiState.Loaded(info)
                loadComments()
                loadInteractions(info.aid)
            } catch (e: VideoInfoService.ServiceError) {
                _state.value = when (e) {
                    VideoInfoService.ServiceError.LoginRequired -> VideoUiState.Error("需要登录")
                    is VideoInfoService.ServiceError.Api -> VideoUiState.Error("API错误 ${e.code}: ${e.message}")
                    VideoInfoService.ServiceError.InvalidResponse -> VideoUiState.Error("接口数据异常")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = VideoUiState.Error(e.message ?: "加载失败")
            }
        }
    }

    fun configureSubtitles(aid: Long, cid: Long, enabled: Boolean, preferredLanguage: String) {
        val context = aid to cid
        if (subtitleContext != context) {
            subtitleContext = context
            subtitleTracksLoaded = false
            _subtitleState.value = VideoSubtitleUiState()
        }
        subtitleJob?.cancel()
        subtitleJob = scope.launch {
            _subtitleState.value = _subtitleState.value.copy(isLoading = true, error = null, document = null)
            try {
                val tracks = if (subtitleTracksLoaded) _subtitleState.value.tracks else service.fetchSubtitleTracks(aid, cid)
                if (subtitleContext != context) return@launch
                subtitleTracksLoaded = true
                val selected = tracks.firstOrNull { !it.isLocked && it.languageCode == preferredLanguage }
                    ?: tracks.firstOrNull { !it.isLocked && it.languageCode.startsWith("zh") }
                    ?: tracks.firstOrNull { !it.isLocked }
                _subtitleState.value = VideoSubtitleUiState(tracks = tracks, selectedTrack = selected, isLoading = enabled && selected != null)
                if (enabled && selected != null) {
                    val document = service.fetchSubtitleDocument(selected)
                    if (subtitleContext == context) _subtitleState.value = _subtitleState.value.copy(document = document, isLoading = false)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (subtitleContext == context) _subtitleState.value = _subtitleState.value.copy(isLoading = false, error = error.message ?: "字幕加载失败")
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
            } catch (cancelled: CancellationException) {
                throw cancelled
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
                    segments = (_danmakuState.value.segments +
                        VideoDanmakuRenderSegment(segmentIndex, segment.danmakus)).sortedBy { it.index },
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
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
        if (current.loading) return
        val mid = loadedAccountMid ?: run { _actionError.value = "请先登录后点赞"; return }
        val revision = generation
        _interactionState.value = current.copy(loading = true)
        scope.launch {
            try {
                actionService.toggleLike(info.aid, !current.liked, expectedMid = mid)
                if (revision != generation) return@launch
                _interactionState.value = current.copy(liked = !current.liked, loading = false)
                updateStats { stats ->
                    stats.copy(likes = (stats.likes + if (!current.liked) 1 else -1).coerceAtLeast(0))
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _actionError.value = error.message ?: "点赞失败"
            } finally {
                if (revision == generation) _interactionState.value = _interactionState.value.copy(loading = false)
            }
        }
    }

    fun coin() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        if (current.coined || current.loading) return
        val mid = loadedAccountMid ?: run { _actionError.value = "请先登录后投币"; return }
        val revision = generation
        _interactionState.value = current.copy(loading = true)
        scope.launch {
            try {
                actionService.coin(info.aid, expectedMid = mid)
                if (revision != generation) return@launch
                _interactionState.value = current.copy(coined = true, loading = false)
                updateStats { stats -> stats.copy(coins = stats.coins + 1) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _actionError.value = error.message ?: "投币失败"
            } finally {
                if (revision == generation) _interactionState.value = _interactionState.value.copy(loading = false)
            }
        }
    }

    fun toggleFavorite() {
        val info = loadedInfo ?: return
        val current = _interactionState.value
        if (current.loading) return
        val mid = loadedAccountMid ?: run { _actionError.value = "请先登录后收藏"; return }
        val revision = generation
        _interactionState.value = current.copy(loading = true)
        scope.launch {
            try {
                val folderId = actionService.toggleFavorite(
                    aid = info.aid,
                    favorited = !current.favorited,
                    folderId = current.favoriteFolderId,
                    expectedMid = mid,
                )
                if (revision != generation) return@launch
                _interactionState.value = current.copy(
                    favorited = !current.favorited,
                    favoriteFolderId = folderId,
                    loading = false,
                )
                updateStats { stats ->
                    stats.copy(favorites = (stats.favorites + if (!current.favorited) 1 else -1).coerceAtLeast(0))
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _actionError.value = error.message ?: "收藏操作失败"
            } finally {
                if (revision == generation) _interactionState.value = _interactionState.value.copy(loading = false)
            }
        }
    }

    fun loadComments(append: Boolean = false) {
        val info = loadedInfo ?: return
        if (_commentState.value.isLoading) return
        val cursor = if (append) nextCommentCursor ?: return else CommentCursor()
        val revision = generation
        commentsJob = scope.launch {
            _commentState.value = _commentState.value.copy(isLoading = true, error = null)
            try {
                val mid = service.currentAccountMid()
                val page = service.fetchCommentPage(info.aid, cursor)
                if (revision != generation) return@launch
                if (!append) seenCommentCursors.clear()
                seenCommentCursors.add(cursor)
                nextCommentCursor = page.cursor.takeIf { !it.nextOffset.isNullOrBlank() && it !in seenCommentCursors }
                _comments.value = ((if (append) _comments.value else emptyList()) + page.comments).distinctBy { it.rpid }
                _commentState.value = _commentState.value.copy(
                    isLoading = false, hasMore = nextCommentCursor != null, accountMid = mid,
                    replies = if (append) _commentState.value.replies else emptyMap(),
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _commentState.value = _commentState.value.copy(isLoading = false, error = error.message ?: "评论加载失败")
            }
        }
    }

    fun loadReplies(root: VideoComment) {
        val info = loadedInfo ?: return
        val current = _commentState.value.replies[root.rpid] ?: VideoRepliesUiState(root.replies)
        if (current.isLoading || current.nextPage == null) return
        val revision = generation
        setReplies(root.rpid, current.copy(isLoading = true, error = null))
        scope.launch {
            try {
                val page = service.fetchCommentReplies(info.aid, root.rpid, current.nextPage)
                if (revision != generation) return@launch
                val displayed = _commentState.value.replies[root.rpid]?.replies ?: current.replies
                setReplies(root.rpid, VideoRepliesUiState((displayed + page.replies).distinctBy { it.rpid }, page.nextPage))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) setReplies(root.rpid, current.copy(error = error.message ?: "回复加载失败"))
            }
        }
    }

    fun toggleCommentLike(comment: VideoComment) = commentAction(comment.rpid) { info, mid, isCurrent ->
        service.setCommentLiked(info.aid, comment.rpid, !comment.isLiked, mid)
        if (!isCurrent()) return@commentAction
        updateComment(comment.rpid) { it.copy(isLiked = !comment.isLiked, likeCount = (it.likeCount + if (comment.isLiked) -1 else 1).coerceAtLeast(0)) }
    }

    fun deleteComment(comment: VideoComment) = commentAction(comment.rpid) { info, mid, isCurrent ->
        if (comment.mid != mid) return@commentAction
        service.deleteComment(info.aid, comment.rpid, mid)
        if (!isCurrent()) return@commentAction
        val parentID = _comments.value.firstOrNull { root -> root.replies.any { it.rpid == comment.rpid } }?.rpid
            ?: _commentState.value.replies.entries.firstOrNull { (_, value) -> value.replies.any { it.rpid == comment.rpid } }?.key
        _comments.value = _comments.value.filterNot { it.rpid == comment.rpid }.map { root -> root.copy(replies = root.replies.filterNot { it.rpid == comment.rpid }) }
        _commentState.value = _commentState.value.copy(replies = (_commentState.value.replies - comment.rpid).mapValues { (_, value) -> value.copy(replies = value.replies.filterNot { it.rpid == comment.rpid }) })
        if (parentID != null) updateComment(parentID) { it.copy(replyCount = (it.replyCount - 1).coerceAtLeast(0)) }
    }

    fun sendComment(message: String, root: VideoComment? = null, parent: VideoComment? = null, onSent: () -> Unit) {
        if (message.isBlank() || message.length > 1000 || _commentState.value.isSending) return
        val info = loadedInfo ?: return
        val mid = _commentState.value.accountMid ?: run { _actionError.value = "请先登录后发表评论"; return }
        val revision = generation
        _commentState.value = _commentState.value.copy(isSending = true)
        scope.launch {
            try {
                val comment = service.sendComment(info.aid, message.trim(), root?.rpid ?: 0, parent?.rpid ?: root?.rpid ?: 0, mid)
                if (revision != generation) return@launch
                if (root == null) _comments.value = listOf(comment) + _comments.value
                else {
                    val replies = _commentState.value.replies[root.rpid] ?: VideoRepliesUiState(root.replies)
                    setReplies(root.rpid, replies.copy(replies = (replies.replies + comment).distinctBy { it.rpid }))
                    updateComment(root.rpid) { it.copy(replyCount = it.replyCount + 1) }
                }
                onSent()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _actionError.value = error.message ?: "发送失败，请确认后重试"
            } finally {
                if (revision == generation) _commentState.value = _commentState.value.copy(isSending = false)
            }
        }
    }

    fun dismissActionError() { _actionError.value = null }

    private fun commentAction(rpid: Long, operation: suspend (VideoInfo, Long, () -> Boolean) -> Unit) {
        val info = loadedInfo ?: return
        val current = _commentState.value
        val mid = current.accountMid ?: run { _actionError.value = "请先登录后操作评论"; return }
        if (rpid in current.actionsInFlight) return
        val revision = generation
        _commentState.value = current.copy(actionsInFlight = current.actionsInFlight + rpid)
        scope.launch {
            try {
                operation(info, mid) { revision == generation && _commentState.value.accountMid == mid }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _actionError.value = error.message ?: "评论操作失败"
            } finally {
                if (revision == generation) _commentState.value = _commentState.value.copy(actionsInFlight = _commentState.value.actionsInFlight - rpid)
            }
        }
    }

    private fun setReplies(root: Long, state: VideoRepliesUiState) {
        _commentState.value = _commentState.value.copy(replies = _commentState.value.replies + (root to state))
    }

    private fun updateComment(rpid: Long, transform: (VideoComment) -> VideoComment) {
        fun update(comment: VideoComment): VideoComment = if (comment.rpid == rpid) transform(comment) else comment.copy(replies = comment.replies.map { if (it.rpid == rpid) transform(it) else it })
        _comments.value = _comments.value.map(::update)
        _commentState.value = _commentState.value.copy(replies = _commentState.value.replies.mapValues { (_, value) -> value.copy(replies = value.replies.map(::update)) })
    }

    private fun loadInteractions(aid: Long) {
        val revision = generation
        scope.launch {
            _interactionState.value = _interactionState.value.copy(loading = true)
            try {
                val value = actionService.fetchInteractionState(aid)
                if (revision == generation) _interactionState.value = value
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                if (revision == generation) _interactionState.value = _interactionState.value.copy(loading = false)
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
    val segments: List<VideoDanmakuRenderSegment> = emptyList(),
    val message: String? = null,
)

data class VideoDanmakuRenderSegment(val index: Int, val danmakus: List<VideoDanmaku>)

data class VideoCommentsUiState(
    val isLoading: Boolean = false,
    val error: String? = null,
    val hasMore: Boolean = false,
    val accountMid: Long? = null,
    val replies: Map<Long, VideoRepliesUiState> = emptyMap(),
    val actionsInFlight: Set<Long> = emptySet(),
    val isSending: Boolean = false,
)

data class VideoRepliesUiState(
    val replies: List<VideoComment> = emptyList(),
    val nextPage: Int? = 1,
    val isLoading: Boolean = false,
    val error: String? = null,
)

data class VideoSubtitleUiState(
    val tracks: List<VideoSubtitleTrack> = emptyList(),
    val selectedTrack: VideoSubtitleTrack? = null,
    val document: VideoSubtitleDocument? = null,
    val isLoading: Boolean = false,
    val error: String? = null,
)
