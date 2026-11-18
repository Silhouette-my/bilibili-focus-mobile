package org.bilibilifocus.android.ui

import android.animation.ValueAnimator
import android.graphics.drawable.Animatable
import android.webkit.CookieManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.foundation.text.selection.SelectionContainer
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
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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

internal data class RichTextEmoteEntry(
    val id: String,
    val run: RichTextRun.Emote,
)

internal data class RichTextContentModel(
    val annotatedString: AnnotatedString,
    val emotes: List<RichTextEmoteEntry>,
)

internal fun buildRichTextContent(
    runs: List<RichTextRun>,
    linkColor: Color,
    onOpenURL: (String) -> Unit = {},
): RichTextContentModel {
    val emotes = mutableListOf<RichTextEmoteEntry>()
    val annotated = buildAnnotatedString {
        runs.forEachIndexed { index, run ->
            when (run) {
                is RichTextRun.Text -> {
                    val explicitColor = run.color?.let(::parseRichTextColor)
                    val spanStyle = SpanStyle(
                        fontWeight = if (run.bold) FontWeight.Bold else null,
                        fontStyle = if (run.italic) FontStyle.Italic else null,
                        textDecoration = when {
                            run.underline && run.strikethrough -> TextDecoration.combine(
                                listOf(TextDecoration.Underline, TextDecoration.LineThrough),
                            )
                            run.underline -> TextDecoration.Underline
                            run.strikethrough -> TextDecoration.LineThrough
                            else -> null
                        },
                        color = when {
                            run.linkUrl != null -> linkColor
                            explicitColor != null -> explicitColor
                            else -> Color.Unspecified
                        },
                    )
                    val linkUrl = run.linkUrl
                    if (linkUrl != null) {
                        withLink(
                            LinkAnnotation.Clickable(
                                tag = "link-$index",
                                styles = TextLinkStyles(style = spanStyle),
                                linkInteractionListener = { onOpenURL(linkUrl) },
                            ),
                        ) {
                            append(run.text)
                        }
                    } else {
                        withStyle(spanStyle) {
                            append(run.text)
                        }
                    }
                }

                is RichTextRun.Emote -> {
                    val id = "emote-$index"
                    appendInlineContent(id = id, alternateText = run.alt.ifEmpty { "[表情]" })
                    emotes += RichTextEmoteEntry(id = id, run = run)
                }

                is RichTextRun.Resource -> {
                    withLink(
                        LinkAnnotation.Clickable(
                            tag = "resource-$index",
                            styles = TextLinkStyles(
                                style = SpanStyle(
                                    color = linkColor,
                                    textDecoration = TextDecoration.Underline,
                                ),
                            ),
                            linkInteractionListener = { onOpenURL(run.url) },
                        ),
                    ) {
                        append(run.label)
                    }
                }
            }
        }
    }
    return RichTextContentModel(annotatedString = annotated, emotes = emotes)
}

@Composable
fun FocusRichText(
    runs: List<RichTextRun>,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    onOpenURL: (String) -> Unit = {},
    selectable: Boolean = false,
) {
    if (runs.isEmpty()) return
    val linkColor = MaterialTheme.colorScheme.primary
    val model = remember(runs, linkColor, onOpenURL) {
        buildRichTextContent(runs = runs, linkColor = linkColor, onOpenURL = onOpenURL)
    }
    val emoteSize = if (style.fontSize.isSp) {
        (style.fontSize.value * 1.35f).coerceIn(18f, 28f).sp
    } else {
        22.sp
    }
    val inlineContent = remember(model.emotes, emoteSize, style) {
        model.emotes.associate { entry ->
            entry.id to InlineTextContent(
                placeholder = Placeholder(
                    width = emoteSize,
                    height = emoteSize,
                    placeholderVerticalAlign = PlaceholderVerticalAlign.Center,
                ),
            ) {
                RichTextEmoteImage(run = entry.run, style = style)
            }
        }
    }

    if (selectable) {
        SelectionContainer {
            Text(
                text = model.annotatedString,
                inlineContent = inlineContent,
                modifier = modifier,
                style = style,
            )
        }
    } else {
        Text(
            text = model.annotatedString,
            inlineContent = inlineContent,
            modifier = modifier,
            style = style,
        )
    }
}

@Composable
private fun RichTextEmoteImage(
    run: RichTextRun.Emote,
    style: TextStyle,
) {
    var failed by remember(run.url) { mutableStateOf(false) }
    if (failed) {
        Text(text = run.alt, style = style)
        return
    }
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
            .fillMaxSize()
            .padding(horizontal = 1.dp),
        contentScale = ContentScale.Fit,
        onError = { failed = true },
        onSuccess = { result ->
            if (!ValueAnimator.areAnimatorsEnabled()) {
                (result.result.drawable as? Animatable)?.stop()
            }
        },
    )
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
