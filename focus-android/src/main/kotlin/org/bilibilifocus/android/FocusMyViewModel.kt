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
import org.bilibilifocus.core.model.FavFolder
import org.bilibilifocus.core.model.HistoryItem
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.service.AccountService
import org.bilibilifocus.core.service.FavoriteService
import org.bilibilifocus.core.service.HistoryService
import org.bilibilifocus.core.service.UserService

class FocusMyViewModel(
    private val accountService: AccountService,
    private val userService: UserService,
    private val historyService: HistoryService,
    private val favoriteService: FavoriteService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main + kotlinx.coroutines.CoroutineExceptionHandler { _, e ->
        _state.value = MyUiState.Failed(e.message ?: "加载失败")
    })
    private var loadJob: Job? = null

    private val _state = MutableStateFlow<MyUiState>(MyUiState.Idle)
    val state: StateFlow<MyUiState> = _state.asStateFlow()

    fun loadIfNeeded() {
        if (_state.value !is MyUiState.Idle) return
        reload()
    }

    fun reload() {
        loadJob?.cancel()
        loadJob = scope.launch {
            _state.value = MyUiState.Loading
            try {
                val account = accountService.fetchLoginAccount()
                if (!account.isLogin) {
                    _state.value = MyUiState.LoginRequired
                    return@launch
                }

                // 关注/粉丝数（失败返回 0,0，不抛异常）
                val relation = userService.fetchRelationInfo(account.mid)
                // 个性签名（可选，失败忽略）
                val sign = try {
                    userService.fetchUserInfo(account.mid).sign
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    ""
                }
                val profile = UserProfile(
                    mid = account.mid,
                    name = account.name,
                    avatarURL = account.avatarURL,
                    sign = sign,
                    level = account.level,
                    following = relation.first,
                    followers = relation.second,
                )

                // 历史与收藏夹各自容错，互不影响主资料展示
                val history = try {
                    historyService.fetchHistory().items
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    emptyList()
                }
                val folders = try {
                    favoriteService.fetchFolders(account.mid)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    emptyList()
                }

                _state.value = MyUiState.Loaded(profile, history, folders)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.value = MyUiState.Failed(e.message ?: "加载失败")
            }
        }
    }

    fun onCleared() {
        scope.cancel()
    }
}

sealed class MyUiState {
    data object Idle : MyUiState()
    data object Loading : MyUiState()
    data object LoginRequired : MyUiState()
    data class Failed(val message: String) : MyUiState()
    data class Loaded(
        val profile: UserProfile,
        val history: List<HistoryItem>,
        val folders: List<FavFolder>,
    ) : MyUiState()
}
