package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
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
import org.bilibilifocus.core.service.DynamicFeedService

class FocusFeedViewModel(
    private val service: DynamicFeedService,
    initialSelectedFilter: FocusDynamicFilterKind = FocusDynamicFilterKind.ALL,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = FeedUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private var nextOffset: String? = null

    private val _state = MutableStateFlow<FeedUiState>(FeedUiState.Idle)
    val state: StateFlow<FeedUiState> = _state.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    private val _selectedFilter = MutableStateFlow(initialSelectedFilter)
    val selectedFilter: StateFlow<FocusDynamicFilterKind> = _selectedFilter.asStateFlow()

    fun selectFilter(filter: FocusDynamicFilterKind) {
        _selectedFilter.value = filter
    }

    fun loadIfNeeded() {
        if (_state.value !is FeedUiState.Idle) return
        reload()
    }

    fun reload() {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = FeedUiState.Loading
            try {
                val page = service.fetchFollowingFeedPage()
                nextOffset = page.nextOffset
                _state.value = if (page.cards.isEmpty()) {
                    FeedUiState.Empty
                } else {
                    FeedUiState.Loaded(page.cards)
                }
            } catch (e: DynamicFeedService.ServiceError) {
                if (e == DynamicFeedService.ServiceError.LoginRequired) {
                    _state.value = FeedUiState.LoginRequired
                } else {
                    _state.value = FeedUiState.Failed(e.message ?: "加载失败")
                }
            } catch (e: Exception) {
                _state.value = FeedUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun refresh(onComplete: () -> Unit = {}) {
        loadJob?.cancel()
        loadJob = scope.launch {
            try {
                val page = service.fetchFollowingFeedPage()
                nextOffset = page.nextOffset
                _state.value = if (page.cards.isEmpty()) {
                    FeedUiState.Empty
                } else {
                    FeedUiState.Loaded(page.cards)
                }
            } catch (e: DynamicFeedService.ServiceError) {
                if (e == DynamicFeedService.ServiceError.LoginRequired) {
                    _state.value = FeedUiState.LoginRequired
                } else {
                    _state.value = FeedUiState.Failed(e.message ?: "加载失败")
                }
            } catch (e: Exception) {
                _state.value = FeedUiState.Failed(e.message ?: "加载失败")
            } finally {
                onComplete()
            }
        }
    }

    fun loadMoreIfNeeded(currentCardID: String) {
        val currentCards = (_state.value as? FeedUiState.Loaded)?.cards ?: return
        if (!shouldLoadMore(currentCardID, currentCards)) return
        if (_isLoadingMore.value) return
        val offset = nextOffset ?: return
        if (offset.isEmpty()) return

        _isLoadingMore.value = true
        loadMoreJob?.cancel()
        loadMoreJob = scope.launch {
            try {
                val page = service.fetchFollowingFeedPage(offset)
                val merged = currentCards + page.cards.filter { new ->
                    currentCards.none { it.id == new.id }
                }
                nextOffset = page.nextOffset
                _state.value = FeedUiState.Loaded(merged)
            } catch (_: DynamicFeedService.ServiceError) {
            } catch (_: Exception) {
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
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
