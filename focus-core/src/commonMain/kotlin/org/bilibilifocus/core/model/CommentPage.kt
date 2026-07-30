package org.bilibilifocus.core.model

data class CommentCursor(
    val nextOffset: String? = null,
)

data class CommentPage(
    val comments: List<VideoComment>,
    val totalCount: Long,
    val cursor: CommentCursor,
)
