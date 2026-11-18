package org.bilibilifocus.android.images

import okhttp3.Dispatcher
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.util.concurrent.TimeUnit

/**
 * Image traffic mirrors iOS's image repository: browser headers, a Bilibili
 * Referer, and a bounded Referer rotation on 403 only. Offline, timeout, TLS
 * and 5xx failures are never retried here (no Referer/URL retry storm).
 */
internal object FocusImageHttpClient {
    const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    private const val DEFAULT_REFERER = "https://www.bilibili.com/"
    internal val fallbackReferers = listOf("https://t.bilibili.com/", DEFAULT_REFERER, "")

    fun isBilibiliImageHost(host: String): Boolean {
        val h = host.lowercase()
        return h.endsWith(".hdslb.com") || h == "hdslb.com" || h.endsWith(".biliimg.com")
    }

    fun create(): OkHttpClient {
        // OkHttp's default of 5 concurrent calls per host starves a feed of
        // avatars + covers that all live on i0/i1/i2.hdslb.com.
        val dispatcher = Dispatcher().apply {
            maxRequests = 64
            maxRequestsPerHost = 16
        }
        return OkHttpClient.Builder()
            .dispatcher(dispatcher)
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            // Coil's own disk cache stores the bytes; no second HTTP cache.
            .addInterceptor(HeaderInterceptor())
            .build()
    }

    internal class HeaderInterceptor : Interceptor {
        override fun intercept(chain: Interceptor.Chain): Response {
            val original = chain.request()
            if (!isBilibiliImageHost(original.url.host)) return chain.proceed(original)
            val callerReferer = original.header("Referer")
            val first = withBrowserHeaders(original, callerReferer ?: DEFAULT_REFERER)
            var response = chain.proceed(first)
            if (response.code != 403) return response
            val tried = mutableSetOf(callerReferer ?: DEFAULT_REFERER)
            for (referer in fallbackReferers) {
                if (!tried.add(referer)) continue
                response.close()
                response = chain.proceed(withBrowserHeaders(original, referer))
                if (response.code != 403) return response
            }
            return response
        }

        private fun withBrowserHeaders(request: Request, referer: String): Request {
            val builder = request.newBuilder()
            if (request.header("User-Agent") == null) builder.header("User-Agent", USER_AGENT)
            if (request.header("Accept") == null) builder.header("Accept", "image/avif,image/webp,image/apng,image/*,*/*;q=0.8")
            if (request.header("Accept-Language") == null) builder.header("Accept-Language", "zh-CN,zh-Hans;q=0.9")
            if (referer.isEmpty()) builder.removeHeader("Referer") else builder.header("Referer", referer)
            return builder.build()
        }
    }
}
