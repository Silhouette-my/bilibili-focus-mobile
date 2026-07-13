package org.bilibilifocus.core.service

internal class ProtobufDecodingException(message: String) : Exception(message)

internal data class ProtobufTag(
    val fieldNumber: Int,
    val wireType: Int,
)

internal class ProtobufReader(private val bytes: ByteArray) {
    private var offset = 0

    val hasRemaining: Boolean get() = offset < bytes.size

    fun readTag(): ProtobufTag? {
        if (!hasRemaining) return null
        val raw = readVarint()
        val fieldNumber = (raw ushr 3).toInt()
        val wireType = (raw and 0x07).toInt()
        if (fieldNumber <= 0) throw ProtobufDecodingException("无效 protobuf 字段")
        return ProtobufTag(fieldNumber, wireType)
    }

    fun readVarint(): Long {
        var result = 0L
        var shift = 0
        while (shift < 64) {
            if (!hasRemaining) throw ProtobufDecodingException("protobuf varint 被截断")
            val value = bytes[offset++].toInt() and 0xff
            result = result or ((value and 0x7f).toLong() shl shift)
            if (value and 0x80 == 0) return result
            shift += 7
        }
        throw ProtobufDecodingException("protobuf varint 过长")
    }

    fun readLengthDelimited(): ByteArray {
        val length = readVarint()
        if (length < 0 || length > Int.MAX_VALUE) {
            throw ProtobufDecodingException("protobuf 字段长度无效")
        }
        val end = offset + length.toInt()
        if (end < offset || end > bytes.size) {
            throw ProtobufDecodingException("protobuf 字段被截断")
        }
        return bytes.copyOfRange(offset, end).also { offset = end }
    }

    fun readString(): String = readLengthDelimited().decodeToString()

    fun skip(tag: ProtobufTag) {
        when (tag.wireType) {
            0 -> readVarint()
            1 -> skipBytes(8)
            2 -> readLengthDelimited()
            5 -> skipBytes(4)
            else -> throw ProtobufDecodingException("不支持的 protobuf wire type: ${tag.wireType}")
        }
    }

    private fun skipBytes(count: Int) {
        val end = offset + count
        if (end < offset || end > bytes.size) {
            throw ProtobufDecodingException("protobuf 固定字段被截断")
        }
        offset = end
    }
}
