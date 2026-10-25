package org.bilibilifocus.core.model

data class VideoComment(
    val rpid: Long,
    val mid: Long,
    val authorName: String,
    val avatarURL: String,
    val content: String,
    val contentRuns: List<RichTextRun> = RichTextRun.plain(content),
    val likeCount: Long,
    val replyCount: Long,
    val publishTime: Long,
    val replies: List<VideoComment> = emptyList(),
    val imageURLs: List<String> = emptyList(),
)
