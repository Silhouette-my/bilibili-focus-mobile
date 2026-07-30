package org.bilibilifocus.core.model

/** ExoPlayer 播放所需的 DASH 流地址（视频/音频分轨）。*/
data class PlayUrlResult(
    val videoUrl: String,
    val audioUrl: String?,
    val referer: String = "https://www.bilibili.com",
    @Deprecated("Media requests intentionally do not receive login cookies")
    val cookie: String = "",
    val userAgent: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
)
