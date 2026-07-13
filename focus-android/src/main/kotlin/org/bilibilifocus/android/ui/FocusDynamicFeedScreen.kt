package org.bilibilifocus.android.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.SearchBar
import androidx.compose.material3.SearchBarDefaults
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.ContentScale.Companion.Crop
import androidx.compose.ui.layout.ContentScale.Companion.Fit
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.geometry.Size
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusFeedViewModel
import org.bilibilifocus.android.FeedUiState
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.model.FocusSettings
import org.bilibilifocus.core.service.DynamicFeedService
import org.bilibilifocus.core.service.KtorHttpClient

private val DynamicCoverCornerRadius = RoundedCornerShape(6.dp)

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun FocusDynamicFeedScreen(
    viewModel: FocusFeedViewModel,
    listState: LazyListState,
    onOpenLogin: () -> Unit = {},
    onOpenCard: (DynamicCard) -> Unit = {},
    onOpenUser: (Long) -> Unit = {},
    onOpenSearch: (String) -> Unit = {},
    onSelectedFilterChange: (FocusDynamicFilterKind) -> Unit = {},
    contentPadding: PaddingValues = PaddingValues(),
    settings: FocusSettings = FocusSettings.DEFAULTS,
) {
    LaunchedEffect(Unit) {
        viewModel.loadIfNeeded()
    }

    val state by viewModel.state.collectAsState()
    val isLoadingMore by viewModel.isLoadingMore.collectAsState()
    val selectedFilter by viewModel.selectedFilter.collectAsState()
    var isRefreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var searchQuery by remember { mutableStateOf("") }
    var galleryRequest by remember { mutableStateOf<FocusImageGalleryRequest?>(null) }
    val showScrollTop by remember { derivedStateOf { listState.firstVisibleItemIndex > 3 } }
    val topContentPadding = contentPadding.calculateTopPadding()
    val pullToRefreshState = rememberPullToRefreshState()

    Box(modifier = Modifier.fillMaxSize()) {
    Column(modifier = Modifier.fillMaxSize()) {
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            when (val s = state) {
                FeedUiState.Idle, FeedUiState.Loading -> {
                    Box(
                        modifier = Modifier.fillMaxSize().padding(top = topContentPadding),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                }

                FeedUiState.LoginRequired -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(top = topContentPadding)
                            .padding(32.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text("需要登录", style = MaterialTheme.typography.headlineSmall)
                            Text(
                                "先在网页登录 Bilibili，再回来刷新",
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
                            ) {
                                Text("重新检测登录态")
                            }
                        }
                    }
                }

                is FeedUiState.Failed -> {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(top = topContentPadding)
                            .padding(32.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text("动态加载失败", style = MaterialTheme.typography.headlineSmall)
                            Text(s.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Button(onClick = { viewModel.reload() }) { Text("重试") }
                        }
                    }
                }

                is FeedUiState.Empty -> {
                    PullToRefreshBox(
                        isRefreshing = isRefreshing,
                        state = pullToRefreshState,
                        onRefresh = {
                            if (!isRefreshing) {
                                isRefreshing = true
                                viewModel.refresh { isRefreshing = false }
                            }
                        },
                        indicator = {
                            PullToRefreshDefaults.Indicator(
                                state = pullToRefreshState,
                                isRefreshing = isRefreshing,
                                modifier = Modifier
                                    .align(Alignment.TopCenter)
                                    .padding(top = topContentPadding),
                            )
                        },
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .padding(top = topContentPadding)
                                .padding(32.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                Text("暂无可显示的关注动态", style = MaterialTheme.typography.headlineSmall)
                                Text(
                                    "当前页面没有拿到内容，稍后可以再刷新一次",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Button(onClick = { viewModel.reload() }) { Text("重新加载") }
                            }
                        }
                    }
                }

                is FeedUiState.Loaded -> {
                    val filteredCards = visibleCards(
                        cards = s.cards,
                        selectedFilter = selectedFilter,
                        settings = settings,
                    )

                    LaunchedEffect(s.cards.size, filteredCards.size, selectedFilter, settings) {
                        if (s.cards.isNotEmpty() && filteredCards.isEmpty()) {
                            viewModel.loadMoreIfNeeded(s.cards.last().id)
                        }
                    }

                    PullToRefreshBox(
                        isRefreshing = isRefreshing,
                        state = pullToRefreshState,
                        onRefresh = {
                            if (!isRefreshing) {
                                isRefreshing = true
                                viewModel.refresh { isRefreshing = false }
                            }
                        },
                        indicator = {
                            PullToRefreshDefaults.Indicator(
                                state = pullToRefreshState,
                                isRefreshing = isRefreshing,
                                modifier = Modifier
                                    .align(Alignment.TopCenter)
                                    .padding(top = topContentPadding),
                            )
                        },
                    ) {
                        LazyColumn(
                            state = listState,
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(
                                start = 16.dp,
                                end = 16.dp,
                                top = topContentPadding + 12.dp,
                                bottom = 12.dp + contentPadding.calculateBottomPadding(),
                            ),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            item(key = "dynamic-feed-header") {
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    SearchBar(
                                        inputField = {
                                            SearchBarDefaults.InputField(
                                                query = searchQuery,
                                                onQueryChange = { searchQuery = it },
                                                onSearch = {
                                                    if (searchQuery.isNotBlank()) {
                                                        onOpenSearch(searchQuery.trim())
                                                    }
                                                },
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
                                        modifier = Modifier.fillMaxWidth(),
                                    ) {}

                                    DynamicFilterRow(
                                        selectedFilter = selectedFilter,
                                        onSelect = { filter ->
                                            if (filter != selectedFilter) {
                                                viewModel.selectFilter(filter)
                                                onSelectedFilterChange(filter)
                                                scope.launch { listState.scrollToItem(0) }
                                            }
                                        },
                                        modifier = Modifier.padding(vertical = 2.dp),
                                    )
                                }
                            }

                            if (filteredCards.isEmpty()) {
                                item {
                                    Column(
                                        modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 28.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(12.dp),
                                    ) {
                                        Text("暂无可显示的关注动态", style = MaterialTheme.typography.titleMedium)
                                        Text(
                                            "当前筛选条件下没有内容，可以切换分类或在设置里调整 UP 主动态配置。",
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                        Button(onClick = { viewModel.reload() }) { Text("重新加载") }
                                    }
                                }
                            }

                            items(filteredCards, key = { it.id }) { card ->
                                LaunchedEffect(card.id, filteredCards.lastOrNull()?.id, s.cards.size) {
                                    if (card.id == filteredCards.lastOrNull()?.id) {
                                        viewModel.loadMoreIfNeeded(s.cards.lastOrNull()?.id ?: card.id)
                                    }
                                }
                                ElevatedCard(
                                    onClick = { onOpenCard(card) },
                                    shape = RoundedCornerShape(16.dp),
                                    colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
                                    elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
                                ) {
                                    FocusDynamicCard(
                                        card = card,
                                        onOpenUser = onOpenUser,
                                        onOpenImage = { index ->
                                            galleryRequest = FocusImageGalleryRequest(
                                                images = card.coverURLs,
                                                initialIndex = index,
                                                referer = card.targetURL,
                                            )
                                        },
                                    )
                                }
                            }

                            if (isLoadingMore) {
                                item {
                                    Box(modifier = Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                                        CircularProgressIndicator(
                                            modifier = Modifier.size(24.dp),
                                            color = MaterialTheme.colorScheme.primary,
                                            strokeWidth = 2.dp,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            AnimatedScrollToTopButton(
                visible = state is FeedUiState.Loaded && showScrollTop,
                onClick = { scope.launch { listState.animateScrollToItem(0) } },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(16.dp)
                    .padding(bottom = contentPadding.calculateBottomPadding()),
            )
        }
    }
        galleryRequest?.let { request ->
            FocusImageGallery(request = request, onDismiss = { galleryRequest = null })
        }
    }
}

@Composable
private fun AnimatedScrollToTopButton(
    visible: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = fadeIn() + scaleIn(initialScale = 0.82f),
        exit = fadeOut() + scaleOut(targetScale = 0.82f),
    ) {
        SmallFloatingActionButton(
            onClick = onClick,
            containerColor = MaterialTheme.colorScheme.primaryContainer,
            contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
        ) {
            Icon(Icons.Filled.KeyboardArrowUp, contentDescription = "回到顶部")
        }
    }
}

@Composable
private fun DynamicFilterRow(
    selectedFilter: FocusDynamicFilterKind,
    onSelect: (FocusDynamicFilterKind) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FocusDynamicFilterKind.entries.forEach { filter ->
            FilterChip(
                selected = filter == selectedFilter,
                onClick = { onSelect(filter) },
                label = {
                    Text(
                        filter.title,
                        modifier = Modifier.fillMaxWidth(),
                        textAlign = TextAlign.Center,
                    )
                },
                modifier = Modifier.weight(1f).heightIn(min = 44.dp),
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
                shape = RoundedCornerShape(14.dp),
            )
        }
    }
}

@Composable
private fun FocusDynamicCard(
    card: DynamicCard,
    onOpenUser: (Long) -> Unit,
    onOpenImage: (Int) -> Unit,
) {
    Column(
        modifier = Modifier.padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            FocusAvatar(
                avatarURL = card.author.avatarURL,
                modifier = Modifier
                    .size(44.dp)
                    .clickable(enabled = card.author.mid > 0) {
                        onOpenUser(card.author.mid)
                    },
            )

            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    text = card.author.name,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (card.publishTime.isNotEmpty()) {
                        Text(
                            text = card.publishTime,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    FocusKindBadge(kind = card.kind)
                }
            }
        }

        if (card.text.isNotEmpty()) {
            FocusExpandableDynamicText(
                cardId = card.id,
                text = card.text,
            )
        }

        if (card.coverURLs.isNotEmpty()) {
            FocusDynamicCardCovers(card = card, onOpenImage = onOpenImage)
        }
    }
}

@Composable
private fun FocusExpandableDynamicText(cardId: String, text: String) {
    var isExpanded by rememberSaveable(cardId, text) { mutableStateOf(false) }
    var hasCollapsedOverflow by remember(cardId, text) { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            maxLines = if (isExpanded) Int.MAX_VALUE else 6,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { result ->
                if (!isExpanded) {
                    hasCollapsedOverflow = result.hasVisualOverflow
                }
            },
        )

        if (hasCollapsedOverflow || isExpanded) {
            TextButton(
                onClick = { isExpanded = !isExpanded },
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp),
            ) {
                Text(if (isExpanded) "收起文本" else "展开全文")
            }
        }
    }
}

private fun visibleCards(
    cards: List<DynamicCard>,
    selectedFilter: FocusDynamicFilterKind,
    settings: FocusSettings,
): List<DynamicCard> = cards.filter { card ->
    val normalizedKind = when (card.kind) {
        DynamicCard.Kind.VIDEO -> FocusDynamicFilterKind.VIDEO
        DynamicCard.Kind.TEXT,
        DynamicCard.Kind.IMAGE,
        DynamicCard.Kind.ARTICLE_LIKE,
        -> FocusDynamicFilterKind.ARTICLE_LIKE
    }
    val authorKey = if (card.author.mid > 0) {
        "mid:${card.author.mid}"
    } else {
        "name:${card.author.name}"
    }
    val authorKinds = settings.perAuthorDynamicFilters[authorKey]
        ?: settings.dynamicVisibleKinds

    normalizedKind in authorKinds &&
        (selectedFilter == FocusDynamicFilterKind.ALL || selectedFilter == normalizedKind)
}

@Composable
private fun FocusAvatar(avatarURL: String?, modifier: Modifier = Modifier) {
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
            .data(avatarURL)
            .crossfade(true)
            .build(),
        contentDescription = null,
        modifier = modifier.clip(CircleShape),
        contentScale = ContentScale.Crop,
    )
}

@Composable
private fun FocusDynamicCardCovers(card: DynamicCard, onOpenImage: (Int) -> Unit) {
    if (card.coverURLs.size == 1) {
        val url = card.coverURLs.first()
        when (card.kind) {
            DynamicCard.Kind.VIDEO, DynamicCard.Kind.ARTICLE_LIKE, DynamicCard.Kind.TEXT -> {
                FocusCoverImage(
                    url = url,
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(16f / 9f),
                    contentScale = Crop,
                    showBackground = false,
                )
            }

            DynamicCard.Kind.IMAGE -> {
                FocusSingleImageCover(
                    url = url,
                    modifier = Modifier.fillMaxWidth(),
                    onClick = { onOpenImage(0) },
                )
            }
        }
        return
    }

    val canFoldImages = card.kind == DynamicCard.Kind.IMAGE && card.coverURLs.size > 4
    var areImagesExpanded by rememberSaveable(card.id, card.coverURLs) { mutableStateOf(false) }
    val visibleCoverURLs = if (canFoldImages && !areImagesExpanded) {
        card.coverURLs.take(4)
    } else {
        card.coverURLs
    }
    val rows = visibleCoverURLs.chunked(2)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEachIndexed { rowIndex, rowUrls ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                rowUrls.forEachIndexed { columnIndex, url ->
                    FocusCoverImage(
                        url = url,
                        modifier = Modifier
                            .weight(1f)
                            .aspectRatio(1f)
                            .then(
                                if (card.kind == DynamicCard.Kind.IMAGE) {
                                    Modifier.clickable { onOpenImage(rowIndex * 2 + columnIndex) }
                                } else Modifier
                            ),
                        contentScale = Crop,
                        showBackground = false,
                    )
                }
                repeat(2 - rowUrls.size) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }

        if (canFoldImages) {
            TextButton(
                onClick = { areImagesExpanded = !areImagesExpanded },
                contentPadding = PaddingValues(horizontal = 0.dp, vertical = 0.dp),
            ) {
                Text(
                    if (areImagesExpanded) {
                        "收起图片"
                    } else {
                        "展开全部 ${card.coverURLs.size} 张图片"
                    }
                )
            }
        }
    }
}

@Composable
private fun FocusSingleImageCover(url: String, modifier: Modifier = Modifier, onClick: () -> Unit = {}) {
    val painter = rememberAsyncImagePainter(
        model = ImageRequest.Builder(LocalContext.current)
            .data(url)
            .crossfade(true)
            .build()
    )
    val intrinsicSize = (painter.state as? AsyncImagePainter.State.Success)
        ?.painter
        ?.intrinsicSize
    val ratio = normalizedIntrinsicRatio(intrinsicSize)
    val widthFraction = when {
        ratio >= 1.15f -> 1f
        ratio >= 0.95f -> 0.82f
        else -> 0.68f
    }

    Image(
        painter = painter,
        contentDescription = null,
        modifier = modifier
            .clickable(onClick = onClick)
            .fillMaxWidth(widthFraction)
            .aspectRatio(ratio)
            .clip(DynamicCoverCornerRadius)
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentScale = Fit,
    )
}

@Composable
private fun FocusCoverImage(
    url: String,
    modifier: Modifier = Modifier,
    contentScale: ContentScale,
    showBackground: Boolean,
) {
    AsyncImage(
        model = ImageRequest.Builder(LocalContext.current)
            .data(url)
            .crossfade(true)
            .build(),
        contentDescription = null,
        modifier = modifier
            .clip(DynamicCoverCornerRadius)
            .then(
                if (showBackground) {
                    Modifier.background(MaterialTheme.colorScheme.surfaceVariant, DynamicCoverCornerRadius)
                } else {
                    Modifier
                }
            ),
        contentScale = contentScale,
    )
}

private fun normalizedIntrinsicRatio(size: Size?): Float {
    if (size == null || size.width <= 0f || size.height <= 0f) {
        return 4f / 3f
    }
    return (size.width / size.height).coerceIn(0.75f, 2f)
}

@Composable
private fun FocusKindBadge(kind: DynamicCard.Kind) {
    val (label, containerColor, contentColor) = when (kind) {
        DynamicCard.Kind.TEXT -> Triple(
            "文字",
            MaterialTheme.colorScheme.tertiaryContainer,
            MaterialTheme.colorScheme.onTertiaryContainer,
        )
        DynamicCard.Kind.IMAGE -> Triple(
            "图片",
            MaterialTheme.colorScheme.secondaryContainer,
            MaterialTheme.colorScheme.onSecondaryContainer,
        )
        DynamicCard.Kind.VIDEO -> Triple(
            "视频",
            MaterialTheme.colorScheme.primaryContainer,
            MaterialTheme.colorScheme.onPrimaryContainer,
        )
        DynamicCard.Kind.ARTICLE_LIKE -> Triple(
            "专栏",
            MaterialTheme.colorScheme.tertiaryContainer,
            MaterialTheme.colorScheme.onTertiaryContainer,
        )
    }

    Text(
        text = label,
        style = MaterialTheme.typography.labelSmall,
        color = contentColor,
        modifier = Modifier
            .background(containerColor, RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}
