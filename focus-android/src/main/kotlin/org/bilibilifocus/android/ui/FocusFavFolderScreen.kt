package org.bilibilifocus.android.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.FavFolderUiState
import org.bilibilifocus.android.FocusFavFolderViewModel
import org.bilibilifocus.core.model.FavResource

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusFavFolderScreen(
    mediaId: Long,
    folderTitle: String,
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit = {},
    viewModel: FocusFavFolderViewModel,
    gridState: LazyGridState = rememberLazyGridState(),
) {
    LaunchedEffect(viewModel, mediaId) { viewModel.loadIfNeeded(mediaId) }

    val state by viewModel.state.collectAsState()
    val managing by viewModel.isManaging.collectAsState()
    val loadingMore by viewModel.isLoadingMore.collectAsState()
    val targets by viewModel.transferTargets.collectAsState()
    val actionError by viewModel.actionError.collectAsState()
    var pendingRemove by remember { mutableStateOf<FavResource?>(null) }
    var transferring by remember { mutableStateOf<FavResource?>(null) }
    var copying by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(folderTitle.ifEmpty { "收藏夹" }, maxLines = 1, overflow = TextOverflow.Ellipsis) },
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
            FavFolderUiState.Idle, FavFolderUiState.Loading -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is FavFolderUiState.Failed -> {
                Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                    Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            is FavFolderUiState.Loaded -> {
                if (s.items.isEmpty()) {
                    Box(modifier = Modifier.fillMaxSize().padding(innerPadding), contentAlignment = Alignment.Center) {
                        Text("收藏夹是空的", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
                        items(s.items, key = { it.bvid }) { resource ->
                            var menu by remember(resource.bvid) { mutableStateOf(false) }
                            Column {
                            ElevatedCard(
                                onClick = { onOpenVideo("https://www.bilibili.com/video/${resource.bvid}") },
                                shape = RoundedCornerShape(16.dp),
                                colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                            ) {
                                FavResourceCard(resource = resource)
                            }
                            if (resource.aid > 0) Box(Modifier.align(Alignment.End)) {
                                IconButton(enabled = !managing, onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "管理收藏") }
                                DropdownMenu(menu, onDismissRequest = { menu = false }) {
                                    DropdownMenuItem(text = { Text("移动到…") }, onClick = { menu = false; copying = false; transferring = resource; viewModel.loadTransferTargets() })
                                    DropdownMenuItem(text = { Text("复制到…") }, onClick = { menu = false; copying = true; transferring = resource; viewModel.loadTransferTargets() })
                                    DropdownMenuItem(text = { Text("移除收藏", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; pendingRemove = resource })
                                }
                            }
                            }
                        }
                        s.appendError?.let { message -> item(span = { GridItemSpan(maxLineSpan) }) { Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                        if (s.hasMore) item(span = { GridItemSpan(maxLineSpan) }) {
                            TextButton(enabled = !loadingMore && !managing, onClick = viewModel::loadMore) { Text(if (loadingMore) "加载中…" else if (s.appendError != null) "重试" else "加载更多") }
                        }
                    }
                }
            }
        }
    }
    pendingRemove?.let { resource -> AlertDialog(onDismissRequest = { pendingRemove = null }, title = { Text("移除这条收藏？") },
        confirmButton = { TextButton(onClick = { pendingRemove = null; viewModel.remove(resource) }) { Text("移除", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { pendingRemove = null }) { Text("取消") } }) }
    transferring?.let { resource -> ModalBottomSheet(onDismissRequest = { transferring = null }) {
        Column(Modifier.padding(16.dp)) {
            Text(if (copying) "复制到收藏夹" else "移动到收藏夹", style = MaterialTheme.typography.titleLarge)
            if (managing) CircularProgressIndicator(Modifier.padding(16.dp))
            else if (targets.isEmpty()) Text("暂无其他收藏夹", Modifier.padding(vertical = 24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) { items(targets, key = { it.id }) { target ->
                TextButton(onClick = { viewModel.transfer(resource, target.id, copying); transferring = null }, modifier = Modifier.fillMaxWidth()) { Text(target.title) }
            } }
        }
    } }
    actionError?.let { message -> AlertDialog(onDismissRequest = viewModel::dismissActionError, title = { Text("操作失败") }, text = { Text(message) },
        confirmButton = { TextButton(onClick = viewModel::dismissActionError) { Text("知道了") } }) }
}

@Composable
private fun FavResourceCard(resource: FavResource) {
    Column {
        Box(modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(resource.coverURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)),
                contentScale = ContentScale.Crop,
            )
            if (resource.duration.isNotEmpty()) {
                Text(
                    text = resource.duration,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(8.dp),
                )
            }
        }
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                resource.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (resource.upperName.isNotEmpty()) {
                Text(
                    resource.upperName,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
