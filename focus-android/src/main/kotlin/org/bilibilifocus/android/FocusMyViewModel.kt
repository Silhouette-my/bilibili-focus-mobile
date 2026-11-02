package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
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
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loadJob: Job? = null
    private var actionJob: Job? = null
    private var generation = 0L
    private val _state = MutableStateFlow<MyUiState>(MyUiState.Idle)
    val state: StateFlow<MyUiState> = _state.asStateFlow()
    private val _isManagingFolder = MutableStateFlow(false)
    val isManagingFolder = _isManagingFolder.asStateFlow()
    private val _actionError = MutableStateFlow<String?>(null)
    val actionError = _actionError.asStateFlow()

    fun loadIfNeeded() { if (_state.value is MyUiState.Idle) reload() }

    fun reload() {
        loadJob?.cancel()
        actionJob?.cancel()
        _isManagingFolder.value = false
        val request = ++generation
        val previous = _state.value as? MyUiState.Loaded
        if (previous == null) _state.value = MyUiState.Loading
        loadJob = scope.launch {
            try {
                val account = accountService.fetchLoginAccount()
                if (!account.isLogin) { _state.value = MyUiState.LoginRequired; return@launch }
                if (request != generation) return@launch
                val retained = previous?.takeIf { it.profile.mid == account.mid }
                val profile = UserProfile(account.mid, account.name, account.avatarURL, "", account.level,
                    retained?.profile?.following ?: 0L, retained?.profile?.followers ?: 0L)
                _state.value = MyUiState.Loaded(profile, retained?.history.orEmpty(), retained?.folders.orEmpty(), isRefreshing = true, isLoadingHistory = true, isLoadingFolders = true, relationLoaded = retained?.relationLoaded == true)
                coroutineScope {
                    val requestScope = this
                    launch {
                        try {
                            val relation = userService.fetchRelationInfoStrict(account.mid)
                            update(account.mid, request) { it.copy(profile = it.profile.copy(following = relation.first, followers = relation.second), relationLoaded = true, relationError = null) }
                        } catch (cancelled: CancellationException) { requestScope.cancel(cancelled); throw cancelled }
                        catch (error: Exception) {
                            if (handleSessionExpiry(error, request)) { requestScope.cancel(); return@launch }
                            update(account.mid, request) { it.copy(relationError = error.message ?: "关注资料暂不可用") }
                        }
                    }
                    launch {
                        try { val items = historyService.fetchHistory().items; update(account.mid, request) { it.copy(history = items, historyError = null, isLoadingHistory = false) } }
                        catch (cancelled: CancellationException) { requestScope.cancel(cancelled); throw cancelled }
                        catch (error: Exception) {
                            if (handleSessionExpiry(error, request)) { requestScope.cancel(); return@launch }
                            update(account.mid, request) { it.copy(historyError = error.message ?: "播放历史暂不可用", isLoadingHistory = false) }
                        }
                    }
                    launch {
                        try { val folders = favoriteService.fetchFolders(account.mid); update(account.mid, request) { it.copy(folders = folders, foldersError = null, isLoadingFolders = false) } }
                        catch (cancelled: CancellationException) { requestScope.cancel(cancelled); throw cancelled }
                        catch (error: Exception) {
                            if (handleSessionExpiry(error, request)) { requestScope.cancel(); return@launch }
                            update(account.mid, request) { it.copy(foldersError = error.message ?: "收藏夹暂不可用", isLoadingFolders = false) }
                        }
                    }
                }
                update(account.mid, request) { it.copy(isRefreshing = false) }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) {
                if (request == generation) {
                    val current = _state.value as? MyUiState.Loaded
                    _state.value = current?.copy(isRefreshing = false, refreshError = error.message ?: "刷新失败")
                        ?: MyUiState.Failed(error.message ?: "加载失败")
                }
            }
        }
    }

    private fun update(mid: Long, request: Long, transform: (MyUiState.Loaded) -> MyUiState.Loaded) {
        val current = _state.value as? MyUiState.Loaded ?: return
        if (request == generation && current.profile.mid == mid) _state.value = transform(current)
    }

    private fun handleSessionExpiry(error: Exception, request: Long): Boolean {
        val expired = error == HistoryService.ServiceError.LoginRequired || error == FavoriteService.ServiceError.LoginRequired ||
            (error is UserService.ServiceError.Api && error.code == -101)
        if (expired && request == generation) _state.value = MyUiState.LoginRequired
        return expired
    }

    fun saveFolder(folder: FavFolder?, title: String, isPrivate: Boolean) = manageFolder { mid ->
        if (folder == null) favoriteService.createFolder(title, isPrivate, mid)
        else favoriteService.renameFolder(folder.id, title, mid)
    }

    fun deleteFolder(folder: FavFolder) = manageFolder { mid -> favoriteService.deleteFolder(folder.id, mid) }

    private fun manageFolder(operation: suspend (Long) -> Unit) {
        val current = _state.value as? MyUiState.Loaded ?: return
        if (_isManagingFolder.value) return
        val request = generation
        val mid = current.profile.mid
        _isManagingFolder.value = true
        _actionError.value = null
        actionJob = scope.launch {
            try {
                operation(mid)
                val folders = favoriteService.fetchFolders(mid)
                update(mid, request) { it.copy(folders = folders, foldersError = null) }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { if (request == generation) _actionError.value = error.message ?: "操作失败" }
            finally { if (request == generation) _isManagingFolder.value = false }
        }
    }

    fun onCleared() { scope.cancel() }
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
        val historyError: String? = null,
        val foldersError: String? = null,
        val refreshError: String? = null,
        val isRefreshing: Boolean = false,
        val isLoadingHistory: Boolean = false,
        val isLoadingFolders: Boolean = false,
        val relationLoaded: Boolean = false,
        val relationError: String? = null,
    ) : MyUiState()
}
