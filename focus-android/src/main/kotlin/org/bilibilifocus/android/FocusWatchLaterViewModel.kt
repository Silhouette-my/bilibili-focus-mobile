package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.WatchLaterItem
import org.bilibilifocus.core.model.WatchLaterList
import org.bilibilifocus.core.service.WatchLaterService

internal interface WatchLaterRepository {
    suspend fun fetchList(): WatchLaterList
    suspend fun remove(aid: Long)
    suspend fun deleteViewed()
    suspend fun clear()
}

private class ServiceWatchLaterRepository(
    private val service: WatchLaterService,
) : WatchLaterRepository {
    override suspend fun fetchList(): WatchLaterList = service.fetchList()

    override suspend fun remove(aid: Long) {
        service.remove(aid)
    }

    override suspend fun deleteViewed() {
        service.deleteViewed()
    }

    override suspend fun clear() {
        service.clear()
    }
}

class FocusWatchLaterViewModel internal constructor(
    private val repository: WatchLaterRepository,
    dispatcher: CoroutineDispatcher,
) {
    constructor(service: WatchLaterService) : this(
        repository = ServiceWatchLaterRepository(service),
        dispatcher = Dispatchers.Main,
    )

    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var loadJob: Job? = null
    private var mutationJob: Job? = null

    private val _state = MutableStateFlow<WatchLaterUiState>(WatchLaterUiState.Idle)
    val state: StateFlow<WatchLaterUiState> = _state.asStateFlow()

    fun loadIfNeeded() {
        if (_state.value !is WatchLaterUiState.Idle) return
        reload()
    }

    fun reload() {
        val loaded = _state.value as? WatchLaterUiState.Loaded
        if (loaded?.pendingAction != null) return
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = WatchLaterUiState.Loading
            try {
                val result = repository.fetchList()
                _state.value = WatchLaterUiState.Loaded(
                    items = result.items,
                    totalCount = result.totalCount,
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: WatchLaterService.ServiceError) {
                _state.value = when (error) {
                    WatchLaterService.ServiceError.LoginRequired,
                    WatchLaterService.ServiceError.MissingCsrf,
                    -> WatchLaterUiState.LoginRequired
                    else -> WatchLaterUiState.Failed(error.message ?: "加载稍后再看失败")
                }
            } catch (error: Exception) {
                _state.value = WatchLaterUiState.Failed(error.message ?: "加载稍后再看失败")
            }
        }
    }

    fun remove(aid: Long) {
        mutate(WatchLaterPendingAction.Remove(aid)) {
            repository.remove(aid)
        }
    }

    fun deleteViewed() {
        mutate(WatchLaterPendingAction.DeleteViewed) {
            repository.deleteViewed()
        }
    }

    fun clear() {
        mutate(WatchLaterPendingAction.Clear) {
            repository.clear()
        }
    }

    fun clearError() {
        val current = _state.value as? WatchLaterUiState.Loaded ?: return
        if (current.errorMessage != null) {
            _state.value = current.copy(errorMessage = null)
        }
    }

    fun onCleared() {
        scope.cancel()
    }

    private fun mutate(
        action: WatchLaterPendingAction,
        operation: suspend () -> Unit,
    ) {
        val current = _state.value as? WatchLaterUiState.Loaded ?: return
        if (current.pendingAction != null) return
        if (action is WatchLaterPendingAction.Remove &&
            current.items.none { it.aid == action.aid }
        ) {
            return
        }

        val optimistic = WatchLaterMutationPolicy.apply(
            items = current.items,
            totalCount = current.totalCount,
            action = action,
        )
        val rollback = current.copy(pendingAction = null, errorMessage = null)
        _state.value = current.copy(
            items = optimistic.items,
            totalCount = optimistic.totalCount,
            pendingAction = action,
            errorMessage = null,
        )

        mutationJob = scope.launch {
            try {
                operation()
                val pending = _state.value as? WatchLaterUiState.Loaded
                if (pending?.pendingAction == action) {
                    _state.value = pending.copy(pendingAction = null)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val pending = _state.value as? WatchLaterUiState.Loaded
                if (pending?.pendingAction == action) {
                    _state.value = rollback.copy(
                        errorMessage = error.message ?: "操作失败，已恢复列表",
                    )
                }
            }
        }
    }
}

sealed interface WatchLaterUiState {
    data object Idle : WatchLaterUiState
    data object Loading : WatchLaterUiState
    data object LoginRequired : WatchLaterUiState
    data class Failed(val message: String) : WatchLaterUiState
    data class Loaded(
        val items: List<WatchLaterItem>,
        val totalCount: Int,
        val pendingAction: WatchLaterPendingAction? = null,
        val errorMessage: String? = null,
    ) : WatchLaterUiState
}

sealed interface WatchLaterPendingAction {
    data class Remove(val aid: Long) : WatchLaterPendingAction
    data object DeleteViewed : WatchLaterPendingAction
    data object Clear : WatchLaterPendingAction
}

internal object WatchLaterMutationPolicy {
    data class Result(
        val items: List<WatchLaterItem>,
        val totalCount: Int,
    )

    fun apply(
        items: List<WatchLaterItem>,
        totalCount: Int,
        action: WatchLaterPendingAction,
    ): Result {
        val updatedItems = when (action) {
            is WatchLaterPendingAction.Remove -> items.filterNot { it.aid == action.aid }
            WatchLaterPendingAction.DeleteViewed -> items.filterNot(::isViewed)
            WatchLaterPendingAction.Clear -> emptyList()
        }
        val removedCount = items.size - updatedItems.size
        val updatedTotal = when (action) {
            WatchLaterPendingAction.Clear -> 0
            else -> (totalCount - removedCount).coerceAtLeast(updatedItems.size)
        }
        return Result(items = updatedItems, totalCount = updatedTotal)
    }

    fun isViewed(item: WatchLaterItem): Boolean =
        item.progressSeconds < 0 ||
            (item.durationSeconds > 0 && item.progressSeconds >= item.durationSeconds)

    fun requiresConfirmation(action: WatchLaterPendingAction): Boolean =
        action == WatchLaterPendingAction.Clear
}
