package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.service.ArticleService
import org.bilibilifocus.core.service.AccountService
import org.bilibilifocus.core.service.FavoriteService
import org.bilibilifocus.core.service.HttpClient
import org.bilibilifocus.core.service.HttpResponse
import org.bilibilifocus.core.service.HistoryService
import org.bilibilifocus.core.service.OpusService
import org.bilibilifocus.core.service.UserService
import org.bilibilifocus.core.service.VideoInfoService
import org.bilibilifocus.core.service.VideoActionService
import kotlin.test.Test
import kotlin.test.assertEquals

@OptIn(ExperimentalCoroutinesApi::class)
class FocusContentCancellationTests {
    @Test
    fun `my page cancellation never proceeds as empty optional content`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val cookies = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        }
        try {
            for (cancelledPath in listOf("/x/web-interface/nav", "/x/space/wbi/acc/info", "/history/cursor", "/fav/folder/created/list-all")) {
                val http = object : HttpClient {
                    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                        if (cancelledPath in url) throw CancellationException("cancelled my page request")
                        return HttpResponse(200, """{"code":0,"data":{"isLogin":true,"mid":42,"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}""")
                    }
                    override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                        error("Unexpected POST")
                }
                val viewModel = FocusMyViewModel(AccountService(cookies, http), UserService(cookies, http), HistoryService(cookies, http), FavoriteService(cookies, http))
                try {
                    viewModel.reload()
                    advanceUntilIdle()
                    assertEquals(MyUiState.Loading, viewModel.state.value, cancelledPath)
                } finally {
                    viewModel.onCleared()
                }
            }
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun `search cancellation does not publish a failure`() = runTest {
        val viewModel = FocusSearchViewModel(
            pageFetcher = SearchPageFetcher { _, _, _, _ -> throw CancellationException("cancel search") },
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        try {
            viewModel.search("test")
            advanceUntilIdle()
            assertEquals(SearchUiState.Loading, viewModel.state.value)
        } finally {
            viewModel.onCleared()
        }
    }

    @Test
    fun `cancelled content requests do not publish error states`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val cookies = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        }
        val http = object : HttpClient {
            override suspend fun get(url: String, headers: Map<String, String>): HttpResponse =
                throw CancellationException("cancelled content request")
            override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                error("Unexpected POST")
        }
        val article = FocusArticleViewModel(ArticleService(cookies, http))
        val favorites = FocusFavFolderViewModel(FavoriteService(cookies, http))
        val opus = FocusOpusViewModel(OpusService(cookies, http))
        val video = FocusVideoViewModel(VideoInfoService(cookies, http), VideoActionService(cookies, http))
        try {
            article.load(123)
            favorites.load(123)
            opus.load("123")
            video.load("BV1TEST00001")
            advanceUntilIdle()
            video.configureDanmaku(42, 101, 60, true, 0)
            advanceUntilIdle()
            assertEquals(ArticleUiState.Loading, article.state.value)
            assertEquals(FavFolderUiState.Loading, favorites.state.value)
            assertEquals(OpusUiState.Loading, opus.state.value)
            assertEquals(VideoUiState.Loading, video.state.value)
            assertEquals(VideoDanmakuLoadStatus.LOADING, video.danmakuState.value.status)
        } finally {
            article.onCleared()
            favorites.onCleared()
            opus.onCleared()
            video.onCleared()
            Dispatchers.resetMain()
        }
    }
}
