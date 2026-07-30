package org.bilibilifocus.core.model

data class VideoInfo(
    val bvid: String,
    val aid: Long,
    val cid: Long,
    val title: String,
    val description: String,
    val coverURL: String,
    val duration: Long,
    val publishDate: Long,
    val author: VideoAuthor,
    val stats: VideoStats,
    val tags: List<String> = emptyList(),
    val pages: List<VideoPage> = emptyList(),
    val episodeGroups: List<VideoEpisodeGroup> = emptyList(),
    val playerURL: String? = null,
    val width: Int = 0,
    val height: Int = 0,
    val lastPlaybackCid: Long? = null,
    val lastPlaybackPositionMillis: Long = 0,
)

data class VideoPage(
    val pageNumber: Int,
    val cid: Long,
    val title: String,
    val duration: Long,
)

data class VideoEpisodeGroup(
    val title: String,
    val episodes: List<VideoEpisode>,
)

data class VideoEpisode(
    val bvid: String,
    val aid: Long,
    val cid: Long,
    val title: String,
    val coverURL: String = "",
    val badgeText: String = "",
)

data class VideoAuthor(
    val name: String,
    val mid: Long,
    val avatarURL: String,
)

data class VideoStats(
    val views: Long,
    val likes: Long,
    val coins: Long,
    val favorites: Long,
    val shares: Long,
    val danmaku: Long,
    val comments: Long,
)

data class VideoInteractionState(
    val liked: Boolean = false,
    val coined: Boolean = false,
    val favorited: Boolean = false,
    val favoriteFolderId: Long? = null,
    val loading: Boolean = true,
)
