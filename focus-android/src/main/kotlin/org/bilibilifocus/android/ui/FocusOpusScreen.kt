package org.bilibilifocus.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.FocusOpusViewModel
import org.bilibilifocus.android.OpusUiState
import org.bilibilifocus.android.images.FocusImageCDNRequest
import org.bilibilifocus.android.ui.video.VideoCommentsSection
import org.bilibilifocus.android.ui.video.commentImageGalleryRequest
import org.bilibilifocus.core.model.OpusBlock
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.model.OpusImage

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusOpusScreen(
    opusId: String,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
    onOpenURL: (String) -> Unit = {},
    viewModel: FocusOpusViewModel,
    listState: LazyListState = rememberLazyListState(),
) {
    LaunchedEffect(viewModel, opusId) {
        viewModel.loadIfNeeded(opusId)
    }

    val state by viewModel.state.collectAsState()
    val comments by viewModel.comments.collectAsState()
    val commentState by viewModel.commentState.collectAsState()
    val commentTotalCount by viewModel.commentTotalCount.collectAsState()
    val actionError by viewModel.actionError.collectAsState()
    var galleryRequest by remember(opusId) { mutableStateOf<FocusImageGalleryRequest?>(null) }
    val opusReferer = "https://www.bilibili.com/opus/$opusId"

    Box(modifier = Modifier.fillMaxSize()) {
        Scaffold(
            topBar = {
                CenterAlignedTopAppBar(
                    title = { Text("图文动态", maxLines = 1) },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        titleContentColor = MaterialTheme.colorScheme.onSurface,
                    ),
                )
            },
        ) { innerPadding ->
            when (val s = state) {
                OpusUiState.Idle, OpusUiState.Loading -> {
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                }

                is OpusUiState.Failed -> {
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(s.message, style = MaterialTheme.typography.bodyMedium)
                            TextButton(onClick = { viewModel.load(opusId) }) { Text("重试") }
                        }
                    }
                }

                OpusUiState.LoginRequired -> {
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                        Text("需要登录才能查看", style = MaterialTheme.typography.bodyMedium)
                    }
                }

                is OpusUiState.Loaded -> {
                    val allImages = s.detail.paragraphs.flatMap { paragraph ->
                        paragraph.blocks.flatMap { block ->
                            (block as? OpusBlock.Image)?.pics.orEmpty()
                        }
                    }
                    val validImages = allImages.filter { it.url.isNotBlank() }
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize().padding(innerPadding),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        item(key = "author-card") {
                            OpusAuthorCard(detail = s.detail, referer = opusReferer, onOpenUser = onOpenUser)
                        }

                        s.detail.paragraphs.forEachIndexed { index, para ->
                            item(key = "para-$index") {
                                ElevatedCard(
                                    shape = RoundedCornerShape(18.dp),
                                    colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                    elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                ) {
                                    OpusParagraphView(
                                        paragraph = para,
                                        referer = opusReferer,
                                        modifier = Modifier.padding(16.dp),
                                        onOpenImage = { selected ->
                                            val imgIndex = validImages.indexOfFirst { it.url == selected.url }.coerceAtLeast(0)
                                            galleryRequest = FocusImageGalleryRequest(
                                                images = validImages.map { it.url },
                                                initialIndex = imgIndex,
                                                referer = opusReferer,
                                            )
                                        },
                                        onOpenURL = onOpenURL,
                                    )
                                }
                            }
                        }

                        item(key = "comments-section") {
                            ElevatedCard(
                                shape = RoundedCornerShape(18.dp),
                                colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                            ) {
                                Box(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                                    VideoCommentsSection(
                                        comments = comments,
                                        state = commentState,
                                        onOpenURL = onOpenURL,
                                        onOpenImage = { images, index ->
                                            galleryRequest = commentImageGalleryRequest(images, index, opusReferer)
                                        },
                                        onToggleLike = viewModel::toggleCommentLike,
                                        onDelete = viewModel::deleteComment,
                                        onLoadReplies = viewModel::loadReplies,
                                        onLoadComments = viewModel::loadComments,
                                        onSendComment = { message, root, parent, onSent ->
                                            viewModel.sendComment(message, root, parent, onSent)
                                        },
                                        totalCount = commentTotalCount,
                                        referer = opusReferer,
                                    )
                                }
                            }
                        }

                        item { Spacer(modifier = Modifier.height(32.dp)) }
                    }
                }
            }
        }
        galleryRequest?.let { request ->
            FocusImageGallery(request = request, onDismiss = { galleryRequest = null })
        }
        actionError?.let { message ->
            AlertDialog(
                onDismissRequest = viewModel::dismissActionError,
                title = { Text("操作未完成") },
                text = { Text(message) },
                confirmButton = {
                    TextButton(onClick = viewModel::dismissActionError) { Text("知道了") }
                },
            )
        }
    }
}

