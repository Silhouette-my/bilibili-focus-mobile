package org.bilibilifocus.core.paging

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class CursorPage<Item, Cursor>(
    val items: List<Item>,
    val nextCursor: Cursor?,
)

data class PagedState<Item>(
    val items: List<Item> = emptyList(),
    val isRefreshing: Boolean = false,
    val isAppending: Boolean = false,
    val endReached: Boolean = false,
    val refreshError: String? = null,
    val appendError: String? = null,
    val refreshCause: Throwable? = null,
    val appendCause: Throwable? = null,
)

/**
 * Generation-guarded cursor pager shared by feed, history, comments, and
 * numbered endpoints. Refresh invalidates in-flight append results; repeated
 * cursors terminate pagination instead of creating request loops.
 */
class CursorPager<Item : Any, Cursor : Any, Key : Any>(
    private val firstCursor: Cursor?,
    private val keyOf: (Item) -> Key,
    private val loadPage: suspend (Cursor?) -> CursorPage<Item, Cursor>,
) {
    private val mutex = Mutex()
    private val _state = MutableStateFlow(PagedState<Item>())
    val state: StateFlow<PagedState<Item>> = _state.asStateFlow()

    private var generation = 0L
    private var nextCursor: Cursor? = firstCursor

    suspend fun refresh(
        firstPageLoader: suspend (Cursor?) -> CursorPage<Item, Cursor> = loadPage,
    ) {
        val requestGeneration = mutex.withLock {
            generation += 1
            nextCursor = firstCursor
            _state.value = _state.value.copy(
                isRefreshing = true,
                isAppending = false,
                refreshError = null,
                appendError = null,
                refreshCause = null,
                appendCause = null,
            )
            generation
        }

        try {
            val page = firstPageLoader(firstCursor)
            mutex.withLock {
                if (requestGeneration != generation) return
                nextCursor = page.nextCursor
                _state.value = PagedState(
                    items = deduplicated(page.items),
                    endReached = page.nextCursor == null || page.nextCursor == firstCursor,
                )
            }
        } catch (error: CancellationException) {
            mutex.withLock {
                if (requestGeneration == generation) {
                    _state.value = _state.value.copy(isRefreshing = false)
                }
            }
            throw error
        } catch (error: Exception) {
            mutex.withLock {
                if (requestGeneration == generation) {
                    _state.value = _state.value.copy(
                        isRefreshing = false,
                        refreshError = error.message ?: "加载失败",
                        refreshCause = error,
                    )
                }
            }
        }
    }

    suspend fun append() {
        val request = mutex.withLock {
            val current = _state.value
            val cursor = nextCursor
            if (current.isRefreshing || current.isAppending || current.endReached || cursor == null) {
                return
            }
            _state.value = current.copy(
                isAppending = true,
                appendError = null,
                appendCause = null,
            )
            AppendRequest(generation, cursor)
        }

        try {
            val page = loadPage(request.cursor)
            mutex.withLock {
                if (request.generation != generation || nextCursor != request.cursor) return
                val currentItems = _state.value.items
                val existingKeys = currentItems.mapTo(mutableSetOf(), keyOf)
                val additions = page.items.filter { existingKeys.add(keyOf(it)) }
                val repeatedCursor = page.nextCursor == request.cursor
                nextCursor = page.nextCursor
                _state.value = _state.value.copy(
                    items = currentItems + additions,
                    isAppending = false,
                    endReached = page.nextCursor == null || repeatedCursor,
                )
            }
        } catch (error: CancellationException) {
            mutex.withLock {
                if (request.generation == generation) {
                    _state.value = _state.value.copy(isAppending = false)
                }
            }
            throw error
        } catch (error: Exception) {
            mutex.withLock {
                if (request.generation == generation) {
                    _state.value = _state.value.copy(
                        isAppending = false,
                        appendError = error.message ?: "加载更多失败",
                        appendCause = error,
                    )
                }
            }
        }
    }

    private fun deduplicated(items: List<Item>): List<Item> {
        val keys = mutableSetOf<Key>()
        return items.filter { keys.add(keyOf(it)) }
    }

    private data class AppendRequest<Cursor>(
        val generation: Long,
        val cursor: Cursor,
    )
}
