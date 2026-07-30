package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
data class WatchLaterAuthor(
    val mid: Long,
    val name: String,
    val avatarURL: String,
)

@Serializable
data class WatchLaterItem(
    val aid: Long,
    val bvid: String,
    val cid: Long,
    val title: String,
    val coverURL: String,
    val author: WatchLaterAuthor,
    val durationSeconds: Long,
    val progressSeconds: Long,
    val addedAt: Long,
    val publishedAt: Long,
    val viewCount: Long,
) {
    val targetURL: String
        get() = when {
            bvid.isNotBlank() -> "https://www.bilibili.com/video/$bvid/"
            aid > 0 -> "https://www.bilibili.com/video/av$aid/"
            else -> ""
        }
}

@Serializable
data class WatchLaterList(
    val totalCount: Int,
    val items: List<WatchLaterItem>,
)
