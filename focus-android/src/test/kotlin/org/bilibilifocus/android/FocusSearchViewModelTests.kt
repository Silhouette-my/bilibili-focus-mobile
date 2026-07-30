package org.bilibilifocus.android

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.model.SearchQuery
import org.bilibilifocus.core.model.SearchResultFilter
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.SearchResultPage
import org.bilibilifocus.core.model.SearchResultSection
import org.bilibilifocus.core.model.SearchVideoSortOption
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

@OptIn(ExperimentalCoroutinesApi::class)
class FocusSearchViewModelTests {
    @Test
    fun `overview appends the next video page when its last item is reached`() = runTest {
        val requests = mutableListOf<SearchRequest>()
        val fetcher = SearchPageFetcher { query, filter, page, sort ->
            requests += SearchRequest(query.keyword, filter, page, sort)
            when (requests.size) {
                1 -> resultPage(ids = listOf("v1", "v2", "v3", "v4"), nextPage = 2)
                2 -> resultPage(ids = listOf("v4", "v5", "v6"), nextPage = null)
                else -> error("Unexpected request")
            }
        }
        val viewModel = FocusSearchViewModel(fetcher, StandardTestDispatcher(testScheduler))

        viewModel.search("分页测试")
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("v4")
        advanceUntilIdle()

        assertEquals(
            listOf(
                SearchRequest("分页测试", SearchResultFilter.ALL, 1, SearchVideoSortOption.DEFAULT),
                SearchRequest("分页测试", SearchResultFilter.VIDEO, 2, SearchVideoSortOption.DEFAULT),
            ),
            requests,
        )
        assertEquals(
            listOf("v1", "v2", "v3", "v4", "v5", "v6"),
            viewModel.loadedVideoIDs(),
        )
        viewModel.loadMoreIfNeeded("v6")
        advanceUntilIdle()
        assertEquals(2, requests.size)
        assertFalse(viewModel.isLoadingMore.value)
        viewModel.onCleared()
    }

    @Test
    fun `video pagination follows the server supplied next page`() = runTest {
        val requestedPages = mutableListOf<Int>()
        val fetcher = SearchPageFetcher { _, filter, page, _ ->
            when (filter) {
                SearchResultFilter.ALL -> resultPage(ids = listOf("overview"), nextPage = 2)
                SearchResultFilter.VIDEO -> {
                    requestedPages += page
                    if (page == 1) {
                        resultPage(ids = listOf("v1", "v2", "v3", "v4"), nextPage = 4)
                    } else {
                        resultPage(ids = listOf("v5"), nextPage = null)
                    }
                }
                else -> error("Unexpected filter: $filter")
            }
        }
        val viewModel = FocusSearchViewModel(fetcher, StandardTestDispatcher(testScheduler))

        viewModel.search("分页游标")
        advanceUntilIdle()
        viewModel.selectFilter(SearchResultFilter.VIDEO)
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("v4")
        advanceUntilIdle()

        assertEquals(listOf(1, 4), requestedPages)
        assertEquals(listOf("v1", "v2", "v3", "v4", "v5"), viewModel.loadedVideoIDs())
        viewModel.onCleared()
    }

    @Test
    fun `failed pagination keeps its cursor and can be retried`() = runTest {
        var requestCount = 0
        val fetcher = SearchPageFetcher { _, filter, page, _ ->
            requestCount++
            when (requestCount) {
                1 -> resultPage(ids = listOf("v1", "v2", "v3", "v4"), nextPage = 2)
                2 -> error("temporary failure")
                3 -> {
                    assertEquals(SearchResultFilter.VIDEO, filter)
                    assertEquals(2, page)
                    resultPage(ids = listOf("v5"), nextPage = null)
                }
                else -> error("Unexpected request")
            }
        }
        val viewModel = FocusSearchViewModel(fetcher, StandardTestDispatcher(testScheduler))

        viewModel.search("失败重试")
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("v4")
        advanceUntilIdle()
        assertEquals(listOf("v1", "v2", "v3", "v4"), viewModel.loadedVideoIDs())

        viewModel.loadMoreIfNeeded("v4")
        advanceUntilIdle()

        assertEquals(3, requestCount)
        assertEquals(listOf("v1", "v2", "v3", "v4", "v5"), viewModel.loadedVideoIDs())
        viewModel.onCleared()
    }
}

private data class SearchRequest(
    val keyword: String,
    val filter: SearchResultFilter,
    val page: Int,
    val sort: SearchVideoSortOption,
)

private fun resultPage(ids: List<String>, nextPage: Int?): SearchResultPage = SearchResultPage(
    sections = listOf(
        SearchResultSection(
            filter = SearchResultFilter.VIDEO,
            items = ids.map(::videoItem),
        ),
    ),
    nextPage = nextPage,
)

private fun videoItem(id: String): SearchResultItem = SearchResultItem(
    id = id,
    kind = SearchResultItem.Kind.VIDEO,
    title = id,
    targetURL = "https://www.bilibili.com/video/$id",
)

private fun FocusSearchViewModel.loadedVideoIDs(): List<String> =
    ((state.value as SearchUiState.Loaded).sections
        .first { it.filter == SearchResultFilter.VIDEO }
        .items
        .map { it.id })
