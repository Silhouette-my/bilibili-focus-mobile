package org.bilibilifocus.android

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.bilibilifocus.core.model.WatchLaterAuthor
import org.bilibilifocus.core.model.WatchLaterItem
import org.bilibilifocus.core.model.WatchLaterList
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class FocusWatchLaterViewModelTests {
    @Test
    fun `load exposes repository list`() = runTest {
        val repository = FakeWatchLaterRepository(
            initial = WatchLaterList(
                totalCount = 2,
                items = listOf(watchLaterItem(1), watchLaterItem(4_294_967_296L)),
            ),
        )
        val viewModel = FocusWatchLaterViewModel(
            repository = repository,
            dispatcher = StandardTestDispatcher(testScheduler),
        )

        viewModel.loadIfNeeded()
        advanceUntilIdle()

        val state = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertEquals(2, state.totalCount)
        assertEquals(listOf(1L, 4_294_967_296L), state.items.map { it.aid })
        assertNull(state.pendingAction)
        viewModel.onCleared()
    }

    @Test
    fun `failed optimistic removal rolls back and exposes error`() = runTest {
        val repository = FakeWatchLaterRepository(
            initial = WatchLaterList(
                totalCount = 2,
                items = listOf(watchLaterItem(1), watchLaterItem(2)),
            ),
            removeFailure = IllegalStateException("移除失败"),
        )
        val viewModel = FocusWatchLaterViewModel(
            repository = repository,
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        viewModel.reload()
        advanceUntilIdle()

        viewModel.remove(1)

        val optimistic = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertEquals(listOf(2L), optimistic.items.map { it.aid })
        assertEquals(WatchLaterPendingAction.Remove(1), optimistic.pendingAction)

        advanceUntilIdle()

        val rolledBack = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertEquals(listOf(1L, 2L), rolledBack.items.map { it.aid })
        assertEquals(2, rolledBack.totalCount)
        assertNull(rolledBack.pendingAction)
        assertEquals("移除失败", rolledBack.errorMessage)

        viewModel.clearError()
        assertNull(assertIs<WatchLaterUiState.Loaded>(viewModel.state.value).errorMessage)
        viewModel.onCleared()
    }

    @Test
    fun `delete viewed removes completed items and clear requires confirmation`() = runTest {
        val repository = FakeWatchLaterRepository(
            initial = WatchLaterList(
                totalCount = 3,
                items = listOf(
                    watchLaterItem(aid = 1, progress = -1),
                    watchLaterItem(aid = 2, progress = 600, duration = 600),
                    watchLaterItem(aid = 3, progress = 30, duration = 600),
                ),
            ),
        )
        val viewModel = FocusWatchLaterViewModel(
            repository = repository,
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        viewModel.reload()
        advanceUntilIdle()

        assertTrue(
            WatchLaterMutationPolicy.requiresConfirmation(WatchLaterPendingAction.Clear),
        )
        assertFalse(
            WatchLaterMutationPolicy.requiresConfirmation(
                WatchLaterPendingAction.DeleteViewed,
            ),
        )

        viewModel.deleteViewed()
        val optimistic = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertEquals(listOf(3L), optimistic.items.map { it.aid })
        assertEquals(1, optimistic.totalCount)
        assertEquals(WatchLaterPendingAction.DeleteViewed, optimistic.pendingAction)

        advanceUntilIdle()
        val completed = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertEquals(listOf(3L), completed.items.map { it.aid })
        assertNull(completed.pendingAction)
        assertEquals(1, repository.deleteViewedCalls)
        viewModel.onCleared()
    }

    @Test
    fun `failed clear restores the complete snapshot`() = runTest {
        val repository = FakeWatchLaterRepository(
            initial = WatchLaterList(
                totalCount = 2,
                items = listOf(watchLaterItem(1), watchLaterItem(2)),
            ),
            clearFailure = IllegalStateException("清空失败"),
        )
        val viewModel = FocusWatchLaterViewModel(
            repository = repository,
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        viewModel.reload()
        advanceUntilIdle()

        viewModel.clear()

        val optimistic = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertTrue(optimistic.items.isEmpty())
        assertEquals(0, optimistic.totalCount)
        assertEquals(WatchLaterPendingAction.Clear, optimistic.pendingAction)

        advanceUntilIdle()

        val rolledBack = assertIs<WatchLaterUiState.Loaded>(viewModel.state.value)
        assertEquals(listOf(1L, 2L), rolledBack.items.map { it.aid })
        assertEquals(2, rolledBack.totalCount)
        assertEquals("清空失败", rolledBack.errorMessage)
        assertNull(rolledBack.pendingAction)
        viewModel.onCleared()
    }

    @Test
    fun `onCleared cancels an in-flight mutation`() = runTest {
        val mutationStarted = CompletableDeferred<Unit>()
        val mutationCancelled = CompletableDeferred<Unit>()
        val repository = FakeWatchLaterRepository(
            initial = WatchLaterList(
                totalCount = 1,
                items = listOf(watchLaterItem(1)),
            ),
            removeBlock = {
                mutationStarted.complete(Unit)
                try {
                    awaitCancellation()
                } finally {
                    mutationCancelled.complete(Unit)
                }
            },
        )
        val viewModel = FocusWatchLaterViewModel(
            repository = repository,
            dispatcher = StandardTestDispatcher(testScheduler),
        )
        viewModel.reload()
        advanceUntilIdle()

        viewModel.remove(1)
        runCurrent()
        assertTrue(mutationStarted.isCompleted)
        assertNotNull(
            assertIs<WatchLaterUiState.Loaded>(viewModel.state.value).pendingAction,
        )

        viewModel.onCleared()
        runCurrent()

        assertTrue(mutationCancelled.isCompleted)
    }
}

private class FakeWatchLaterRepository(
    private val initial: WatchLaterList,
    private val removeFailure: Exception? = null,
    private val removeBlock: (suspend () -> Unit)? = null,
    private val clearFailure: Exception? = null,
) : WatchLaterRepository {
    var deleteViewedCalls: Int = 0
        private set

    override suspend fun fetchList(): WatchLaterList = initial

    override suspend fun remove(aid: Long) {
        removeBlock?.invoke()
        removeFailure?.let { throw it }
    }

    override suspend fun deleteViewed() {
        deleteViewedCalls += 1
    }

    override suspend fun clear() {
        clearFailure?.let { throw it }
    }
}

private fun watchLaterItem(
    aid: Long,
    progress: Long = 0,
    duration: Long = 600,
): WatchLaterItem = WatchLaterItem(
    aid = aid,
    bvid = "BV$aid",
    cid = aid * 10,
    title = "视频 $aid",
    coverURL = "https://i0.hdslb.com/$aid.jpg",
    author = WatchLaterAuthor(
        mid = aid + 100,
        name = "UP $aid",
        avatarURL = "",
    ),
    durationSeconds = duration,
    progressSeconds = progress,
    addedAt = 1_700_000_000,
    publishedAt = 1_690_000_000,
    viewCount = 10_000,
)
