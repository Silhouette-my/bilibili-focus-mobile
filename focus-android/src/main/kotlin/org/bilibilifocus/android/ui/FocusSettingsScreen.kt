package org.bilibilifocus.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import org.bilibilifocus.android.AndroidCookieProvider
import org.bilibilifocus.android.FocusFollowingAuthorsViewModel
import org.bilibilifocus.android.FocusSettingsViewModel
import org.bilibilifocus.android.FollowingAuthorsUiState
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.model.FocusDynamicFilterKind
import org.bilibilifocus.core.model.FocusEntry
import org.bilibilifocus.core.model.FocusSettings
import org.bilibilifocus.core.model.FocusThemeMode
import org.bilibilifocus.core.service.FollowingAuthorsService
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.android.ui.theme.focusAccentColor

private val AccentColorPresets = listOf(
    "#FB7299",
    "#FF5C5C",
    "#FF9500",
    "#34C759",
    "#00A1D6",
    "#5856D6",
)

@Composable
fun FocusSettingsScreen(
    settings: FocusSettings,
    knownAuthors: List<DynamicCard.Author>,
    onBack: () -> Unit,
    onUpdate: ((FocusSettings) -> FocusSettings) -> Unit,
    onSetAuthorKind: (DynamicCard.Author, FocusDynamicFilterKind, Boolean) -> Unit,
    authorKinds: (DynamicCard.Author) -> Set<FocusDynamicFilterKind>,
    onReset: () -> Unit,
) {
    var showAuthorSettings by remember { mutableStateOf(false) }
    val authorsViewModel = remember {
        FocusFollowingAuthorsViewModel(
            service = FollowingAuthorsService(
                cookieProvider = AndroidCookieProvider(),
                httpClient = KtorHttpClient(),
            ),
            fallbackAuthors = knownAuthors,
        )
    }
    DisposableEffect(authorsViewModel) {
        onDispose { authorsViewModel.onCleared() }
    }
    BackHandler(enabled = showAuthorSettings) { showAuthorSettings = false }

    if (showAuthorSettings) {
        DynamicAuthorSettingsScreen(
            viewModel = authorsViewModel,
            onBack = { showAuthorSettings = false },
            onSetAuthorKind = onSetAuthorKind,
            authorKinds = authorKinds,
        )
    } else {
        SettingsHomeScreen(
            settings = settings,
            onBack = onBack,
            onUpdate = onUpdate,
            onOpenAuthorSettings = { showAuthorSettings = true },
            onReset = onReset,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsHomeScreen(
    settings: FocusSettings,
    onBack: () -> Unit,
    onUpdate: ((FocusSettings) -> FocusSettings) -> Unit,
    onOpenAuthorSettings: () -> Unit,
    onReset: () -> Unit,
) {
    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("设置") },
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
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(innerPadding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            item {
                SettingsSection(title = "入口与主题") {
                    Text("默认入口", style = MaterialTheme.typography.titleSmall)
                    SettingsChoiceRow(
                        values = FocusEntry.entries,
                        selected = settings.defaultEntry,
                        title = { it.title },
                        onSelect = { entry -> onUpdate { it.copy(defaultEntry = entry) } },
                    )

                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                    Text("主题", style = MaterialTheme.typography.titleSmall)
                    SettingsChoiceRow(
                        values = FocusThemeMode.entries,
                        selected = settings.themeMode,
                        title = { it.title },
                        onSelect = { mode -> onUpdate { it.copy(themeMode = mode) } },
                    )

                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                    Text("强调色", style = MaterialTheme.typography.titleSmall)
                    AccentColorSettings(
                        accentColorHex = settings.accentColorHex,
                        onAccentColorChange = { hex ->
                            onUpdate { it.copy(accentColorHex = hex) }
                        },
                    )
                }
            }

            item {
                SettingsSection(title = "规则") {
                    SettingsSwitchRow(
                        title = "首页重定向",
                        checked = settings.redirectEnabled,
                        onCheckedChange = { enabled -> onUpdate { it.copy(redirectEnabled = enabled) } },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    SettingsSwitchRow(
                        title = "动态详情页去干扰",
                        checked = settings.dynamicMaskEnabled,
                        onCheckedChange = { enabled -> onUpdate { it.copy(dynamicMaskEnabled = enabled) } },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    SettingsSwitchRow(
                        title = "搜索结果页去干扰",
                        checked = settings.searchMaskEnabled,
                        onCheckedChange = { enabled -> onUpdate { it.copy(searchMaskEnabled = enabled) } },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    SettingsSwitchRow(
                        title = "播放页去干扰",
                        checked = settings.playerMaskEnabled,
                        onCheckedChange = { enabled -> onUpdate { it.copy(playerMaskEnabled = enabled) } },
                    )
                }
            }

            item {
                SettingsSection(title = "播放") {
                    SettingsSwitchRow(
                        title = "原生播放器默认显示弹幕",
                        checked = settings.nativeDanmakuEnabled,
                        onCheckedChange = { enabled -> onUpdate { it.copy(nativeDanmakuEnabled = enabled) } },
                    )
                }
            }

            item {
                SettingsSection(title = "动态分类") {
                    SettingsNavigationRow(
                        title = "关注 UP 主动态配置",
                        subtitle = "分别选择每位 UP 主要保留的视频或图文动态",
                        onClick = onOpenAuthorSettings,
                    )
                }
            }

            item {
                SettingsSection(title = "高级") {
                    SettingsSwitchRow(
                        title = "调试日志",
                        checked = settings.debugMode,
                        onCheckedChange = { enabled -> onUpdate { it.copy(debugMode = enabled) } },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    TextButton(
                        onClick = onReset,
                        colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    ) {
                        Text("恢复默认设置")
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DynamicAuthorSettingsScreen(
    viewModel: FocusFollowingAuthorsViewModel,
    onBack: () -> Unit,
    onSetAuthorKind: (DynamicCard.Author, FocusDynamicFilterKind, Boolean) -> Unit,
    authorKinds: (DynamicCard.Author) -> Set<FocusDynamicFilterKind>,
) {
    LaunchedEffect(Unit) { viewModel.loadIfNeeded() }
    val state by viewModel.state.collectAsState()
    var query by remember { mutableStateOf("") }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("UP 主动态配置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回设置")
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
            FollowingAuthorsUiState.Idle, FollowingAuthorsUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            is FollowingAuthorsUiState.Failed -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding).padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Text("关注列表加载失败", style = MaterialTheme.typography.headlineSmall)
                        Text(
                            current.message,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                        Button(onClick = viewModel::reload) { Text("重试") }
                    }
                }
            }

            is FollowingAuthorsUiState.Loaded -> {
                val keyword = query.trim()
                val visibleAuthors = if (keyword.isEmpty()) {
                    current.authors
                } else {
                    current.authors.filter { author ->
                        author.name.contains(keyword, ignoreCase = true) ||
                            author.mid.toString().contains(keyword)
                    }
                }
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            OutlinedTextField(
                                value = query,
                                onValueChange = { query = it },
                                modifier = Modifier.fillMaxWidth(),
                                singleLine = true,
                                label = { Text("搜索 UP 主或 UID") },
                                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                            )
                            Text(
                                "已读取 ${current.authors.size} 位关注 UP 主",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            current.notice?.let { notice ->
                                Text(
                                    notice,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.error,
                                )
                            }
                        }
                    }

                    items(visibleAuthors, key = { FocusSettingsViewModel.authorFilterKey(it) }) { author ->
                        AuthorDynamicSettingsCard(
                            author = author,
                            selectedKinds = authorKinds(author),
                            onSetKind = { kind, enabled -> onSetAuthorKind(author, kind, enabled) },
                        )
                    }

                    if (visibleAuthors.isEmpty()) {
                        item {
                            Box(
                                modifier = Modifier.fillMaxWidth().padding(32.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    if (query.isBlank()) "关注列表为空" else "没有匹配的 UP 主",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
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
private fun SettingsSection(
    title: String? = null,
    content: @Composable () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (title != null) {
            Text(
                title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 2.dp),
            )
        }
        ElevatedCard(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(18.dp),
            colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
        ) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                content = { content() },
            )
        }
    }
}

@Composable
private fun <T> SettingsChoiceRow(
    values: List<T>,
    selected: T,
    title: (T) -> String,
    onSelect: (T) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        values.forEach { value ->
            FilterChip(
                selected = value == selected,
                onClick = { onSelect(value) },
                label = {
                    Text(
                        title(value),
                        modifier = Modifier.fillMaxWidth(),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.Center,
                    )
                },
                modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                ),
            )
        }
    }
}

@Composable
private fun AccentColorSettings(
    accentColorHex: String,
    onAccentColorChange: (String) -> Unit,
) {
    var input by remember(accentColorHex) { mutableStateOf(accentColorHex) }
    val previewHex = FocusSettings.normalizedAccentColorHex(input) ?: accentColorHex

    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(AccentColorPresets, key = { it }) { hex ->
                val selected = hex.equals(accentColorHex, ignoreCase = true)
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(focusAccentColor(hex))
                        .border(
                            width = if (selected) 3.dp else 1.dp,
                            color = if (selected) {
                                MaterialTheme.colorScheme.onSurface
                            } else {
                                MaterialTheme.colorScheme.outline
                            },
                            shape = CircleShape,
                        )
                        .clickable {
                            input = hex
                            onAccentColorChange(hex)
                        },
                )
            }
        }

        OutlinedTextField(
            value = input,
            onValueChange = { rawValue ->
                val trimmed = rawValue.trim().uppercase()
                val digits = trimmed
                    .removePrefix("#")
                    .filter { it.digitToIntOrNull(16) != null }
                    .take(6)
                input = if (trimmed.startsWith("#")) "#$digits" else digits
                FocusSettings.normalizedAccentColorHex(input)?.let(onAccentColorChange)
            },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            label = { Text("自定义 HEX") },
            leadingIcon = {
                Box(
                    modifier = Modifier
                        .size(22.dp)
                        .clip(CircleShape)
                        .background(focusAccentColor(previewHex))
                        .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape),
                )
            },
            supportingText = {
                Text("输入 6 位颜色值，例如 #00A1D6")
            },
        )
    }
}

@Composable
private fun SettingsSwitchRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable { onCheckedChange(!checked) },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun SettingsNavigationRow(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun AuthorDynamicSettingsCard(
    author: DynamicCard.Author,
    selectedKinds: Set<FocusDynamicFilterKind>,
    onSetKind: (FocusDynamicFilterKind, Boolean) -> Unit,
) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.elevatedCardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current)
                        .data(author.avatarURL)
                        .crossfade(true)
                        .build(),
                    contentDescription = null,
                    modifier = Modifier.size(44.dp).clip(CircleShape),
                    contentScale = ContentScale.Crop,
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        author.name,
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (author.mid > 0L) {
                        Text(
                            "UID ${author.mid}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf(FocusDynamicFilterKind.VIDEO, FocusDynamicFilterKind.ARTICLE_LIKE).forEach { kind ->
                    FilterChip(
                        selected = kind in selectedKinds,
                        onClick = { onSetKind(kind, kind !in selectedKinds) },
                        label = {
                            Text(
                                kind.title,
                                modifier = Modifier.fillMaxWidth(),
                                textAlign = TextAlign.Center,
                            )
                        },
                        modifier = Modifier.weight(1f).heightIn(min = 44.dp),
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                            selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        ),
                    )
                }
            }
        }
    }
}
