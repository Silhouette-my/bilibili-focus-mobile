package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.ui.FocusImageGalleryRequest
import org.bilibilifocus.android.ui.FocusRichText
import org.bilibilifocus.core.model.VideoComment
import org.bilibilifocus.android.FocusVideoViewModel
import org.bilibilifocus.android.VideoCommentsUiState

@Composable
internal fun CommentItem(
    comment: VideoComment,
    onOpenURL: (String) -> Unit,
    onOpenImage: (List<String>, Int) -> Unit = { _, _ -> },
    showReplies: Boolean = true,
    onReply: (() -> Unit)? = null,
    onLike: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null,
    actionsEnabled: Boolean = true,
) {
    val contentStyle = MaterialTheme.typography.bodyMedium.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    val replyStyle = MaterialTheme.typography.bodySmall.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    val authorStyle = MaterialTheme.typography.labelMedium.let {
        it.copy(fontSize = it.fontSize * 1.15f)
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(comment.avatarURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.size(28.dp).clip(CircleShape),
                contentScale = ContentScale.Crop,
            )
            Text(comment.authorName, style = authorStyle, color = MaterialTheme.colorScheme.primary)
            Spacer(modifier = Modifier.weight(1f))
            Text(
                formatTimeAgo(comment.publishTime),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (onLike == null) Text("${comment.likeCount}赞", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        FocusRichText(comment.contentRuns, style = contentStyle, onOpenURL = onOpenURL)
        CommentImageStrip(comment.imageURLs, onOpenImage, referer = "https://www.bilibili.com/")

        if (onReply != null || onLike != null || onDelete != null) Row {
            if (onLike != null) TextButton(onClick = onLike, enabled = actionsEnabled) { Text("${if (comment.isLiked) "已赞" else "赞"} ${comment.likeCount}") }
            if (onReply != null) TextButton(onClick = onReply, enabled = actionsEnabled) { Text("回复") }
            if (onDelete != null) TextButton(onClick = onDelete, enabled = actionsEnabled) { Text("删除", color = MaterialTheme.colorScheme.error) }
        }
        if (showReplies) comment.replies.take(3).forEach { reply ->
            Column(modifier = Modifier.padding(start = 36.dp, top = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row {
                    Text("${reply.authorName}: ", style = replyStyle, color = MaterialTheme.colorScheme.primary)
                    FocusRichText(
                        reply.contentRuns,
                        style = replyStyle.copy(color = MaterialTheme.colorScheme.onSurfaceVariant),
                        modifier = Modifier.weight(1f),
                        onOpenURL = onOpenURL,
                    )
                }
                CommentImageStrip(reply.imageURLs, onOpenImage, referer = "https://www.bilibili.com/")
            }
        }
    }
}

@Composable
internal fun VideoCommentsSection(
    viewModel: FocusVideoViewModel,
    comments: List<VideoComment>,
    state: VideoCommentsUiState,
    onOpenURL: (String) -> Unit,
    onOpenImage: (List<String>, Int) -> Unit,
) {
    var composing by remember { mutableStateOf(false) }
    var replyTarget by remember { mutableStateOf<Pair<VideoComment, VideoComment>?>(null) }
    var message by remember { mutableStateOf("") }
    var deleting by remember { mutableStateOf<VideoComment?>(null) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("评论", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            TextButton(onClick = { replyTarget = null; composing = true }) { Text("发表评论") }
        }
        comments.forEach { root ->
            CommentItem(
                root, onOpenURL, onOpenImage, showReplies = false,
                onReply = { replyTarget = root to root; composing = true },
                onLike = { viewModel.toggleCommentLike(root) },
                onDelete = if (state.accountMid == root.mid && root.mid > 0) ({ deleting = root }) else null,
                actionsEnabled = root.rpid !in state.actionsInFlight,
            )
            val replies = state.replies[root.rpid]
            (replies?.replies ?: root.replies.take(3)).forEach { reply ->
                Column(Modifier.padding(start = 28.dp)) {
                    CommentItem(
                        reply, onOpenURL, onOpenImage, showReplies = false,
                        onReply = { replyTarget = root to reply; composing = true },
                        onLike = { viewModel.toggleCommentLike(reply) },
                        onDelete = if (state.accountMid == reply.mid && reply.mid > 0) ({ deleting = reply }) else null,
                        actionsEnabled = reply.rpid !in state.actionsInFlight,
                    )
                }
            }
            if (root.replyCount > 0 && (replies == null || replies.nextPage != null)) {
                TextButton(onClick = { viewModel.loadReplies(root) }, enabled = replies?.isLoading != true) {
                    Text(when { replies?.isLoading == true -> "加载回复中…"; replies?.error != null -> "回复加载失败，重试"; replies == null -> "展开 ${root.replyCount} 条回复"; else -> "更多回复" })
                }
            }
            replies?.error?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error) }
        }
        when {
            state.isLoading -> CircularProgressIndicator(Modifier.size(24.dp))
            state.error != null -> {
                Text(state.error, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                TextButton(onClick = { viewModel.loadComments(append = comments.isNotEmpty()) }) { Text("重试评论") }
            }
            state.hasMore -> TextButton(onClick = { viewModel.loadComments(append = true) }) { Text("加载更多评论") }
            comments.isEmpty() -> Text("还没有评论", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (composing) AlertDialog(
        onDismissRequest = { if (!state.isSending) composing = false },
        title = { Text(replyTarget?.second?.let { "回复 ${it.authorName}" } ?: "发表评论") },
        text = {
            OutlinedTextField(
                value = message, onValueChange = { if (it.length <= 1000) message = it },
                minLines = 3, maxLines = 6, enabled = !state.isSending,
                supportingText = { Text("${message.length}/1000") }, placeholder = { Text("分享你的想法") },
            )
        },
        confirmButton = { TextButton(
            onClick = { viewModel.sendComment(message, replyTarget?.first, replyTarget?.second) { message = ""; composing = false; replyTarget = null } },
            enabled = message.isNotBlank() && !state.isSending,
        ) { Text(if (state.isSending) "发送中…" else "发送") } },
        dismissButton = { TextButton(onClick = { composing = false }, enabled = !state.isSending) { Text("取消") } },
    )
    deleting?.let { comment -> AlertDialog(
        onDismissRequest = { deleting = null }, title = { Text("删除这条评论？") },
        confirmButton = { TextButton(onClick = { viewModel.deleteComment(comment); deleting = null }) { Text("删除", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } },
    ) }
}

@Composable
internal fun CommentImageStrip(
    imageURLs: List<String>,
    onOpenImage: (List<String>, Int) -> Unit,
    referer: String,
    thumbnailWidth: Dp = 112.dp,
    thumbnailHeight: Dp = 84.dp,
) {
    if (imageURLs.isEmpty()) return
    Row(
        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        imageURLs.forEachIndexed { index, imageURL ->
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(imageURL)
                    .addHeader("Referer", referer)
                    .crossfade(true)
                    .build(),
                contentDescription = "评论图片",
                modifier = Modifier
                    .size(thumbnailWidth, thumbnailHeight)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable { onOpenImage(imageURLs, index) },
                contentScale = ContentScale.Crop,
            )
        }
    }
}

internal fun commentImageGalleryRequest(
    imageURLs: List<String>,
    imageIndex: Int,
    referer: String,
): FocusImageGalleryRequest = FocusImageGalleryRequest(
    images = imageURLs,
    initialIndex = imageIndex,
    referer = referer,
)


private fun formatTimeAgo(ts: Long): String {
    val now = System.currentTimeMillis() / 1000
    val diff = now - ts
    return when {
        diff < 60 -> "刚刚"
        diff < 3600 -> "${diff / 60}分钟前"
        diff < 86400 -> "${diff / 3600}小时前"
        diff < 2592000 -> "${diff / 86400}天前"
        else -> java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault())
            .format(java.util.Date(ts * 1000))
    }
}
