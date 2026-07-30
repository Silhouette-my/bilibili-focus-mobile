package org.bilibilifocus.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.flow.distinctUntilChanged
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusSearchViewModel
import org.bilibilifocus.android.SearchUiState
import org.bilibilifocus.core.model.SearchResultFilter
import org.bilibilifocus.core.model.SearchResultItem
import org.bilibilifocus.core.model.SearchResultSection
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.SearchResultService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusSearchScreen(
    viewModel: FocusSearchViewModel,
    onOpenItem: (SearchResultItem) -> Unit = {},
    onOpenLogin: () -> Unit = {},
    initialQuery: String? = null,
    onInitialQueryConsumed: () -> Unit = {},
    contentPadding: PaddingValues = PaddingValues(),
    resultColumns: Int = 2,
) {
    var searchQuery by remember { mutableStateOf("") }
    val state by viewModel.state.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    val resolvedResultColumns = resultColumns.coerceAtLeast(1)

    // 从动态页搜索框带入的查询：自动填入并搜索一次
    LaunchedEffect(initialQuery) {
        val q = initialQuery
        if (!q.isNullOrBlank()) {
            searchQuery = q
            viewModel.search(q)
            onInitialQueryConsumed()
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(top = contentPadding.calculateTopPadding())) {
        SearchBar(
            inputField = {
                SearchBarDefaults.InputField(
                    query = searchQuery,
                    onQueryChange = { searchQuery = it },
                    onSearch = { viewModel.search(searchQuery) },
                    expanded = false,
                    onExpandedChange = {},
                    placeholder = { Text("搜索视频、UP主、番剧…") },
                    leadingIcon = {
                        Icon(Icons.Default.Search, contentDescription = "搜索")
                    },
                )
            },
            expanded = false,
            onExpandedChange = {},
            shape = RoundedCornerShape(28.dp),
            colors = SearchBarDefaults.colors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
            windowInsets = WindowInsets(0, 0, 0, 0),
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
        ) {}

        FilterChipRow(
            filters = SearchResultFilter.defaultOrder,
            selectedFilter = viewModel.selectedFilter,
            onSelect = { viewModel.selectFilter(it) },
            modifier = Modifier.padding(horizontal = 16.dp),
        )

        Spacer(modifier = Modifier.height(12.dp))

        when (val s = state) {
            SearchUiState.Idle -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("还没有搜索内容", style = MaterialTheme.typography.titleMedium)
                        Text("在上方输入关键词开始搜索", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            SearchUiState.Loading -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            SearchUiState.LoginRequired -> {
                Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("需要登录", style = MaterialTheme.typography.headlineSmall)
                        Text("搜索功能也需要 Bilibili 登录态", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(onClick = onOpenLogin) { Text("去登录") }
                    }
                }
            }

            is SearchUiState.Failed -> {
                Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("搜索加载失败", style = MaterialTheme.typography.headlineSmall)
                        Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Button(onClick = { viewModel.search(searchQuery) }) { Text("重试") }
                    }
                }
            }

            SearchUiState.Empty -> {
                Box(modifier = Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("没有找到结果", style = MaterialTheme.typography.titleMedium)
                        Text("换个关键词试试", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }

            is SearchUiState.Loaded -> {
                val listState = rememberLazyListState()
                val videoSection = s.sections.firstOrNull { it.filter == SearchResultFilter.VIDEO }
                val loadMoreThreshold = with(LocalDensity.current) { 240.dp.roundToPx() }

                LaunchedEffect(listState, videoSection?.items?.lastOrNull()?.id) {
                    val currentSection = videoSection ?: return@LaunchedEffect
                    val lastItemID = currentSection.items.lastOrNull()?.id ?: return@LaunchedEffect
                    snapshotFlow {
                        val layoutInfo = listState.layoutInfo
                        val visibleSection = layoutInfo.visibleItemsInfo
                            .firstOrNull { it.key == currentSection.id }
                        visibleSection != null &&
                            visibleSection.offset + visibleSection.size <=
                            layoutInfo.viewportEndOffset + loadMoreThreshold
                    }
                        .distinctUntilChanged()
                        .collect { reachedEnd ->
                            if (reachedEnd) {
                                viewModel.loadMoreIfNeeded(lastItemID)
                            }
                        }
                }

                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(
                        start = 16.dp,
                        end = 16.dp,
                        top = 8.dp,
                        bottom = 8.dp + contentPadding.calculateBottomPadding(),
                    ),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(s.sections, key = { it.id }) { section ->
                        FocusSearchSection(
                            section = section,
                            onOpenItem = onOpenItem,
                            onOpenPreview = { item -> onOpenItem(item) },
                            resultColumns = resolvedResultColumns,
                            isLoadingMore = isLoadingMore && section.filter == SearchResultFilter.VIDEO,
                        )
                    }
                    item { Spacer(modifier = Modifier.height(8.dp)) }
                }
            }
        }
    }
}

private fun SearchResultItem.PreviewVideo.toItem(): SearchResultItem = SearchResultItem(
    id = id,
    kind = SearchResultItem.Kind.VIDEO,
    title = title,
    subtitle = "",
    metadataText = metadataText,
    badgeText = badgeText,
    coverURL = coverURL,
    targetURL = targetURL,
)

@Composable
private fun FilterChipRow(
    filters: List<SearchResultFilter>,
    selectedFilter: SearchResultFilter,
    onSelect: (SearchResultFilter) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        filters.forEach { filter ->
            val selected = filter == selectedFilter
            FilterChip(
                selected = selected,
                onClick = { onSelect(filter) },
                label = { Text(filter.title) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
                shape = RoundedCornerShape(20.dp),
            )
        }
    }
}

