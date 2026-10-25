package org.bilibilifocus.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.FocusWatchLaterViewModel
import org.bilibilifocus.android.WatchLaterMutationPolicy
import org.bilibilifocus.android.WatchLaterPendingAction
import org.bilibilifocus.android.WatchLaterUiState
import org.bilibilifocus.core.model.WatchLaterItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusWatchLaterScreen(
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit,
    onOpenLogin: () -> Unit,
    viewModel: FocusWatchLaterViewModel,
    gridState: LazyGridState = rememberLazyGridState(),
) {
    LaunchedEffect(viewModel) { viewModel.loadIfNeeded() }

    val state by viewModel.state.collectAsState()
    val loaded = state as? WatchLaterUiState.Loaded
    val pendingAction = loaded?.pendingAction
    val snackbarHostState = remember { SnackbarHostState() }
    var showClearConfirmation by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(loaded?.errorMessage) {
        loaded?.errorMessage?.let { message ->
            snackbarHostState.showSnackbar(message)
            viewModel.clearError()
        }
    }

    if (showClearConfirmation) {
        AlertDialog(
            onDismissRequest = { showClearConfirmation = false },
            title = { Text("清空稍后再看？") },
            text = { Text("列表中的全部视频都会被移除，此操作无法在应用内撤销。") },
            confirmButton = {
                Button(
                    onClick = {
                        showClearConfirmation = false
                        viewModel.clear()
                    },
                ) {
                    Text("确认清空")
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearConfirmation = false }) {
                    Text("取消")
                }
            },
        )
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            Column {
                CenterAlignedTopAppBar(
                    title = {
                        Text(
                            text = loaded?.let { "稍后再看 · ${it.totalCount}" } ?: "稍后再看",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                        }
                    },
                    actions = {
                        if (loaded != null && loaded.items.isNotEmpty()) {
                            TextButton(
                                enabled = pendingAction == null,
                                onClick = viewModel::deleteViewed,
                            ) {
                                Text("删除已看")
                            }
                            TextButton(
                                enabled = pendingAction == null,
                                onClick = {
                                    if (WatchLaterMutationPolicy.requiresConfirmation(
                                            WatchLaterPendingAction.Clear,
                                        )
                                    ) {
                                        showClearConfirmation = true
                                    } else {
                                        viewModel.clear()
                                    }
                                },
                            ) {
                                Text("清空")
                            }
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        titleContentColor = MaterialTheme.colorScheme.onSurface,
                    ),
                )
                if (pendingAction != null) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                }
            }
        },
    ) { innerPadding ->
        when (val current = state) {
            WatchLaterUiState.Idle,
            WatchLaterUiState.Loading,
            -> LoadingWatchLaterContent(innerPadding)

            WatchLaterUiState.LoginRequired -> {
                WatchLaterMessageContent(
                    contentPadding = innerPadding,
                    title = "登录已失效",
                    message = "重新登录后即可管理稍后再看。",
                    actionLabel = "去登录",
                    onAction = onOpenLogin,
                )
            }

            is WatchLaterUiState.Failed -> {
                WatchLaterMessageContent(
                    contentPadding = innerPadding,
                    title = "加载失败",
                    message = current.message,
                    actionLabel = "重试",
                    onAction = viewModel::reload,
                )
            }

            is WatchLaterUiState.Loaded -> {
                if (current.items.isEmpty()) {
                    WatchLaterMessageContent(
                        contentPadding = innerPadding,
                        title = "列表是空的",
                        message = "在视频页添加的内容会出现在这里。",
                    )
                } else {
                    LazyVerticalGrid(
                        state = gridState,
                        columns = GridCells.Adaptive(minSize = 168.dp),
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        items(current.items, key = { it.aid }) { item ->
                            FocusWatchLaterCard(
                                item = item,
                                onClick = {
                                    item.targetURL.takeIf(String::isNotEmpty)?.let(onOpenVideo)
                                },
                                onRemove = { viewModel.remove(item.aid) },
                                removeEnabled = current.pendingAction == null,
                                removing = current.pendingAction ==
                                    WatchLaterPendingAction.Remove(item.aid),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun WatchLaterPreviewGrid(
    items: List<WatchLaterItem>,
    columns: Int,
    onOpenVideo: (WatchLaterItem) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        items.chunked(columns.coerceAtLeast(1)).forEach { rowItems ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                rowItems.forEach { item ->
                    FocusWatchLaterCard(
                        item = item,
                        modifier = Modifier.weight(1f),
                        onClick = { onOpenVideo(item) },
                    )
                }
                repeat(columns.coerceAtLeast(1) - rowItems.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
internal fun FocusWatchLaterCard(
    item: WatchLaterItem,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
    onRemove: (() -> Unit)? = null,
    removeEnabled: Boolean = true,
    removing: Boolean = false,
) {
    ElevatedCard(
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.clickable(enabled = !removing, onClick = onClick),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f),
            ) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(item.coverURL)
                        .crossfade(true)
                        .build(),
                    contentDescription = item.title,
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)),
                    contentScale = ContentScale.Crop,
                )
                Text(
                    text = watchLaterProgressText(item),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(8.dp)
                        .background(
                            color = Color.Black.copy(alpha = 0.72f),
                            shape = RoundedCornerShape(5.dp),
                        )
                        .padding(horizontal = 6.dp, vertical = 3.dp),
                )
            }

            Column(
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.labelLarge,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (item.author.name.isNotEmpty()) {
                    Text(
                        text = item.author.name,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (item.viewCount > 0) {
                        Text(
                            text = "${formatWatchLaterCount(item.viewCount)} 播放",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(modifier = Modifier.weight(1f))
                    if (onRemove != null) {
                        if (removing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            TextButton(
                                enabled = removeEnabled,
                                onClick = onRemove,
                                contentPadding = PaddingValues(horizontal = 6.dp),
                            ) {
                                Text("移除")
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingWatchLaterContent(contentPadding: PaddingValues) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun WatchLaterMessageContent(
    contentPadding: PaddingValues,
    title: String,
    message: String,
    actionLabel: String? = null,
    onAction: () -> Unit = {},
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(contentPadding)
            .padding(32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, style = MaterialTheme.typography.headlineSmall)
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (actionLabel != null) {
                Button(onClick = onAction) {
                    Text(actionLabel)
                }
            }
        }
    }
}

internal fun watchLaterProgressText(item: WatchLaterItem): String = when {
    WatchLaterMutationPolicy.isViewed(item) -> "已看完"
    item.progressSeconds > 0 && item.durationSeconds > 0 ->
        "${formatWatchLaterDuration(item.progressSeconds)} / " +
            formatWatchLaterDuration(item.durationSeconds)
    item.durationSeconds > 0 -> formatWatchLaterDuration(item.durationSeconds)
    else -> "稍后再看"
}

private fun formatWatchLaterDuration(totalSeconds: Long): String {
    val total = totalSeconds.coerceAtLeast(0)
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val seconds = total % 60
    return if (hours > 0) {
        "$hours:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
    } else {
        "$minutes:${seconds.toString().padStart(2, '0')}"
    }
}

private fun formatWatchLaterCount(count: Long): String = when {
    count >= 100_000_000L -> "${count / 100_000_000L}亿"
    count >= 10_000L -> {
        val value = count / 10_000.0
        if (value >= 10) "${value.toLong()}万" else "%.1f万".format(value)
    }
    else -> count.toString()
}
