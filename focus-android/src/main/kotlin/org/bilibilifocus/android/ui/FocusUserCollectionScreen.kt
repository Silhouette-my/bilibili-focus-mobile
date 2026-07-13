package org.bilibilifocus.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
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
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusUserCollectionViewModel
import org.bilibilifocus.android.UserCollectionUiState
import org.bilibilifocus.core.model.UserContentCollection
import org.bilibilifocus.core.model.UserVideo
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.UserService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusUserCollectionScreen(
    collection: UserContentCollection,
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit,
    viewModel: FocusUserCollectionViewModel? = null,
    gridState: LazyGridState = rememberLazyGridState(),
) {
    val resolvedViewModel = viewModel ?: remember(collection.id) {
        FocusUserCollectionViewModel(
            UserService(AndroidCookieProvider(), KtorHttpClient()),
        )
    }
    LaunchedEffect(collection.id) { resolvedViewModel.loadIfNeeded(collection) }

    val state by resolvedViewModel.state.collectAsState()
    val isLoadingMore by resolvedViewModel.isLoadingMore.collectAsState()

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(collection.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
        when (val current = state) {
            UserCollectionUiState.Idle, UserCollectionUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is UserCollectionUiState.Failed -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding).padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Text("合集加载失败", style = MaterialTheme.typography.headlineSmall)
                        Text(
                            current.message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        Button(onClick = { resolvedViewModel.load(collection) }) { Text("重试") }
                    }
                }
            }

            is UserCollectionUiState.Loaded -> {
                LazyVerticalGrid(
                    state = gridState,
                    columns = GridCells.Adaptive(minSize = 156.dp),
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item(span = { GridItemSpan(maxLineSpan) }) {
                        CollectionHero(collection = collection)
                    }

                    items(current.page.videos, key = { it.bvid }) { video ->
                        LaunchedEffect(video.bvid) {
                            resolvedViewModel.loadMoreIfNeeded(video.bvid)
                        }
                        ElevatedCard(
                            onClick = { onOpenVideo("https://www.bilibili.com/video/${video.bvid}") },
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                            elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                        ) {
                            CollectionVideoCard(video)
                        }
                    }

                    if (current.page.videos.isEmpty()) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Box(
                                modifier = Modifier.fillMaxWidth().padding(32.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    "这个合集暂时没有可展示的视频",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }

                    if (isLoadingMore) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Box(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CollectionHero(collection: UserContentCollection) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(collection.coverURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.size(112.dp, 82.dp).clip(RoundedCornerShape(16.dp)),
                contentScale = ContentScale.Crop,
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(
                    collection.title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "${collection.kind.title} · ${collection.itemCount} 个视频",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (collection.description.isNotEmpty()) {
                    Text(
                        collection.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun CollectionVideoCard(video: UserVideo) {
    Column {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(video.coverURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f),
            contentScale = ContentScale.Crop,
        )
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                video.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                if (video.playCount > 0) "${compactCount(video.playCount)}播放" else " ",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
    }
}

private fun compactCount(value: Long): String = when {
    value >= 100_000_000L -> "${value / 100_000_000L}亿"
    value >= 10_000L -> {
        val whole = value / 10_000L
        val decimal = (value % 10_000L) * 10 / 10_000L
        if (decimal == 0L) "${whole}万" else "$whole.${decimal}万"
    }
    else -> value.toString()
}
