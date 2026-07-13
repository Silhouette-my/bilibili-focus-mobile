package org.bilibilifocus.android

import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.service.DynamicFeedService
import org.bilibilifocus.core.service.HttpClient
import org.bilibilifocus.core.service.HttpResponse
import kotlin.test.Test
import kotlin.test.assertEquals

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
