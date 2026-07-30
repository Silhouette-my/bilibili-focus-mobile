package org.bilibilifocus.core.service

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.crypto.md5Hex

/**
 * Application-shareable WBI signer.
 *
 * The key returned by nav is short-lived, so requests that receive either an
 * HTTP 403 or a Bilibili API -403 invalidate it and retry with a fresh key.
 */
class WbiSigner(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = DEFAULT_USER_AGENT,
    private val clock: () -> Long = ::currentEpochSeconds,
    private val keyTtlSeconds: Long = DEFAULT_KEY_TTL_SECONDS,
) {
    class SigningUnavailable internal constructor(
        message: String = "WBI 签名初始化失败",
        cause: Throwable? = null,
    ) : Exception(message, cause)

    private val json = Json { ignoreUnknownKeys = true }
    private val keyMutex = Mutex()
    private var cachedMixinKey: String? = null
    private var expiresAtEpochSeconds: Long = 0

    suspend fun signedQuery(parameters: Map<String, String>): String =
        signWbiQuery(
            parameters = parameters,
            mixinKey = mixinKey(),
            wts = clock(),
        )

    /**
     * Executes a signed request and retries only signature rejections.
     *
     * The result is deliberately returned to the caller so each service can
     * preserve its existing error mapping and response model.
     */
    suspend fun <T> execute(
        parameters: Map<String, String>,
        maxAttempts: Int = DEFAULT_MAX_ATTEMPTS,
        request: suspend (signedQuery: String) -> WbiRequestResult<T>,
    ): WbiRequestResult<T> {
        require(maxAttempts > 0) { "maxAttempts 必须大于 0" }

        repeat(maxAttempts) { attempt ->
            val result = request(signedQuery(parameters))
            val signatureRejected =
                result.httpStatusCode == 403 || result.apiCode == WBI_REJECTED_API_CODE
            if (!signatureRejected || attempt == maxAttempts - 1) {
                return result
            }
            invalidate()
        }
        error("unreachable")
    }

    suspend fun invalidate() {
        keyMutex.withLock {
            cachedMixinKey = null
            expiresAtEpochSeconds = 0
        }
    }

    private suspend fun mixinKey(): String {
        return keyMutex.withLock {
            val lockedNow = clock()
            cachedMixinKey?.takeIf { lockedNow < expiresAtEpochSeconds }?.let { return@withLock it }

            val navUrl = BiliApiContractCatalog.require("credential.info.valid").url
            val headers = cookieProvider.attachCookies(
                mapOf(
                    "Referer" to "https://www.bilibili.com/",
                    "Accept" to "application/json, text/plain, */*",
                    "User-Agent" to userAgent,
                ),
                navUrl,
            )
            val response = try {
                httpClient.get(navUrl, headers)
            } catch (error: Exception) {
                throw SigningUnavailable(cause = error)
            }
            if (response.statusCode !in 200..299) {
                throw SigningUnavailable("WBI nav 请求失败：HTTP ${response.statusCode}")
            }

            val payload = try {
                json.parseToJsonElement(response.body) as? JsonObject
            } catch (error: Exception) {
                throw SigningUnavailable(cause = error)
            } ?: throw SigningUnavailable()
            if (payload.intValueAt("code") != 0) {
                throw SigningUnavailable(payload.stringValueAt("message") ?: "WBI nav 返回错误")
            }

            val imgKey = payload.stringValueAt("data", "wbi_img", "img_url")
                ?.substringAfterLast("/")
                ?.substringBefore(".")
                ?.takeIf(String::isNotEmpty)
                ?: throw SigningUnavailable()
            val subKey = payload.stringValueAt("data", "wbi_img", "sub_url")
                ?.substringAfterLast("/")
                ?.substringBefore(".")
                ?.takeIf(String::isNotEmpty)
                ?: throw SigningUnavailable()
            val refreshedKey = mixinKey(imgKey, subKey)
                .takeIf(String::isNotEmpty)
                ?: throw SigningUnavailable()

            cachedMixinKey = refreshedKey
            expiresAtEpochSeconds = lockedNow + keyTtlSeconds.coerceAtLeast(0)
            refreshedKey
        }
    }

    companion object {
        private const val DEFAULT_KEY_TTL_SECONDS = 30L * 60L
        private const val DEFAULT_MAX_ATTEMPTS = 3
        private const val WBI_REJECTED_API_CODE = -403
        private const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

        private val MIXIN_KEY_ENC_TAB = intArrayOf(
            46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
            27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
            37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
            22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 52, 34, 44,
        )

        internal fun mixinKey(imgKey: String, subKey: String): String {
            val source = imgKey + subKey
            return buildString {
                MIXIN_KEY_ENC_TAB.forEach { index ->
                    if (index < source.length) append(source[index])
                }
            }.take(32)
        }
    }
}

data class WbiRequestResult<T>(
    val value: T,
    val httpStatusCode: Int,
    val apiCode: Int? = null,
)

internal fun signWbiQuery(
    parameters: Map<String, String>,
    mixinKey: String,
    wts: Long,
): String {
    val canonicalQuery = parameters
        .asSequence()
        .filter { (key, _) -> key != "w_rid" && key != "wts" }
        .map { (key, value) ->
            key to value.filterNot { character -> character in "!'()*" }
        }
        .plus(sequenceOf("wts" to wts.toString()))
        .sortedBy { (key, _) -> key }
        .joinToString("&") { (key, value) ->
            "${rfc3986Encode(key)}=${rfc3986Encode(value)}"
        }
    return "$canonicalQuery&w_rid=${md5Hex(canonicalQuery + mixinKey)}"
}

internal fun rfc3986Encode(value: String): String = buildString {
    value.encodeToByteArray().forEach { byte ->
        val octet = byte.toInt() and 0xff
        if (
            octet in 'A'.code..'Z'.code ||
            octet in 'a'.code..'z'.code ||
            octet in '0'.code..'9'.code ||
            octet == '-'.code ||
            octet == '.'.code ||
            octet == '_'.code ||
            octet == '~'.code
        ) {
            append(octet.toChar())
        } else {
            append('%')
            append(HEX_DIGITS[octet ushr 4])
            append(HEX_DIGITS[octet and 0x0f])
        }
    }
}

private const val HEX_DIGITS = "0123456789ABCDEF"
