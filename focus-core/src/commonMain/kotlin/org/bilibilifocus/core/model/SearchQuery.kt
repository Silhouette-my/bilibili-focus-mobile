package org.bilibilifocus.core.model

import kotlinx.serialization.Serializable

@Serializable
@ConsistentCopyVisibility
data class SearchQuery private constructor(
    val keyword: String,
) {
    init {
        require(keyword == keyword.trim()) { "keyword 必须去除首尾空白" }
    }

    val resultURL: String
        get() {
            val encoded = org.bilibilifocus.core.routing.urlEncode(keyword)
            return "https://search.bilibili.com/all?keyword=$encoded"
        }

    companion object {
        operator fun invoke(keyword: String): SearchQuery = SearchQuery(keyword.trim())
    }
}

@Serializable
enum class SearchResultFilter {
    ALL,
    VIDEO,
    USERS,
    LIVE,
    BANGUMI,
    FILM;

    val title: String
        get() = when (this) {
            ALL -> "综合"
            VIDEO -> "视频"
            USERS -> "UP主"
            LIVE -> "直播"
            BANGUMI -> "番剧"
            FILM -> "影视"
        }

    val apiSearchType: String?
        get() = when (this) {
            ALL -> null
            VIDEO -> "video"
            USERS -> "bili_user"
            LIVE -> "live_room"
            BANGUMI -> "media_bangumi"
            FILM -> "media_ft"
        }

    val sectionTitle: String
        get() = when (this) {
            ALL -> "综合"
            VIDEO -> "视频结果"
            USERS -> "相关 UP 主"
            LIVE -> "直播"
            BANGUMI -> "番剧"
            FILM -> "影视"
        }

    companion object {
        val defaultOrder: List<SearchResultFilter> = listOf(ALL, VIDEO, USERS, LIVE, BANGUMI, FILM)
    }
}

@Serializable
enum class SearchVideoSortOption {
    DEFAULT,
    MOST_PLAYED,
    LATEST_PUBLISHED;

    val title: String
        get() = when (this) {
            DEFAULT -> "默认"
            MOST_PLAYED -> "最多播放"
            LATEST_PUBLISHED -> "最新发布"
        }

    val apiOrderValue: String?
        get() = when (this) {
            DEFAULT -> null
            MOST_PLAYED -> "click"
            LATEST_PUBLISHED -> "pubdate"
        }
}

@Serializable
data class SearchResultPage(
    val sections: List<SearchResultSection>,
    val nextPage: Int? = null,
)

@Serializable
data class SearchResultSection(
    val filter: SearchResultFilter,
    val items: List<SearchResultItem>,
) {
    val id: String get() = filter.name
    val title: String get() = filter.sectionTitle
}

@Serializable
data class SearchResultItem(
    val id: String,
    val kind: Kind,
    val title: String,
    val subtitle: String = "",
    val metadataText: String = "",
    val badgeText: String = "",
    val descriptionText: String = "",
    val coverURL: String? = null,
    val avatarURL: String? = null,
    val targetURL: String,
    val previews: List<PreviewVideo> = emptyList(),
) {
    @Serializable
    enum class Kind {
        VIDEO,
        USER,
        LIVE,
        MEDIA,
    }

    @Serializable
    data class PreviewVideo(
        val id: String,
        val title: String,
        val coverURL: String? = null,
        val targetURL: String,
        val metadataText: String = "",
        val badgeText: String = "",
    )
}
