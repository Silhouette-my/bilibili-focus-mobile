package org.bilibilifocus.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TextButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.FocusMyViewModel
import org.bilibilifocus.android.FocusWatchLaterViewModel
import org.bilibilifocus.android.MyUiState
import org.bilibilifocus.android.WatchLaterUiState
import org.bilibilifocus.core.model.FavFolder
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.model.UserProfile

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusMyScreen(
    viewModel: FocusMyViewModel,
    watchLaterViewModel: FocusWatchLaterViewModel,
    listState: LazyListState,
    onOpenLogin: () -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
    onOpenWatchLater: () -> Unit = {},
    onOpenHistory: () -> Unit = {},
    onOpenFolder: (FavFolder) -> Unit = {},
    contentPadding: PaddingValues = PaddingValues(),
) {
    LaunchedEffect(Unit) { viewModel.loadIfNeeded() }

    val state by viewModel.state.collectAsState()
    val watchLaterState by watchLaterViewModel.state.collectAsState()

    when (val s = state) {
        MyUiState.Idle, MyUiState.Loading -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }
        }

        MyUiState.LoginRequired -> {
            Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("需要登录", style = MaterialTheme.typography.headlineSmall)
                    Text(
                        "登录后即可查看稍后再看、播放历史和收藏夹",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = onOpenLogin) { Text("去登录") }
                    Button(
                        onClick = { viewModel.reload() },
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.secondaryContainer,
                            contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                        ),
                    ) { Text("重新检测登录态") }
                }
            }
        }

        is MyUiState.Failed -> {
            Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("加载失败", style = MaterialTheme.typography.headlineSmall)
                    Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = { viewModel.reload() }) { Text("重试") }
                }
            }
        }

        is MyUiState.Loaded -> {
            LaunchedEffect(s.profile.mid) {
                watchLaterViewModel.reload()
            }
            val historyVideos = s.history.filter { it.bvid.isNotEmpty() }
            val watchLaterItems = (watchLaterState as? WatchLaterUiState.Loaded)
                ?.items
                .orEmpty()
                .filter { it.targetURL.isNotEmpty() }
            BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
                val previewColumns = when {
                    maxWidth >= 1160.dp -> 5
                    maxWidth >= 920.dp -> 4
                    maxWidth >= 720.dp -> 3
                    else -> 2
                }
                val previewCapacity = if (maxWidth >= 920.dp) {
                    previewColumns * 2
                } else {
                    previewColumns
                }
                val previewItems = historyVideos.take(
                    previewCapacity
                )
                val watchLaterPreviewItems = watchLaterItems.take(previewCapacity)

                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier
                            .fillMaxWidth()
                            .widthIn(max = 1080.dp),
                        contentPadding = PaddingValues(
                            start = 16.dp,
                            end = 16.dp,
                            top = 12.dp + contentPadding.calculateTopPadding(),
                            bottom = 12.dp + contentPadding.calculateBottomPadding(),
                        ),
                        verticalArrangement = Arrangement.spacedBy(20.dp),
                    ) {
                        item { MyProfileHeader(profile = s.profile) }

                        item {
                            SectionHeader(
                                title = "稍后再看",
                                actionLabel = "查看全部",
                                onAction = onOpenWatchLater,
                            )
                        }
                        item {
                            when (val current = watchLaterState) {
                                WatchLaterUiState.Idle,
                                WatchLaterUiState.Loading,
                                -> Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 16.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator(
                                        color = MaterialTheme.colorScheme.primary,
                                    )
                                }

                                WatchLaterUiState.LoginRequired -> {
                                    CompactSectionMessage(
                                        message = "登录状态已失效",
                                        actionLabel = "重新检测",
                                        onAction = watchLaterViewModel::reload,
                                    )
                                }

                                is WatchLaterUiState.Failed -> {
                                    CompactSectionMessage(
                                        message = current.message,
                                        actionLabel = "重试",
                                        onAction = watchLaterViewModel::reload,
                                    )
                                }

                                is WatchLaterUiState.Loaded -> {
                                    if (watchLaterPreviewItems.isEmpty()) {
                                        CompactSectionMessage(message = "暂无稍后再看")
                                    } else {
                                        WatchLaterPreviewGrid(
                                            items = watchLaterPreviewItems,
                                            columns = previewColumns,
                                            onOpenVideo = { item ->
                                                item.targetURL
                                                    .takeIf(String::isNotEmpty)
                                                    ?.let(onOpenVideo)
                                            },
                                        )
                                    }
                                }
                            }
                        }

                        if (historyVideos.isNotEmpty()) {
                            item {
                                SectionHeader(
                                    title = "播放历史",
                                    actionLabel = "查看更多",
                                    onAction = onOpenHistory,
                                )
                            }
                            item {
                                HistoryPreviewGrid(
                                    items = previewItems,
                                    columns = previewColumns,
                                    onOpenVideo = { item ->
                                        onOpenVideo("https://www.bilibili.com/video/${item.bvid}")
                                    },
                                )
                            }
                        }

                        if (s.folders.isNotEmpty()) {
                            item { SectionTitle("收藏夹") }
                            items(s.folders, key = { folder -> "f-${folder.id}" }) { folder ->
                                FolderRow(
                                    folder = folder,
                                    onClick = { onOpenFolder(folder) },
                                )
                            }
                        }

                        if (historyVideos.isEmpty() && s.folders.isEmpty()) {
                            item {
                                Box(modifier = Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                                    Text(
                                        "暂无历史和收藏",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MyProfileHeader(profile: UserProfile) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(profile.avatarURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier.size(80.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
        Text(profile.name, style = MaterialTheme.typography.headlineSmall)
        if (profile.sign.isNotEmpty()) {
            Text(
                profile.sign,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
            StatLabel(value = formatProfileCount(profile.following), label = "关注")
            StatLabel(value = formatProfileCount(profile.followers), label = "粉丝")
            StatLabel(value = "LV${profile.level}", label = "等级")
        }
    }
}

@Composable
private fun StatLabel(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
    )
}

@Composable
private fun SectionHeader(
    title: String,
    actionLabel: String,
    onAction: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
        )
        Spacer(modifier = Modifier.weight(1f))
        TextButton(onClick = onAction) {
            Text(actionLabel)
        }
    }
}

@Composable
private fun CompactSectionMessage(
    message: String,
    actionLabel: String? = null,
    onAction: () -> Unit = {},
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.weight(1f))
        if (actionLabel != null) {
            TextButton(onClick = onAction) {
                Text(actionLabel)
            }
        }
    }
}

