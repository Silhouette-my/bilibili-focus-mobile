package org.bilibilifocus.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.bilibilifocus.android.FocusUserViewModel
import org.bilibilifocus.android.UserContentSection
import org.bilibilifocus.android.UserUiState
import org.bilibilifocus.core.model.UserArticle
import org.bilibilifocus.core.model.UserContentCollection
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.model.UserVideo

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusUserScreen(
    userId: Long,
    onBack: () -> Unit,
    onOpenVideo: (String) -> Unit = {},
    onOpenCollection: (UserContentCollection) -> Unit = {},
    onOpenArticle: (String) -> Unit = {},
    viewModel: FocusUserViewModel,
    gridState: LazyGridState = rememberLazyGridState(),
) {
    LaunchedEffect(viewModel, userId) { viewModel.loadIfNeeded(userId) }

    val state by viewModel.state.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    var selectedSection by remember(userId) { mutableStateOf(viewModel.selectedSection) }
    var isRefreshing by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    val name = (state as? UserUiState.Loaded)?.profile?.name ?: "UP主空间"
                    Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                },
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
            UserUiState.Idle, UserUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is UserUiState.Failed -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding).padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Text("UP 主空间加载失败", style = MaterialTheme.typography.headlineSmall)
                        Text(
                            current.message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        Button(onClick = { viewModel.load(userId) }) { Text("重试") }
                    }
                }
            }

            is UserUiState.Loaded -> {
                val sections = buildList {
                    if (current.videos.isNotEmpty()) add(UserContentSection.VIDEOS)
                    if (current.collections.isNotEmpty()) add(UserContentSection.COLLECTIONS)
                    if (current.articles.isNotEmpty()) add(UserContentSection.ARTICLES)
                }
                val activeSection = selectedSection.takeIf { it in sections } ?: sections.firstOrNull()
                LaunchedEffect(sections) {
                    if (activeSection != null && selectedSection != activeSection) {
                        selectedSection = activeSection
                        viewModel.selectSection(activeSection)
                    }
                }

                PullToRefreshBox(
                    isRefreshing = isRefreshing,
                    onRefresh = {
                        isRefreshing = true
                        viewModel.load(userId) { isRefreshing = false }
                    },
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                ) {
                    LazyVerticalGrid(
                        state = gridState,
                        columns = GridCells.Adaptive(minSize = 156.dp),
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            UserProfileHeader(profile = current.profile)
                        }

                        if (sections.isNotEmpty()) {
                            item(span = { GridItemSpan(maxLineSpan) }) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(
                                        "内容",
                                        style = MaterialTheme.typography.titleMedium,
                                        fontWeight = FontWeight.SemiBold,
                                        modifier = Modifier.padding(horizontal = 2.dp),
                                    )
                                    UserSectionPicker(
                                        sections = sections,
                                        selected = activeSection ?: sections.first(),
                                        onSelect = { section ->
                                            selectedSection = section
                                            viewModel.selectSection(section)
                                        },
                                    )
                                }
                            }
                        }

                        when (activeSection) {
                            UserContentSection.VIDEOS -> {
                                items(current.videos, key = { "video-${it.bvid}" }) { video ->
                                    LaunchedEffect(video.bvid) {
                                        viewModel.loadMoreIfNeeded(video.bvid)
                                    }
                                    ElevatedCard(
                                        onClick = { onOpenVideo("https://www.bilibili.com/video/${video.bvid}") },
                                        shape = RoundedCornerShape(16.dp),
                                        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                    ) {
                                        UserVideoCard(video = video)
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

                            UserContentSection.COLLECTIONS -> {
                                items(
                                    current.collections,
                                    key = { "collection-${it.id}" },
                                    span = { GridItemSpan(maxLineSpan) },
                                ) { collection ->
                                    UserCollectionCard(collection = collection, onClick = { onOpenCollection(collection) })
                                }
                            }

                            UserContentSection.ARTICLES -> {
                                items(
                                    current.articles,
                                    key = { "article-${it.id}" },
                                    span = { GridItemSpan(maxLineSpan) },
                                ) { article ->
                                    UserArticleCard(article = article, onClick = { onOpenArticle(article.targetURL) })
                                }
                            }

                            null -> {
                                item(span = { GridItemSpan(maxLineSpan) }) {
                                    Box(
                                        modifier = Modifier.fillMaxWidth().padding(32.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Text(
                                            "这个 UP 主暂时没有可展示的公开内容",
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            textAlign = TextAlign.Center,
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
}

@Composable
private fun UserSectionPicker(
    sections: List<UserContentSection>,
    selected: UserContentSection,
    onSelect: (UserContentSection) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        sections.forEach { section ->
            FilterChip(
                selected = section == selected,
                onClick = { onSelect(section) },
                label = {
                    Text(
                        section.title,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center,
                    )
                },
                modifier = Modifier.weight(1f).heightIn(min = 44.dp),
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primary,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
                ),
                shape = RoundedCornerShape(14.dp),
            )
        }
    }
}

@Composable
private fun UserProfileHeader(profile: UserProfile) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(profile.avatarURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.size(82.dp).clip(CircleShape),
                contentScale = ContentScale.Crop,
            )
            Text(
                profile.name,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            )
            Text(
                "LV${profile.level}",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.SemiBold,
            )
            if (profile.sign.isNotEmpty()) {
                Text(
                    profile.sign,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ProfileStat(formatProfileCount(profile.following), "关注", Modifier.weight(1f))
                ProfileStat(formatProfileCount(profile.followers), "粉丝", Modifier.weight(1f))
                ProfileStat(profile.videoCount.toString(), "视频", Modifier.weight(1f))
                ProfileStat(profile.articleCount.toString(), "专栏", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ProfileStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            value,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun UserVideoCard(video: UserVideo) {
    Column {
        Box(modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f)) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(video.coverURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
            if (video.duration.isNotEmpty()) {
                Text(
                    text = video.duration,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(7.dp)
                        .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(5.dp))
                        .padding(horizontal = 5.dp, vertical = 2.dp),
                )
            }
        }
        Column(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 9.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                video.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "${formatCount(video.playCount)}播放${formatDate(video.created)?.let { " · $it" }.orEmpty()}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun UserCollectionCard(collection: UserContentCollection, onClick: () -> Unit) {
    ElevatedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(collection.coverURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier.size(82.dp).clip(RoundedCornerShape(14.dp)),
                contentScale = ContentScale.Crop,
            )
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    collection.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    "${collection.kind.title} · ${collection.itemCount} 个视频",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
                if (collection.description.isNotEmpty()) {
                    Text(
                        collection.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun UserArticleCard(article: UserArticle, onClick: () -> Unit) {
    ElevatedCard(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (article.coverURL.isNotEmpty()) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(article.coverURL)
                        .crossfade(true)
                        .build(),
                    contentDescription = null,
                    modifier = Modifier.size(96.dp, 70.dp).clip(RoundedCornerShape(12.dp)),
                    contentScale = ContentScale.Crop,
                )
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(
                    article.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (article.summary.isNotEmpty()) {
                    Text(
                        article.summary,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(
                    listOfNotNull(
                        formatDate(article.publishedAt),
                        formatCount(article.viewCount).takeIf { article.viewCount > 0 }?.let { "$it 阅读" },
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun formatProfileCount(count: Long): String = when {
    count >= 100_000_000L -> compactDecimal(count, 100_000_000L, "亿")
    count >= 10_000L -> compactDecimal(count, 10_000L, "万")
    else -> count.toString()
}

private fun formatCount(count: Long): String = formatProfileCount(count)

private fun compactDecimal(value: Long, unit: Long, suffix: String): String {
    val whole = value / unit
    val decimal = (value % unit) * 10 / unit
    return if (decimal == 0L) "$whole$suffix" else "$whole.$decimal$suffix"
}

private fun formatDate(seconds: Long): String? {
    if (seconds <= 0) return null
    return SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(Date(seconds * 1000))
}
