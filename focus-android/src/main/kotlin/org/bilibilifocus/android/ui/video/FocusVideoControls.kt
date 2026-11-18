package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import org.bilibilifocus.android.R
import org.bilibilifocus.core.model.VideoInfo
import org.bilibilifocus.core.model.VideoInteractionState

@Composable
internal fun VideoActionBar(
    interactionState: VideoInteractionState,
    info: VideoInfo,
    onToggleLike: () -> Unit,
    onCoin: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(
                MaterialTheme.colorScheme.surfaceVariant.copy(
                    alpha = if (MaterialTheme.colorScheme.background.luminance() < 0.5f) 0.72f else 0.86f,
                )
            )
            .padding(horizontal = 6.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_like),
            value = formatVideoCount(info.stats.likes),
            active = interactionState.liked,
            onClick = onToggleLike,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_coin),
            value = formatVideoCount(info.stats.coins),
            active = interactionState.coined,
            onClick = onCoin,
            enabled = !interactionState.loading && !interactionState.coined,
            modifier = Modifier.weight(1f),
        )
        VerticalDivider()
        ActionMetricButton(
            painter = painterResource(R.drawable.ic_bili_fav),
            value = formatVideoCount(info.stats.favorites),
            active = interactionState.favorited,
            onClick = onToggleFavorite,
            enabled = !interactionState.loading,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun ActionMetricButton(
    painter: Painter,
    value: String,
    active: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 8.dp),
        colors = ButtonDefaults.textButtonColors(
            contentColor = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            disabledContentColor = MaterialTheme.colorScheme.outline,
        ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                painter = painter,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
            Text(
                value,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun VerticalDivider() {
    Box(
        modifier = Modifier
            .width(1.dp)
            .height(20.dp)
            .background(MaterialTheme.colorScheme.outlineVariant),
    )
}


internal fun formatVideoCount(count: Long): String = when {
    count >= 100_000_000L -> {
        "%.1f亿".format(count / 100_000_000.0).replace(".0亿", "亿")
    }
    count >= 10000L -> {
        "%.1f万".format(count / 10_000.0).replace(".0万", "万")
    }
    else -> count.toString()
}