@Composable
private fun HistoryPreviewGrid(
    items: List<HistoryItem>,
    columns: Int,
    onOpenVideo: (HistoryItem) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        items.chunked(columns).forEach { rowItems ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                rowItems.forEach { item ->
                    HistoryCard(
                        item = item,
                        modifier = Modifier.weight(1f),
                        onClick = { onOpenVideo(item) },
                    )
                }
                repeat(columns - rowItems.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
fun HistoryCard(
    item: HistoryItem,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier = modifier.clickable { onClick() },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(item.coverURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(10.dp)),
            contentScale = ContentScale.Crop,
        )
        Text(
            item.title,
            style = MaterialTheme.typography.labelLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        if (item.authorName.isNotEmpty()) {
            Text(
                item.authorName,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun FolderRow(folder: FavFolder, onClick: () -> Unit, modifier: Modifier = Modifier) {
    ElevatedCard(
        onClick = onClick,
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (folder.coverURL.isNotEmpty()) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(folder.coverURL)
                        .crossfade(true)
                        .build(),
                    contentDescription = null,
                    modifier = Modifier.size(64.dp, 48.dp).clip(RoundedCornerShape(8.dp)),
                    contentScale = ContentScale.Crop,
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    folder.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "${folder.mediaCount} 个内容",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun formatProfileCount(count: Long): String = when {
    count >= 10000L -> {
        val v = count / 1000 / 10.0
        if (v >= 10) "${v.toLong()}万" else "%.1f万".format(v)
    }
    else -> count.toString()
}
