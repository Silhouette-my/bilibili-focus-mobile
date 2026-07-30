package org.bilibilifocus.core.service

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.cookie.CookieRequestPolicy

/**
 * Privacy-safe authentication states shared with the Swift implementation.
 */
@Serializable
enum class LoginHealth {
    @SerialName("not_logged_in")
    NOT_LOGGED_IN,

    @SerialName("session_expired")
    SESSION_EXPIRED,

    @SerialName("missing_csrf")
    MISSING_CSRF,

    @SerialName("wbi_risk_controlled")
    WBI_RISK_CONTROLLED,

    @SerialName("network_unavailable")
    NETWORK_UNAVAILABLE,

    @SerialName("healthy")
    HEALTHY,

    @SerialName("unknown")
    UNKNOWN,
}

/**
 * Runs one read-only `/x/web-interface/nav` probe. Raw response bodies and
 * transport errors are deliberately collapsed into the finite state model.
 */
class LoginHealthService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = DEFAULT_USER_AGENT,
    private val clock: () -> Long = ::currentEpochSeconds,
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun check(): LoginHealth {
        val endpoint = BiliApiContractCatalog.require("credential.info.valid")
        val now = clock()
        val cookies = cookieProvider.loadCookies()
        val matchingCookies = CookieRequestPolicy.matchingCookies(
            cookies = cookies,
            targetUrl = endpoint.url,
            nowEpochSeconds = now,
        )
        val hasValidSession = matchingCookies.any {
            it.name.equals("SESSDATA", ignoreCase = true) && it.value.isNotEmpty()
        }
        if (!hasValidSession) {
            val scopedCookiesIncludingExpired = CookieRequestPolicy.matchingCookies(
                cookies = cookies,
                targetUrl = endpoint.url,
                nowEpochSeconds = Long.MIN_VALUE,
            )
            val hasExpiredSession = scopedCookiesIncludingExpired.any {
                it.name.equals("SESSDATA", ignoreCase = true) &&
                    it.value.isNotEmpty() &&
                    it.expiresAtEpochSeconds?.let { expiresAt -> expiresAt <= now } == true
            }
            return if (hasExpiredSession) {
                LoginHealth.SESSION_EXPIRED
            } else {
                LoginHealth.NOT_LOGGED_IN
            }
        }

        val hasCsrf = matchingCookies.any {
            it.name.equals("bili_jct", ignoreCase = true) && it.value.isNotEmpty()
        }
        val headers = cookieProvider.attachCookies(
            requestHeaders = mapOf(
                "Referer" to "https://www.bilibili.com/",
                "Accept" to "application/json, text/plain, */*",
                "User-Agent" to userAgent,
            ),
            cookies = cookies,
            targetUrl = endpoint.url,
            nowEpochSeconds = now,
        )

        val response = try {
            httpClient.get(endpoint.url, headers)
        } catch (_: CancellationException) {
            return LoginHealth.UNKNOWN
        } catch (_: Exception) {
            return LoginHealth.NETWORK_UNAVAILABLE
        }

        if (response.statusCode == 401) return LoginHealth.SESSION_EXPIRED
        if (response.statusCode == 403) return LoginHealth.WBI_RISK_CONTROLLED
        if (response.statusCode !in 200..299) return LoginHealth.UNKNOWN

        val payload = try {
            json.parseToJsonElement(response.body) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return LoginHealth.UNKNOWN

        return when (payload.intValueAt("code")) {
            -403, -352 -> LoginHealth.WBI_RISK_CONTROLLED
            -101 -> LoginHealth.SESSION_EXPIRED
            0 -> {
                when (payload.stringValueAt("data", "isLogin")?.toBooleanStrictOrNull()) {
                    false -> LoginHealth.SESSION_EXPIRED
                    true -> if (hasCsrf) LoginHealth.HEALTHY else LoginHealth.MISSING_CSRF
                    null -> LoginHealth.UNKNOWN
                }
            }
            else -> LoginHealth.UNKNOWN
        }
    }

    private companion object {
        private const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    }
}
