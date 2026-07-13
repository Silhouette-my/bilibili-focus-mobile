package org.bilibilifocus.android

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.bilibilifocus.core.model.UserArticle
import org.bilibilifocus.core.model.UserContentCollection
import org.bilibilifocus.core.model.UserProfile
import org.bilibilifocus.core.model.UserVideo
import org.bilibilifocus.core.model.UserVideoPage
import org.bilibilifocus.core.service.UserService

class FocusUserViewModel(
    private val service: UserService,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var loadJob: Job? = null
    private var loadMoreJob: Job? = null
    private var loadedMid: Long? = null
    private var nextVideoPage: Int? = null

    var selectedSection: UserContentSection = UserContentSection.VIDEOS
        private set

    private val _state = MutableStateFlow<UserUiState>(UserUiState.Idle)
    val state: StateFlow<UserUiState> = _state.asStateFlow()

    private val _isLoadingMore = MutableStateFlow(false)
    val isLoadingMore: StateFlow<Boolean> = _isLoadingMore.asStateFlow()

    fun loadIfNeeded(mid: Long) {
        if (loadedMid == mid && _state.value is UserUiState.Loaded) return
        load(mid)
    }

    fun load(mid: Long, onComplete: () -> Unit = {}) {
        loadJob?.cancel()
        loadMoreJob?.cancel()
        _isLoadingMore.value = false
        loadJob = scope.launch {
            _state.value = UserUiState.Loading
            try {
                val info = service.fetchUserInfo(mid)
                val (relation, videoPage, collections, articles) = coroutineScope {
                    val relationTask = async { runCatching { service.fetchRelationInfo(mid) }.getOrDefault(0L to 0L) }
                    val videoTask = async {
                        runCatching { service.fetchUserVideoPage(mid) }
                            .getOrDefault(UserVideoPage(0, emptyList(), null))
                    }
                    val collectionTask = async { runCatching { service.fetchUserCollections(mid) }.getOrDefault(emptyList()) }
                    val articleTask = async { runCatching { service.fetchUserArticles(mid) }.getOrDefault(emptyList()) }
                    UserPageParts(
                        relation = relationTask.await(),
                        videos = videoTask.await(),
                        collections = collectionTask.await(),
                        articles = articleTask.await(),
                    )
                }

                val profile = info.copy(
                    following = relation.first,
                    followers = relation.second,
                    videoCount = maxOf(info.videoCount, videoPage.totalCount),
                    articleCount = maxOf(info.articleCount, articles.size),
                )
                loadedMid = mid
                nextVideoPage = videoPage.nextPage
                _state.value = UserUiState.Loaded(profile, videoPage.items, collections, articles)
            } catch (e: CancellationException) {
                throw e
            } catch (e: UserService.ServiceError) {
                _state.value = when (e) {
                    UserService.ServiceError.SigningUnavailable -> UserUiState.Failed("签名初始化失败，请重试")
                    is UserService.ServiceError.Api -> UserUiState.Failed("API错误 ${e.code}: ${e.message}")
                    UserService.ServiceError.InvalidResponse -> UserUiState.Failed("接口数据异常")
                }
            } catch (e: Exception) {
                _state.value = UserUiState.Failed(e.message ?: "加载失败")
            } finally {
                onComplete()
            }
        }
    }

    fun loadMoreIfNeeded(currentVideoBvid: String) {
        val current = _state.value as? UserUiState.Loaded ?: return
        val index = current.videos.indexOfFirst { it.bvid == currentVideoBvid }
        if (index < maxOf(current.videos.size - 4, 0)) return
        if (_isLoadingMore.value) return
        val mid = loadedMid ?: return
        val page = nextVideoPage ?: return

        _isLoadingMore.value = true
        loadMoreJob?.cancel()
        loadMoreJob = scope.launch {
            try {
                val payload = service.fetchUserVideoPage(mid = mid, page = page)
                val seen = current.videos.mapTo(mutableSetOf()) { it.bvid }
                val merged = current.videos + payload.items.filter { seen.add(it.bvid) }
                nextVideoPage = payload.nextPage
                _state.value = current.copy(videos = merged)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // 保留已经加载的主页内容。
            } finally {
                _isLoadingMore.value = false
            }
        }
    }

    fun selectSection(section: UserContentSection) {
        selectedSection = section
    }

    fun onCleared() {
        scope.cancel()
    }

    private data class UserPageParts(
        val relation: Pair<Long, Long>,
        val videos: UserVideoPage,
        val collections: List<UserContentCollection>,
        val articles: List<UserArticle>,
    )
}

enum class UserContentSection(val title: String) {
    VIDEOS("视频"),
    COLLECTIONS("合集"),
    ARTICLES("专栏"),
}

sealed class UserUiState {
    data object Idle : UserUiState()
    data object Loading : UserUiState()
    data class Failed(val message: String) : UserUiState()
    data class Loaded(
        val profile: UserProfile,
        val videos: List<UserVideo>,
        val collections: List<UserContentCollection>,
        val articles: List<UserArticle>,
    ) : UserUiState()
}
