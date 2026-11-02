package org.bilibilifocus.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.Close
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import org.bilibilifocus.android.FocusHistoryViewModel
import org.bilibilifocus.android.HistoryUiState
import org.bilibilifocus.android.stableKey

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusHistoryScreen(
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit = {},
    viewModel: FocusHistoryViewModel,
    gridState: LazyGridState = rememberLazyGridState(),
) {
    // A retained history view model may have been loaded before opening a video.
    // Refresh on each screen appearance so the just-reported server position is visible.
    LaunchedEffect(viewModel) { viewModel.reload() }

    val state by viewModel.state.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    val isMutating by viewModel.isMutating.collectAsState()
    val actionError by viewModel.actionError.collectAsState()
    val query by viewModel.query.collectAsState()
    var pendingDelete by remember { mutableStateOf<org.bilibilifocus.core.model.HistoryItem?>(null) }
    var confirmsClear by remember { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current

    LaunchedEffect(gridState, state) {
        snapshotFlow<String?> { gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.key as? String }
            .filterNotNull()
            .distinctUntilChanged()
            .collect { key -> viewModel.loadMoreIfNeeded(key) }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("播放历史") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = { TextButton(enabled = !isMutating && state is HistoryUiState.Loaded && viewModel.canManageHistory, onClick = { confirmsClear = true }) { Text("清空") } },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
    ) { innerPadding ->
        Column(Modifier.fillMaxSize().padding(innerPadding)) {
        OutlinedTextField(
            value = query, onValueChange = viewModel::setQuery,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            label = { Text("搜索播放历史") }, singleLine = true, enabled = !isMutating,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { viewModel.submitSearch(); keyboard?.hide() }),
            trailingIcon = {
                androidx.compose.foundation.layout.Row {
                    if (query.isNotEmpty()) IconButton(enabled = !isMutating, onClick = { viewModel.setQuery("") }) { Icon(Icons.Default.Close, "清空关键词") }
                    TextButton(enabled = !isMutating, onClick = { viewModel.submitSearch(); keyboard?.hide() }) { Text("搜索") }
                }
            },
        )
        when (val s = state) {
            HistoryUiState.Idle, HistoryUiState.Loading -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is HistoryUiState.Failed -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        TextButton(onClick = viewModel::reload) { Text("重试") }
                    }
                }
            }

            is HistoryUiState.Loaded -> {
                if (s.items.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(if (viewModel.isSearchingHistory) "未找到相关历史，换个关键词试试" else "暂无播放历史", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    LazyVerticalGrid(
                        state = gridState,
                        columns = GridCells.Adaptive(minSize = 156.dp),
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        items(s.items, key = { it.stableKey }) { item ->
                            Column {
                                HistoryCard(item = item, onClick = { onOpenVideo(historyItemVideoURL(item)) })
                                if (item.historyKey.isNotEmpty() && viewModel.canManageHistory) TextButton(enabled = !isMutating, onClick = { pendingDelete = item }) { Icon(Icons.Default.DeleteOutline, null); Text("删除记录") }
                            }
                        }

                        if (isLoadingMore) {
                            item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 12.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                                }
                            }
                        }
                        s.appendError?.let { message -> item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) { Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                        if (s.hasMore) item(span = { androidx.compose.foundation.lazy.grid.GridItemSpan(maxLineSpan) }) {
                            TextButton(enabled = !isLoadingMore && !isMutating, onClick = viewModel::loadMore) { Text(if (s.appendError == null) "加载更多记录" else "重试") }
                        }
                    }
                }
            }
        }
        }
    }
    if (confirmsClear) AlertDialog(onDismissRequest = { confirmsClear = false }, title = { Text("清空全部播放历史？") },
        text = { Text("将删除 B 站账号全部播放历史，不仅是当前搜索结果，无法撤销。") },
        confirmButton = { TextButton(onClick = { confirmsClear = false; viewModel.clear() }) { Text("清空全部", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmsClear = false }) { Text("取消") } })
    pendingDelete?.let { item -> AlertDialog(onDismissRequest = { pendingDelete = null }, title = { Text("删除这条播放历史？") },
        confirmButton = { TextButton(onClick = { pendingDelete = null; viewModel.delete(item) }) { Text("删除", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text("取消") } }) }
    actionError?.let { message -> AlertDialog(onDismissRequest = viewModel::dismissActionError, title = { Text("操作失败") }, text = { Text(message) },
        confirmButton = { TextButton(onClick = viewModel::dismissActionError) { Text("知道了") } }) }
}

internal fun historyItemVideoURL(item: org.bilibilifocus.core.model.HistoryItem): String = buildString {
    append("https://www.bilibili.com/video/${item.bvid}/")
    val partParameter = when {
        item.cid > 0 -> "cid=${item.cid}"
        item.page > 0 -> "p=${item.page}"
        else -> null
    }
    val historyPositionMillis = when {
        partParameter == null -> null
        item.progress == -1L -> 0L
        item.progress in 1..(Long.MAX_VALUE / 1_000) -> item.progress * 1_000
        else -> null
    }
    val parameters = listOfNotNull(
        partParameter,
        historyPositionMillis?.let { "focus_history_position_ms=$it" },
    )
    if (parameters.isNotEmpty()) append("?${parameters.joinToString("&")}")
}
