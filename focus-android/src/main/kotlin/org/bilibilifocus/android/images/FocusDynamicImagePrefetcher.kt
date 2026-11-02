package org.bilibilifocus.android.images

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** Owns only optional prefetch consumers. Visible Coil requests never enter this queue. */
internal class FocusDynamicImagePrefetcher(
    parentScope: CoroutineScope,
    private val load: suspend (FocusDynamicImageRequest) -> Unit,
) {
    private val scope = CoroutineScope(parentScope.coroutineContext + SupervisorJob(parentScope.coroutineContext[Job]))
    private val permits = Semaphore(2)
    private val requests = linkedMapOf<FocusDynamicImageRequest, Job>()

    fun update(window: List<FocusDynamicImageRequest>) {
        val desired = window.toSet()
        requests.keys.filter { it !in desired }.forEach { key -> requests.remove(key)?.cancel() }
        window.distinct().forEach { request ->
            if (request !in requests) requests[request] = scope.launch { permits.withPermit { load(request) } }
        }
    }

    fun clear() = update(emptyList())

    fun close() {
        requests.clear()
        scope.cancel()
    }
}
