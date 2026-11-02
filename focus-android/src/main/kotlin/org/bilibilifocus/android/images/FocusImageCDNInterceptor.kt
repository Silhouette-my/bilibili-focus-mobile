package org.bilibilifocus.android.images

import coil.intercept.Interceptor
import coil.network.HttpException
import coil.request.ErrorResult
import coil.request.ImageResult
import coil.request.ImageRequest
import coil.request.SuccessResult
import coil.size.Dimension
import coil.size.Scale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.net.URI

/** Matches iOS's public-BFS still-image policy; galleries and emotes keep their source. */
internal object FocusImageCDNRequest {
    private val buckets = intArrayOf(128, 256, 384, 512, 768, 1_024, 1_536, 2_048, 3_072, 4_096)
    private val imageHost = Regex("i[0-9]+\\.hdslb\\.com")
    private val folders = listOf("/bfs/archive/", "/bfs/face/", "/bfs/new_dyn/", "/bfs/article/", "/bfs/album/")

    /** Upgrade only known public image CDNs; preserve path, query and fragment byte-for-byte. */
    fun canonicalURL(source: String): String {
        val uri = try {
            URI(source)
        } catch (_: java.net.URISyntaxException) {
            return source
        }
        if (uri.rawUserInfo != null || uri.port != -1 || !imageHost.matches(uri.host.orEmpty().lowercase())) return source
        return when (uri.scheme?.lowercase()) {
            "http" -> "https:" + source.substringAfter(':')
            null -> if (source.startsWith("//")) "https:$source" else source
            else -> source
        }
    }

    fun thumbnailURL(source: String, pixelSize: Int): String? {
        val uri = try {
            URI(source)
        } catch (_: java.net.URISyntaxException) {
            return null
        }
        if (uri.scheme != "https" || uri.rawUserInfo != null || uri.port != -1 ||
            uri.rawQuery != null || uri.rawFragment != null || !imageHost.matches(uri.host.orEmpty().lowercase())
        ) return null
        val path = uri.rawPath.substringBefore('@')
        if (folders.none(path::startsWith) || path.substringAfterLast('.').lowercase() !in setOf("jpg", "jpeg", "png", "webp")) {
            return null
        }
        val pixels = buckets.firstOrNull { it >= pixelSize.coerceAtLeast(1) } ?: buckets.last()
        // 0e fits a bounding box without cropping. No format conversion for GIF/APNG emotes.
        return "https://${uri.rawAuthority}$path@${pixels}w_${pixels}h_0e.webp"
    }
}

/** Coil resolves the rendered size before this interceptor, so no UI-specific URL rewriting is needed. */
internal class FocusImageCDNInterceptor : Interceptor {
    internal data class FlightKey(val url: String, val width: Int, val height: Int, val scale: Scale, val fallbackURL: String)
    private val flights = FocusImageInFlightRequests<FlightKey, ImageResult>(CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate))

    override suspend fun intercept(chain: Interceptor.Chain): ImageResult {
        val original = chain.request
        val source = original.data as? String ?: return chain.proceed(original)
        val canonicalSource = FocusImageCDNRequest.canonicalURL(source)
        val normalized = if (canonicalSource == source) original else original.newBuilder().data(canonicalSource).build()
        // Size.ORIGINAL and width-fitted long images intentionally bypass thumbnails.
        val width = (chain.size.width as? Dimension.Pixels)?.px ?: return chain.proceed(normalized)
        val height = (chain.size.height as? Dimension.Pixels)?.px ?: return chain.proceed(normalized)
        val thumbnail = FocusImageCDNRequest.thumbnailURL(canonicalSource, maxOf(width, height)) ?: return chain.proceed(normalized)
        val request = if (canonicalSource == thumbnail) normalized else normalized.newBuilder().data(thumbnail).build()
        val dynamicRequest = original.tags.tag(FocusDynamicImageRequest::class.java)
        if (dynamicRequest == null) return proceedWithFallback(chain, request, normalized)

        val result = flights.execute(FlightKey(thumbnail, width, height, dynamicRequest.scale, canonicalSource)) {
            proceedWithFallback(chain, request, normalized)
        }
        // Results must retain this consumer's target/listener, not the first caller's.
        val consumerRequest = request.newBuilder().data(result.request.data).build()
        return when (result) {
            is SuccessResult -> result.copy(
                request = consumerRequest,
                drawable = result.drawable.constantState?.newDrawable(request.context.resources) ?: result.drawable,
            )
            is ErrorResult -> result.copy(request = consumerRequest)
        }
    }

    private suspend fun proceedWithFallback(chain: Interceptor.Chain, request: ImageRequest, normalized: ImageRequest): ImageResult {
        val result = try {
            chain.proceed(request)
        } catch (error: HttpException) {
            if (error.response.code !in setOf(403, 404)) throw error
            // A derivative rejected by the CDN may still have a valid original.
            // Offline, timeout, TLS and 5xx failures never cause a second fetch.
            return chain.proceed(normalized)
        }
        return if (result is ErrorResult && (result.throwable as? HttpException)?.response?.code in setOf(403, 404)) {
            chain.proceed(normalized)
        } else {
            result
        }
    }
}

