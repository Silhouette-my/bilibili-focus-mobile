package org.bilibilifocus.android.ui

import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        },
    ) { innerPadding ->
        when (val s = state) {
            HistoryUiState.Idle, HistoryUiState.Loading -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is HistoryUiState.Failed -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            is HistoryUiState.Loaded -> {
                if (s.items.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                        Text("暂无播放历史", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                } else {
                    LazyVerticalGrid(
                        state = gridState,
                        columns = GridCells.Adaptive(minSize = 156.dp),
                        modifier = Modifier.fillMaxSize().padding(innerPadding),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        items(s.items, key = { it.stableKey }) { item ->
                            HistoryCard(
                                item = item,
                                onClick = { onOpenVideo(historyItemVideoURL(item)) },
                            )
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
                    }
                }
            }
        }
    }
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
