package org.bilibilifocus.android

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.service.DynamicFeedService
import org.bilibilifocus.core.service.HttpClient
import org.bilibilifocus.core.service.HttpResponse
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

@OptIn(ExperimentalCoroutinesApi::class)
class FocusFeedViewModelTests {
    @Test
    fun `restored filter remains selected across feed screen recreation`() {
        val viewModel = FocusFeedViewModel(
            service = DynamicFeedService(EmptyCookieProvider, NoopHttpClient),
            initialSelectedFilter = FocusDynamicFilterKind.VIDEO,
        )

        assertEquals(FocusDynamicFilterKind.VIDEO, viewModel.selectedFilter.value)
        viewModel.selectFilter(FocusDynamicFilterKind.ARTICLE_LIKE)
        assertEquals(FocusDynamicFilterKind.ARTICLE_LIKE, viewModel.selectedFilter.value)

        viewModel.onCleared()
    }

    @Test
    fun `pager deduplicates feed cards and stops a repeated offset`() = runTest {
        val requests = mutableListOf<Pair<String?, Boolean>>()
        val fetcher = FeedPageFetcher { offset, forceRefresh ->
            requests += offset to forceRefresh
            when (offset) {
                null -> feedPage(listOf("1", "2", "3", "4"), "next")
                "next" -> feedPage(listOf("4", "5"), "next")
                else -> error("Unexpected offset: $offset")
            }
        }
        val viewModel = FocusFeedViewModel(
            pageFetcher = fetcher,
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.loadIfNeeded()
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("4")
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("5")
        advanceUntilIdle()

        assertEquals(
            listOf(null to false, "next" to false),
            requests,
        )
        assertEquals(listOf("1", "2", "3", "4", "5"), viewModel.loadedCardIDs())
        assertFalse(viewModel.isLoadingMore.value)
        viewModel.onCleared()
    }

    @Test
    fun `failed feed append keeps its cursor and can retry`() = runTest {
        var requestCount = 0
        val viewModel = FocusFeedViewModel(
            pageFetcher = FeedPageFetcher { offset, _ ->
                requestCount += 1
                when (requestCount) {
                    1 -> feedPage(listOf("1", "2", "3", "4"), "next")
                    2 -> {
                        assertEquals("next", offset)
                        error("temporary")
                    }
                    3 -> feedPage(listOf("5"), null)
                    else -> error("Unexpected request")
                }
            },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.loadIfNeeded()
        advanceUntilIdle()
        viewModel.loadMoreIfNeeded("4")
        advanceUntilIdle()
        assertEquals(listOf("1", "2", "3", "4"), viewModel.loadedCardIDs())

        viewModel.loadMoreIfNeeded("4")
        advanceUntilIdle()

        assertEquals(3, requestCount)
        assertEquals(listOf("1", "2", "3", "4", "5"), viewModel.loadedCardIDs())
        viewModel.onCleared()
    }

    @Test
    fun `manual feed refresh is forced and preserves login state mapping`() = runTest {
        val forceFlags = mutableListOf<Boolean>()
        var completed = false
        val viewModel = FocusFeedViewModel(
            pageFetcher = FeedPageFetcher { _, forceRefresh ->
                forceFlags += forceRefresh
                if (forceRefresh) throw DynamicFeedService.ServiceError.LoginRequired
                feedPage(listOf("1"), null)
            },
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.loadIfNeeded()
        advanceUntilIdle()
        viewModel.refresh { completed = true }
        advanceUntilIdle()

        assertEquals(listOf(false, true), forceFlags)
        assertEquals(FeedUiState.LoginRequired, viewModel.state.value)
        assertEquals(true, completed)
        viewModel.onCleared()
    }
}

private data object EmptyCookieProvider : CookieProvider {
    override suspend fun loadCookies(): List<Cookie> = emptyList()
}

private data object NoopHttpClient : HttpClient {
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse =
        error("Unexpected GET: $url")

    override suspend fun post(
        url: String,
        body: String,
        headers: Map<String, String>,
    ): HttpResponse = error("Unexpected POST: $url")
}

private fun feedPage(ids: List<String>, nextOffset: String?): DynamicFeedService.FeedPage =
    DynamicFeedService.FeedPage(
        cards = ids.map(::feedCard),
        nextOffset = nextOffset,
    )

private fun feedCard(id: String): DynamicCard = DynamicCard(
    id = id,
    kind = DynamicCard.Kind.TEXT,
    author = DynamicCard.Author(name = "UP"),
    publishTime = "",
    text = id,
    coverURLs = emptyList(),
    targetURL = "https://www.bilibili.com/opus/$id",
)

private fun FocusFeedViewModel.loadedCardIDs(): List<String> =
    (state.value as FeedUiState.Loaded).cards.map(DynamicCard::id)