@Composable
private fun FocusSearchSection(
    section: SearchResultSection,
    onOpenItem: (SearchResultItem) -> Unit,
    onOpenPreview: (SearchResultItem) -> Unit,
    resultColumns: Int,
    isLoadingMore: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = section.title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onBackground,
        )

        when (section.filter) {
            SearchResultFilter.VIDEO, SearchResultFilter.LIVE -> {
                val rows = gridRows(section.items, resultColumns)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    rows.forEach { rowItems ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            rowItems.forEach { item ->
                                ElevatedCard(
                                    onClick = { onOpenItem(item) },
                                    shape = RoundedCornerShape(16.dp),
                                    colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                    elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                    modifier = Modifier.weight(1f),
                                ) {
                                    FocusSearchVideoCard(
                                        item = item,
                                        resultColumns = resultColumns,
                                    )
                                }
                            }
                            repeat(resultColumns - rowItems.size) {
                                Spacer(modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }

            SearchResultFilter.USERS -> {
                val userColumns = resultColumns.coerceAtMost(2)
                val rows = gridRows(section.items, userColumns)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    rows.forEach { rowItems ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            rowItems.forEach { item ->
                                ElevatedCard(
                                    onClick = { onOpenItem(item) },
                                    shape = RoundedCornerShape(16.dp),
                                    colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                    elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                    modifier = Modifier.weight(1f),
                                ) {
                                    FocusSearchUserCard(
                                        item = item,
                                        onOpenItem = onOpenItem,
                                        onOpenPreview = onOpenPreview,
                                    )
                                }
                            }
                            repeat(userColumns - rowItems.size) {
                                Spacer(modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }

            SearchResultFilter.BANGUMI, SearchResultFilter.FILM -> {
                val mediaColumns = resultColumns.coerceAtMost(3)
                if (mediaColumns <= 2) {
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(section.items, key = { it.id }) { item ->
                            ElevatedCard(
                                onClick = { onOpenItem(item) },
                                shape = RoundedCornerShape(16.dp),
                                colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                modifier = Modifier.width(160.dp),
                            ) {
                                FocusSearchMediaCard(item = item)
                            }
                        }
                    }
                } else {
                    val rows = gridRows(section.items, mediaColumns)
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        rows.forEach { rowItems ->
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                rowItems.forEach { item ->
                                    ElevatedCard(
                                        onClick = { onOpenItem(item) },
                                        shape = RoundedCornerShape(16.dp),
                                        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                        modifier = Modifier.weight(1f),
                                    ) {
                                        FocusSearchMediaCard(item = item)
                                    }
                                }
                                repeat(mediaColumns - rowItems.size) {
                                    Spacer(modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
            }

            else -> {}
        }

        if (isLoadingMore) {
            Box(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

private fun <T> gridRows(items: List<T>, columns: Int): List<List<T>> {
    val safeColumns = columns.coerceAtLeast(1)
    return items.chunked(safeColumns)
}

@Composable
private fun FocusSearchVideoCard(
    item: SearchResultItem,
    resultColumns: Int,
) {
    Column {
        FocusSearchCover(
            url = item.coverURL,
            badgeText = item.badgeText,
            aspectRatio = videoCoverAspectRatio(resultColumns),
        )

        Column(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.height(40.dp),
            )
            Text(
                text = item.subtitle.ifEmpty { " " },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.metadataText.ifEmpty { " " },
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun FocusSearchCover(
    url: String?,
    badgeText: String,
    height: Int? = null,
    aspectRatio: Float? = null,
) {
    val coverModifier = when {
        aspectRatio != null -> Modifier.fillMaxWidth().aspectRatio(aspectRatio)
        height != null -> Modifier.fillMaxWidth().height(height.dp)
        else -> Modifier.fillMaxWidth().aspectRatio(16f / 9f)
    }

    Box(modifier = coverModifier) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(url)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier
                .fillMaxSize()
                .clip(RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp)),
            contentScale = ContentScale.Crop,
        )

        if (badgeText.isNotEmpty()) {
            Text(
                text = badgeText,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onPrimary,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(8.dp)
                    .background(
                        Color.Black.copy(alpha = 0.65f),
                        RoundedCornerShape(4.dp),
                    )
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun FocusSearchUserCard(
    item: SearchResultItem,
    onOpenItem: (SearchResultItem) -> Unit,
    onOpenPreview: (SearchResultItem) -> Unit,
) {
    Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.clickable { onOpenItem(item) },
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(item.avatarURL)
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                modifier = Modifier
                    .size(48.dp)
                    .clip(CircleShape),
                contentScale = ContentScale.Crop,
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (item.subtitle.isNotEmpty()) {
                    Text(
                        text = item.subtitle,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (item.metadataText.isNotEmpty()) {
                    Text(
                        text = item.metadataText,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        if (item.previews.isNotEmpty()) {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(item.previews, key = { it.id }) { preview ->
                    Box(modifier = Modifier.width(132.dp).clickable { onOpenPreview(preview.toItem()) }) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            FocusSearchCover(
                                url = preview.coverURL,
                                badgeText = preview.badgeText,
                                height = 76,
                            )
                            Text(
                                text = preview.title,
                                style = MaterialTheme.typography.labelSmall,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                            if (preview.metadataText.isNotEmpty()) {
                                Text(
                                    text = preview.metadataText,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FocusSearchMediaCard(item: SearchResultItem) {
    Column {
        FocusSearchCover(
            url = item.coverURL,
            badgeText = item.badgeText,
            height = 220,
        )
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            if (item.subtitle.isNotEmpty()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (item.metadataText.isNotEmpty()) {
                Text(
                    text = item.metadataText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

private fun videoCoverAspectRatio(resultColumns: Int): Float = when {
    resultColumns >= 4 -> 16f / 9f
    resultColumns == 3 -> 1.9f
    else -> 2.0f
}
