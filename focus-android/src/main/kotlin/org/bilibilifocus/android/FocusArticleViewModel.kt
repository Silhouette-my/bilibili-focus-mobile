package org.bilibilifocus.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.ArticleDetail
import org.bilibilifocus.core.service.ArticleService

class FocusArticleViewModel(
    private val service: ArticleService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = ArticleUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<ArticleUiState>(ArticleUiState.Idle)
    val state: StateFlow<ArticleUiState> = _state.asStateFlow()

    private var loadedCvid: Long? = null

    fun loadIfNeeded(cvid: Long) {
        if (loadedCvid == cvid && _state.value is ArticleUiState.Loaded) return
        load(cvid)
    }

    fun load(cvid: Long) {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = ArticleUiState.Loading
            try {
                val detail = service.fetchArticle(cvid)
                loadedCvid = cvid
                _state.value = ArticleUiState.Loaded(detail)
            } catch (e: ArticleService.ServiceError.LoginRequired) {
                _state.value = ArticleUiState.LoginRequired
            } catch (e: ArticleService.ServiceError) {
                _state.value = ArticleUiState.Failed(e.message ?: "加载失败")
            } catch (e: Exception) {
                _state.value = ArticleUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class ArticleUiState {
    data object Idle : ArticleUiState()
    data object Loading : ArticleUiState()
    data object LoginRequired : ArticleUiState()
    data class Failed(val message: String) : ArticleUiState()
    data class Loaded(val detail: ArticleDetail) : ArticleUiState()
}
