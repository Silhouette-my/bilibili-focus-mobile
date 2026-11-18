package org.bilibilifocus.android

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.service.HttpClient
import org.bilibilifocus.core.service.HttpResponse
import org.bilibilifocus.core.service.OpusService
import org.bilibilifocus.core.service.VideoInfoService
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FocusOpusViewModelTests {
    @Test
    fun `opus viewmodel loads paginated comments and routes like send delete via resolved target type`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val postedActions = mutableListOf<Pair<String, String>>()
        val commentRequests = mutableListOf<String>()
        val cookies = object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = listOf(
                Cookie(name = "DedeUserID", value = "42", domain = ".bilibili.com", path = "/"),
                Cookie(name = "SESSDATA", value = "sess", domain = ".bilibili.com", path = "/"),
                Cookie(name = "bili_jct", value = "csrf_token", domain = ".bilibili.com", path = "/"),
            )
        }
        val http = object : HttpClient {
            override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
                val body = when {
                    "/opus/detail" in url -> """
                        {"code":0,"data":{"item":{
                          "basic":{"comment_id_str":"7788","comment_type":11},
                          "modules":{
                            "module_author":{"name":"作者","mid":1,"face":"//i0.hdslb.com/face.jpg"},
                            "module_content":{"paragraphs":[{"para_type":1,"text":{"nodes":[{"word":{"words":"图文正文"}}]}}]}
                          }
                        }}}
                    """.trimIndent()
                    "/x/web-interface/nav" in url ->
                        """{"code":0,"data":{"isLogin":true,"mid":42,"wbi_img":{"img_url":"https://i0.hdslb.com/abcdefghijklmnopqrstuvwxyz012345.png","sub_url":"https://i0.hdslb.com/ABCDEFGHIJKLMNOPQRSTUVWXYZ012345.png"}}}"""
                    "/x/v2/reply/wbi/main" in url -> {
                        commentRequests += url
                        if ("page2" in url) {
                            """{"code":0,"data":{"cursor":{"all_count":2,"pagination_reply":{"next_offset":""}},"replies":[{"rpid":20,"mid":99,"member":{"uname":"二楼","avatar":""},"content":{"message":"第二页"},"like":0,"rcount":0,"ctime":1700000100}]}}"""
                        } else {
                            """{"code":0,"data":{"cursor":{"all_count":2,"pagination_reply":{"next_offset":"page2"}},"replies":[{"rpid":10,"mid":42,"member":{"uname":"我","avatar":""},"content":{"message":"第一条"},"like":5,"rcount":0,"ctime":1700000000}]}}"""
                        }
                    }
                    else -> error("Unexpected GET: $url")
                }
                return HttpResponse(200, body)
            }

            override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse {
                postedActions += url to body
                val resp = when {
                    "/x/v2/reply/add" in url ->
                        """{"code":0,"data":{"reply":{"rpid":30,"mid":42,"member":{"uname":"我","avatar":""},"content":{"message":"新评论"},"like":0,"rcount":0,"ctime":1700000200}}}"""
                    else -> """{"code":0,"data":{}}"""
                }
                return HttpResponse(200, resp)
            }
        }
        val viewModel = FocusOpusViewModel(
            service = OpusService(cookies, http),
            commentService = VideoInfoService(cookies, http),
        )
        try {
            viewModel.load("7788")
            advanceUntilIdle()

            assertIs<OpusUiState.Loaded>(viewModel.state.value)
            assertEquals(listOf(10L), viewModel.comments.value.map { it.rpid })
            assertEquals(2, viewModel.commentTotalCount.value)
            assertTrue(viewModel.commentState.value.hasMore)
            assertEquals(42L, viewModel.commentState.value.accountMid)
            assertTrue(commentRequests.single().contains("type=11") && commentRequests.single().contains("oid=7788"))

            viewModel.loadComments(append = true)
            advanceUntilIdle()
            assertEquals(listOf(10L, 20L), viewModel.comments.value.map { it.rpid })
            assertFalse(viewModel.commentState.value.hasMore)

            viewModel.toggleCommentLike(viewModel.comments.value.first())
            advanceUntilIdle()
            assertTrue(viewModel.comments.value.first().isLiked)
            assertEquals(6L, viewModel.comments.value.first().likeCount)

            var sent = false
            viewModel.sendComment("新评论") { sent = true }
            advanceUntilIdle()
            assertTrue(sent)
            assertEquals(listOf(30L, 10L, 20L), viewModel.comments.value.map { it.rpid })

            viewModel.deleteComment(viewModel.comments.value.first())
            advanceUntilIdle()
            assertEquals(listOf(10L, 20L), viewModel.comments.value.map { it.rpid })

            assertEquals(3, postedActions.size)
            assertTrue(postedActions.all { (_, body) -> "type=11" in body && "oid=7788" in body })
        } finally {
            viewModel.onCleared()
            Dispatchers.resetMain()
        }
    }
}
