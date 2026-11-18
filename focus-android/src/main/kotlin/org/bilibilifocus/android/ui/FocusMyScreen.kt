package org.bilibilifocus.android.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.*
import org.bilibilifocus.core.model.FavFolder
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.service.FollowingAuthorsService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusMyScreen(
    viewModel: FocusMyViewModel,
    listState: LazyListState,
    followingService: FollowingAuthorsService,
    onOpenLogin: () -> Unit = {},
    onOpenVideo: (String) -> Unit = {},
    onOpenHistory: () -> Unit = {},
    onOpenFolder: (FavFolder) -> Unit = {},
    onOpenUser: (Long) -> Unit = {},
    onOpenSettings: () -> Unit = {},
    contentPadding: PaddingValues = PaddingValues(),
) {
    LaunchedEffect(viewModel) { viewModel.reload() }
    val state by viewModel.state.collectAsState()
    val managing by viewModel.isManagingFolder.collectAsState()
    val actionError by viewModel.actionError.collectAsState()
    val page = state as? MyUiState.Loaded
    var showsFolders by remember { mutableStateOf(false) }
    var showsFollowing by remember { mutableStateOf(false) }
    var showsEditor by remember { mutableStateOf(false) }
    var editingFolder by remember { mutableStateOf<FavFolder?>(null) }
    var deletingFolder by remember { mutableStateOf<FavFolder?>(null) }
    var title by remember { mutableStateOf("") }
    var isPrivate by remember { mutableStateOf(false) }

    fun gated(action: () -> Unit) { if (state is MyUiState.LoginRequired) onOpenLogin() else action() }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().widthIn(max = 1080.dp),
            contentPadding = PaddingValues(16.dp, 14.dp + contentPadding.calculateTopPadding(), 16.dp, 16.dp + contentPadding.calculateBottomPadding()),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            item {
                PersonalPanel {
                    if (page != null) {
                        MyProfileHeader(page.profile, page.relationLoaded, { onOpenUser(page.profile.mid) }, { showsFollowing = true })
                    } else {
                        val headerAction = if (state is MyUiState.LoginRequired) Modifier.clickable(onClick = onOpenLogin) else if (state is MyUiState.Failed) Modifier.clickable(onClick = viewModel::reload) else Modifier
                        Row(Modifier.fillMaxWidth().then(headerAction), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Icon(Icons.Default.AccountCircle, null, Modifier.size(54.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(if (state is MyUiState.LoginRequired) "登录 B 站" else if (state is MyUiState.Failed) "个人资料暂不可用" else "正在加载个人资料", style = MaterialTheme.typography.titleLarge)
                                Text(if (state is MyUiState.LoginRequired) "同步播放历史与收藏" else "历史、收藏与关注入口仍可使用", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (state is MyUiState.LoginRequired || state is MyUiState.Failed) Icon(Icons.Default.ChevronRight, null)
                        }
                    }
                }
            }
            page?.relationError?.let { message -> item { SectionMessage(message, viewModel::reload) } }
            item {
                PersonalPanel {
                    Row(Modifier.fillMaxWidth()) {
                        QuickAction("历史记录", Icons.Default.History, Modifier.weight(1f)) { gated(onOpenHistory) }
                        QuickAction("我的收藏", Icons.Default.StarBorder, Modifier.weight(1f)) { gated { showsFolders = true } }
                        QuickAction("我的关注", Icons.Default.PeopleOutline, Modifier.weight(1f)) { gated { showsFollowing = true } }
                    }
                }
            }
            if (page != null) {
                page.refreshError?.let { message -> item { SectionMessage(message, viewModel::reload) } }
                if (page.isLoadingHistory && page.history.isEmpty()) item { LinearProgressIndicator(modifier = Modifier.fillMaxWidth()) }
                val continuation = page.history.firstOrNull { it.bvid.isNotEmpty() && it.progress > 0 && it.duration > it.progress + 10 }
                if (continuation != null) item {
                    PersonalPanel {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            SectionHeading("继续观看", "播放历史", onOpenHistory)
                            Row(Modifier.fillMaxWidth().clickable { onOpenVideo(historyItemVideoURL(continuation)) }, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                AsyncImage(model = continuation.coverURL, contentDescription = null, modifier = Modifier.size(128.dp, 72.dp).clip(RoundedCornerShape(10.dp)), contentScale = ContentScale.Crop)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                    Text(continuation.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    Text("已看 ${durationLabel(continuation.progress)} / ${durationLabel(continuation.duration)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    LinearProgressIndicator(progress = { (continuation.progress.toFloat() / continuation.duration).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
                                }
                            }
                        }
                    }
                }
                page.historyError?.let { message -> item { SectionMessage(message, viewModel::reload) } }
                if (page.folders.isNotEmpty()) item {
                    PersonalPanel {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            SectionHeading("我的收藏", "查看全部") { showsFolders = true }
                            page.folders.take(3).forEach { folder -> FolderRow(folder, onClick = { onOpenFolder(folder) }) }
                        }
                    }
                }
                page.foldersError?.let { message -> item { SectionMessage(message, viewModel::reload) } }
                if (page.isLoadingFolders && page.folders.isEmpty()) item { LinearProgressIndicator(modifier = Modifier.fillMaxWidth()) }
            } else {
                when (val current = state) {
                    MyUiState.Idle, MyUiState.Loading -> item { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                    is MyUiState.Failed -> item { SectionMessage(current.message, viewModel::reload) }
                    else -> Unit
                }
            }
            item {
                PersonalPanel {
                    Row(Modifier.fillMaxWidth().clickable(onClick = onOpenSettings), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Tune, null)
                        Text("播放、外观与动态设置", Modifier.weight(1f))
                        Icon(Icons.Default.ChevronRight, null)
                    }
                }
            }
        }
    }

    if (showsFolders) ModalBottomSheet(onDismissRequest = { showsFolders = false }) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
            if (page != null) SectionHeading("我的收藏", "新建") { editingFolder = null; title = ""; isPrivate = false; showsEditor = true }
            else Text("我的收藏", style = MaterialTheme.typography.titleLarge)
            actionError?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            page?.foldersError?.let { SectionMessage(it, viewModel::reload) }
            if (managing) LinearProgressIndicator(Modifier.fillMaxWidth())
            LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false), contentPadding = PaddingValues(bottom = 32.dp)) {
                items(page?.folders.orEmpty(), key = { it.id }) { folder ->
                    var menu by remember(folder.id) { mutableStateOf(false) }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) { FolderRow(folder) { showsFolders = false; onOpenFolder(folder) } }
                        Box {
                            IconButton(onClick = { menu = true }, enabled = !managing) { Icon(Icons.Default.MoreVert, "管理收藏夹") }
                            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text("重命名") }, onClick = { menu = false; editingFolder = folder; title = folder.title; showsEditor = true })
                                DropdownMenuItem(text = { Text("删除收藏夹", color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; deletingFolder = folder })
                            }
                        }
                    }
                }
                if (page != null && page.folders.isEmpty() && !page.isLoadingFolders && page.foldersError == null) item { Text("暂无收藏夹，点击右上角新建", Modifier.padding(vertical = 24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (page?.isLoadingFolders == true) item { CircularProgressIndicator(Modifier.padding(16.dp)) }
                if (page == null) when (val current = state) {
                    MyUiState.Idle, MyUiState.Loading -> item { CircularProgressIndicator(Modifier.padding(16.dp)) }
                    is MyUiState.Failed -> item { SectionMessage(current.message, viewModel::reload) }
                    MyUiState.LoginRequired -> item { TextButton(onClick = onOpenLogin) { Text("登录后管理收藏夹") } }
                    is MyUiState.Loaded -> Unit
                }
            }
        }
    }
    if (showsFollowing) {
        val model = remember(followingService) { FocusFollowingAuthorsViewModel(followingService) }
        DisposableEffect(model) { onDispose { model.onCleared() } }
        LaunchedEffect(model) { model.loadIfNeeded() }
        val following by model.state.collectAsState()
        ModalBottomSheet(onDismissRequest = { showsFollowing = false }) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                Text("我的关注", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(bottom = 16.dp))
                when (val current = following) {
                    FollowingAuthorsUiState.Idle, FollowingAuthorsUiState.Loading -> CircularProgressIndicator()
                    is FollowingAuthorsUiState.Failed -> SectionMessage(current.message, model::reload)
                    is FollowingAuthorsUiState.Loaded -> LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
                        items(current.authors, key = { it.mid }) { author ->
                            ListItem(headlineContent = { Text(author.name) }, modifier = Modifier.clickable { showsFollowing = false; onOpenUser(author.mid) }, leadingContent = {
                                AsyncImage(model = author.avatarURL, contentDescription = null, modifier = Modifier.size(40.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                            })
                        }
                        if (current.authors.isEmpty()) item { Text("暂无关注", Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                }
            }
        }
    }
    if (showsEditor) AlertDialog(
        onDismissRequest = { showsEditor = false }, title = { Text(if (editingFolder == null) "新建收藏夹" else "重命名收藏夹") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(title, { title = it }, label = { Text("收藏夹名称") }, singleLine = true)
                if (editingFolder == null) Row(verticalAlignment = Alignment.CenterVertically) { Text("私密收藏夹", Modifier.weight(1f)); Switch(isPrivate, { isPrivate = it }) }
            }
        },
        confirmButton = { TextButton(enabled = title.isNotBlank() && !managing && page != null, onClick = { viewModel.saveFolder(editingFolder, title, isPrivate); showsEditor = false }) { Text("保存") } },
        dismissButton = { TextButton(onClick = { showsEditor = false }) { Text("取消") } },
    )
    deletingFolder?.let { folder -> AlertDialog(
        onDismissRequest = { deletingFolder = null }, title = { Text("删除收藏夹？") },
        text = { Text("将从 B 站账号删除“${folder.title}”及其中的收藏记录，此操作无法撤销。") },
        confirmButton = { TextButton(onClick = { viewModel.deleteFolder(folder); deletingFolder = null }) { Text("删除", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { deletingFolder = null }) { Text("取消") } },
    ) }
}

@Composable private fun PersonalPanel(content: @Composable () -> Unit) {
    Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) { Box(Modifier.padding(16.dp)) { content() } }
}

