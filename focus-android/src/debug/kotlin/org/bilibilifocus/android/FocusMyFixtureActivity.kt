package org.bilibilifocus.android

import android.os.Bundle
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import org.bilibilifocus.android.playback.FocusPlaybackAccountScopeProvider
import org.bilibilifocus.android.playback.FocusPlaybackHistoryOutbox
import org.bilibilifocus.android.playback.FocusPlaybackProgressStore
import org.bilibilifocus.android.ui.FocusFavFolderScreen
import org.bilibilifocus.android.ui.FocusHistoryScreen
import org.bilibilifocus.android.ui.FocusMyScreen
import org.bilibilifocus.android.ui.theme.BilibiliFocusTheme
import org.bilibilifocus.core.cookie.Cookie
import org.bilibilifocus.core.cookie.CookieProvider
import org.bilibilifocus.core.model.FocusThemeMode
import org.bilibilifocus.core.service.*
import java.io.File
import java.io.FileOutputStream

/** Separate-process, debug-only visual fixture. Every API request is in-memory. */
class FocusMyFixtureActivity : ComponentActivity() {
    @OptIn(ExperimentalMaterial3Api::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val fixture = PersonalFixtureHttpClient(intent.getBooleanExtra("empty", false))
        val cookies = object : CookieProvider {
            override suspend fun loadCookies() = listOf(
                Cookie("DedeUserID", "42", ".bilibili.com"), Cookie("SESSDATA", "offline-fixture", ".bilibili.com"), Cookie("bili_jct", "offline-fixture", ".bilibili.com"),
            )
        }
        val accounts = AccountService(cookies, fixture)
        val users = UserService(cookies, fixture)
        val history = HistoryService(cookies, fixture)
        val favorites = FavoriteService(cookies, fixture)
        val following = FollowingAuthorsService(cookies, fixture)
        val progress = FocusPlaybackProgressStore()
        val outbox = FocusPlaybackHistoryOutbox(FocusPlaybackAccountScopeProvider(cookies), progress, submitReport = { _, _ -> error("Fixture must not report playback") })
        val myModel = FocusMyViewModel(accounts, users, history, favorites)
        val historyModel = FocusHistoryViewModel(history, outbox::mutateRemoteHistory)
        val folderModel = FocusFavFolderViewModel(favorites)
        setContent {
            BilibiliFocusTheme(themeMode = FocusThemeMode.LIGHT) {
                var route by remember { mutableStateOf(intent.getStringExtra("page") ?: "my") }
                var folderID by remember { mutableLongStateOf(1L) }
                var folderTitle by remember { mutableStateOf("学习收藏") }
                var message by remember { mutableStateOf<String?>(null) }
                DisposableEffect(Unit) { onDispose { myModel.onCleared(); historyModel.onCleared(); folderModel.onCleared() } }
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    when (route) {
                        "history" -> FocusHistoryScreen(onBack = { route = "my" }, onOpenVideo = { message = "继续播放入口已触发" }, viewModel = historyModel)
                        "folder" -> FocusFavFolderScreen(folderID, folderTitle, onBack = { route = "my" }, onOpenVideo = { message = "视频入口已触发" }, viewModel = folderModel)
                        else -> Scaffold(topBar = { CenterAlignedTopAppBar(title = { Text("我的") }) }) { padding ->
                            FocusMyScreen(myModel, rememberLazyListState(), following,
                                onOpenLogin = { message = "离线登录入口" }, onOpenVideo = { message = "继续播放入口已触发" },
                                onOpenHistory = { route = "history" }, onOpenFolder = { folderID = it.id; folderTitle = it.title; route = "folder" },
                                onOpenUser = { message = "个人空间入口已触发" }, onOpenSettings = { message = "设置入口已触发" }, contentPadding = padding)
                        }
                    }
                    message?.let { text -> AlertDialog(onDismissRequest = { message = null }, text = { Text(text) }, confirmButton = { TextButton(onClick = { message = null }) { Text("完成") } }) }
                }
            }
        }
        captureFixtureScreenshotIfRequested()
    }
}

