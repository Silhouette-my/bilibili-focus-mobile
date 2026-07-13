package org.bilibilifocus.android.ui

import android.animation.ValueAnimator
import android.graphics.drawable.Animatable
import android.webkit.CookieManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import coil.request.ImageRequest
import coil.size.Precision
import coil.size.Size
import org.bilibilifocus.core.model.RichTextRun

data class FocusImageGalleryRequest(
    val images: List<String>,
    val initialIndex: Int,
    val referer: String,
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FocusRichText(
    runs: List<RichTextRun>,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    onOpenURL: (String) -> Unit = {},
) {
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.Start,
        verticalArrangement = Arrangement.Center,
    ) {
        runs.forEachIndexed { index, run ->
            when (run) {
                is RichTextRun.Text -> {
                    val explicitColor = run.color?.let(::parseRichTextColor)
                    Text(
                        text = run.text,
                        style = style.copy(
                            fontWeight = if (run.bold) FontWeight.Bold else style.fontWeight,
                            fontStyle = if (run.italic) FontStyle.Italic else style.fontStyle,
                            textDecoration = when {
                                run.underline && run.strikethrough -> TextDecoration.combine(listOf(TextDecoration.Underline, TextDecoration.LineThrough))
                                run.underline -> TextDecoration.Underline
                                run.strikethrough -> TextDecoration.LineThrough
                                else -> style.textDecoration
                            },
                            color = when {
                                run.linkUrl != null -> MaterialTheme.colorScheme.primary
                                explicitColor != null -> explicitColor
                                else -> style.color
                            },
                        ),
                        modifier = if (run.linkUrl != null) Modifier.pointerInput(run.linkUrl) {
                            detectTapGestures { onOpenURL(requireNotNull(run.linkUrl)) }
                        } else Modifier,
                    )
                }

                is RichTextRun.Emote -> {
                    var failed by remember(run.url) { mutableStateOf(false) }
                    if (failed) {
                        Text(text = run.alt, style = style)
                    } else {
                        val cookie = remember(run.url) { CookieManager.getInstance().getCookie(run.url) }
                        AsyncImage(
                            model = ImageRequest.Builder(LocalContext.current)
                                .data(run.url)
                                .addHeader("Referer", "https://www.bilibili.com/")
                                .apply { if (!cookie.isNullOrBlank()) addHeader("Cookie", cookie) }
                                .crossfade(false)
                                .build(),
                            contentDescription = run.alt,
                            modifier = Modifier
                                .padding(horizontal = 1.dp)
                                .size(24.dp),
                            contentScale = ContentScale.Fit,
                            onError = { failed = true },
                            onSuccess = { result ->
                                if (!ValueAnimator.areAnimatorsEnabled()) {
                                    (result.result.drawable as? Animatable)?.stop()
                                }
                            },
                        )
                    }
                }

                is RichTextRun.Resource -> Text(
                    text = run.label,
                    style = style.copy(
                        color = MaterialTheme.colorScheme.primary,
                        textDecoration = TextDecoration.Underline,
                    ),
                    modifier = Modifier.pointerInput("resource-$index-${run.url}") {
                        detectTapGestures { onOpenURL(run.url) }
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FocusImageGallery(
    request: FocusImageGalleryRequest,
    onDismiss: () -> Unit,
) {
    val images = request.images.filter(String::isNotBlank)
    if (images.isEmpty()) return
    val initialIndex = request.initialIndex.coerceIn(images.indices)
    val pagerState = rememberPagerState(initialPage = initialIndex, pageCount = { images.size })
    BackHandler(onBack = onDismiss)

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        Box(modifier = Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize(),
                key = { images[it] + "#$it" },
            ) { page ->
                ZoomableGalleryImage(
                    url = images[page],
                    referer = request.referer,
                    resetKey = pagerState.currentPage,
                )
            }

            IconButton(
                onClick = onDismiss,
                modifier = Modifier.align(Alignment.TopStart).padding(top = 36.dp, start = 12.dp),
            ) {
                Icon(Icons.Default.Close, contentDescription = "关闭", tint = Color.White)
            }

            Text(
                text = "${pagerState.currentPage + 1} / ${images.size}",
                style = MaterialTheme.typography.labelLarge,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 48.dp)
                    .background(Color.Black.copy(alpha = 0.45f), MaterialTheme.shapes.extraLarge)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
    }
}

@Composable
private fun ZoomableGalleryImage(url: String, referer: String, resetKey: Int) {
    var userScale by remember(url) { mutableFloatStateOf(1f) }
    var offset by remember(url) { mutableStateOf(Offset.Zero) }
    var imageAspectRatio by remember(url) { mutableStateOf<Float?>(null) }
    val sourceURL = remember(url) { originalGalleryImageURL(url) }

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().clipToBounds(),
        contentAlignment = Alignment.Center,
    ) {
        val viewportWidth = constraints.maxWidth.toFloat().coerceAtLeast(1f)
        val viewportHeight = constraints.maxHeight.toFloat().coerceAtLeast(1f)
        val viewportAspect = viewportWidth / viewportHeight
        val imageAspect = imageAspectRatio
        val usesWidthFittedLongLayout = imageAspect != null && imageAspect < 0.5f && imageAspect < viewportAspect
        val baseScale = if (usesWidthFittedLongLayout) viewportAspect / requireNotNull(imageAspect) else 1f
        val totalScale = baseScale * userScale
        val topAlignmentOffset = if (usesWidthFittedLongLayout) {
            (viewportHeight * (totalScale - 1f) / 2f).coerceAtLeast(0f)
        } else {
            0f
        }

        LaunchedEffect(resetKey) {
            userScale = 1f
            offset = Offset.Zero
        }

        val transformState = rememberTransformableState { zoomChange, panChange, _ ->
            val nextScale = (userScale * zoomChange).coerceIn(1f, 5f)
            userScale = nextScale
            offset = clampGalleryOffset(
                proposed = offset + panChange,
                viewportWidth = viewportWidth,
                viewportHeight = viewportHeight,
                baseScale = baseScale,
                userScale = nextScale,
                isLongImage = usesWidthFittedLongLayout,
            )
        }

        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(sourceURL)
                .size(Size.ORIGINAL)
                .precision(Precision.EXACT)
                .memoryCacheKey("focus-gallery-original:$sourceURL")
                .allowHardware(false)
                .addHeader("Referer", referer)
                .apply {
                    CookieManager.getInstance().getCookie(sourceURL)?.takeIf(String::isNotBlank)?.let { cookie ->
                        addHeader("Cookie", cookie)
                    }
                }
                .crossfade(true)
                .build(),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = totalScale
                    scaleY = totalScale
                    translationX = offset.x
                    translationY = topAlignmentOffset + offset.y
                }
                .pointerInput(sourceURL, userScale) {
                    detectTapGestures(
                        onDoubleTap = {
                            userScale = if (userScale > 1.1f) 1f else 2.5f
                            offset = Offset.Zero
                        }
                    )
                }
                .transformable(transformState),
            onSuccess = { result ->
                val drawable = result.result.drawable
                val width = drawable.intrinsicWidth
                val height = drawable.intrinsicHeight
                if (width > 0 && height > 0) {
                    imageAspectRatio = width.toFloat() / height.toFloat()
                }
            },
        )
    }
}

private fun clampGalleryOffset(
    proposed: Offset,
    viewportWidth: Float,
    viewportHeight: Float,
    baseScale: Float,
    userScale: Float,
    isLongImage: Boolean,
): Offset {
    val totalScale = baseScale * userScale
    return if (isLongImage) {
        val maxHorizontal = (viewportWidth * (userScale - 1f) / 2f).coerceAtLeast(0f)
        val verticalOverflow = (viewportHeight * (totalScale - 1f)).coerceAtLeast(0f)
        Offset(
            x = proposed.x.coerceIn(-maxHorizontal, maxHorizontal),
            y = proposed.y.coerceIn(-verticalOverflow, 0f),
        )
    } else {
        val maxHorizontal = (viewportWidth * (totalScale - 1f) / 2f).coerceAtLeast(0f)
        val maxVertical = (viewportHeight * (totalScale - 1f) / 2f).coerceAtLeast(0f)
        Offset(
            x = proposed.x.coerceIn(-maxHorizontal, maxHorizontal),
            y = proposed.y.coerceIn(-maxVertical, maxVertical),
        )
    }
}

private fun originalGalleryImageURL(url: String): String =
    url.replace(Regex("""@[^/?#]+"""), "")

private fun parseRichTextColor(raw: String): Color? = runCatching {
    Color(android.graphics.Color.parseColor(raw.trim()))
}.getOrNull()
