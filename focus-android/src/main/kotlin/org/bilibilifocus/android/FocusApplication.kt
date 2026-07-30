package org.bilibilifocus.android

import android.app.Application
import android.os.Build
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.decode.GifDecoder
import coil.decode.ImageDecoderDecoder
import org.bilibilifocus.android.playback.AndroidFocusPlaybackPersistence
import org.bilibilifocus.android.playback.FocusPlaybackProgressStore
import org.bilibilifocus.android.playback.FocusPlaybackHistoryWorkScheduler

class FocusApplication : Application(), ImageLoaderFactory {
    val appGraph: FocusAppGraph by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        FocusAppGraph(
            playbackProgressStore = FocusPlaybackProgressStore(
                AndroidFocusPlaybackPersistence(this),
            ),
        )
    }

    override fun onCreate() {
        super.onCreate()
        FocusPlaybackHistoryWorkScheduler.enqueue(this)
    }

    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .components {
            if (Build.VERSION.SDK_INT >= 28) {
                add(ImageDecoderDecoder.Factory())
            } else {
                add(GifDecoder.Factory())
            }
        }
        .build()

    override fun onTerminate() {
        appGraph.close()
        super.onTerminate()
    }
}
