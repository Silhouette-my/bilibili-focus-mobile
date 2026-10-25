package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.core.model.VideoEpisode
import org.bilibilifocus.core.model.VideoEpisodeGroup
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoPage

@Composable
internal fun VideoPageSection(
    pages: List<VideoPage>,
    selectedCid: Long?,
    onSelect: (VideoPage) -> Unit,
) {
    val selectedIndex = pages.indexOfFirst { it.cid == selectedCid }.coerceAtLeast(0)
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = selectedIndex)

    LaunchedEffect(pages, selectedCid) {
        val currentIndex = pages.indexOfFirst { it.cid == selectedCid }
        if (currentIndex >= 0) {
            listState.scrollToItem(currentIndex)
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("分 P", style = MaterialTheme.typography.titleMedium)
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(pages, key = { it.cid }) { page ->
                val selected = page.cid == selectedCid
                val chipShape = RoundedCornerShape(10.dp)
                FilterChip(
                    selected = selected,
                    onClick = { onSelect(page) },
                    label = {
                        val label = buildString {
                            append("P${page.pageNumber}")
                            if (page.title.isNotBlank()) append(" ${page.title}")
                        }
                        Text(
                            label,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            textAlign = TextAlign.Center,
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                        selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                    ),
                    shape = chipShape,
                    modifier = Modifier.then(
                        if (selected) {
                            Modifier.border(2.dp, MaterialTheme.colorScheme.primary, chipShape)
                        } else {
                            Modifier
                        }
                    ),
                )
            }
        }
    }
}

@Composable
internal fun VideoEpisodeSections(
    groups: List<VideoEpisodeGroup>,
    currentBvid: String,
    currentCid: Long,
    onOpenVideo: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        groups.forEach { group ->
            VideoEpisodeGroupRow(
                group = group,
                currentBvid = currentBvid,
                currentCid = currentCid,
                onOpenVideo = onOpenVideo,
            )
        }
    }
}