private fun ComponentActivity.captureFixtureScreenshotIfRequested() {
    val name = intent.getStringExtra("capture") ?: return
    require(name.matches(Regex("[A-Za-z0-9_-]{1,80}"))) { "Invalid fixture capture name" }
    window.decorView.postDelayed({
        val bitmap = Bitmap.createBitmap(window.decorView.width.coerceAtLeast(1), window.decorView.height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        PixelCopy.request(window, bitmap, { result ->
            if (result == PixelCopy.SUCCESS) {
                val directory = File(filesDir, "fixture-captures").apply { mkdirs() }
                FileOutputStream(File(directory, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
            bitmap.recycle()
        }, Handler(Looper.getMainLooper()))
    }, 1800)
}

private class PersonalFixtureHttpClient(empty: Boolean) : HttpClient {
    private val historyAIDs = if (empty) mutableListOf() else mutableListOf(42L, 43L)
    private val folders = if (empty) linkedMapOf() else linkedMapOf(1L to "学习收藏", 2L to "摄影灵感", 3L to "音乐现场")
    private val resources: MutableMap<Long, MutableList<Long>> = if (empty) mutableMapOf() else mutableMapOf(1L to mutableListOf(42L), 2L to mutableListOf(43L), 3L to mutableListOf())
    private fun fields(value: String): Map<String, String> = value.split('&').filter { it.isNotEmpty() }.associate { pair ->
        val parts = pair.split('=', limit = 2)
        java.net.URLDecoder.decode(parts[0], "UTF-8") to java.net.URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
    }
    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        val path = java.net.URI(url).path
        val query = fields(java.net.URI(url).rawQuery.orEmpty())
        val payload = when (path) {
            "/x/web-interface/nav" -> """{"isLogin":true,"mid":42,"uname":"专注看视频","face":"","level_info":{"current_level":5}}"""
            "/x/relation/stat" -> """{"following":128,"follower":36}"""
            "/x/web-interface/history/cursor" -> """{"list":[${historyAIDs.joinToString(",") { aid ->
                val title = if (aid == 42L) "从零理解光线追踪：让画面真正亮起来" else "周末城市漫步｜把平凡的日子拍成电影"
                """{"title":${org.json.JSONObject.quote(title)},"cover":"","author_name":"图形学实验室","view_at":${1800000000 - aid},"progress":126,"duration":600,"history":{"bvid":"BV1xx411c7mD$aid","oid":$aid,"business":"archive","cid":${aid + 59},"page":2}}"""
            }}],"cursor":{"max":0}}"""
            "/x/web-interface/history/search" -> {
                val matches = if (query["pn"] == "1") historyAIDs.filter { aid ->
                    val title = if (aid == 42L) "从零理解光线追踪：让画面真正亮起来" else "周末城市漫步｜把平凡的日子拍成电影"
                    title.contains(query["keyword"].orEmpty(), ignoreCase = true)
                } else emptyList()
                """{"list":[${matches.joinToString(",") { aid ->
                    val title = if (aid == 42L) "从零理解光线追踪：让画面真正亮起来" else "周末城市漫步｜把平凡的日子拍成电影"
                    """{"title":${org.json.JSONObject.quote(title)},"cover":"","author_name":"图形学实验室","view_at":${1800000000 - aid},"duration":600,"progress":126,"history":{"bvid":"BV1xx411c7mD$aid","oid":$aid,"business":"archive","cid":${aid + 59},"page":2}}"""
                }}],"cursor":{"fixture":"ignored"}}"""
            }
            "/x/v3/fav/folder/created/list-all" -> """{"list":[${folders.entries.joinToString(",") { (id, title) -> """{"id":$id,"title":${org.json.JSONObject.quote(title)},"media_count":${resources[id]?.size ?: 0}}""" }}]}"""
            "/x/v3/fav/resource/list" -> """{"medias":[${resources[query["media_id"]?.toLong()]?.joinToString(",") { aid -> """{"id":$aid,"bvid":"BV1xx411c7mD$aid","title":"从零理解光线追踪","cover":"","duration":600,"upper":{"name":"图形学实验室"},"cnt_info":{"play":18000}}""" }.orEmpty()}]}"""
            "/x/v3/fav/folder/info" -> """{"id":1,"title":"学习收藏","intro":"保留的简介","attr":1,"cover":""}"""
            "/x/relation/followings" -> """{"total":2,"list":[{"mid":101,"uname":"图形学实验室","face":""},{"mid":102,"uname":"生活记录","face":""}]}"""
            "/x/relation/attentions" -> """{"list":[]}"""
            else -> error("Unexpected offline fixture request: $path")
        }
        return HttpResponse(200, """{"code":0,"data":$payload}""")
    }
    override suspend fun post(url: String, body: String, headers: Map<String, String>): HttpResponse {
        val values = fields(body)
        when (java.net.URI(url).path) {
            "/x/v2/history/delete" -> historyAIDs.remove(values.getValue("kid").removePrefix("archive_").toLong())
            "/x/v2/history/clear" -> historyAIDs.clear()
            "/x/v3/fav/folder/del" -> values.getValue("media_ids").split(',').forEach { folders.remove(it.toLong()) }
            "/x/v3/fav/folder/add" -> { val id = (folders.keys.maxOrNull() ?: 0L) + 1L; folders[id] = values.getValue("title"); resources[id] = mutableListOf() }
            "/x/v3/fav/folder/edit" -> folders[values.getValue("media_id").toLong()] = values.getValue("title")
            "/x/v3/fav/resource/copy", "/x/v3/fav/resource/move" -> {
                val aid = values.getValue("resources").substringBefore(':').toLong()
                val source = values.getValue("src_media_id").toLong()
                val target = values.getValue("tar_media_id").toLong()
                if (java.net.URI(url).path.endsWith("/move")) resources[source]?.remove(aid)
                resources.getOrPut(target) { mutableListOf() }.let { if (aid !in it) it.add(aid) }
            }
            "/x/v3/fav/resource/batch-del" -> resources[values.getValue("media_id").toLong()]?.remove(values.getValue("resources").substringBefore(':').toLong())
            else -> error("Unexpected offline fixture mutation")
        }
        return HttpResponse(200, """{"code":0,"data":{}}""")
    }
}
