package org.bilibilifocus.android

import android.webkit.CookieManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import java.net.URI

class AndroidCookieProvider : CookieProvider {
    override suspend fun cookieHeaderFor(url: String): String = withContext(Dispatchers.Main) {
        if (trustedBilibiliCookieTarget(url) == null) {
            return@withContext ""
        }

        CookieManager.getInstance().getCookie(url)?.trim().orEmpty()
    }

    override suspend fun loadCookies(): List<Cookie> = withContext(Dispatchers.Main) {
        val manager = CookieManager.getInstance()
        // getCookie reads WebView's current cookie store. flush writes to disk
        // and can block, so persistence belongs to the login mutation path.
        buildAndroidCookieSnapshot(
            BILIBILI_COOKIE_SNAPSHOT_URLS.map { url ->
                AndroidCookieHeaderSnapshot(
                    url = url,
                    cookieHeader = manager.getCookie(url),
                )
            },
        )
    }

    private companion object {
        val BILIBILI_COOKIE_SNAPSHOT_URLS = listOf(
            "https://bilibili.com/",
            "https://www.bilibili.com/",
            "https://m.bilibili.com/",
            "https://t.bilibili.com/",
            "https://api.bilibili.com/",
            "https://s.search.bilibili.com/",
            "https://search.bilibili.com/",
            "https://passport.bilibili.com/",
            "https://player.bilibili.com/",
            "https://live.bilibili.com/",
            "https://space.bilibili.com/",
        )
    }
}

/**
 * WebView exposes only the request Cookie header, not the original
 * Domain/Path attributes. Bind every parsed pair to the exact trusted origin
 * that produced it so a later common-layer match cannot accidentally drop an
 * API cookie or promote it to an unrelated host.
 */
internal data class AndroidCookieHeaderSnapshot(
    val url: String,
    val cookieHeader: String?,
)

internal fun buildAndroidCookieSnapshot(
    snapshots: List<AndroidCookieHeaderSnapshot>,
): List<Cookie> = snapshots
    .flatMap { snapshot ->
        val target = trustedBilibiliCookieTarget(snapshot.url) ?: return@flatMap emptyList()
        snapshot.cookieHeader
            ?.split(';')
            .orEmpty()
            .mapNotNull { rawPair ->
                val pair = rawPair.trim()
                val separator = pair.indexOf('=')
                if (separator <= 0) return@mapNotNull null
                val name = pair.substring(0, separator).trim()
                if (name.isEmpty()) return@mapNotNull null
                Cookie(
                    name = name,
                    value = pair.substring(separator + 1).trim(),
                    domain = target.host,
                    path = target.path,
                    secure = target.secure,
                    hostOnly = true,
                )
            }
    }
    // Only exact synthetic duplicates are redundant. Same-name cookies with a
    // different value, host, or path must remain separate.
    .distinct()

internal fun isTrustedBilibiliCookieUrl(url: String): Boolean =
    trustedBilibiliCookieTarget(url) != null

private fun trustedBilibiliCookieTarget(url: String): BilibiliCookieTarget? {
    val parsed = runCatching { URI(url) }.getOrNull() ?: return null
    val scheme = parsed.scheme?.lowercase()
    if (scheme != "http" && scheme != "https") return null
    if (parsed.rawUserInfo != null) return null

    val host = parsed.host
        ?.trimEnd('.')
        ?.lowercase()
        ?.takeIf { it == "bilibili.com" || it.endsWith(".bilibili.com") }
        ?: return null
    val path = parsed.rawPath
        ?.takeIf(String::isNotEmpty)
        ?.takeIf { it.startsWith("/") }
        ?: "/"
    return BilibiliCookieTarget(
        host = host,
        path = path,
        secure = scheme == "https",
    )
}

private data class BilibiliCookieTarget(
    val host: String,
    val path: String,
    val secure: Boolean,
)
