package app.juicr.flutter.update

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicLong
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request

sealed class UpdateTransferResult {
    data class Complete(val file: File) : UpdateTransferResult()
    data class Paused(val downloadedBytes: Long) : UpdateTransferResult()
    data class Failed(val failure: AppUpdateFailure) : UpdateTransferResult()
    data object Cancelled : UpdateTransferResult()
}

internal class ProgressCheckpointPolicy(private val intervalBytes: Long) {
    private var lastPersistedBytes = Long.MIN_VALUE

    fun shouldPersist(downloadedBytes: Long): Boolean =
        lastPersistedBytes == Long.MIN_VALUE ||
            downloadedBytes - lastPersistedBytes >= intervalBytes

    fun markPersisted(downloadedBytes: Long) {
        lastPersistedBytes = downloadedBytes
    }
}

interface UpdateTransferGateway {
    fun beginGeneration(): Long
    fun pause()
    fun cancel()
    fun transfer(
        request: AppUpdateRequest,
        generation: Long,
        onProgress: (Long) -> Unit,
    ): UpdateTransferResult
}

class UpdateDownloadOwner(
    private val client: OkHttpClient,
    private val rootDirectory: File,
    private val stateStore: UpdateStateStore,
    private val allowedFinalHosts: Set<String> = setOf(
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ),
) : UpdateTransferGateway {
    private enum class StopMode { NONE, PAUSE, CANCEL }

    private val generationCounter = AtomicLong(0)
    @Volatile private var activeCall: Call? = null
    @Volatile private var stopMode = StopMode.NONE

    override fun beginGeneration(): Long {
        activeCall?.cancel()
        stopMode = StopMode.CANCEL
        return generationCounter.incrementAndGet()
    }

    override fun pause() {
        stopMode = StopMode.PAUSE
        activeCall?.cancel()
    }

    override fun cancel() {
        stopMode = StopMode.CANCEL
        generationCounter.incrementAndGet()
        activeCall?.cancel()
    }

    fun transfer(
        request: AppUpdateRequest,
        onProgress: (Long) -> Unit = {},
    ): UpdateTransferResult = transfer(request, beginGeneration(), onProgress)

    fun transfer(
        request: AppUpdateRequest,
        generation: Long,
    ): UpdateTransferResult = transfer(request, generation) {}

    override fun transfer(
        request: AppUpdateRequest,
        generation: Long,
        onProgress: (Long) -> Unit,
    ): UpdateTransferResult {
        if (generation != generationCounter.get()) return UpdateTransferResult.Cancelled
        stopMode = StopMode.NONE
        rootDirectory.mkdirs()

        var state = stateStore.restore()
        if (state == null || state.request != request) {
            state = stateStore.replaceIdentity(request)
        }
        var partialFile = File(rootDirectory, state.partialFileName)
        if (!partialFile.name.endsWith(".part")) {
            partialFile = File(rootDirectory, "${request.assetName}.part")
        }
        var downloaded = partialFile.takeIf(File::isFile)?.length() ?: 0L
        if (downloaded > request.expectedSize) {
            partialFile.delete()
            return fail(request, partialFile.name, AppUpdateFailure.SIZE_MISMATCH, 0)
        }
        var entityTag = state.entityTag
        val checkpointPolicy = ProgressCheckpointPolicy(PROGRESS_CHECKPOINT_BYTES)
        saveProgress(request, partialFile.name, AppUpdateStage.DOWNLOADING, downloaded, entityTag)
        checkpointPolicy.markPersisted(downloaded)

        var resetAfterRangeFailure = false
        while (true) {
            if (!owns(generation)) {
                return stoppedResult(generation, request, partialFile, downloaded, entityTag)
            }
            val requestBuilder = Request.Builder().url(request.assetUrl).get()
            if (downloaded > 0) {
                requestBuilder.header("Range", "bytes=$downloaded-")
                entityTag?.let { requestBuilder.header("If-Range", it) }
            }
            val call = client.newCall(requestBuilder.build())
            activeCall = call
            try {
                call.execute().use { response ->
                    if (!owns(generation)) {
                        return stoppedResult(generation, request, partialFile, downloaded, entityTag)
                    }
                    if (response.request.url.host !in allowedFinalHosts) {
                        return fail(request, partialFile.name, AppUpdateFailure.ASSET_CHANGED, downloaded)
                    }
                    if (response.code == 416 && downloaded > 0 && !resetAfterRangeFailure) {
                        partialFile.delete()
                        downloaded = 0
                        entityTag = null
                        resetAfterRangeFailure = true
                        saveProgress(request, partialFile.name, AppUpdateStage.DOWNLOADING, 0, null)
                        continue
                    }
                    val append = when {
                        response.code == 206 && downloaded > 0 -> {
                            val range = parseContentRange(response.header("Content-Range"))
                            if (
                                range == null ||
                                range.first != downloaded ||
                                range.total != request.expectedSize ||
                                (entityTag != null && response.header("ETag") != null &&
                                    response.header("ETag") != entityTag)
                            ) {
                                return fail(
                                    request,
                                    partialFile.name,
                                    AppUpdateFailure.ASSET_CHANGED,
                                    downloaded,
                                )
                            }
                            true
                        }
                        response.code == 200 -> {
                            if (downloaded > 0) {
                                partialFile.delete()
                                downloaded = 0
                            }
                            false
                        }
                        else -> return fail(
                            request,
                            partialFile.name,
                            AppUpdateFailure.NETWORK,
                            downloaded,
                        )
                    }
                    val body = response.body ?: return fail(
                        request,
                        partialFile.name,
                        AppUpdateFailure.NETWORK,
                        downloaded,
                    )
                    entityTag = response.header("ETag") ?: entityTag
                    var exceededExpectedSize = false
                    FileOutputStream(partialFile, append).use { output ->
                        body.byteStream().use { input ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                            while (true) {
                                if (!owns(generation)) {
                                    return stoppedResult(
                                        generation,
                                        request,
                                        partialFile,
                                        downloaded,
                                        entityTag,
                                    )
                                }
                                val count = input.read(buffer)
                                if (count < 0) break
                                if (downloaded + count > request.expectedSize) {
                                    exceededExpectedSize = true
                                    break
                                }
                                output.write(buffer, 0, count)
                                downloaded += count
                                onProgress(downloaded)
                                if (checkpointPolicy.shouldPersist(downloaded)) {
                                    saveProgress(
                                        request,
                                        partialFile.name,
                                        AppUpdateStage.DOWNLOADING,
                                        downloaded,
                                        entityTag,
                                    )
                                    checkpointPolicy.markPersisted(downloaded)
                                }
                            }
                            output.fd.sync()
                        }
                    }
                    if (exceededExpectedSize) {
                        partialFile.delete()
                        return fail(
                            request,
                            partialFile.name,
                            AppUpdateFailure.SIZE_MISMATCH,
                            0,
                        )
                    }
                }
            } catch (_: IOException) {
                return if (!owns(generation) || stopMode != StopMode.NONE) {
                    stoppedResult(generation, request, partialFile, downloaded, entityTag)
                } else {
                    fail(request, partialFile.name, AppUpdateFailure.NETWORK, downloaded)
                }
            } finally {
                if (activeCall === call) activeCall = null
            }
            if (downloaded != request.expectedSize) {
                return fail(
                    request,
                    partialFile.name,
                    AppUpdateFailure.SIZE_MISMATCH,
                    downloaded,
                )
            }
            val completeFile = File(rootDirectory, request.assetName)
            completeFile.delete()
            if (!partialFile.renameTo(completeFile)) {
                return fail(request, partialFile.name, AppUpdateFailure.STORAGE, downloaded)
            }
            saveProgress(
                request,
                completeFile.name,
                AppUpdateStage.VERIFYING,
                downloaded,
                entityTag,
            )
            return UpdateTransferResult.Complete(completeFile)
        }
    }

    private fun owns(generation: Long): Boolean =
        generation == generationCounter.get() && stopMode == StopMode.NONE

    private fun stoppedResult(
        generation: Long,
        request: AppUpdateRequest,
        partialFile: File,
        downloadedBytes: Long,
        entityTag: String?,
    ): UpdateTransferResult {
        if (isStaleGeneration(generation)) return UpdateTransferResult.Cancelled
        return when (stopMode) {
        StopMode.PAUSE -> {
            saveProgress(
                request,
                partialFile.name,
                AppUpdateStage.PAUSED,
                downloadedBytes,
                entityTag,
            )
            UpdateTransferResult.Paused(downloadedBytes)
        }
        StopMode.CANCEL, StopMode.NONE -> {
            partialFile.delete()
            stateStore.clear(deletePartial = false)
            UpdateTransferResult.Cancelled
        }
        }
    }

    private fun isStaleGeneration(generation: Long): Boolean =
        generation != generationCounter.get()

    private fun fail(
        request: AppUpdateRequest,
        fileName: String,
        failure: AppUpdateFailure,
        downloadedBytes: Long,
    ): UpdateTransferResult.Failed {
        saveProgress(
            request,
            fileName,
            AppUpdateStage.FAILED,
            downloadedBytes,
            null,
            failure,
        )
        return UpdateTransferResult.Failed(failure)
    }

    private fun saveProgress(
        request: AppUpdateRequest,
        fileName: String,
        stage: AppUpdateStage,
        downloadedBytes: Long,
        entityTag: String?,
        failure: AppUpdateFailure? = null,
    ) {
        stateStore.save(
            PersistedUpdateState(
                request = request,
                snapshot = AppUpdateSnapshot(
                    stage = stage,
                    releaseTag = request.releaseTag,
                    assetName = request.assetName,
                    expectedSize = request.expectedSize,
                    downloadedBytes = downloadedBytes,
                    failure = failure,
                ),
                partialFileName = fileName,
                entityTag = entityTag,
            ),
        )
    }

    private data class ContentRange(val first: Long, val last: Long, val total: Long)

    companion object {
        private const val PROGRESS_CHECKPOINT_BYTES = 1024L * 1024L
    }

    private fun parseContentRange(value: String?): ContentRange? {
        val match = Regex("^bytes ([0-9]+)-([0-9]+)/([0-9]+)$").matchEntire(value ?: "")
            ?: return null
        val first = match.groupValues[1].toLongOrNull() ?: return null
        val last = match.groupValues[2].toLongOrNull() ?: return null
        val total = match.groupValues[3].toLongOrNull() ?: return null
        if (first > last || last >= total) return null
        return ContentRange(first, last, total)
    }
}
