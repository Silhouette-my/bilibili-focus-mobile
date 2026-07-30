package org.bilibilifocus.android.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import org.bilibilifocus.core.service.BiliDiagnosticEvent
import org.bilibilifocus.core.service.BiliDiagnosticSnapshot
import org.bilibilifocus.core.service.BiliDiagnostics
import org.bilibilifocus.core.service.InMemoryNetworkEventSink
import org.bilibilifocus.core.service.LoginHealth
import org.bilibilifocus.core.service.LoginHealthService

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun FocusDiagnosticsScreen(
    loginHealthService: LoginHealthService,
    networkEvents: InMemoryNetworkEventSink,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    var refreshRevision by remember { mutableIntStateOf(0) }
    var state by remember(loginHealthService, networkEvents) {
        mutableStateOf<FocusDiagnosticsUiState>(FocusDiagnosticsUiState.Loading)
    }

    LaunchedEffect(loginHealthService, networkEvents, refreshRevision) {
        state = FocusDiagnosticsUiState.Loading
        state = try {
            val health = loginHealthService.check()
            FocusDiagnosticsUiState.Ready(
                BiliDiagnostics.snapshot(
                    loginHealth = health,
                    eventSink = networkEvents,
                ),
            )
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            FocusDiagnosticsUiState.Unavailable
        }
    }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text("登录与网络诊断") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "返回设置",
                        )
                    }
                },
                actions = {
                    IconButton(onClick = { refreshRevision += 1 }) {
                        Icon(Icons.Filled.Refresh, contentDescription = "刷新诊断")
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
            FocusDiagnosticsUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize().padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }

            FocusDiagnosticsUiState.Unavailable -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding)
                        .padding(32.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Text("诊断暂不可用", style = MaterialTheme.typography.titleLarge)
                        Text(
                            "未保留原始错误信息，请稍后重试。",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Button(onClick = { refreshRevision += 1 }) {
                            Text("重试")
                        }
                    }
                }
            }

            is FocusDiagnosticsUiState.Ready -> DiagnosticsContent(
                snapshot = current.snapshot,
                onShare = {
                    shareDiagnosticSnapshot(
                        context = context,
                        json = current.snapshot.toJson(prettyPrinted = true),
                    )
                },
                contentPadding = innerPadding,
            )
        }
    }
}

@Composable
private fun DiagnosticsContent(
    snapshot: BiliDiagnosticSnapshot,
    onShare: () -> Unit,
    contentPadding: PaddingValues,
) {
    val visibleEvents = snapshot.events.takeLast(MAXIMUM_VISIBLE_EVENTS).asReversed()
    LazyColumn(
        modifier = Modifier.fillMaxSize().padding(contentPadding),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            DiagnosticsCard {
                Text(
                    "登录状态",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    diagnosticHealthLabel(snapshot.loginHealth),
                    style = MaterialTheme.typography.headlineSmall,
                    color = diagnosticHealthColor(snapshot.loginHealth),
                )
                Text(
                    "状态来自只读登录探测，不展示账号、Cookie 或响应正文。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    "最近脱敏网络事件",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "${visibleEvents.size}/${snapshot.events.size}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        itemsIndexed(
            items = visibleEvents,
            key = { index, event ->
                "$index-${event.method}-${event.target}-${event.statusCode}-${event.durationMilliseconds}"
            },
        ) { _, event ->
            DiagnosticEventCard(event)
        }

        if (visibleEvents.isEmpty()) {
            item {
                DiagnosticsCard {
                    Text(
                        "暂无网络事件",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item {
            DiagnosticsCard {
                Text(
                    "隐私说明",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    "导出内容仅包含有限登录状态、HTTP 方法、无查询参数的目标、状态码、耗时、响应大小和归一化失败类型。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = onShare,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("导出脱敏诊断 JSON")
                }
            }
        }
    }
}

@Composable
private fun DiagnosticEventCard(event: BiliDiagnosticEvent) {
    DiagnosticsCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                event.method,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Bold,
            )
            Text(
                event.statusCode?.toString() ?: diagnosticFailureLabel(event.failureType),
                style = MaterialTheme.typography.labelLarge,
                color = if (event.statusCode in 200..299) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.error
                },
            )
        }
        Text(
            safeDiagnosticTarget(event.target),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            diagnosticEventMetadata(event),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DiagnosticsCard(content: @Composable ColumnScope.() -> Unit) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.elevatedCardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        elevation = CardDefaults.elevatedCardElevation(defaultElevation = 1.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content,
        )
    }
}

@Composable
private fun diagnosticHealthColor(health: LoginHealth) = when (health) {
    LoginHealth.HEALTHY -> MaterialTheme.colorScheme.primary
    LoginHealth.NOT_LOGGED_IN,
    LoginHealth.SESSION_EXPIRED,
    LoginHealth.MISSING_CSRF,
    LoginHealth.WBI_RISK_CONTROLLED,
    LoginHealth.NETWORK_UNAVAILABLE,
    LoginHealth.UNKNOWN,
    -> MaterialTheme.colorScheme.error
}

internal fun diagnosticHealthLabel(health: LoginHealth): String = when (health) {
    LoginHealth.NOT_LOGGED_IN -> "未登录"
    LoginHealth.SESSION_EXPIRED -> "登录状态已过期"
    LoginHealth.MISSING_CSRF -> "缺少 CSRF 凭据"
    LoginHealth.WBI_RISK_CONTROLLED -> "请求受到风控"
    LoginHealth.NETWORK_UNAVAILABLE -> "网络不可用"
    LoginHealth.HEALTHY -> "登录状态健康"
    LoginHealth.UNKNOWN -> "状态未知"
}

internal fun safeDiagnosticTarget(target: String): String =
    target.substringBefore('?').substringBefore('#')

internal fun diagnosticEventMetadata(event: BiliDiagnosticEvent): String = buildString {
    append(event.durationMilliseconds.coerceAtLeast(0))
    append(" ms")
    event.responseBytes?.let { bytes ->
        append(" · ")
        append(bytes.coerceAtLeast(0))
        append(" B")
    }
    event.failureType?.let { failure ->
        append(" · ")
        append(diagnosticFailureLabel(failure))
    }
}

private fun diagnosticFailureLabel(failureType: String?): String = when (failureType) {
    "cancelled" -> "已取消"
    "timeout" -> "超时"
    "network_unavailable" -> "网络不可用"
    "transport_error" -> "传输错误"
    else -> "无状态码"
}

private fun shareDiagnosticSnapshot(context: Context, json: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "application/json"
        putExtra(Intent.EXTRA_SUBJECT, "Bilibili Focus 脱敏诊断")
        putExtra(Intent.EXTRA_TEXT, json)
    }
    runCatching {
        context.startActivity(
            Intent.createChooser(sendIntent, "导出脱敏诊断"),
        )
    }
}

private sealed interface FocusDiagnosticsUiState {
    data object Loading : FocusDiagnosticsUiState
    data object Unavailable : FocusDiagnosticsUiState
    data class Ready(val snapshot: BiliDiagnosticSnapshot) : FocusDiagnosticsUiState
}

private const val MAXIMUM_VISIBLE_EVENTS = 50
