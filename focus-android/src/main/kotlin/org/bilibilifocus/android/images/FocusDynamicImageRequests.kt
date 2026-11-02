package org.bilibilifocus.android.images

import android.content.Context
import coil.request.ImageRequest
import coil.size.Scale
import coil.size.Precision
import org.bilibilifocus.core.model.DynamicCard
import kotlin.math.roundToInt

/** One request description is used by both the card and its forward prefetch. */
internal data class FocusDynamicImageRequest(
    val source: String,
    val width: Int,
    val height: Int,
    val scale: Scale,
) {
    fun build(context: Context): ImageRequest = ImageRequest.Builder(context)
        .data(source)
        .size(width, height)
        .scale(scale)
        .precision(Precision.INEXACT)
        .tag(FocusDynamicImageRequest::class.java, this)
        .crossfade(true)
        .build()
}

internal data class FocusDynamicImageLayout(
    val contentWidth: Int,
    val avatarSize: Int,
    val imageGap: Int,
) {
    fun avatar(source: String?): FocusDynamicImageRequest? = source?.takeIf(String::isNotBlank)?.let {
        FocusDynamicImageRequest(FocusImageCDNRequest.canonicalURL(it), avatarSize, avatarSize, Scale.FILL)
    }

    fun cover(card: DynamicCard, source: String): FocusDynamicImageRequest {
        val single = card.coverURLs.size == 1
        val width = if (single) contentWidth else ((contentWidth - imageGap) / 2).coerceAtLeast(1)
        val aspectRatio = when {
            !single -> 1f
            card.kind == DynamicCard.Kind.IMAGE -> 4f / 3f
            else -> 16f / 9f
        }
        return FocusDynamicImageRequest(
            FocusImageCDNRequest.canonicalURL(source), width, (width / aspectRatio).roundToInt().coerceAtLeast(1),
            if (single && card.kind == DynamicCard.Kind.IMAGE) Scale.FIT else Scale.FILL,
        )
    }

    fun prefetchRequests(cards: List<DynamicCard>, firstVisibleCardID: String?): List<FocusDynamicImageRequest> {
        val start = firstVisibleCardID?.let { id -> cards.indexOfFirst { it.id == id }.takeIf { it >= 0 } } ?: 0
        return cards.asSequence().drop(start).take(8).flatMap { card ->
            sequence {
                avatar(card.author.avatarURL)?.let { yield(it) }
                card.coverURLs.take(2).forEach { yield(cover(card, it)) }
            }
        }.distinct().toList()
    }
}
