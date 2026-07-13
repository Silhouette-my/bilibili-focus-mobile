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
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusHistoryViewModel
import org.bilibilifocus.android.HistoryUiState
import org.bilibilifocus.android.stableKey
import org.bilibilifocus.core.service.HistoryService
import org.bilibilifocus.core.service.KtorHttpClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusHistoryScreen(
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit = {},
    viewModel: FocusHistoryViewModel? = null,
    gridState: LazyGridState = rememberLazyGridState(),
) {
    val resolvedViewModel = viewModel ?: remember {
        FocusHistoryViewModel(
            service = HistoryService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            )
        )
    }

    // A retained history view model may have been loaded before opening a video.
    // Refresh on each screen appearance so the just-reported server position is visible.
    LaunchedEffect(Unit) { resolvedViewModel.reload() }

    val state by resolvedViewModel.state.collectAsState()
    val isLoadingMore by resolvedViewModel.isLoadingMore.collectAsState()

    LaunchedEffect(gridState, state) {
        snapshotFlow<String?> { gridState.layoutInfo.visibleItemsInfo.lastOrNull()?.key as? String }
            .filterNotNull()
            .distinctUntilChanged()
            .collect { key -> resolvedViewModel.loadMoreIfNeeded(key) }
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
                                onClick = { onOpenVideo("https://www.bilibili.com/video/${item.bvid}") },
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