@Composable
private fun VideoEpisodeGroupRow(
    group: VideoEpisodeGroup,
    currentBvid: String,
    currentCid: Long,
    onOpenVideo: (String) -> Unit,
) {
    val currentIndex = currentVideoEpisodeIndex(group.episodes, currentBvid, currentCid)
    val listState = remember(group, currentBvid, currentCid) {
        LazyListState(firstVisibleItemIndex = currentIndex.coerceAtLeast(0))
    }

    LaunchedEffect(group.episodes, currentBvid, currentCid, currentIndex) {
        if (currentIndex >= 0) {
            withFrameNanos { }
            listState.scrollToItem(currentIndex)
            withFrameNanos { }
            if (listState.layoutInfo.visibleItemsInfo.none { it.index == currentIndex }) {
                listState.scrollToItem(currentIndex)
            }
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(group.title, style = MaterialTheme.typography.titleMedium)
        LazyRow(
            state = listState,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            itemsIndexed(
                items = group.episodes,
                key = { _, episode -> "${group.title}-${episode.bvid}-${episode.cid}" },
            ) { index, episode ->
                val selected = index == currentIndex
                EpisodeCard(
                    episode = episode,
                    selected = selected,
                    onClick = {
                        if (!selected) {
                            onOpenVideo(videoEpisodeURL(episode))
                        }
                    },
                )
            }
        }
    }
}

internal fun currentVideoEpisodeIndex(
    episodes: List<VideoEpisode>,
    currentBvid: String,
    currentCid: Long? = null,
): Int {
    if (currentCid != null && currentCid > 0) {
        val exactMatch = episodes.indexOfFirst {
            it.bvid == currentBvid && it.cid == currentCid
        }
        if (exactMatch >= 0) return exactMatch

        val caseInsensitiveMatch = episodes.indexOfFirst {
            it.cid == currentCid && it.bvid.equals(currentBvid, ignoreCase = true)
        }
        if (caseInsensitiveMatch >= 0) return caseInsensitiveMatch

        val cidMatch = episodes.indexOfFirst { it.cid == currentCid }
        if (cidMatch >= 0) return cidMatch
    }

    val exactIndex = episodes.indexOfFirst { it.bvid == currentBvid }
    return if (exactIndex >= 0) {
        exactIndex
    } else {
        episodes.indexOfFirst { it.bvid.equals(currentBvid, ignoreCase = true) }
    }
}

internal fun videoEpisodeURL(episode: VideoEpisode): String = buildString {
    append("https://www.bilibili.com/video/")
    append(episode.bvid)
    append('/')
    if (episode.cid > 0) {
        append("?cid=")
        append(episode.cid)
    }
}

@Composable
private fun EpisodeCard(
    episode: VideoEpisode,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val cardShape = RoundedCornerShape(14.dp)
    ElevatedCard(
        onClick = onClick,
        shape = cardShape,
        colors = CardDefaults.elevatedCardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.primaryContainer
            } else {
                MaterialTheme.colorScheme.surface
            }
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        modifier = Modifier
            .size(width = 156.dp, height = 88.dp)
            .then(
                if (selected) {
                    Modifier.border(2.dp, MaterialTheme.colorScheme.primary, cardShape)
                } else {
                    Modifier
                }
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(12.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                episode.title,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
            )
            if (episode.badgeText.isNotBlank()) {
                Text(
                    episode.badgeText,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}


@Composable
private fun StatItem(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurface)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
internal fun VideoTitleSection(info: VideoInfo) {
    val titleStyle = MaterialTheme.typography.titleMedium
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = info.title,
            style = titleStyle.copy(fontSize = titleStyle.fontSize * 1.2f),
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "${formatVideoCount(info.stats.views)}播放",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "${formatVideoCount(info.stats.danmaku)}弹幕",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (info.publishDate > 0) {
                Text(
                    text = formatPublishDate(info.publishDate),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
internal fun AuthorCard(info: VideoInfo, onClick: () -> Unit = {}) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onClick() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(info.author.avatarURL)
                .crossfade(true)
                .build(),
            contentDescription = null,
            modifier = Modifier.size(44.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(info.author.name, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("UID: ${info.author.mid}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun ExpandableDescription(desc: String) {
    var expanded by remember(desc) { mutableStateOf(true) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = desc,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = if (expanded) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
        )
        if (desc.length > 120) {
            Text(
                text = if (expanded) "收起" else "展开",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.clickable { expanded = !expanded },
            )
        }
    }
}


internal fun resolveActivePage(
    info: VideoInfo?,
    selectedCid: Long?,
    requestedPageNumber: Int?,
    requestedPageCid: Long?,
    resumeCid: Long? = null,
): VideoPage? {
    if (info == null) return null
    return info.pages.firstOrNull { it.cid == selectedCid }
        ?: requestedPageNumber?.let { pageNumber ->
            info.pages.firstOrNull { it.pageNumber == pageNumber }
        }
        ?: requestedPageCid?.let { cid ->
            info.pages.firstOrNull { it.cid == cid }
        }
        ?: resumeCid?.let { cid ->
            info.pages.firstOrNull { it.cid == cid }
        }
        ?: info.pages.firstOrNull { it.cid == info.cid }
        ?: info.pages.firstOrNull()
        ?: VideoPage(
            pageNumber = 1,
            cid = info.cid,
            title = "正片",
            duration = info.duration,
        )
}

internal fun parseRequestedPage(url: String): Int? {
    return Regex("""[?&]p=(\d+)""", RegexOption.IGNORE_CASE)
        .find(url.replace("&amp;", "&", ignoreCase = true))
        ?.groupValues
        ?.getOrNull(1)
        ?.toIntOrNull()
        ?.takeIf { it > 0 }
}

internal fun parseRequestedCid(url: String): Long? {
    return Regex("""[?&]cid=(\d+)""", RegexOption.IGNORE_CASE)
        .find(url.replace("&amp;", "&", ignoreCase = true))
        ?.groupValues
        ?.getOrNull(1)
        ?.toLongOrNull()
        ?.takeIf { it > 0 }
}

internal fun parseRequestedHistoryPositionMillis(url: String): Long? {
    return Regex("""[?&]focus_history_position_ms=(\d+)""", RegexOption.IGNORE_CASE)
        .find(url.replace("&amp;", "&", ignoreCase = true))
        ?.groupValues
        ?.getOrNull(1)
        ?.toLongOrNull()
}

internal fun historyPositionForRequestedPage(
    positionMillis: Long?,
    requestedPageNumber: Int?,
    requestedPageCid: Long?,
    activePageNumber: Int,
    activePageCid: Long,
): Long? {
    if (positionMillis == null) return null
    val cidMatches = requestedPageCid != null && requestedPageCid == activePageCid
    val pageMatches = requestedPageNumber != null && requestedPageNumber == activePageNumber
    return positionMillis.takeIf { cidMatches || pageMatches }
}


private fun formatPublishDate(timestamp: Long): String =
    java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.CHINA)
        .format(java.util.Date(timestamp * 1000))
