package org.bilibilifocus.core.paging

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class CursorPagerTests {
    @Test
    fun `deduplicates items and stops a repeated cursor`() = runTest {
        val pager = CursorPager<Item, String, Long>(
            firstCursor = "first",
            keyOf = Item::id,
        ) { cursor ->
            when (cursor) {
                "first" -> CursorPage(listOf(Item(1), Item(2)), "next")
                else -> CursorPage(listOf(Item(2), Item(3)), "next")
            }
        }

        pager.refresh()
        pager.append()

        assertEquals(listOf(1L, 2L, 3L), pager.state.value.items.map(Item::id))
        assertTrue(pager.state.value.endReached)
        assertFalse(pager.state.value.isAppending)
    }

    @Test
    fun `refresh invalidates an older append result`() = runTest {
        val appendGate = CompletableDeferred<Unit>()
        var firstPageRevision = 0
        val pager = CursorPager<Item, String, Long>(
            firstCursor = "first",
            keyOf = Item::id,
        ) { cursor ->
            if (cursor == "next") {
                appendGate.await()
                CursorPage(listOf(Item(99)), null)
            } else {
                firstPageRevision += 1
                CursorPage(listOf(Item(firstPageRevision.toLong())), "next")
            }
        }

        pager.refresh()
        val append = async { pager.append() }
        runCurrent()
        pager.refresh()
        appendGate.complete(Unit)
        append.await()

        assertEquals(listOf(2L), pager.state.value.items.map(Item::id))
    }

    @Test
    fun `append error preserves content and becomes retryable`() = runTest {
        var shouldFail = true
        val pager = CursorPager<Item, Int, Long>(
            firstCursor = 1,
            keyOf = Item::id,
        ) { cursor ->
            if (cursor == 1) {
                CursorPage(listOf(Item(1)), 2)
            } else if (shouldFail) {
                error("temporary")
            } else {
                CursorPage(listOf(Item(2)), null)
            }
        }

        pager.refresh()
        pager.append()
        assertEquals("temporary", pager.state.value.appendError)
        assertEquals(listOf(1L), pager.state.value.items.map(Item::id))

        shouldFail = false
        pager.append()
        assertEquals(listOf(1L, 2L), pager.state.value.items.map(Item::id))
        assertEquals(null, pager.state.value.appendError)
    }
}

private data class Item(val id: Long)
