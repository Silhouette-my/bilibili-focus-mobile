package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.UserCollectionPage
import org.bilibilifocus.core.model.UserContentCollection
import org.bilibilifocus.core.service.UserService

class FocusUserCollectionViewModel(
    private val service: UserService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private var currentCollection: UserContentCollection? = null
    private var nextPage: Int? = null

    private val _state = MutableStateFlow<UserCollectionUiState>(UserCollectionUiState.Idle)
    val state: StateFlow<UserCollectionUiState> = _state.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    fun loadIfNeeded(collection: UserContentCollection) {
        if (currentCollection?.id == collection.id && _state.value is UserCollectionUiState.Loaded) return
        load(collection)
    }

    fun load(collection: UserContentCollection) {
        currentCollection = collection
        loadJob?.cancel()
        loadMoreJob?.cancel()
        _isLoadingMore.value = false
        loadJob = scope.launch {
            _state.value = UserCollectionUiState.Loading
            try {
                val page = service.fetchUserCollectionPage(collection)
                nextPage = page.nextPage
                _state.value = UserCollectionUiState.Loaded(page)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = UserCollectionUiState.Failed(e.message ?: "合集加载失败")
            }
        }
    }

    fun loadMoreIfNeeded(currentBvid: String) {
        val current = (_state.value as? UserCollectionUiState.Loaded)?.page ?: return
        val index = current.videos.indexOfFirst { it.bvid == currentBvid }
        if (index < maxOf(current.videos.size - 4, 0)) return
        if (_isLoadingMore.value) return
        val collection = currentCollection ?: return
        val page = nextPage ?: return

        _isLoadingMore.value = true
        loadMoreJob?.cancel()
        loadMoreJob = scope.launch {
            try {
                val payload = service.fetchUserCollectionPage(collection, page)
                val seen = current.videos.mapTo(mutableSetOf()) { it.bvid }
                val merged = current.videos + payload.videos.filter { seen.add(it.bvid) }
                nextPage = payload.nextPage
                _state.value = UserCollectionUiState.Loaded(
                    UserCollectionPage(collection, merged, payload.nextPage),
                )
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // 保留已加载结果。
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class UserCollectionUiState {
    data object Idle : UserCollectionUiState()
    data object Loading : UserCollectionUiState()
    data class Failed(val message: String) : UserCollectionUiState()
    data class Loaded(val page: UserCollectionPage) : UserCollectionUiState()
}
