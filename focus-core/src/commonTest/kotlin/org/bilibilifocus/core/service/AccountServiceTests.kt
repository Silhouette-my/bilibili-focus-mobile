package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

class AccountServiceTests {
    @Test
    fun `only explicit logged out responses become login required`() = runTest {
        for (payload in listOf("""{"code":-101}""", """{"code":0,"data":{"isLogin":false}}""")) {
            assertFalse(service(payload).fetchLoginAccount().isLogin)
        }
        for (payload in listOf("""{"code":-352}""", """{"code":0}""", """{"code":0,"data":{}}""")) {
            assertFailsWith<AccountService.ServiceError.InvalidResponse> {
                service(payload).fetchLoginAccount()
            }
        }
    }

    @Test
    fun `authenticated response keeps account identity`() = runTest {
        val account = service("""{"code":0,"data":{"isLogin":true,"mid":42,"uname":"fixture"}}""")
            .fetchLoginAccount()
        assertEquals(42L, account.mid)
        assertEquals("fixture", account.name)
    }

    private fun service(payload: String) = AccountService(
        object : CookieProvider {
            override suspend fun loadCookies(): List<Cookie> = emptyList()
        },
        object : HttpClient {
            override suspend fun get(url: String, headers: Map<String, String>) = HttpResponse(200, payload)
            override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse =
                error("Unexpected POST")
        },
    )
}
