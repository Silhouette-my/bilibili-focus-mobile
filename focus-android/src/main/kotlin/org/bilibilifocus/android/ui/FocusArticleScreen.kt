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
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.ArticleUiState
import org.bilibilifocus.android.FocusArticleViewModel
import org.bilibilifocus.core.model.ArticleBlock
import org.bilibilifocus.core.model.ArticleDetail
import org.bilibilifocus.core.model.TextAlignment
import org.bilibilifocus.core.model.plainText
import org.bilibilifocus.core.service.ArticleService
import org.bilibilifocus.core.service.KtorHttpClient
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FocusArticleScreen(
    cvid: Long,
    onBack: () -> Unit,
    onOpenUser: (Long) -> Unit = {},
    onOpenURL: (String) -> Unit = {},
    onOpenWeb: (String) -> Unit = onOpenURL,
    viewModel: FocusArticleViewModel? = null,
) {
    val resolvedViewModel = viewModel ?: remember(cvid) {
        FocusArticleViewModel(ArticleService(AndroidCookieProvider(), KtorHttpClient()))
    }
    LaunchedEffect(cvid) { resolvedViewModel.loadIfNeeded(cvid) }
    val state by resolvedViewModel.state.collectAsState()
    val originalURL = "https://www.bilibili.com/read/cv$cvid"

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(
                        (state as? ArticleUiState.Loaded)?.detail?.title ?: "专栏",
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    IconButton(onClick = { onOpenWeb(originalURL) }) {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = "在网页中打开")
                    }
                },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
    ) { innerPadding ->
        when (val value = state) {
            ArticleUiState.Idle, ArticleUiState.Loading -> Box(
                Modifier.fillMaxSize().padding(innerPadding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            ArticleUiState.LoginRequired -> ArticleFailure(
                message = "当前专栏需要登录后查看",
                onRetry = { resolvedViewModel.load(cvid) },
                onOpenWeb = { onOpenWeb(originalURL) },
                modifier = Modifier.padding(innerPadding),
            )

            is ArticleUiState.Failed -> ArticleFailure(
                message = value.message,
                onRetry = { resolvedViewModel.load(cvid) },
                onOpenWeb = { onOpenWeb(originalURL) },
                modifier = Modifier.padding(innerPadding),
            )

            is ArticleUiState.Loaded -> ArticleContent(
                detail = value.detail,
                onOpenUser = onOpenUser,
                onOpenURL = onOpenURL,
                contentPadding = innerPadding,
            )
        }
    }
}

@Composable
private fun ArticleContent(
    detail: ArticleDetail,
    onOpenUser: (Long) -> Unit,
    onOpenURL: (String) -> Unit,
    contentPadding: PaddingValues,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(
            start = 16.dp,
            end = 16.dp,
            top = contentPadding.calculateTopPadding() + 12.dp,
            bottom = contentPadding.calculateBottomPadding() + 32.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (detail.bannerUrl.isNotBlank()) {
            item("banner") {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(detail.bannerUrl)
                        .addHeader("Referer", detail.originalURL)
                        .crossfade(true)
                        .build(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxWidth().height(200.dp).clip(RoundedCornerShape(18.dp)),
                    contentScale = ContentScale.Crop,
                )
            }
        }
        item("title") { Text(detail.title, style = MaterialTheme.typography.headlineSmall) }
        item("author") { ArticleAuthorCard(detail, onOpenUser) }
        if (detail.tags.isNotEmpty()) {
            item("tags") {
                Row(
                    modifier = Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    detail.tags.forEach { tag ->
                        Text(
                            tag,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier
                                .background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(50))
                                .padding(horizontal = 12.dp, vertical = 7.dp),
                        )
                    }
                }
            }
        }
        item("stats") { ArticleStats(detail) }
        items(detail.blocks.size, key = { "block-$it" }) { index ->
            ArticleBlockView(detail.blocks[index], detail.originalURL, onOpenURL)
        }
    }
}

