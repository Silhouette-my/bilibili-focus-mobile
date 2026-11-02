package org.bilibilifocus.core.service

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BiliApiContractTests {
    @Test
    fun `loads the attributed sibling snapshot`() {
        val snapshot = BiliApiContractCatalog.snapshot

        assertEquals(1, snapshot.schemaVersion)
        assertTrue(snapshot.endpoints.size >= 40)
        assertEquals(40, snapshot.source.validatedCommit.length)
        assertTrue(snapshot.source.repository.contains("github.com/Nemo2011/bilibili-api"))
    }

    @Test
    fun `exposes verified endpoint metadata`() {
        val endpoint = BiliApiContractCatalog.require("video.info.get_player_info")

        assertEquals("https://api.bilibili.com/x/player/wbi/v2", endpoint.url)
        assertEquals("GET", endpoint.method)
        assertTrue(endpoint.requiresAuthentication)
        assertTrue(endpoint.usesWbi)
    }

    @Test
    fun `includes authenticated management contracts and excludes removed features`() {
        assertTrue(BiliApiContractCatalog.require("common.comment.send").usesWbi)
        assertTrue(BiliApiContractCatalog.require("common.comment.del").requiresAuthentication)
        assertEquals("POST", BiliApiContractCatalog.require("favorite-list.operate.content_move").method)
        assertTrue(BiliApiContractCatalog.snapshot.endpoints.keys.none { it.startsWith("toview.") })
    }
}
