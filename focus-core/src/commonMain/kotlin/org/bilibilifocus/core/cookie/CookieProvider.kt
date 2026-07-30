package org.bilibilifocus.core.cookie

import io.ktor.http.parseUrl
import org.bilibilifocus.core.service.currentEpochSeconds

data class Cookie(
    val name: String,
    val value: String,
    val domain: String,
    val path: String = "/",
    val secure: Boolean = false,
    val expiresAtEpochSeconds: Long? = null,
    val hostOnly: Boolean = !domain.startsWith("."),
)

object CookieRequestPolicy {
    fun matchingCookies(
        cookies: List<Cookie>,
        targetUrl: String,
        nowEpochSeconds: Long = currentEpochSeconds(),
    ): List<Cookie> {
        val url = parseUrl(targetUrl) ?: return emptyList()
        val scheme = url.protocol.name.lowercase()
        if (scheme != "http" && scheme != "https") return emptyList()

        val requestHost = url.host.lowercase().trimEnd('.')
        if (requestHost.isEmpty()) return emptyList()
        val requestPath = url.encodedPath.ifEmpty { "/" }

        return cookies.withIndex()
            .filter { (_, cookie) ->
                cookie.name.isNotEmpty() &&
                    cookie.expiresAtEpochSeconds?.let { it > nowEpochSeconds } != false &&
                    (!cookie.secure || scheme == "https") &&
                    domainMatches(cookie, requestHost) &&
                    pathMatches(cookie.path, requestPath)
            }
            .sortedWith(
                compareByDescending<IndexedValue<Cookie>> {
                    normalizedCookiePath(it.value.path).length
                }.thenBy { it.index },
            )
            .map { it.value }
    }

    fun cookieHeader(
        cookies: List<Cookie>,
        targetUrl: String,
        nowEpochSeconds: Long = currentEpochSeconds(),
    ): String = matchingCookies(cookies, targetUrl, nowEpochSeconds)
        .joinToString("; ") { "${it.name}=${it.value}" }

    private fun domainMatches(cookie: Cookie, requestHost: String): Boolean {
        val cookieDomain = cookie.domain
            .trim()
            .trimStart('.')
            .trimEnd('.')
            .lowercase()
        if (cookieDomain.isEmpty()) return false
        if (requestHost == cookieDomain) return true
        return !cookie.hostOnly && requestHost.endsWith(".$cookieDomain")
    }

    private fun pathMatches(rawCookiePath: String, requestPath: String): Boolean {
        val cookiePath = normalizedCookiePath(rawCookiePath)
        if (requestPath == cookiePath) return true
        if (!requestPath.startsWith(cookiePath)) return false
        return cookiePath.endsWith("/") ||
            requestPath.getOrNull(cookiePath.length) == '/'
    }

    private fun normalizedCookiePath(path: String): String =
        path.takeIf { it.startsWith("/") } ?: "/"
}

interface CookieProvider {
    suspend fun loadCookies(): List<Cookie>

    suspend fun cookieHeaderFor(url: String): String =
        CookieRequestPolicy.cookieHeader(loadCookies(), url)

    suspend fun attachCookies(
        requestHeaders: Map<String, String>,
        targetUrl: String,
    ): Map<String, String> {
        val headersWithoutCookie = requestHeaders.filterKeys {
            !it.equals("Cookie", ignoreCase = true)
        }
        val cookieHeader = cookieHeaderFor(targetUrl)
        return if (cookieHeader.isEmpty()) {
            headersWithoutCookie
        } else {
            headersWithoutCookie + mapOf("Cookie" to cookieHeader)
        }
    }

    fun attachCookies(
        requestHeaders: Map<String, String>,
        cookies: List<Cookie>,
        targetUrl: String,
        nowEpochSeconds: Long = currentEpochSeconds(),
    ): Map<String, String> {
        val headersWithoutCookie = requestHeaders.filterKeys {
            !it.equals("Cookie", ignoreCase = true)
        }
        val cookieHeader = CookieRequestPolicy.cookieHeader(cookies, targetUrl, nowEpochSeconds)
        return if (cookieHeader.isEmpty()) {
            headersWithoutCookie
        } else {
            headersWithoutCookie + mapOf("Cookie" to cookieHeader)
        }
    }
}
