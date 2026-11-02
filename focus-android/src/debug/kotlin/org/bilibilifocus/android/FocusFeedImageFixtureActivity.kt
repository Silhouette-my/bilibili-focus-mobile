package org.bilibilifocus.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import coil.Coil
import coil.EventListener
import coil.ImageLoader
import coil.request.CachePolicy
import coil.request.ErrorResult
import coil.request.ImageRequest
import coil.request.SuccessResult
import coil.size.Scale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import okhttp3.OkHttpClient
import okhttp3.Handshake
import okhttp3.TlsVersion
import okhttp3.CipherSuite
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import org.bilibilifocus.android.ui.FocusDynamicFeedScreen
import org.bilibilifocus.android.ui.theme.BilibiliFocusTheme
import org.bilibilifocus.android.images.FocusDynamicImageRequest
import org.bilibilifocus.core.model.DynamicCard
import org.bilibilifocus.core.model.FocusThemeMode
import org.bilibilifocus.core.service.DynamicFeedService
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/** Production feed + production Coil components; all image HTTP responses are synthetic. */
class FocusFeedImageFixtureActivity : ComponentActivity() {
    private val requests = CopyOnWriteArrayList<String>()
    private val events = CopyOnWriteArrayList<JSONObject>()
    private var fixtureLoader: ImageLoader? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val run = intent.getStringExtra("run") ?: System.currentTimeMillis().toString()
        require(run.matches(Regex("[A-Za-z0-9_-]{1,64}")))
        fun imageURL(id: String, avatar: Boolean = false) = "http://i0.hdslb.com/bfs/${if (avatar) "face" else "archive"}/focus-fixture-$run-$id.png"
        val png = fixtureImage()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            val request = chain.request()
            check(request.url.host == "i0.hdslb.com" && request.url.encodedPath.contains("/focus-fixture-$run-"))
            requests += request.url.toString()
            val started = System.currentTimeMillis()
            Thread.sleep(250) // Controlled network latency, not a real-device speed benchmark.
            val rejectedDerivative = request.url.encodedPath.endsWith("-fallback.png@512w_512h_0e.webp")
            Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(if (rejectedDerivative) 404 else 200).message(if (rejectedDerivative) "Not Found" else "OK")
                // Coil correctly refuses a cached HTTPS response without TLS metadata.
                .handshake(Handshake.get(TlsVersion.TLS_1_3, CipherSuite.TLS_AES_128_GCM_SHA256, emptyList(), emptyList()))
                .header("Content-Type", "image/png").header("Cache-Control", "public, max-age=86400")
                .sentRequestAtMillis(started).receivedResponseAtMillis(System.currentTimeMillis())
                .body(png.toResponseBody("image/png".toMediaType())).build()
        }.build()
        val loader = (application as FocusApplication).newImageLoader().newBuilder()
            .okHttpClient(client)
            .eventListenerFactory {
                object : EventListener {
                    override fun onSuccess(request: ImageRequest, result: SuccessResult) {
                        events += JSONObject().put("url", request.data.toString()).put("source", result.dataSource.name)
                    }
                    override fun onError(request: ImageRequest, result: ErrorResult) {
                        events += JSONObject().put("url", request.data.toString()).put("error", result.throwable.toString())
                    }
                }
            }.build()
        fixtureLoader = loader
        Coil.setImageLoader(loader)
        val cards = (0 until 12).map { index ->
            DynamicCard(
                id = "fixture-$index", kind = DynamicCard.Kind.VIDEO,
                author = DynamicCard.Author("图片加载测试 $index", index + 1L, imageURL("avatar-$index", true)),
                publishTime = "离线测试", text = "动态封面 $index · 预加载与可见请求共用缓存",
                coverURLs = listOf(imageURL("cover-$index")), targetURL = "https://www.bilibili.com/",
            )
        }
        setContent {
            BilibiliFocusTheme(themeMode = FocusThemeMode.LIGHT) {
                val model = remember { FocusFeedViewModel(FeedPageFetcher { _, _ -> DynamicFeedService.FeedPage(cards, null) }, dispatcher = Dispatchers.Main) }
                val listState = rememberLazyListState()
                DisposableEffect(model) { onDispose { model.onCleared() } }
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    FocusDynamicFeedScreen(model, listState)
                }
                LaunchedEffect(Unit) {
                    delay(6_000)
                    val beforeScroll = requests.toList()
                    listState.scrollToItem(6)
                    delay(3_000)
                    val afterScroll = requests.toList()
                    val warmedCover = beforeScroll.any { it.contains("-cover-5.png") }
                    val coverCalls = afterScroll.count { it.contains("-cover-5.png") }
                    val concurrent = concurrentProbe(loader, imageURL("concurrent"))
                    val cancel = cancellationProbe(loader, imageURL("cancel"))
                    val diskURL = imageURL("disk")
                    val firstDisk = loader.execute(probeRequest(diskURL))
                    val disk = loader.execute(probeRequest(diskURL).newBuilder().memoryCachePolicy(CachePolicy.DISABLED).build())
                    val fallbacksIsolated = fallbackProbe(loader, imageURL("fallback"))
                    val report = JSONObject()
                        .put("warmedBeforeScroll", warmedCover).put("networkCallsForScrolledCover", coverCalls)
                        .put("allRequestsHTTPS", requests.all { it.startsWith("https://") })
                        .put("regularRequestsSized", requests.filterNot { it.contains("-fallback.png") }.all { it.contains("@") && it.endsWith(".webp") })
                        .put("concurrentSuccess", concurrent).put("concurrentFetchCount", requests.count { it.contains("-concurrent.png") })
                        .put("visibleSurvivesPrefetchCancellation", cancel)
                        .put("diskFirstSuccess", firstDisk is SuccessResult)
                        .put("diskReloadSource", (disk as? SuccessResult)?.dataSource?.name ?: disk.toString())
                        .put("fallbacksIsolated", fallbacksIsolated)
                        .put("requests", JSONArray(requests.toList())).put("results", JSONArray(events.toList()))
                    val folder = File(filesDir, "feed-image-fixtures").apply { mkdirs() }
                    File(folder, "$run.json").writeText(report.toString(2))
                    capture(File(folder, "$run.png"))
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Coil.setImageLoader((application as FocusApplication).newImageLoader())
        fixtureLoader?.shutdown()
    }

    private fun probeRequest(url: String) = FocusDynamicImageRequest(url, 512, 288, Scale.FILL).build(this)

    private suspend fun concurrentProbe(loader: ImageLoader, url: String): Boolean = coroutineScope {
        val prefetch = async { loader.execute(probeRequest(url)) }
        delay(60)
        val visible = async { loader.execute(probeRequest(url)) }
        prefetch.await() is SuccessResult && visible.await() is SuccessResult
    }

    private suspend fun cancellationProbe(loader: ImageLoader, url: String): Boolean = coroutineScope {
        val prefetch = async { loader.execute(probeRequest(url)) }
        delay(60)
        val visible = async { loader.execute(probeRequest(url)) }
        delay(60)
        prefetch.cancel()
        visible.await() is SuccessResult
    }

    private suspend fun fallbackProbe(loader: ImageLoader, url: String): Boolean = coroutineScope {
        val smallSource = async { loader.execute(probeRequest("$url@100w.webp")) }
        val originalSource = async { loader.execute(probeRequest(url)) }
        val small = smallSource.await()
        val original = originalSource.await()
        small is SuccessResult && original is SuccessResult &&
            small.request.data.toString().endsWith("@100w.webp") &&
            original.request.data.toString().endsWith("-fallback.png")
    }

    private fun capture(file: File) {
        val bitmap = Bitmap.createBitmap(window.decorView.width, window.decorView.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(window, bitmap, { result ->
            if (result == PixelCopy.SUCCESS) {
                val pending = File(file.parentFile, "${file.name}.tmp")
                pending.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                check(pending.renameTo(file))
            }
            bitmap.recycle()
        }, Handler(Looper.getMainLooper()))
    }

    private fun fixtureImage(): ByteArray {
        val bitmap = Bitmap.createBitmap(960, 540, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.rgb(32, 46, 67))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(251, 114, 153) }
        canvas.drawCircle(720f, 180f, 150f, paint)
        paint.color = Color.WHITE
        paint.textSize = 56f
        canvas.drawText("FOCUS / IMAGE CACHE", 48f, 310f, paint)
        val output = ByteArrayOutputStream()
        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
        bitmap.recycle()
        return output.toByteArray()
    }
}
