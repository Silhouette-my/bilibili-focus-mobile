package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
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
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
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

internal fun interface HistorySearchFetcher {
    suspend fun fetchPage(keyword: String, page: Int): List<HistoryItem>
}

typealias HistoryRemoteMutation = suspend (Long, Long?, suspend () -> Unit) -> Unit

class FocusHistoryViewModel internal constructor(
    private val pageFetcher: HistoryPageFetcher,
    dispatcher: CoroutineDispatcher,
    private val mutationService: HistoryService? = null,
    private val remoteHistoryMutation: HistoryRemoteMutation? = null,
    private val searchFetcher: HistorySearchFetcher? = null,
) {
    constructor(service: HistoryService, remoteHistoryMutation: HistoryRemoteMutation) : this(
        pageFetcher = HistoryPageFetcher(service::fetchHistory),
        dispatcher = Dispatchers.Main,
        mutationService = service,
        remoteHistoryMutation = remoteHistoryMutation,
        searchFetcher = HistorySearchFetcher(service::searchHistory),
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
    private var mutationJob: Job? = null
    private var loadedMID: Long? = null
    private var generation = 0L
    private var activeQuery = ""
    private val _isMutating = MutableStateFlow(false)
    val isMutating = _isMutating.asStateFlow()
    private val _actionError = MutableStateFlow<String?>(null)
    val actionError = _actionError.asStateFlow()
    private val _query = MutableStateFlow("")
    val query = _query.asStateFlow()
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
        mutationJob?.cancel()
        loadedMID = null
        _isMutating.value = false
        _isLoadingMore.value = false
        val request = ++generation
        loadJob = scope.launch {
            _state.value = HistoryUiState.Loading
            pager.refresh()
            coroutineContext.ensureActive()
            if (request == generation) applyRefreshState()
        }
    }

    fun loadMoreIfNeeded(anchorKey: String) {
        val current = _state.value as? HistoryUiState.Loaded ?: return
        if (!current.hasMore) return
        if (_isLoadingMore.value || _isMutating.value) return
        if (pager.state.value.endReached) return

        val anchorIndex = current.items.indexOfLast { it.stableKey == anchorKey }
        if (anchorIndex < 0 || anchorIndex < current.items.size - 6) return

        _isLoadingMore.value = true
        val request = generation
        loadMoreJob = scope.launch {
            try {
                pager.append()
                coroutineContext.ensureActive()
                val pagedState = pager.state.value
                if (!pagedState.isRefreshing && request == generation) {
                    _state.value = HistoryUiState.Loaded(
                        items = pagedState.items,
                        hasMore = !pagedState.endReached,
                        appendError = pagedState.appendError,
                    )
                }
            } finally {
                if (request == generation) _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }

    fun setQuery(value: String) {
        _query.value = value
        if (value.isBlank() && activeQuery.isNotEmpty()) submitSearch()
    }
    fun submitSearch() { activeQuery = _query.value.trim(); reload() }
    val isSearchingHistory: Boolean get() = activeQuery.isNotEmpty()
    fun dismissActionError() { _actionError.value = null }
    val canManageHistory: Boolean get() = loadedMID != null && remoteHistoryMutation != null

    fun loadMore() {
        val current = _state.value as? HistoryUiState.Loaded ?: return
        current.items.lastOrNull()?.let { loadMoreIfNeeded(it.stableKey) }
    }

    fun delete(item: HistoryItem) = mutateHistory(item.historyKey)
    fun clear() = mutateHistory(null)

    private fun mutateHistory(key: String?) {
        val service = mutationService ?: return
        val mid = loadedMID ?: return
        val remoteMutation = checkNotNull(remoteHistoryMutation)
        if (_isMutating.value) return
        loadMoreJob?.cancel()
        _isLoadingMore.value = false
        _isMutating.value = true
        _actionError.value = null
        val request = generation
        mutationJob = scope.launch {
            try {
                val aid = key?.removePrefix("archive_")?.toLong()
                remoteMutation(mid, aid) {
                    if (key == null) service.clearHistory(mid) else service.deleteHistory(key, mid)
                }
                coroutineContext.ensureActive()
                if (request != generation) return@launch
                // Rebuild the pager after mutation: its retained old rows must not reappear on append.
                pager.refresh()
                applyRefreshState()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { if (request == generation) _actionError.value = error.message ?: "操作失败" }
            finally { if (request == generation) _isMutating.value = false }
        }
    }

    private suspend fun loadCursorPage(cursor: HistoryCursor?): CursorPage<HistoryItem, HistoryCursor> {
        val keyword = activeQuery
        if (cursor == null && mutationService != null) {
            loadedMID = try { mutationService.authenticatedMID() }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (_: HistoryService.ServiceError.LoginRequired) { null }
        }
        if (keyword.isNotEmpty()) {
            val pageNumber = cursor?.searchPage ?: 1
            val items = checkNotNull(searchFetcher).fetchPage(keyword, pageNumber).filter { it.bvid.isNotEmpty() }
            val existing = if (cursor == null) emptySet() else pager.state.value.items.map(HistoryItem::stableKey).toSet()
            val hasNewItems = items.any { it.stableKey !in existing }
            return CursorPage(items, if (items.isNotEmpty() && hasNewItems) HistoryCursor(0, 0, "", pageNumber + 1) else null)
        }
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
        val appendError: String? = null,
    ) : HistoryUiState()
}

val HistoryItem.stableKey: String
    get() = "$bvid-$viewAt"

private data class HistoryCursor(
    val max: Long,
    val viewAt: Long,
    val business: String,
    val searchPage: Int? = null,
)
