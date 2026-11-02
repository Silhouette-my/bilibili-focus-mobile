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
    private var loadedMID: Long? = null
    private var page = 1
    private var appendJob: Job? = null
    private var actionJob: Job? = null
    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore = _isLoadingMore.asStateFlow()
    private val _isManaging = MutableStateFlow(false)
    val isManaging = _isManaging.asStateFlow()
    private val _actionError = MutableStateFlow<String?>(null)
    val actionError = _actionError.asStateFlow()
    private val _transferTargets = MutableStateFlow<List<org.bilibilifocus.core.model.FavFolder>>(emptyList())
    val transferTargets = _transferTargets.asStateFlow()

    fun loadIfNeeded(mediaId: Long) {
        if (loadedMediaId == mediaId && _state.value is FavFolderUiState.Loaded) return
        load(mediaId)
    }

    fun load(mediaId: Long) {
        loadJob?.cancel()
        appendJob?.cancel()
        _isLoadingMore.value = false
        loadJob = scope.launch {
            _state.value = FavFolderUiState.Loading
            try {
                loadedMID = try { service.authenticatedMID() } catch (cancelled: CancellationException) { throw cancelled } catch (_: org.bilibilifocus.core.service.FavoriteService.ServiceError.LoginRequired) { null }
                val items = service.fetchFolderContents(mediaId)
                loadedMediaId = mediaId
                page = 1
                _state.value = FavFolderUiState.Loaded(items, hasMore = items.size >= 20)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = FavFolderUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun loadMore() {
        val current = _state.value as? FavFolderUiState.Loaded ?: return
        val id = loadedMediaId ?: return
        if (!current.hasMore || _isLoadingMore.value || _isManaging.value) return
        _isLoadingMore.value = true
        appendJob = scope.launch {
            try {
                val items = service.fetchFolderContents(id, page + 1)
                val merged = (current.items + items).distinctBy { it.bvid }
                page += 1
                _state.value = FavFolderUiState.Loaded(merged, items.size >= 20 && merged.size > current.items.size)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { _state.value = current.copy(appendError = error.message ?: "加载失败") }
            finally { _isLoadingMore.value = false }
        }
    }

    fun loadTransferTargets() {
        val mid = loadedMID ?: return
        if (_isManaging.value) return
        _isManaging.value = true
        _transferTargets.value = emptyList()
        _actionError.value = null
        actionJob = scope.launch {
            try { _transferTargets.value = service.fetchFolders(mid).filter { it.id != loadedMediaId } }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { _actionError.value = error.message ?: "收藏夹加载失败" }
            finally { _isManaging.value = false }
        }
    }

    fun remove(item: FavResource) = mutate(item, null, false)
    fun transfer(item: FavResource, target: Long, copy: Boolean) = mutate(item, target, copy)
    fun dismissActionError() { _actionError.value = null }

    private fun mutate(item: FavResource, target: Long?, copy: Boolean) {
        val id = loadedMediaId ?: return
        val mid = loadedMID ?: return
        if (_isManaging.value || item.aid <= 0) return
        appendJob?.cancel()
        _isLoadingMore.value = false
        _isManaging.value = true
        _actionError.value = null
        actionJob = scope.launch {
            try {
                if (target == null) service.removeResource(id, item.aid, mid)
                else service.transferResource(id, target, item.aid, copy, mid)
                if (!copy) load(id)
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { _actionError.value = error.message ?: "操作失败" }
            finally { _isManaging.value = false }
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
    data class Loaded(val items: List<FavResource>, val hasMore: Boolean = false, val appendError: String? = null) : FavFolderUiState()
}
