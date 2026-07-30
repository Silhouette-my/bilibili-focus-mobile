package org.bilibilifocus.android

import org.bilibilifocus.android.playback.FocusPlaybackProgressStore
import org.bilibilifocus.android.playback.FocusPlaybackAccountScopeProvider
import org.bilibilifocus.android.playback.FocusPlaybackHistoryOutbox
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.service.AccountService
import org.bilibilifocus.core.service.ArticleService
import org.bilibilifocus.core.service.DynamicFeedService
import org.bilibilifocus.core.service.FavoriteService
import org.bilibilifocus.core.service.HistoryService
import org.bilibilifocus.core.service.HttpClient
import org.bilibilifocus.core.service.InMemoryNetworkEventSink
import org.bilibilifocus.core.service.KtorHttpClient
import org.bilibilifocus.core.service.LoginHealthService
import org.bilibilifocus.core.service.ObservingHttpClient
import org.bilibilifocus.core.service.OpusService
import org.bilibilifocus.core.service.PlayUrlService
import org.bilibilifocus.core.service.ResilientHttpClient
import org.bilibilifocus.core.service.SearchResultService
import org.bilibilifocus.core.service.UserService
import org.bilibilifocus.core.service.VideoActionService
import org.bilibilifocus.core.service.VideoInfoService
import org.bilibilifocus.core.service.WatchLaterService
import org.bilibilifocus.core.service.WbiSigner

/**
 * Application-scoped composition root for shared session and network
 * resources. Feature services remain lightweight and can still be replaced in
 * tests, while production no longer creates a new HTTP engine per screen.
 */
class FocusAppGraph(
    val cookieProvider: CookieProvider = AndroidCookieProvider(),
    rawHttpClient: HttpClient = KtorHttpClient(),
    val playbackProgressStore: FocusPlaybackProgressStore = FocusPlaybackProgressStore(),
    val networkEvents: InMemoryNetworkEventSink = InMemoryNetworkEventSink(),
) {
    val httpClient: HttpClient = ObservingHttpClient(
        delegate = ResilientHttpClient(rawHttpClient),
        sink = networkEvents,
    )
    val playbackAccountScopeProvider: FocusPlaybackAccountScopeProvider =
        FocusPlaybackAccountScopeProvider(cookieProvider)
    val wbiSigner: WbiSigner = WbiSigner(cookieProvider, httpClient)

    // Feature services are application-scoped and share one CookieProvider,
    // transport, WBI key cache, retry policy, and diagnostics sink.
    val accountService: AccountService = AccountService(cookieProvider, httpClient)
    val articleService: ArticleService = ArticleService(cookieProvider, httpClient)
    val dynamicFeedService: DynamicFeedService = DynamicFeedService(cookieProvider, httpClient)
    val favoriteService: FavoriteService = FavoriteService(cookieProvider, httpClient)
    val historyService: HistoryService = HistoryService(cookieProvider, httpClient)
    val loginHealthService: LoginHealthService = LoginHealthService(cookieProvider, httpClient)
    val opusService: OpusService =
        OpusService(cookieProvider, httpClient, wbiSigner = wbiSigner)
    val playUrlService: PlayUrlService =
        PlayUrlService(cookieProvider, httpClient, wbiSigner = wbiSigner)
    val searchResultService: SearchResultService =
        SearchResultService(cookieProvider, httpClient, wbiSigner = wbiSigner)
    val userService: UserService =
        UserService(cookieProvider, httpClient, wbiSigner = wbiSigner)
    val videoActionService: VideoActionService = VideoActionService(cookieProvider, httpClient)
    val videoInfoService: VideoInfoService =
        VideoInfoService(cookieProvider, httpClient, wbiSigner = wbiSigner)
    val watchLaterService: WatchLaterService = WatchLaterService(cookieProvider, httpClient)
    internal val playbackHistoryOutbox: FocusPlaybackHistoryOutbox =
        FocusPlaybackHistoryOutbox(
            accountScopeProvider = playbackAccountScopeProvider,
            progressStore = playbackProgressStore,
            submitReport = { report, cookies ->
                videoActionService.reportWatchHistory(
                    aid = report.aid,
                    cid = report.cid,
                    progressSeconds = report.progressSeconds,
                    cookies = cookies,
                )
            },
        )

    fun close() {
        httpClient.close()
    }
}
