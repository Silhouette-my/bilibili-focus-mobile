package org.bilibilifocus.core.service

import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LoginHealthDiagnosticsTests {
    @Test
    fun `cookie presence distinguishes logged out from expired session`() = runTest {
        assertEquals(
            LoginHealth.NOT_LOGGED_IN,
            service(cookies = emptyList()).check(),
        )
        assertEquals(
            LoginHealth.SESSION_EXPIRED,
            service(
                cookies = listOf(
                    healthCookie(
                        name = "SESSDATA",
                        value = "expired-secret",
                        expiresAt = NOW - 1,
                    ),
                ),
            ).check(),
        )
    }

    @Test
    fun `valid login distinguishes healthy from missing CSRF`() = runTest {
        assertEquals(
            LoginHealth.MISSING_CSRF,
            service(cookies = listOf(healthCookie("SESSDATA", "session-secret"))).check(),
        )
        assertEquals(
            LoginHealth.HEALTHY,
            service(cookies = authenticatedCookies()).check(),
        )
    }

    @Test
    fun `server invalidation and risk control responses are classified`() = runTest {
        assertEquals(
            LoginHealth.SESSION_EXPIRED,
            service(response = HttpResponse(200, """{"code":-101}""")).check(),
        )
        assertEquals(
            LoginHealth.WBI_RISK_CONTROLLED,
            service(response = HttpResponse(200, """{"code":-352}""")).check(),
        )
        assertEquals(
            LoginHealth.WBI_RISK_CONTROLLED,
            service(response = HttpResponse(403, "blocked")).check(),
        )
    }

    @Test
    fun `transport failure and malformed payload are collapsed`() = runTest {
        assertEquals(
            LoginHealth.NETWORK_UNAVAILABLE,
            service(failure = IllegalStateException("offline secret")).check(),
        )
        assertEquals(
            LoginHealth.UNKNOWN,
            service(response = HttpResponse(200, "not-json secret-body")).check(),
        )
    }

    @Test
    fun `diagnostic export strips user info query fragment and raw failures`() = runTest {
        val sink = InMemoryNetworkEventSink(capacity = 2)
        sink.record(
            NetworkEvent(
                method = "custom secret-method",
                target = "https://SESSDATA:cookie-secret@api.bilibili.com/private/path" +
                    "?keyword=search-secret#body-secret",
                statusCode = 999,
                durationMillis = -1,
                responseBytes = -20,
                failureType = "SecretTransportError_cookie-secret",
            ),
        )

        val snapshot = BiliDiagnostics.snapshot(LoginHealth.NETWORK_UNAVAILABLE, sink)
        assertEquals(
            listOf(
                BiliDiagnosticEvent(
                    method = "OTHER",
                    target = "https://api.bilibili.com/private/path",
                    statusCode = null,
                    durationMilliseconds = 0,
                    responseBytes = 0,
                    failureType = "transport_error",
                ),
            ),
            snapshot.events,
        )

        val encoded = snapshot.toJson()
        listOf(
            "SESSDATA",
            "cookie-secret",
            "keyword",
            "search-secret",
            "body-secret",
            "SecretTransportError",
        ).forEach { secret ->
            assertFalse(secret in encoded)
        }
        assertTrue(""""loginHealth":"network_unavailable"""" in encoded)
    }

    private fun service(
        cookies: List<Cookie> = authenticatedCookies(),
        response: HttpResponse = SUCCESSFUL_LOGIN_RESPONSE,
        failure: Exception? = null,
    ): LoginHealthService =
        LoginHealthService(
            cookieProvider = StaticHealthCookieProvider(cookies),
            httpClient = HealthHttpClient(response, failure),
            clock = { NOW },
        )

    private companion object {
        private const val NOW = 2_000_000_000L
        private val SUCCESSFUL_LOGIN_RESPONSE =
            HttpResponse(200, """{"code":0,"data":{"isLogin":true}}""")
    }
}

private class StaticHealthCookieProvider(
    private val cookies: List<Cookie>,
) : CookieProvider {
    override suspend fun loadCookies(): List<Cookie> = cookies
}

private class HealthHttpClient(
    private val response: HttpResponse,
    private val failure: Exception?,
) : HttpClient {
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        failure?.let { throw it }
        return response
    }

    override suspend fun post(
        url: String,
        body: String,
        headers: Map<String, String>,
    ): HttpResponse = error("login health must stay read-only")
}

private fun authenticatedCookies(): List<Cookie> =
    listOf(
        healthCookie("SESSDATA", "session-secret"),
        healthCookie("bili_jct", "csrf-secret"),
    )

private fun healthCookie(
    name: String,
    value: String,
    expiresAt: Long? = null,
): Cookie =
    Cookie(
        name = name,
        value = value,
        domain = ".bilibili.com",
        path = "/",
        secure = true,
        expiresAtEpochSeconds = expiresAt,
        hostOnly = false,
    )
