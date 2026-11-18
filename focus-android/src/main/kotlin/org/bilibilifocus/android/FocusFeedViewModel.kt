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
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.paging.CursorPage
import org.bilibilifocus.core.paging.CursorPager
import org.bilibilifocus.core.service.DynamicFeedService

internal fun interface FeedPageFetcher {
    suspend fun fetchPage(
        offset: String?,
        forceRefresh: Boolean,
    ): DynamicFeedService.FeedPage
}

class FocusFeedViewModel internal constructor(
    private val pageFetcher: FeedPageFetcher,
    initialSelectedFilter: FocusDynamicFilterKind = FocusDynamicFilterKind.ALL,
    dispatcher: CoroutineDispatcher,
) {
    constructor(
        service: DynamicFeedService,
        initialSelectedFilter: FocusDynamicFilterKind = FocusDynamicFilterKind.ALL,
    ) : this(
        pageFetcher = FeedPageFetcher { offset, forceRefresh ->
            if (forceRefresh) {
                service.refreshFollowingFeedPage(offset)
            } else {
                service.fetchFollowingFeedPage(offset)
            }
        },
        initialSelectedFilter = initialSelectedFilter,
        dispatcher = Dispatchers.Main,
    )

    private val _state = MutableStateFlow<FeedUiState>(FeedUiState.Idle)
    val state: StateFlow<FeedUiState> = _state.asStateFlow()

    private val scope = CoroutineScope(
        SupervisorJob() +
            dispatcher +
            CoroutineExceptionHandler { _, error ->
                _state.value = FeedUiState.Failed(error.message ?: "加载失败")
            },
    )
    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private val pager = CursorPager<DynamicCard, String, String>(
        firstCursor = null,
        keyOf = DynamicCard::id,
        loadPage = { offset -> loadCursorPage(offset, forceRefresh = false) },
    )

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    private val _selectedFilter = MutableStateFlow(initialSelectedFilter)
    val selectedFilter: StateFlow<FocusDynamicFilterKind> = _selectedFilter.asStateFlow()

    fun selectFilter(filter: FocusDynamicFilterKind) {
        _selectedFilter.value = filter
    }

    fun loadIfNeeded() {
        if (_state.value !is FeedUiState.Idle) return
        startRefresh(showLoading = true, forceRefresh = false)
    }

    fun reload() {
        startRefresh(showLoading = true, forceRefresh = true)
    }

    fun refresh(onComplete: () -> Unit = {}) {
        startRefresh(
            showLoading = false,
            forceRefresh = true,
            onComplete = onComplete,
        )
    }

    private fun startRefresh(
        showLoading: Boolean,
        forceRefresh: Boolean,
        onComplete: () -> Unit = {},
    ) {
        loadJob?.cancel()
        loadMoreJob?.cancel()
        _isLoadingMore.value = false
        loadJob = scope.launch {
            if (showLoading) {
                _state.value = FeedUiState.Loading
            }
            try {
                if (forceRefresh) {
                    pager.refresh { offset ->
                        loadCursorPage(offset, forceRefresh = true)
                    }
                } else {
                    pager.refresh()
                }
                applyRefreshState()
            } finally {
                onComplete()
            }
        }
    }

    fun loadMoreIfNeeded(currentCardID: String) {
        val currentCards = (_state.value as? FeedUiState.Loaded)?.cards ?: return
        if (!shouldLoadMore(currentCardID, currentCards)) return
        if (_isLoadingMore.value) return
        if (pager.state.value.endReached) return

        _isLoadingMore.value = true
        loadMoreJob = scope.launch {
            try {
                pager.append()
                val pagedState = pager.state.value
                if (!pagedState.isRefreshing) {
                    _state.value = if (pagedState.items.isEmpty()) {
                        FeedUiState.Empty
                    } else {
                        FeedUiState.Loaded(pagedState.items)
                    }
                }
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }

    private suspend fun loadCursorPage(
        offset: String?,
        forceRefresh: Boolean,
    ): CursorPage<DynamicCard, String> {
        val page = pageFetcher.fetchPage(offset, forceRefresh)
        return CursorPage(page.cards, page.nextOffset)
    }

    private fun applyRefreshState() {
        val pagedState = pager.state.value
        val refreshError = pagedState.refreshError
        if (refreshError != null) {
            _state.value = if (
                pagedState.refreshCause == DynamicFeedService.ServiceError.LoginRequired
            ) {
                FeedUiState.LoginRequired
            } else {
                FeedUiState.Failed(refreshError)
            }
            return
        }
        _state.value = if (pagedState.items.isEmpty()) {
            FeedUiState.Empty
        } else {
            FeedUiState.Loaded(pagedState.items)
        }
    }

    private fun shouldLoadMore(currentCardID: String, cards: List<DynamicCard>): Boolean {
        if (cards.isEmpty()) return false
        val index = cards.indexOfLast { it.id == currentCardID }
        return index >= 0 && index >= cards.size - 4
    }
}

sealed class FeedUiState {
    data object Idle : FeedUiState()
    data object Loading : FeedUiState()
    data object Empty : FeedUiState()
    data object LoginRequired : FeedUiState()
    data class Failed(val message: String) : FeedUiState()
    data class Loaded(val cards: List<DynamicCard>) : FeedUiState()
}
