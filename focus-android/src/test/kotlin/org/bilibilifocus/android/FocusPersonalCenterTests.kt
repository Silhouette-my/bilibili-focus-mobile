package org.bilibilifocus.android

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.service.*
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FocusPersonalCenterTests {
    @Test
    fun `expired section revokes previously loaded personal content`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val transport = PersonalCenterTestTransport(CompletableDeferred(Unit))
        val model = makeModel(transport)
        try {
            model.reload(); advanceUntilIdle()
            assertIs<MyUiState.Loaded>(model.state.value)
            transport.expireHistory = true
            model.reload(); advanceUntilIdle()
            assertEquals(MyUiState.LoginRequired, model.state.value)
        } finally { model.onCleared(); Dispatchers.resetMain() }
    }

    @Test
    fun `profile and folder metadata publish while history waits without fetching previews`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val historyGate = CompletableDeferred<Unit>()
        val transport = PersonalCenterTestTransport(historyGate)
        val model = makeModel(transport)
        try {
            model.reload()
            runCurrent()
            val partial = assertIs<MyUiState.Loaded>(model.state.value)
            assertEquals("Fixture account", partial.profile.name)
            assertEquals(1, partial.folders.size)
            assertTrue(partial.isLoadingHistory)
            assertTrue(partial.isRefreshing)
            assertFalse(transport.paths.any { "/fav/resource/list" in it || "/acc/info" in it || "/toview" in it })
            historyGate.complete(Unit)
            advanceUntilIdle()
            val loaded = assertIs<MyUiState.Loaded>(model.state.value)
            assertEquals(1, loaded.history.size)
            assertFalse(loaded.isRefreshing)
            assertFalse(loaded.isLoadingHistory)
        } finally { model.onCleared(); Dispatchers.resetMain() }
    }

    @Test
    fun `section refresh failure preserves previous history with visible error`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val transport = PersonalCenterTestTransport(CompletableDeferred(Unit))
        val model = makeModel(transport)
        try {
            model.reload(); advanceUntilIdle()
            val previous = assertIs<MyUiState.Loaded>(model.state.value)
            transport.failHistory = true
            model.reload(); advanceUntilIdle()
            val refreshed = assertIs<MyUiState.Loaded>(model.state.value)
            assertEquals(previous.history, refreshed.history)
            assertTrue(refreshed.historyError?.contains("offline") == true)
            assertEquals(previous.folders, refreshed.folders)
            assertFalse(refreshed.isLoadingHistory)
        } finally { model.onCleared(); Dispatchers.resetMain() }
    }

    private fun makeModel(transport: HttpClient): FocusMyViewModel {
        val cookies = object : CookieProvider { override suspend fun loadCookies() = emptyList<Cookie>() }
        return FocusMyViewModel(AccountService(cookies, transport), UserService(cookies, transport), HistoryService(cookies, transport), FavoriteService(cookies, transport))
    }
}

private class PersonalCenterTestTransport(private val historyGate: CompletableDeferred<Unit>) : HttpClient {
    val paths = mutableListOf<String>()
    var failHistory = false
    var expireHistory = false
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        val path = java.net.URI(url).path
        paths += path
        val data = when (path) {
            "/x/web-interface/nav" -> """{"isLogin":true,"mid":42,"uname":"Fixture account"}"""
            "/x/relation/stat" -> """{"following":2,"follower":3}"""
            "/x/v3/fav/folder/created/list-all" -> """{"list":[{"id":1,"title":"Folder","media_count":1}]}"""
            "/x/web-interface/history/cursor" -> { historyGate.await(); if (failHistory) throw IOException("offline"); if (expireHistory) return HttpResponse(200, """{"code":-101,"message":"session expired"}"""); """{"list":[{"title":"History","history":{"bvid":"BV-ONE"}}],"cursor":{"max":0}}""" }
            else -> error("Unexpected request: $path")
        }
        return HttpResponse(200, """{"code":0,"data":$data}""")
    }
    override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse = error("Unexpected mutation")
}
