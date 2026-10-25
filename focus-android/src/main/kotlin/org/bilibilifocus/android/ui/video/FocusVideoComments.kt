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
import androidx.compose.runtime.Composable
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

@Composable
internal fun CommentItem(
    comment: VideoComment,
    onOpenURL: (String) -> Unit,
    onOpenImage: (List<String>, Int) -> Unit = { _, _ -> },
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
            Text("${comment.likeCount}赞", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        FocusRichText(comment.contentRuns, style = contentStyle, onOpenURL = onOpenURL)
        CommentImageStrip(comment.imageURLs, onOpenImage, referer = "https://www.bilibili.com/")

        comment.replies.take(3).forEach { reply ->
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