@Composable
private fun ArticleBlockView(block: ArticleBlock, referer: String, onOpenURL: (String) -> Unit) {
    when (block) {
        is ArticleBlock.Paragraph -> FocusRichText(
            runs = block.runs,
            style = MaterialTheme.typography.bodyLarge.copy(
                textAlign = when (block.alignment) {
                    TextAlignment.START -> TextAlign.Start
                    TextAlignment.CENTER -> TextAlign.Center
                    TextAlignment.END -> TextAlign.End
                }
            ),
            modifier = Modifier.fillMaxWidth(),
            onOpenURL = onOpenURL,
        )

        is ArticleBlock.Heading -> FocusRichText(
            runs = block.runs,
            style = when (block.level) {
                1 -> MaterialTheme.typography.headlineSmall
                2 -> MaterialTheme.typography.titleLarge
                else -> MaterialTheme.typography.titleMedium
            },
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
            onOpenURL = onOpenURL,
        )

        is ArticleBlock.Image -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            val ratio = if (block.width > 0 && block.height > 0) {
                (block.width.toFloat() / block.height).coerceIn(0.55f, 2.2f)
            } else 4f / 3f
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(block.url)
                    .addHeader("Referer", referer)
                    .crossfade(true)
                    .build(),
                contentDescription = block.caption.ifBlank { null },
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)),
                contentScale = ContentScale.FillWidth,
            )
            if (block.caption.isNotBlank()) {
                Text(block.caption, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        is ArticleBlock.Quote -> FocusRichText(
            runs = block.runs,
            style = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurfaceVariant),
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(10.dp))
                .padding(14.dp),
            onOpenURL = onOpenURL,
        )

        is ArticleBlock.ListBlock -> Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            block.items.forEachIndexed { index, runs ->
                Row(verticalAlignment = Alignment.Top) {
                    Text(if (block.ordered) "${index + 1}." else "•", modifier = Modifier.width(28.dp))
                    FocusRichText(runs, modifier = Modifier.weight(1f), onOpenURL = onOpenURL)
                }
            }
        }

        is ArticleBlock.CodeBlock -> Column(
            modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(12.dp)).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (block.language.isNotBlank()) Text(block.language.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
            Text(block.code, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
        }

        is ArticleBlock.Resource -> ElevatedCard(onClick = { onOpenURL(block.url) }) {
            Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(block.title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
                Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null)
            }
        }

        ArticleBlock.Divider -> HorizontalDivider()
    }
}

@Composable
private fun ArticleAuthorCard(detail: ArticleDetail, onOpenUser: (Long) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable(enabled = detail.author.mid > 0) { onOpenUser(detail.author.mid) }
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current).data(detail.author.avatarURL).crossfade(true).build(),
            contentDescription = null,
            modifier = Modifier.size(44.dp).clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(detail.author.name, style = MaterialTheme.typography.titleSmall)
            if (detail.publishTime > 0) {
                Text(
                    SimpleDateFormat("yyyy-MM-dd", Locale.getDefault()).format(Date(detail.publishTime * 1000)),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ArticleStats(detail: ArticleDetail) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        ArticleStat(formatCount(detail.stats.views), "阅读")
        ArticleStat(formatCount(detail.stats.likes), "点赞")
        ArticleStat(formatCount(detail.stats.coins), "硬币")
        ArticleStat(formatCount(detail.stats.favorites), "收藏")
        ArticleStat(formatCount(detail.stats.comments), "评论")
    }
}

@Composable
private fun ArticleStat(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, style = MaterialTheme.typography.titleSmall)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ArticleFailure(message: String, onRetry: () -> Unit, onOpenWeb: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(message, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Button(onClick = onRetry) { Text("重试") }
        TextButton(onClick = onOpenWeb) { Text("在网页中打开") }
    }
}

private fun formatCount(count: Long): String = when {
    count >= 100_000_000 -> "%.1f亿".format(count / 100_000_000.0).replace(".0", "")
    count >= 10_000 -> "%.1f万".format(count / 10_000.0).replace(".0", "")
    else -> count.toString()
}
