package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.SearchQuery
import org.bilibilifocus.core.model.SearchResultFilter
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.SearchResultPage
import org.bilibilifocus.core.model.SearchResultSection
import org.bilibilifocus.core.model.SearchVideoSortOption
import org.bilibilifocus.core.service.SearchResultService

internal fun interface SearchPageFetcher {
    suspend fun fetchPage(
        query: SearchQuery,
        filter: SearchResultFilter,
        page: Int,
        videoSort: SearchVideoSortOption,
    ): SearchResultPage
}

class FocusSearchViewModel internal constructor(
    private val pageFetcher: SearchPageFetcher,
    dispatcher: CoroutineDispatcher,
) {
    constructor(service: SearchResultService) : this(
        pageFetcher = SearchPageFetcher { query, filter, page, videoSort ->
            service.fetchPage(query, filter, page, videoSort)
        },
        dispatcher = Dispatchers.Main,
    )

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var searchJob: Job? = null
    private var loadMoreJob: Job? = null

    private var currentQuery: SearchQuery? = null
    private var nextVideoPage: Int? = null
    private var requestGeneration: Long = 0
    var selectedFilter: SearchResultFilter = SearchResultFilter.ALL
        private set
    var selectedVideoSort: SearchVideoSortOption = SearchVideoSortOption.DEFAULT
        private set

    private val _state = MutableStateFlow<SearchUiState>(SearchUiState.Idle)
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    fun search(keyword: String) {
        val trimmed = keyword.trim()
        if (trimmed.isEmpty()) return

        val query = SearchQuery(trimmed)
        currentQuery = query
        selectedFilter = SearchResultFilter.ALL
        selectedVideoSort = SearchVideoSortOption.DEFAULT
        loadFirstPage(query, SearchResultFilter.ALL, SearchVideoSortOption.DEFAULT)
    }

    fun selectFilter(filter: SearchResultFilter) {
        if (filter == selectedFilter) return
        selectedFilter = filter

        val query = currentQuery ?: return
        loadFirstPage(query, filter, selectedVideoSort)
    }

    fun selectVideoSort(sort: SearchVideoSortOption) {
        if (sort == selectedVideoSort) return
        selectedVideoSort = sort

        val query = currentQuery ?: return
        loadFirstPage(query, selectedFilter, selectedVideoSort)
    }

    fun loadMoreIfNeeded(currentItemID: String) {
        val sections = (_state.value as? SearchUiState.Loaded)?.sections ?: return
        if (_isLoadingMore.value) return

        val videoSection = sections.find { it.filter == SearchResultFilter.VIDEO } ?: return
        val index = videoSection.items.indexOfLast { it.id == currentItemID }
        if (index < 0 || index < videoSection.items.size - 4) return

        val query = currentQuery ?: return
        val page = nextVideoPage ?: return
        val sort = selectedVideoSort
        val generation = requestGeneration

        _isLoadingMore.value = true
        loadMoreJob?.cancel()
        loadMoreJob = scope.launch {
            try {
                val newPage = pageFetcher.fetchPage(query, SearchResultFilter.VIDEO, page, sort)
                if (generation != requestGeneration) return@launch
                nextVideoPage = newPage.nextPage
                val incomingVideoItems = newPage.sections
                    .firstOrNull { it.filter == SearchResultFilter.VIDEO }
                    ?.items
                    .orEmpty()
                    .filter { it.kind == SearchResultItem.Kind.VIDEO }
                val mergedVideoItems = (videoSection.items + incomingVideoItems)
                    .distinctBy { it.id }
                val mergedSection = SearchResultSection(
                    filter = SearchResultFilter.VIDEO,
                    items = mergedVideoItems,
                )
                val mergedSections = sections.map {
                    if (it.filter == SearchResultFilter.VIDEO) mergedSection else it
                }
                _state.value = SearchUiState.Loaded(mergedSections)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
            } finally {
                if (generation == requestGeneration) {
                    _isLoadingMore.value = false
                }
            }
        }
    }

    private fun loadFirstPage(
        query: SearchQuery,
        filter: SearchResultFilter,
        videoSort: SearchVideoSortOption,
    ) {
        requestGeneration++
        val generation = requestGeneration
        searchJob?.cancel()
        loadMoreJob?.cancel()
        _isLoadingMore.value = false
        nextVideoPage = null

        searchJob = scope.launch {
            _state.value = SearchUiState.Loading
            try {
                val page = pageFetcher.fetchPage(query, filter, 1, videoSort)
                if (generation != requestGeneration) return@launch
                nextVideoPage = when (filter) {
                    SearchResultFilter.ALL, SearchResultFilter.VIDEO -> page.nextPage
                    else -> null
                }
                _state.value = if (page.sections.isEmpty()) {
                    SearchUiState.Empty
                } else {
                    SearchUiState.Loaded(page.sections)
                }
            } catch (e: SearchResultService.ServiceError) {
                if (generation != requestGeneration) return@launch
                if (e == SearchResultService.ServiceError.SigningUnavailable) {
                    _state.value = SearchUiState.LoginRequired
                } else {
                    _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (generation == requestGeneration) {
                    _state.value = SearchUiState.Failed(e.message ?: "搜索失败")
                }
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class SearchUiState {
    data object Idle : SearchUiState()
    data object Loading : SearchUiState()
    data object Empty : SearchUiState()
    data object LoginRequired : SearchUiState()
    data class Failed(val message: String) : SearchUiState()
    data class Loaded(val sections: List<SearchResultSection>) : SearchUiState()
}
