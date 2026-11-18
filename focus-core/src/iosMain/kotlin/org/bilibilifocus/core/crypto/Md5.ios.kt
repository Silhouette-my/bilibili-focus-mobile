package org.bilibilifocus.core.crypto

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.allocArray
import kotlinx.cinterop.get
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.set
import platform.CoreCrypto.CC_MD5
import platform.CoreCrypto.CC_MD5_DIGEST_LENGTH

@OptIn(ExperimentalForeignApi::class)
actual fun md5Hex(input: String): String = memScoped {
    val bytes = input.encodeToByteArray()
    val inputBuffer = allocArray<UByteVar>(bytes.size.coerceAtLeast(1))
    bytes.forEachIndexed { index, byte ->
        inputBuffer[index] = byte.toUByte()
    }
    val digestLength = CC_MD5_DIGEST_LENGTH.toInt()
    val digestBuffer = allocArray<UByteVar>(digestLength)
    CC_MD5(inputBuffer, bytes.size.toUInt(), digestBuffer)

    buildString(digestLength * 2) {
        repeat(digestLength) { index ->
            val byte = digestBuffer[index].toInt()
            append(HEX_DIGITS[byte ushr 4])
            append(HEX_DIGITS[byte and 0x0F])
        }
    }
}

private const val HEX_DIGITS = "0123456789abcdef"
