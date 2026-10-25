package org.bilibilifocus.core.service

import org.bilibilifocus.core.crypto.sha256Hex
import kotlin.test.Test
import kotlin.test.assertEquals

class SessionFingerprintTests {
    @Test
    fun `platform digest matches SHA256 known vectors`() {
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", sha256Hex(""))
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", sha256Hex("abc"))
    }
}