@Composable
private fun OpusAuthorCard(detail: OpusDetail, referer: String, onOpenUser: (Long) -> Unit) {
    ElevatedCard(
        onClick = { if (detail.author.mid > 0) onOpenUser(detail.author.mid) },
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(FocusImageCDNRequest.canonicalURL(detail.author.avatarURL))
                    .addHeader("Referer", referer)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentScale = ContentScale.Crop,
            )
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(detail.author.name, style = MaterialTheme.typography.titleSmall)
                if (detail.publishTime.isNotBlank()) {
                    Text(
                        detail.publishTime,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun OpusParagraphView(
    paragraph: OpusDetail.Paragraph,
    referer: String,
    modifier: Modifier = Modifier,
    onOpenImage: (OpusImage) -> Unit = {},
    onOpenURL: (String) -> Unit = {},
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        paragraph.blocks.forEach { block ->
            when (block) {
                is OpusBlock.Text -> FocusRichText(runs = block.nodes, onOpenURL = onOpenURL)
                is OpusBlock.Image -> OpusImageGrid(images = block.pics, referer = referer, onOpenImage = onOpenImage)
                is OpusBlock.Code -> OpusCodeBlock(lang = block.lang, content = block.content)
            }
        }
    }
}

@Composable
private fun OpusImageGrid(images: List<OpusImage>, referer: String, onOpenImage: (OpusImage) -> Unit) {
    if (images.size == 1) {
        val image = images.first()
        val ratio = normalizedImageRatio(image)
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(FocusImageCDNRequest.canonicalURL(image.url))
                .addHeader("Referer", referer)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onOpenImage(image) }
                .clip(RoundedCornerShape(12.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .border(
                    width = 0.5.dp,
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
                    shape = RoundedCornerShape(12.dp),
                )
                .height(singleImageHeightForRatio(ratio)),
            contentScale = ContentScale.Fit,
        )
        return
    }

    val columnCount = 2
    val rows = images.chunked(columnCount)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { rowImages ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                rowImages.forEach { image ->
                    AsyncImage(
                        model = ImageRequest.Builder(LocalContext.current)
                            .data(FocusImageCDNRequest.canonicalURL(image.url))
                            .addHeader("Referer", referer)
                            .crossfade(true)
                            .build(),
                        contentDescription = null,
                        modifier = Modifier
                            .weight(1f)
                            .clickable { onOpenImage(image) }
                            .height(160.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .border(
                                width = 0.5.dp,
                                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f),
                                shape = RoundedCornerShape(12.dp),
                            ),
                        contentScale = ContentScale.Crop,
                    )
                }
                repeat(columnCount - rowImages.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun OpusCodeBlock(lang: String, content: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
    ) {
        Text(
            text = content,
            style = MaterialTheme.typography.bodySmall.copy(fontStyle = FontStyle.Italic),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun normalizedImageRatio(image: OpusImage): Float {
    val width = image.width.takeIf { it > 0 } ?: return 1f
    val height = image.height.takeIf { it > 0 } ?: return 1f
    return (width.toFloat() / height.toFloat()).coerceIn(0.75f, 1.8f)
}

private fun singleImageHeightForRatio(ratio: Float): Dp = when {
    ratio >= 1.45f -> 220.dp
    ratio >= 1.1f -> 260.dp
    ratio >= 0.9f -> 320.dp
    else -> 420.dp
}
