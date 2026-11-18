package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.CommentCursor
import org.bilibilifocus.core.model.CommentTarget
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.core.service.OpusService
import org.bilibilifocus.core.service.VideoInfoService

class FocusOpusViewModel(
    private val service: OpusService,
    private val commentService: VideoInfoService? = null,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = OpusUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null
    private var commentsJob: Job? = null
    private var generation = 0L

    private val _state = MutableStateFlow<OpusUiState>(OpusUiState.Idle)
    val state: StateFlow<OpusUiState> = _state.asStateFlow()

    private val _comments = MutableStateFlow<List<VideoComment>>(emptyList())
    val comments: StateFlow<List<VideoComment>> = _comments.asStateFlow()

    private val _commentState = MutableStateFlow(VideoCommentsUiState())
    val commentState: StateFlow<VideoCommentsUiState> = _commentState.asStateFlow()

    private val _commentTotalCount = MutableStateFlow(0)
    val commentTotalCount: StateFlow<Int> = _commentTotalCount.asStateFlow()

    private val _actionError = MutableStateFlow<String?>(null)
    val actionError: StateFlow<String?> = _actionError.asStateFlow()

    private var loadedId: String? = null
    private var loadedDetail: OpusDetail? = null
    private var commentTarget: CommentTarget? = null
    private var nextCommentCursor: CommentCursor? = null
    private val seenCommentCursors = mutableSetOf<CommentCursor>()

    fun loadIfNeeded(id: String) {
        if (loadedId == id && _state.value is OpusUiState.Loaded) return
        load(id)
    }

    fun load(id: String) {
        loadJob?.cancel()
        commentsJob?.cancel()
        generation += 1
        val revision = generation
        loadJob = scope.launch {
            _state.value = OpusUiState.Loading
            _comments.value = emptyList()
            _commentState.value = VideoCommentsUiState()
            _commentTotalCount.value = 0
            _actionError.value = null
            loadedDetail = null
            commentTarget = null
            nextCommentCursor = null
            seenCommentCursors.clear()
            try {
                val detail = service.fetchOpusDetail(id)
                if (revision != generation) return@launch
                loadedId = id
                loadedDetail = detail
                _state.value = OpusUiState.Loaded(detail)
                loadInitialComments(revision, detail)
            } catch (e: OpusService.ServiceError) {
                if (revision == generation) {
                    _state.value = if (e == OpusService.ServiceError.LoginRequired) {
                        OpusUiState.LoginRequired
                    } else {
                        OpusUiState.Failed(e.message ?: "加载失败")
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (revision == generation) {
                    _state.value = OpusUiState.Failed(e.message ?: "加载失败")
                }
            }
        }
    }

    private fun loadInitialComments(revision: Long, detail: OpusDetail) {
        commentsJob?.cancel()
        commentsJob = scope.launch {
            _commentState.value = VideoCommentsUiState(isLoading = true)
            try {
                val resolvedTarget = service.resolveCommentTarget(detail)
                if (revision != generation) return@launch
                commentTarget = resolvedTarget
                val infoService = commentService
                if (infoService != null && resolvedTarget != null) {
                    fetchCommentPageLocked(revision, infoService, resolvedTarget, append = false)
                } else if (infoService == null && detail.commentId > 0) {
                    val (list, total) = service.fetchComments(detail.commentId, detail.id)
                    if (revision != generation) return@launch
                    _comments.value = list
                    _commentTotalCount.value = total
                    _commentState.value = VideoCommentsUiState(isLoading = false)
                } else {
                    _commentState.value = VideoCommentsUiState(isLoading = false)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) {
                    _commentState.value = _commentState.value.copy(
                        isLoading = false,
                        error = error.message ?: "评论加载失败",
                    )
                }
            }
        }
    }

    fun loadComments(append: Boolean = false) {
        val infoService = commentService ?: return
        val detail = loadedDetail ?: return
        if (_commentState.value.isLoading) return
        if (append && nextCommentCursor == null) return
        val revision = generation
        commentsJob = scope.launch {
            _commentState.value = _commentState.value.copy(isLoading = true, error = null)
            try {
                val target = commentTarget ?: service.resolveCommentTarget(detail).also {
                    if (revision == generation) commentTarget = it
                }
                if (revision != generation) return@launch
                if (target == null) {
                    _commentState.value = _commentState.value.copy(isLoading = false)
                    return@launch
                }
                fetchCommentPageLocked(revision, infoService, target, append = append)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) {
                    _commentState.value = _commentState.value.copy(
                        isLoading = false,
                        error = error.message ?: "评论加载失败",
                    )
                }
            }
        }
    }

    private suspend fun fetchCommentPageLocked(
        revision: Long,
        infoService: VideoInfoService,
        target: CommentTarget,
        append: Boolean,
    ) {
        val cursor = if (append) nextCommentCursor ?: return else CommentCursor()
        val mid = infoService.currentAccountMid()
        val page = infoService.fetchCommentPage(target.oid, cursor, type = target.type)
        if (revision != generation) return
        if (!append) seenCommentCursors.clear()
        seenCommentCursors.add(cursor)
        nextCommentCursor = page.cursor.takeIf { !it.nextOffset.isNullOrBlank() && it !in seenCommentCursors }
        _comments.value = ((if (append) _comments.value else emptyList()) + page.comments).distinctBy { it.rpid }
        _commentTotalCount.value = page.totalCount.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        _commentState.value = _commentState.value.copy(
            isLoading = false,
            error = null,
            hasMore = nextCommentCursor != null,
            accountMid = mid,
            replies = if (append) _commentState.value.replies else emptyMap(),
        )
    }

    fun loadReplies(root: VideoComment) {
        val infoService = commentService ?: return
        val target = commentTarget ?: return
        val current = _commentState.value.replies[root.rpid] ?: VideoRepliesUiState(root.replies)
        if (current.isLoading || current.nextPage == null) return
        val revision = generation
        setReplies(root.rpid, current.copy(isLoading = true, error = null))
        scope.launch {
            try {
                val page = infoService.fetchCommentReplies(target.oid, root.rpid, current.nextPage, type = target.type)
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

    fun toggleCommentLike(comment: VideoComment) = commentAction(comment.rpid) { infoService, target, mid, isCurrent ->
        infoService.setCommentLiked(target.oid, comment.rpid, !comment.isLiked, mid, type = target.type)
        if (!isCurrent()) return@commentAction
        updateComment(comment.rpid) {
            it.copy(
                isLiked = !comment.isLiked,
                likeCount = (it.likeCount + if (comment.isLiked) -1 else 1).coerceAtLeast(0),
            )
        }
    }

    fun deleteComment(comment: VideoComment) = commentAction(comment.rpid) { infoService, target, mid, isCurrent ->
        if (comment.mid != mid) return@commentAction
        infoService.deleteComment(target.oid, comment.rpid, mid, type = target.type)
        if (!isCurrent()) return@commentAction
        val parentID = _comments.value.firstOrNull { root -> root.replies.any { it.rpid == comment.rpid } }?.rpid
            ?: _commentState.value.replies.entries.firstOrNull { (_, value) -> value.replies.any { it.rpid == comment.rpid } }?.key
        val removedRoot = _comments.value.any { it.rpid == comment.rpid }
        _comments.value = _comments.value.filterNot { it.rpid == comment.rpid }
            .map { root -> root.copy(replies = root.replies.filterNot { it.rpid == comment.rpid }) }
        _commentState.value = _commentState.value.copy(
            replies = (_commentState.value.replies - comment.rpid).mapValues { (_, value) ->
                value.copy(replies = value.replies.filterNot { it.rpid == comment.rpid })
            },
        )
        if (parentID != null) updateComment(parentID) { it.copy(replyCount = (it.replyCount - 1).coerceAtLeast(0)) }
        if (removedRoot && _commentTotalCount.value > 0) _commentTotalCount.value -= 1
    }

    fun sendComment(message: String, root: VideoComment? = null, parent: VideoComment? = null, onSent: () -> Unit) {
        if (message.isBlank() || message.length > 1000 || _commentState.value.isSending) return
        val infoService = commentService ?: return
        val detail = loadedDetail ?: return
        val mid = _commentState.value.accountMid ?: run {
            _actionError.value = "请先登录后发表评论"
            return
        }
        val revision = generation
        _commentState.value = _commentState.value.copy(isSending = true)
        scope.launch {
            try {
                val target = commentTarget ?: service.resolveCommentTarget(detail).also {
                    if (revision == generation) commentTarget = it
                } ?: throw IllegalStateException("该动态暂不支持评论")
                val comment = infoService.sendComment(
                    aid = target.oid,
                    message = message.trim(),
                    root = root?.rpid ?: 0,
                    parent = parent?.rpid ?: root?.rpid ?: 0,
                    expectedMid = mid,
                    type = target.type,
                )
                if (revision != generation) return@launch
                if (root == null) {
                    _comments.value = listOf(comment) + _comments.value
                    _commentTotalCount.value += 1
                } else {
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

    fun dismissActionError() {
        _actionError.value = null
    }

    private fun commentAction(
        rpid: Long,
        operation: suspend (VideoInfoService, CommentTarget, Long, () -> Boolean) -> Unit,
    ) {
        val infoService = commentService ?: return
        val target = commentTarget ?: return
        val current = _commentState.value
        val mid = current.accountMid ?: run {
            _actionError.value = "请先登录后操作评论"
            return
        }
        if (rpid in current.actionsInFlight) return
        val revision = generation
        _commentState.value = current.copy(actionsInFlight = current.actionsInFlight + rpid)
        scope.launch {
            try {
                operation(infoService, target, mid) { revision == generation && _commentState.value.accountMid == mid }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (revision == generation) _actionError.value = error.message ?: "评论操作失败"
            } finally {
                if (revision == generation) {
                    _commentState.value = _commentState.value.copy(actionsInFlight = _commentState.value.actionsInFlight - rpid)
                }
            }
        }
    }

    private fun setReplies(root: Long, state: VideoRepliesUiState) {
        _commentState.value = _commentState.value.copy(replies = _commentState.value.replies + (root to state))
    }

    private fun updateComment(rpid: Long, transform: (VideoComment) -> VideoComment) {
        fun update(comment: VideoComment): VideoComment =
            if (comment.rpid == rpid) transform(comment) else comment.copy(replies = comment.replies.map { if (it.rpid == rpid) transform(it) else it })
        _comments.value = _comments.value.map(::update)
        _commentState.value = _commentState.value.copy(
            replies = _commentState.value.replies.mapValues { (_, value) -> value.copy(replies = value.replies.map(::update)) },
        )
    }

    fun onCleared() {
        loadJob?.cancel()
        commentsJob?.cancel()
        scope.cancel()
    }
}

sealed class OpusUiState {
    data object Idle : OpusUiState()
    data object Loading : OpusUiState()
    data object LoginRequired : OpusUiState()
    data class Failed(val message: String) : OpusUiState()
    data class Loaded(val detail: OpusDetail) : OpusUiState()
}
