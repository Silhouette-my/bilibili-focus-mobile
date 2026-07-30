package org.bilibilifocus.core.service

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class JsonHelpersTests {
    @Test
    fun `long values preserve ids and cursors beyond Int range`() {
        val payload = Json.parseToJsonElement(
            """
            {
              "mid": 3547000000000000,
              "cursor": {"max": "9223372036854770000"}
            }
            """.trimIndent(),
        ) as JsonObject

        assertEquals(3_547_000_000_000_000L, payload.longValueAt("mid"))
        assertEquals(9_223_372_036_854_770_000L, payload.longValueAt("cursor", "max"))
        assertNull(payload.intValueAt("mid"))
    }
}
