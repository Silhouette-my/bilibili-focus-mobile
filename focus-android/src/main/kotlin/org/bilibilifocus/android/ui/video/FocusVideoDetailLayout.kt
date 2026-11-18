package org.bilibilifocus.android.ui.video

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.movableContentOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

internal object FocusVideoDetailLayoutPolicy {
    // Leave at least 640dp for the video and a readable 320dp detail column.
    fun usesSidePanel(widthDp: Float, heightDp: Float): Boolean =
        widthDp >= 960f && heightDp >= 400f && widthDp >= heightDp * 1.15f

    fun sidePanelWidth(widthDp: Float): Float = (widthDp * 0.32f).coerceIn(320f, 420f)

    fun inlinePlayerHeight(widthDp: Float, heightDp: Float, aspectRatio: Float): Float =
        minOf(
            widthDp / aspectRatio,
            heightDp * when {
                aspectRatio < 1f -> 0.74f
                widthDp < 840f -> 0.46f
                else -> 0.58f
            },
        )
}

/** The same player slot is retained when a tablet window changes between one and two columns. */
@Composable
internal fun FocusVideoDetailLayout(
    videoAspectRatio: Float,
    scrollState: ScrollState,
    modifier: Modifier = Modifier,
    playerContent: @Composable () -> Unit,
    detailContent: @Composable () -> Unit,
) {
    val currentPlayer by rememberUpdatedState(playerContent)
    val currentDetails by rememberUpdatedState(detailContent)
    val retainedPlayer = remember { movableContentOf { currentPlayer() } }
    val retainedDetails = remember { movableContentOf { currentDetails() } }

    BoxWithConstraints(modifier.fillMaxSize()) {
        if (FocusVideoDetailLayoutPolicy.usesSidePanel(maxWidth.value, maxHeight.value)) {
            val sidePanelWidth = FocusVideoDetailLayoutPolicy.sidePanelWidth(maxWidth.value).dp
            Row(Modifier.fillMaxSize()) {
                Box(
                    Modifier.weight(1f).fillMaxHeight().background(Color.Black),
                    contentAlignment = Alignment.Center,
                ) {
                    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        val playerHeight = minOf(maxWidth / videoAspectRatio, maxHeight)
                        Box(Modifier.fillMaxWidth().height(playerHeight)) { retainedPlayer() }
                    }
                }
                Column(
                    Modifier.width(sidePanelWidth)
                        .fillMaxHeight().verticalScroll(scrollState),
                ) { retainedDetails() }
            }
        } else {
            val playerHeight = FocusVideoDetailLayoutPolicy.inlinePlayerHeight(
                maxWidth.value, maxHeight.value, videoAspectRatio,
            ).dp
            Column(Modifier.fillMaxSize().verticalScroll(scrollState)) {
                Box(Modifier.fillMaxWidth().height(playerHeight).background(Color.Black)) { retainedPlayer() }
                retainedDetails()
            }
        }
    }
}
