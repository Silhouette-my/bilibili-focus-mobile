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
import org.bilibilifocus.core.model.OpusDetail
import org.bilibilifocus.core.service.OpusService

class FocusOpusViewModel(
    private val service: OpusService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = OpusUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<OpusUiState>(OpusUiState.Idle)
    val state: StateFlow<OpusUiState> = _state.asStateFlow()

    private val _comments = MutableStateFlow<List<org.bilibilifocus.core.model.VideoComment>>(emptyList())
    val comments: StateFlow<List<org.bilibilifocus.core.model.VideoComment>> = _comments.asStateFlow()

    private var loadedId: String? = null

    fun loadIfNeeded(id: String) {
        if (loadedId == id && _state.value is OpusUiState.Loaded) return
        load(id)
    }

    fun load(id: String) {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = OpusUiState.Loading
            _comments.value = emptyList()
            try {
                val detail = service.fetchOpusDetail(id)
                loadedId = id
                _state.value = OpusUiState.Loaded(detail)
                if (detail.commentId > 0) {
                    val (comments, _) = service.fetchComments(detail.commentId, detail.id)
                    _comments.value = comments
                }
            } catch (e: OpusService.ServiceError) {
                if (e == OpusService.ServiceError.LoginRequired) {
                    _state.value = OpusUiState.LoginRequired
                } else {
                    _state.value = OpusUiState.Failed(e.message ?: "加载失败")
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = OpusUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class OpusUiState {
    data object Idle : OpusUiState()
    data object Loading : OpusUiState()
    data object LoginRequired : OpusUiState()
    data class Failed(val message: String) : OpusUiState()
    data class Loaded(val detail: OpusDetail) : OpusUiState()
}
