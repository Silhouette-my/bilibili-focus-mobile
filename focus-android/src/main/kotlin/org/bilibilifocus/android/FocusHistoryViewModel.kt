package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.model.HistoryPage
import org.bilibilifocus.core.paging.CursorPage
import org.bilibilifocus.core.paging.CursorPager
import org.bilibilifocus.core.service.HistoryService

internal fun interface HistoryPageFetcher {
    suspend fun fetchPage(
        max: Long,
        viewAt: Long,
        business: String,
    ): HistoryPage
}

class FocusHistoryViewModel internal constructor(
    private val pageFetcher: HistoryPageFetcher,
    dispatcher: CoroutineDispatcher,
) {
    constructor(service: HistoryService) : this(
        pageFetcher = HistoryPageFetcher(service::fetchHistory),
        dispatcher = Dispatchers.Main,
    )

    private val _state = MutableStateFlow<HistoryUiState>(HistoryUiState.Idle)
    val state: StateFlow<HistoryUiState> = _state.asStateFlow()

    private val scope = CoroutineScope(
        SupervisorJob() +
            dispatcher +
            CoroutineExceptionHandler { _, error ->
                _state.value = HistoryUiState.Failed(error.message ?: "加载失败")
            },
    )
    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private val pager = CursorPager<HistoryItem, HistoryCursor, String>(
        firstCursor = null,
        keyOf = HistoryItem::stableKey,
        loadPage = ::loadCursorPage,
    )

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    fun loadIfNeeded() {
        if (_state.value is HistoryUiState.Loaded) return
        reload()
    }

    fun reload() {
        loadJob?.cancel()
        loadMoreJob?.cancel()
        _isLoadingMore.value = false
        loadJob = scope.launch {
            _state.value = HistoryUiState.Loading
            pager.refresh()
            applyRefreshState()
        }
    }

    fun loadMoreIfNeeded(anchorKey: String) {
        val current = _state.value as? HistoryUiState.Loaded ?: return
        if (!current.hasMore) return
        if (_isLoadingMore.value) return
        if (pager.state.value.endReached) return

        val anchorIndex = current.items.indexOfLast { it.stableKey == anchorKey }
        if (anchorIndex < 0 || anchorIndex < current.items.size - 6) return

        _isLoadingMore.value = true
        loadMoreJob = scope.launch {
            try {
                pager.append()
                val pagedState = pager.state.value
                if (!pagedState.isRefreshing) {
                    _state.value = HistoryUiState.Loaded(
                        items = pagedState.items,
                        hasMore = !pagedState.endReached,
                    )
                }
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }

    private suspend fun loadCursorPage(cursor: HistoryCursor?): CursorPage<HistoryItem, HistoryCursor> {
        val page = pageFetcher.fetchPage(
            max = cursor?.max ?: 0L,
            viewAt = cursor?.viewAt ?: 0L,
            business = cursor?.business.orEmpty(),
        )
        val hasMore = page.items.isNotEmpty() &&
            (page.nextMax > 0L || page.nextViewAt > 0L || page.nextBusiness.isNotEmpty())
        val nextCursor = if (hasMore) {
            HistoryCursor(
                max = page.nextMax,
                viewAt = page.nextViewAt,
                business = page.nextBusiness,
            )
        } else {
            null
        }
        return CursorPage(
            items = page.items.filter { it.bvid.isNotEmpty() },
            nextCursor = nextCursor,
        )
    }

    private fun applyRefreshState() {
        val pagedState = pager.state.value
        val refreshError = pagedState.refreshError
        _state.value = if (refreshError != null) {
            HistoryUiState.Failed(refreshError)
        } else {
            HistoryUiState.Loaded(
                items = pagedState.items,
                hasMore = !pagedState.endReached,
            )
        }
    }
}

sealed class HistoryUiState {
    data object Idle : HistoryUiState()
    data object Loading : HistoryUiState()
    data class Failed(val message: String) : HistoryUiState()
    data class Loaded(
        val items: List<HistoryItem>,
        val hasMore: Boolean,
    ) : HistoryUiState()
}

val HistoryItem.stableKey: String
    get() = "$bvid-$viewAt"

private data class HistoryCursor(
    val max: Long,
    val viewAt: Long,
    val business: String,
)
