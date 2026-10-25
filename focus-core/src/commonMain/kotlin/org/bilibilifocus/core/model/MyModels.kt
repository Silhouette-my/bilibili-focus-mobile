package org.bilibilifocus.core.model

/** 当前登录账号信息（来自 x/web-interface/nav）。*/
data class LoginAccount(
    val isLogin: Boolean,
    val mid: Long,
    val name: String,
    val avatarURL: String,
    val level: Int,
)

/** 一条播放历史（来自 x/web-interface/history/cursor 的 data.list[]）。*/
data class HistoryItem(
    val title: String,
    val coverURL: String,
    val bvid: String,
    val authorName: String,
    val viewAt: Long,
    val progress: Long,
    val duration: Long,
    val cid: Long = 0,
    val page: Int = 0,
)

/** 历史记录翻页游标。*/
data class HistoryPage(
    val items: List<HistoryItem>,
    val nextMax: Long,
    val nextViewAt: Long,
    val nextBusiness: String,
)

/** 一个收藏夹（来自 x/v3/fav/folder/created/list-all 的 data.list[]）。*/
data class FavFolder(
    val id: Long,
    val title: String,
    val mediaCount: Int,
    val coverURL: String,
)

/** 收藏夹内的一个视频（来自 x/v3/fav/resource/list 的 data.medias[]）。*/
data class FavResource(
    val bvid: String,
    val title: String,
    val coverURL: String,
    val upperName: String,
    val duration: String,
    val playCount: Long,
)
