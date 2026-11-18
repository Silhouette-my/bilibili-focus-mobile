package org.bilibilifocus.android

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.runCurrent
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.model.HistoryPage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FocusHistoryViewModelTests {
    @Test
    fun `remote search waits for submit paginates by pn and clearing restores cursor history`() = runTest {
        var historyRequests = 0
        val searches = mutableListOf<Pair<String, Int>>()
        val viewModel = FocusHistoryViewModel(
            pageFetcher = HistoryPageFetcher { _, _, _ -> historyRequests++; historyPage(listOf(historyItem("normal", 1))) },
            dispatcher = StandardTestDispatcher(testScheduler),
            searchFetcher = HistorySearchFetcher { keyword, page ->
                searches += keyword to page
                if (page <= 2) listOf(historyItem("remote$page", page.toLong())) else emptyList()
            },
        )
        try {
            viewModel.setQuery("  remote keyword  ")
            advanceUntilIdle()
            assertTrue(searches.isEmpty())
            viewModel.submitSearch(); advanceUntilIdle()
            assertEquals(listOf("remote1"), viewModel.loadedBvids())
            viewModel.loadMore(); advanceUntilIdle()
            assertEquals(listOf("remote1", "remote2"), viewModel.loadedBvids())
            viewModel.loadMore(); advanceUntilIdle()
            assertFalse((viewModel.state.value as HistoryUiState.Loaded).hasMore)
            assertEquals(listOf("remote keyword" to 1, "remote keyword" to 2, "remote keyword" to 3), searches)
            viewModel.setQuery(""); advanceUntilIdle()
            assertEquals(listOf("normal"), viewModel.loadedBvids())
            assertEquals(1, historyRequests)
            assertFalse(viewModel.isSearchingHistory)
        } finally { viewModel.onCleared() }
    }

    @Test
    fun `remote search append error retains page then duplicate-only retry terminates`() = runTest {
        var pageTwoAttempts = 0
        val requests = mutableListOf<Int>()
        val viewModel = FocusHistoryViewModel(
            pageFetcher = HistoryPageFetcher { _, _, _ -> error("Search must not use cursor endpoint") },
            dispatcher = StandardTestDispatcher(testScheduler),
            searchFetcher = HistorySearchFetcher { _, page ->
                requests += page
                if (page == 2 && pageTwoAttempts++ == 0) error("temporary search failure")
                listOf(historyItem("duplicate", 100))
            },
        )
        try {
            viewModel.setQuery("duplicate"); viewModel.submitSearch(); advanceUntilIdle()
            viewModel.loadMore(); advanceUntilIdle()
            assertEquals("temporary search failure", (viewModel.state.value as HistoryUiState.Loaded).appendError)
            assertEquals(listOf("duplicate"), viewModel.loadedBvids())
            viewModel.loadMore(); advanceUntilIdle()
            assertFalse((viewModel.state.value as HistoryUiState.Loaded).hasMore)
            viewModel.loadMore(); advanceUntilIdle()
            assertEquals(listOf(1, 2, 2), requests)
        } finally { viewModel.onCleared() }
    }

    @Test
    fun `late cancelled search cannot replace a newer query`() = runTest {
        val releaseOld = CompletableDeferred<Unit>()
        val viewModel = FocusHistoryViewModel(
            pageFetcher = HistoryPageFetcher { _, _, _ -> historyPage(emptyList()) },
            dispatcher = StandardTestDispatcher(testScheduler),
            searchFetcher = HistorySearchFetcher { keyword, _ ->
                if (keyword == "old") withContext(NonCancellable) { releaseOld.await() }
                listOf(historyItem(keyword, 100))
            },
        )
        try {
            viewModel.setQuery("old"); viewModel.submitSearch(); runCurrent()
            viewModel.setQuery("new"); viewModel.submitSearch(); advanceUntilIdle()
            assertEquals(listOf("new"), viewModel.loadedBvids())
            releaseOld.complete(Unit); advanceUntilIdle()
            assertEquals(listOf("new"), viewModel.loadedBvids())
        } finally { releaseOld.complete(Unit); viewModel.onCleared() }
    }

    @Test
    fun `pager forwards history cursor deduplicates and stops a repeated cursor`() = runTest {
        val requests = mutableListOf<HistoryRequest>()
        val viewModel = FocusHistoryViewModel(
            pageFetcher = HistoryPageFetcher { max, viewAt, business ->
                requests += HistoryRequest(max, viewAt, business)
                when (requests.size) {
                    1 -> historyPage(
                        items = listOf(historyItem("BV1", 100), historyItem("BV2", 200)),
                        max = 10,
                        viewAt = 20,
                        business = "archive",
                    )
                    2 -> historyPage(
                        items = listOf(historyItem("BV2", 200), historyItem("BV3", 300)),
                        max = 10,
                        viewAt = 20,
                        business = "archive",
                    )
                    else -> error("Unexpected request")
                }
            },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.loadIfNeeded()
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("BV2-200")
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("BV3-300")
        advanceUntilIdle()

        assertEquals(
            listOf(
                HistoryRequest(0, 0, ""),
                HistoryRequest(10, 20, "archive"),
            ),
            requests,
        )
        val loaded = viewModel.state.value as HistoryUiState.Loaded
        assertEquals(listOf("BV1", "BV2", "BV3"), loaded.items.map(HistoryItem::bvid))
        assertFalse(loaded.hasMore)
        assertFalse(viewModel.isLoadingMore.value)
        viewModel.onCleared()
    }

    @Test
    fun `failed history append keeps cursor and can retry`() = runTest {
        var requestCount = 0
        val viewModel = FocusHistoryViewModel(
            pageFetcher = HistoryPageFetcher { max, _, _ ->
                requestCount += 1
                when (requestCount) {
                    1 -> historyPage(listOf(historyItem("BV1", 100)), max = 10)
                    2 -> {
                        assertEquals(10, max)
                        error("temporary")
                    }
                    3 -> historyPage(listOf(historyItem("BV2", 200)))
                    else -> error("Unexpected request")
                }
            },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.loadIfNeeded()
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("BV1-100")
        advanceUntilIdle()
        assertEquals(listOf("BV1"), viewModel.loadedBvids())

        viewModel.loadMoreIfNeeded("BV1-100")
        advanceUntilIdle()

        assertEquals(3, requestCount)
        assertEquals(listOf("BV1", "BV2"), viewModel.loadedBvids())
        assertFalse((viewModel.state.value as HistoryUiState.Loaded).hasMore)
        viewModel.onCleared()
    }

    @Test
    fun `history refresh error maps to existing failed state`() = runTest {
        val viewModel = FocusHistoryViewModel(
            pageFetcher = HistoryPageFetcher { _, _, _ -> error("history offline") },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.reload()
        advanceUntilIdle()

        assertEquals(HistoryUiState.Failed("history offline"), viewModel.state.value)
        viewModel.onCleared()
    }
}

private data class HistoryRequest(
    val max: Long,
    val viewAt: Long,
    val business: String,
)

private fun historyPage(
    items: List<HistoryItem>,
    max: Long = 0,
    viewAt: Long = 0,
    business: String = "",
): HistoryPage = HistoryPage(
    items = items,
    nextMax = max,
    nextViewAt = viewAt,
    nextBusiness = business,
)

private fun historyItem(bvid: String, viewAt: Long): HistoryItem = HistoryItem(
    title = bvid,
    coverURL = "",
    bvid = bvid,
    authorName = "UP",
    viewAt = viewAt,
    progress = 0,
    duration = 0,
)

private fun FocusHistoryViewModel.loadedBvids(): List<String> =
    (state.value as HistoryUiState.Loaded).items.map(HistoryItem::bvid)