@Composable private fun QuickAction(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, action: () -> Unit) {
    Column(modifier.clickable(onClick = action).padding(vertical = 4.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(9.dp)) {
        Icon(icon, null, Modifier.size(25.dp), tint = MaterialTheme.colorScheme.primary)
        Text(title, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable private fun MyProfileHeader(profile: UserProfile, hasRelation: Boolean, onProfile: () -> Unit, onFollowing: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        AsyncImage(model = profile.avatarURL, contentDescription = "个人空间", modifier = Modifier.size(58.dp).clip(CircleShape).clickable(onClick = onProfile), contentScale = ContentScale.Crop)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.clickable(onClick = onProfile), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(profile.name, Modifier.weight(1f, fill = false), style = MaterialTheme.typography.titleLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("LV${profile.level}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("${if (hasRelation) formatProfileCount(profile.following) else "—"} 关注", Modifier.clickable(onClick = onFollowing), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("${if (hasRelation) formatProfileCount(profile.followers) else "—"} 粉丝", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        TextButton(onClick = onProfile) { Text("个人空间", style = MaterialTheme.typography.labelSmall) }
    }
}

@Composable private fun SectionHeading(title: String, action: String, onAction: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleMedium); TextButton(onClick = onAction) { Text(action) } }
}

@Composable private fun SectionMessage(message: String, retry: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text(message, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant); TextButton(onClick = retry) { Text("重试") } }
}

@Composable private fun FolderRow(folder: FavFolder, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Default.Folder, null, tint = MaterialTheme.colorScheme.primary)
        Text(folder.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(folder.mediaCount.toString(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable fun HistoryCard(item: HistoryItem, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(modifier.clickable(onClick = onClick), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        AsyncImage(model = ImageRequest.Builder(LocalContext.current).data(item.coverURL).crossfade(true).build(), contentDescription = null, modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(RoundedCornerShape(10.dp)), contentScale = ContentScale.Crop)
        Text(item.title, style = MaterialTheme.typography.labelLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (item.authorName.isNotEmpty()) Text(item.authorName, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

private fun formatProfileCount(count: Long): String = if (count >= 10_000L) String.format("%.1f万", count / 10_000.0).replace(".0万", "万") else count.toString()
private fun durationLabel(seconds: Long): String = "${seconds / 60}:${(seconds % 60).toString().padStart(2, '0')}"
