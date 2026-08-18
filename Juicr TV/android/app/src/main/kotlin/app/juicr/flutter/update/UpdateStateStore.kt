package app.juicr.flutter.update

import java.io.File
import java.io.FileOutputStream
import java.util.Properties

data class PersistedUpdateState(
    val request: AppUpdateRequest,
    val snapshot: AppUpdateSnapshot,
    val partialFileName: String,
    val entityTag: String? = null,
    val installGeneration: Long? = null,
    val installSessionId: Int? = null,
)

class UpdateStateStore(
    private val rootDirectory: File,
    private val validateRequest: (AppUpdateRequest) -> Boolean = { request ->
        val lane = when {
            request.assetName.startsWith("juicr-android-") -> "android"
            request.assetName.startsWith("juicr-tv-") -> "tv"
            else -> ""
        }
        lane.isNotEmpty() && AppUpdateRequestValidator.validate(request, lane) == null
    },
) {
    private val stateFile = File(rootDirectory, STATE_FILE_NAME)

    init {
        rootDirectory.mkdirs()
    }

    @Synchronized
    fun save(state: PersistedUpdateState) {
        require(isSafeFileName(state.partialFileName))
        val properties = Properties().apply {
            setProperty("schema", SCHEMA_VERSION)
            setProperty("releaseTag", state.request.releaseTag)
            setProperty("assetName", state.request.assetName)
            setProperty("assetUrl", state.request.assetUrl)
            setProperty("expectedSize", state.request.expectedSize.toString())
            setProperty("expectedSha256", state.request.expectedSha256)
            setProperty("stage", state.snapshot.stage.wireValue)
            setProperty("downloadedBytes", state.snapshot.downloadedBytes.toString())
            setProperty("failure", state.snapshot.failure?.wireValue.orEmpty())
            setProperty("partialFileName", state.partialFileName)
            setProperty("entityTag", state.entityTag.orEmpty())
            setProperty("installGeneration", state.installGeneration?.toString().orEmpty())
            setProperty("installSessionId", state.installSessionId?.toString().orEmpty())
        }
        val temporary = File(rootDirectory, "$STATE_FILE_NAME.tmp")
        FileOutputStream(temporary).use { output ->
            properties.store(output, null)
            output.fd.sync()
        }
        commitUpdateFile(temporary, stateFile)
    }

    @Synchronized
    fun restore(): PersistedUpdateState? {
        recoverUpdateFile(stateFile)
        if (!stateFile.isFile) return null
        val restored = runCatching {
            val properties = Properties().apply {
                stateFile.inputStream().use(::load)
            }
            require(properties.getProperty("schema") in SUPPORTED_SCHEMA_VERSIONS)
            val request = AppUpdateRequest(
                releaseTag = properties.required("releaseTag"),
                assetName = properties.required("assetName"),
                assetUrl = properties.required("assetUrl"),
                expectedSize = properties.required("expectedSize").toLong(),
                expectedSha256 = properties.required("expectedSha256"),
            )
            require(validateRequest(request))
            val persistedStage = AppUpdateStage.fromWireValue(properties.required("stage"))
                ?: error("Unknown stage")
            val restoredStage = if (persistedStage == AppUpdateStage.DOWNLOADING) {
                AppUpdateStage.PAUSED
            } else {
                persistedStage
            }
            val downloaded = properties.required("downloadedBytes").toLong().coerceAtLeast(0)
            val failureValue = properties.getProperty("failure").orEmpty()
            val failure = failureValue.takeIf(String::isNotEmpty)?.let {
                AppUpdateFailure.fromWireValue(it) ?: error("Unknown failure")
            }
            val partialFileName = properties.required("partialFileName")
            require(isSafeFileName(partialFileName))
            PersistedUpdateState(
                request = request,
                snapshot = AppUpdateSnapshot(
                    stage = restoredStage,
                    releaseTag = request.releaseTag,
                    assetName = request.assetName,
                    expectedSize = request.expectedSize,
                    downloadedBytes = downloaded,
                    failure = failure,
                ),
                partialFileName = partialFileName,
                entityTag = properties.getProperty("entityTag").orEmpty().ifEmpty { null },
                installGeneration = properties.getProperty("installGeneration")
                    .orEmpty()
                    .ifEmpty { null }
                    ?.toLong()
                    ?.takeIf { it > 0 },
                installSessionId = properties.getProperty("installSessionId")
                    .orEmpty()
                    .ifEmpty { null }
                    ?.toInt()
                    ?.takeIf { it >= 0 },
            )
        }.getOrNull()
        if (restored == null) clear(deletePartial = false)
        return restored
    }

    @Synchronized
    fun replaceIdentity(request: AppUpdateRequest): PersistedUpdateState {
        val current = restore()
        if (current != null && current.request != request) {
            File(rootDirectory, current.partialFileName).delete()
        }
        val replacement = PersistedUpdateState(
            request = request,
            snapshot = AppUpdateSnapshot(
                stage = AppUpdateStage.AVAILABLE,
                releaseTag = request.releaseTag,
                assetName = request.assetName,
                expectedSize = request.expectedSize,
            ),
            partialFileName = "${request.assetName}.part",
        )
        save(replacement)
        return replacement
    }

    @Synchronized
    fun clear(deletePartial: Boolean = true) {
        if (deletePartial) {
            restore()?.let { File(rootDirectory, it.partialFileName).delete() }
        }
        stateFile.delete()
        File(rootDirectory, "$STATE_FILE_NAME.tmp").delete()
        File(rootDirectory, "$STATE_FILE_NAME.bak").delete()
    }

    private fun isSafeFileName(value: String): Boolean =
        value.isNotEmpty() && value == File(value).name && !value.contains("..")

    private fun Properties.required(name: String): String =
        getProperty(name)?.takeIf(String::isNotEmpty) ?: error("Missing $name")

    companion object {
        const val STATE_FILE_NAME = "app-update-state.properties"
        private const val SCHEMA_VERSION = "3"
        private val SUPPORTED_SCHEMA_VERSIONS = setOf("2", SCHEMA_VERSION)
    }
}
