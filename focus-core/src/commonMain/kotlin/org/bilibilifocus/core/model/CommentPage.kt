package org.bilibilifocus.core.model

data class CommentCursor(
    val nextOffset: String? = null,
)

data class CommentPage(
    val comments: List<VideoComment>,
    val totalCount: Long,
    val cursor: CommentCursor,
)

/** A Bilibili comment area: [oid] + [type] (1 video, 11 image dynamic, 12 article, 17 text dynamic). */
data class CommentTarget(
    val oid: Long,
    val type: Int,
)
