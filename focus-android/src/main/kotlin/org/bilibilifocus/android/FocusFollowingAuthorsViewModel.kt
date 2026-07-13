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
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.service.FollowingAuthorsService

class FocusFollowingAuthorsViewModel(
    private val service: FollowingAuthorsService,
    fallbackAuthors: List<DynamicCard.Author> = emptyList(),
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loadJob: Job? = null
    private val fallbackAuthors = deduplicated(fallbackAuthors)

    private val _state = MutableStateFlow<FollowingAuthorsUiState>(FollowingAuthorsUiState.Idle)
    val state: StateFlow<FollowingAuthorsUiState> = _state.asStateFlow()

    fun loadIfNeeded() {
        if (_state.value !is FollowingAuthorsUiState.Idle) return
        reload()
    }

    fun reload() {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = FollowingAuthorsUiState.Loading
            try {
                val authors = deduplicated(service.fetchFollowingAuthors() + fallbackAuthors)
                _state.value = FollowingAuthorsUiState.Loaded(authors)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (fallbackAuthors.isNotEmpty()) {
                    _state.value = FollowingAuthorsUiState.Loaded(
                        authors = fallbackAuthors,
                        notice = "完整关注列表加载失败，当前仅显示动态页已读取到的 UP 主。",
                    )
                } else {
                    _state.value = FollowingAuthorsUiState.Failed(e.message ?: "关注列表加载失败")
                }
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }

    private fun deduplicated(authors: List<DynamicCard.Author>): List<DynamicCard.Author> {
        val seen = mutableSetOf<String>()
        return authors.filter { author ->
            val key = FocusSettingsViewModel.authorFilterKey(author)
            (author.mid > 0L || author.name.isNotBlank()) && seen.add(key)
        }.sortedBy { it.name.lowercase() }
    }
}

sealed class FollowingAuthorsUiState {
    data object Idle : FollowingAuthorsUiState()
    data object Loading : FollowingAuthorsUiState()
    data class Loaded(
        val authors: List<DynamicCard.Author>,
        val notice: String? = null,
    ) : FollowingAuthorsUiState()
    data class Failed(val message: String) : FollowingAuthorsUiState()
}
