package org.bilibilifocus.core.service

import org.bilibilifocus.core.model.VideoDanmaku
import org.bilibilifocus.core.model.VideoDanmakuMode
import org.bilibilifocus.core.model.VideoDanmakuSegment
import org.bilibilifocus.core.model.VideoDanmakuView

internal object VideoDanmakuDecoder {
    const val DEFAULT_SEGMENT_DURATION_MILLIS = 360_000L

    fun decodeView(bytes: ByteArray): VideoDanmakuView {
        if (bytes.isEmpty()) throw ProtobufDecodingException("弹幕视图为空")
        val reader = ProtobufReader(bytes)
        var state = 0
        var segmentDuration = DEFAULT_SEGMENT_DURATION_MILLIS
        var totalSegments = 0
        var count = 0L

        while (reader.hasRemaining) {
            val tag = reader.readTag() ?: break
            when {
                tag.fieldNumber == 1 && tag.wireType == 0 -> state = reader.readVarint().toInt()
                tag.fieldNumber == 4 && tag.wireType == 2 -> {
                    val segmentReader = ProtobufReader(reader.readLengthDelimited())
                    while (segmentReader.hasRemaining) {
                        val segmentTag = segmentReader.readTag() ?: break
                        when {
                            segmentTag.fieldNumber == 1 && segmentTag.wireType == 0 -> {
                                segmentDuration = segmentReader.readVarint().takeIf { it > 0 }
                                    ?: DEFAULT_SEGMENT_DURATION_MILLIS
                            }
                            segmentTag.fieldNumber == 2 && segmentTag.wireType == 0 -> {
                                totalSegments = segmentReader.readVarint().coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
                            }
                            else -> segmentReader.skip(segmentTag)
                        }
                    }
                }
                tag.fieldNumber == 8 && tag.wireType == 0 -> count = reader.readVarint()
                else -> reader.skip(tag)
            }
        }

        return VideoDanmakuView(
            state = state,
            segmentDurationMillis = segmentDuration,
            totalSegments = totalSegments,
            count = count,
        )
    }

    fun decodeSegment(bytes: ByteArray): VideoDanmakuSegment {
        if (bytes.contentEquals(byteArrayOf(0x10, 0x01))) {
            return VideoDanmakuSegment(emptyList(), isClosed = true)
        }
        if (bytes.isEmpty()) return VideoDanmakuSegment(emptyList())

        val reader = ProtobufReader(bytes)
        val danmakus = mutableListOf<VideoDanmaku>()
        while (reader.hasRemaining) {
            val tag = reader.readTag() ?: break
            if (tag.fieldNumber == 1 && tag.wireType == 2) {
                decodeElement(reader.readLengthDelimited())?.let(danmakus::add)
            } else {
                reader.skip(tag)
            }
        }
        return VideoDanmakuSegment(
            danmakus = danmakus.sortedWith(
                compareBy<VideoDanmaku> { it.progressMillis }
                    .thenByDescending { it.weight }
                    .thenBy { it.id }
            )
        )
    }

    private fun decodeElement(bytes: ByteArray): VideoDanmaku? {
        val reader = ProtobufReader(bytes)
        var id = 0L
        var progressMillis = 0L
        var mode: VideoDanmakuMode? = null
        var fontSize = 25
        var colorRgb: Int? = 0xffffff
        var content = ""
        var weight = 0
        var pool = 0

        while (reader.hasRemaining) {
            val tag = reader.readTag() ?: break
            when {
                tag.fieldNumber == 1 && tag.wireType == 0 -> id = reader.readVarint()
                tag.fieldNumber == 2 && tag.wireType == 0 -> progressMillis = reader.readVarint()
                tag.fieldNumber == 3 && tag.wireType == 0 -> {
                    mode = VideoDanmakuMode.fromRawValue(reader.readVarint().toInt())
                }
                tag.fieldNumber == 4 && tag.wireType == 0 -> fontSize = reader.readVarint().toInt()
                tag.fieldNumber == 5 && tag.wireType == 0 -> {
                    val rawColor = reader.readVarint().toInt()
                    colorRgb = if (rawColor == 60_001) null else rawColor and 0xffffff
                }
                tag.fieldNumber == 7 && tag.wireType == 2 -> content = reader.readString()
                tag.fieldNumber == 9 && tag.wireType == 0 -> weight = reader.readVarint().toInt()
                tag.fieldNumber == 11 && tag.wireType == 0 -> pool = reader.readVarint().toInt()
                else -> reader.skip(tag)
            }
        }

        val resolvedMode = mode ?: return null
        if (content.isBlank()) return null
        return VideoDanmaku(
            id = id,
            progressMillis = progressMillis,
            mode = resolvedMode,
            fontSize = fontSize.coerceIn(12, 64),
            colorRgb = colorRgb,
            content = content,
            weight = weight,
            pool = pool,
        )
    }
}
