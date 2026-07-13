package org.bilibilifocus.core.model

data class UserProfile(
    val mid: Long,
    val name: String,
    val avatarURL: String,
    val sign: String,
    val level: Int,
    val following: Long,
    val followers: Long,
    val videoCount: Int = 0,
    val articleCount: Int = 0,
)

data class UserVideo(
    val aid: Long,
    val bvid: String,
    val title: String,
    val coverURL: String,
    val playCount: Long,
    val danmakuCount: Long,
    val duration: String,
    val created: Long,
    val author: String = "",
)

data class UserVideoPage(
    val totalCount: Int,
    val items: List<UserVideo>,
    val nextPage: Int?,
)

data class UserContentCollection(
    val id: String,
    val ownerMid: Long,
    val rawId: Long,
    val kind: Kind,
    val title: String,
    val description: String,
    val coverURL: String,
    val itemCount: Int,
    val updatedAt: Long,
) {
    enum class Kind(val title: String) {
        SEASON("合集"),
        SERIES("系列"),
    }
}

data class UserArticle(
    val id: Long,
    val title: String,
    val summary: String,
    val coverURL: String,
    val publishedAt: Long,
    val viewCount: Long,
    val targetURL: String,
)

data class UserCollectionPage(
    val collection: UserContentCollection,
    val videos: List<UserVideo>,
    val nextPage: Int?,
)
