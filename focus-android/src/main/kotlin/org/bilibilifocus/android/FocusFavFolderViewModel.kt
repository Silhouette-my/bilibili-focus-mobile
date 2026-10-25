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
import org.bilibilifocus.core.model.FavResource
import org.bilibilifocus.core.service.FavoriteService

class FocusFavFolderViewModel(
    private val service: FavoriteService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = FavFolderUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<FavFolderUiState>(FavFolderUiState.Idle)
    val state: StateFlow<FavFolderUiState> = _state.asStateFlow()
    private var loadedMediaId: Long? = null

    fun loadIfNeeded(mediaId: Long) {
        if (loadedMediaId == mediaId && _state.value is FavFolderUiState.Loaded) return
        load(mediaId)
    }

    fun load(mediaId: Long) {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = FavFolderUiState.Loading
            try {
                val items = service.fetchFolderContents(mediaId)
                loadedMediaId = mediaId
                _state.value = FavFolderUiState.Loaded(items)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = FavFolderUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class FavFolderUiState {
    data object Idle : FavFolderUiState()
    data object Loading : FavFolderUiState()
    data class Failed(val message: String) : FavFolderUiState()
    data class Loaded(val items: List<FavResource>) : FavFolderUiState()
}
