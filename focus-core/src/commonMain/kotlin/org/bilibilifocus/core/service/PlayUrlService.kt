package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.PlayUrlResult
import org.bilibilifocus.core.model.VideoQuality

/**
 * 取视频 DASH 流地址，供 ExoPlayer 播放。基于 x/player/wbi/playurl（需 WBI 签名）。
 * 优先选 AVC(H.264, codecid=7) 视频轨以保证设备/模拟器兼容；音频取接口返回的首轨。
 * 流地址下载时必须带 Referer + User-Agent。
 */
class PlayUrlService(
    private val cookieProvider: CookieProvider,
    private val httpClient: HttpClient,
    private val userAgent: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    private val wbiSigner: WbiSigner = WbiSigner(cookieProvider, httpClient, userAgent),
) {
    sealed class ServiceError(message: String) : Exception(message) {
        data object InvalidResponse : ServiceError("接口返回无效数据")
        data object NoStream : ServiceError("未获取到可播放的视频流")
        data object SigningUnavailable : ServiceError("签名初始化失败")
        data class Api(val code: Int, override val message: String) : ServiceError(message)
    }

    private val json = Json { ignoreUnknownKeys = true }

    suspend fun fetchPlayUrl(bvid: String, cid: Long, quality: Int = 80): PlayUrlResult {
        require(quality > 0)
        val endpoint = BiliApiContractCatalog.require("video.info.playurl").url
        val parameters = mapOf(
            "bvid" to bvid,
            "cid" to cid.toString(),
            "fnval" to "4048",
            "fourk" to "1",
            "otype" to "json",
            "platform" to "pc",
            "qn" to quality.toString(),
        )
        val result = try {
            wbiSigner.execute(parameters) { signedQuery ->
                val url = "$endpoint?$signedQuery"
                val response = httpClient.get(url, buildHeaders(url))
                val apiCode = runCatching {
                    (json.parseToJsonElement(response.body) as? JsonObject)?.intValueAt("code")
                }.getOrNull()
                WbiRequestResult(response, response.statusCode, apiCode)
            }
        } catch (_: WbiSigner.SigningUnavailable) {
            throw ServiceError.SigningUnavailable
        }
        val response = result.value
        if (response.statusCode !in 200..299) throw ServiceError.InvalidResponse

        val payload = json.parseToJsonElement(response.body) as? JsonObject
            ?: throw ServiceError.InvalidResponse
        val code = payload.intValueAt("code") ?: -1
        if (code != 0) throw ServiceError.Api(code, payload.stringValueAt("message") ?: "未知错误")

        val videos = payload.arrayValueAt("data", "dash", "video") ?: throw ServiceError.NoStream
        val audios = payload.arrayValueAt("data", "dash", "audio") ?: emptyList()

        // Keep all routes for bounded recovery, preferring regular CDN hosts.
        fun urls(item: JsonObject): List<String> {
            val candidates = mutableListOf<String>()
            (item.stringValueAt("baseUrl") ?: item.stringValueAt("base_url"))?.let { candidates.add(it) }
            (item.arrayValueAt("backupUrl") ?: item.arrayValueAt("backup_url"))?.forEach { el ->
                (el as? kotlinx.serialization.json.JsonPrimitive)?.content?.let { candidates.add(it) }
            }
            return candidates.filter(String::isNotBlank).distinct().sortedBy { "mcdn" in it || "szbdyd" in it }
        }

        val videoObjs = videos.mapNotNull { it as? JsonObject }
        val deliveredQuality = payload.intValueAt("data", "quality") ?: quality
        val requestedCandidates = videoObjs.filter { it.intValueAt("id") == deliveredQuality }
            .ifEmpty { videoObjs.filter { (it.intValueAt("id") ?: Int.MAX_VALUE) <= quality } }
            .ifEmpty { videoObjs }
        val selectedQuality = requestedCandidates.maxOfOrNull { it.intValueAt("id") ?: 0 }
        val matching = requestedCandidates.filter { it.intValueAt("id") == selectedQuality }.ifEmpty { requestedCandidates }
        val selected = matching.firstOrNull { it.intValueAt("codecid") == 7 } ?: matching.firstOrNull()
            ?: throw ServiceError.NoStream
        val videoUrls = urls(selected)
        val videoUrl = videoUrls.firstOrNull() ?: throw ServiceError.NoStream
        val audioUrls = audios.mapNotNull { it as? JsonObject }.firstOrNull()?.let(::urls).orEmpty()
        val descriptions = payload.arrayValueAt("data", "accept_description").orEmpty()
        val qualities = payload.arrayValueAt("data", "accept_quality").orEmpty().mapIndexedNotNull { index, raw ->
            val id = (raw as? kotlinx.serialization.json.JsonPrimitive)?.content?.toIntOrNull() ?: return@mapIndexedNotNull null
            val title = (descriptions.getOrNull(index) as? kotlinx.serialization.json.JsonPrimitive)?.content ?: "${id}P"
            VideoQuality(id, title)
        }

        return PlayUrlResult(
            videoUrl = videoUrl,
            audioUrl = audioUrls.firstOrNull(),
            userAgent = userAgent,
            quality = selectedQuality?.takeIf { it > 0 } ?: deliveredQuality,
            availableQualities = qualities,
            backupVideoUrls = videoUrls.drop(1),
            backupAudioUrls = audioUrls.drop(1),
        )
    }

    private suspend fun buildHeaders(targetUrl: String): Map<String, String> {
        val headers = mutableMapOf(
            "User-Agent" to userAgent,
            "Referer" to "https://www.bilibili.com/",
            "Accept" to "application/json, text/plain, */*",
        )
        return cookieProvider.attachCookies(headers, targetUrl)
    }

}
