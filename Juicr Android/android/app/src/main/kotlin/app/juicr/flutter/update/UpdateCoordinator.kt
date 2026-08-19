package app.juicr.flutter.update

import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicLong

fun interface UpdateTaskRunner {
    fun execute(task: () -> Unit)
}

class UpdateCoordinator(
    private val lane: String,
    private val rootDirectory: File,
    private val stateStore: UpdateStateStore,
    private val transfer: UpdateTransferGateway,
    private val verifier: UpdateVerifierGateway,
    private val installer: UpdateInstallerGateway,
    private val taskRunner: UpdateTaskRunner,
) {
    private val listeners = CopyOnWriteArrayList<(AppUpdateSnapshot) -> Unit>()
    private val installGeneration = AtomicLong(0)
    private val operationGeneration = AtomicLong(0)
    @Volatile private var currentRequest: AppUpdateRequest? = null
    private var pendingInstallRecovery: PendingInstallRecovery? = null

    @Volatile
    var snapshot: AppUpdateSnapshot = AppUpdateSnapshot(AppUpdateStage.IDLE)
        private set

    init {
        stateStore.restore()?.let { restored ->
            currentRequest = restored.request
            restored.installGeneration?.let { generation ->
                installGeneration.set(generation)
            }
            when (restored.snapshot.stage) {
                AppUpdateStage.VERIFYING,
                AppUpdateStage.READY_TO_INSTALL,
                -> {
                    snapshot = restored.snapshot.copy(stage = AppUpdateStage.VERIFYING)
                    val operation = operationGeneration.incrementAndGet()
                    taskRunner.execute {
                        verifyCompleted(
                            restored.request,
                            File(rootDirectory, restored.partialFileName),
                            operation,
                        )
                    }
                }
                AppUpdateStage.INSTALLING,
                AppUpdateStage.AWAITING_CONFIRMATION,
                -> {
                    val generation = restored.installGeneration
                    if (generation == null) {
                        snapshot = restored.snapshot.copy(
                            stage = AppUpdateStage.FAILED,
                            failure = AppUpdateFailure.INSTALL_FAILED,
                        )
                    } else {
                        val sessionActive = installer.restoreOwnedGeneration(
                            generation,
                            restored.installSessionId,
                        )
                        if (sessionActive) {
                            snapshot = restored.snapshot
                        } else {
                            snapshot = restored.snapshot.copy(stage = AppUpdateStage.VERIFYING)
                            pendingInstallRecovery = PendingInstallRecovery(
                                restored.request,
                                File(rootDirectory, restored.partialFileName),
                                generation,
                            )
                        }
                    }
                }
                else -> snapshot = restored.snapshot
            }
        }
    }

    fun addListener(listener: (AppUpdateSnapshot) -> Unit) {
        listeners.add(listener)
        listener(snapshot)
    }

    fun removeListener(listener: (AppUpdateSnapshot) -> Unit) {
        listeners.remove(listener)
    }

    @Synchronized
    fun reconcileRestoredInstall() {
        val pending = pendingInstallRecovery ?: return
        if (snapshot.stage != AppUpdateStage.VERIFYING) {
            pendingInstallRecovery = null
            return
        }
        pendingInstallRecovery = null
        val operation = operationGeneration.incrementAndGet()
        taskRunner.execute {
            verifyRecoveredInstall(
                pending.request,
                pending.file,
                pending.generation,
                operation,
            )
        }
    }

    @Synchronized
    fun start(request: AppUpdateRequest) {
        if (installOwnsRoute()) return
        val validationFailure = AppUpdateRequestValidator.validate(request, lane)
        if (validationFailure != null) {
            publish(
                AppUpdateSnapshot(
                    stage = AppUpdateStage.FAILED,
                    releaseTag = request.releaseTag,
                    assetName = request.assetName,
                    expectedSize = request.expectedSize,
                    failure = validationFailure,
                ),
            )
            return
        }
        currentRequest = request
        val operation = operationGeneration.incrementAndGet()
        stateStore.replaceIdentity(request)
        runTransfer(request, operation)
    }

    @Synchronized
    fun pause() {
        if (snapshot.stage == AppUpdateStage.DOWNLOADING) transfer.pause()
    }

    @Synchronized
    fun resume() {
        if (snapshot.stage != AppUpdateStage.PAUSED) return
        currentRequest?.let { request ->
            runTransfer(request, operationGeneration.incrementAndGet())
        }
    }

    @Synchronized
    fun cancel() {
        if (installOwnsRoute()) return
        operationGeneration.incrementAndGet()
        transfer.cancel()
        stateStore.clear(deletePartial = true)
        currentRequest = null
        publish(AppUpdateSnapshot(AppUpdateStage.IDLE))
    }

    @Synchronized
    fun deleteDownload() {
        if (installOwnsRoute()) return
        operationGeneration.incrementAndGet()
        currentRequest?.let { File(rootDirectory, it.assetName).delete() }
        stateStore.clear(deletePartial = true)
        currentRequest = null
        publish(AppUpdateSnapshot(AppUpdateStage.IDLE))
    }

    @Synchronized
    fun install() {
        if (snapshot.stage != AppUpdateStage.READY_TO_INSTALL) return
        val request = currentRequest ?: return
        val file = File(rootDirectory, request.assetName)
        if (!installer.canInstallPackages()) {
            publishAndPersist(
                snapshot.copy(
                    stage = AppUpdateStage.AWAITING_PERMISSION,
                    failure = AppUpdateFailure.INSTALL_PERMISSION,
                ),
            )
            return
        }
        val generation = installGeneration.incrementAndGet()
        publishAndPersist(
            snapshot.copy(stage = AppUpdateStage.INSTALLING, failure = null),
            installGeneration = generation,
        )
        taskRunner.execute {
            when (installer.install(file, generation) { sessionId ->
                recordInstallSession(generation, sessionId)
            }) {
                InstallStartResult.Started -> Unit
                InstallStartResult.AwaitingPermission -> publishAndPersist(
                    snapshot.copy(
                        stage = AppUpdateStage.AWAITING_PERMISSION,
                        failure = AppUpdateFailure.INSTALL_PERMISSION,
                    ),
                )
                InstallStartResult.AlreadyInstalling -> Unit
                InstallStartResult.Failed -> publishAndPersist(
                    snapshot.copy(
                        stage = AppUpdateStage.FAILED,
                        failure = installer.lastFailure ?: AppUpdateFailure.INSTALL_FAILED,
                    ),
                )
            }
        }
    }

    fun openInstallPermissionSettings() = installer.openPermissionSettings()

    @Synchronized
    fun refreshInstallPermission() {
        if (
            snapshot.stage == AppUpdateStage.AWAITING_PERMISSION &&
            installer.canInstallPackages()
        ) {
            publishAndPersist(snapshot.copy(stage = AppUpdateStage.READY_TO_INSTALL, failure = null))
        }
    }

    @Synchronized
    fun acceptInstallStatus(generation: Long, status: InstallStatus) {
        val stage = installer.acceptStatus(generation, status) ?: return
        pendingInstallRecovery = null
        if (stage != AppUpdateStage.AWAITING_CONFIRMATION) operationGeneration.incrementAndGet()
        val retainedGeneration = if (stage == AppUpdateStage.AWAITING_CONFIRMATION) generation else null
        publishAndPersist(
            snapshot.copy(stage = stage, failure = installer.lastFailure),
            installGeneration = retainedGeneration,
            installSessionId = if (retainedGeneration == null) null else stateStore.restore()?.installSessionId,
        )
    }

    @Synchronized
    fun dispose() {
        operationGeneration.incrementAndGet()
        pendingInstallRecovery = null
        transfer.pause()
        installer.dispose()
        listeners.clear()
    }

    internal fun restoreReadyForTest(request: AppUpdateRequest) {
        operationGeneration.incrementAndGet()
        currentRequest = request
        val ready = AppUpdateSnapshot(
            stage = AppUpdateStage.READY_TO_INSTALL,
            releaseTag = request.releaseTag,
            assetName = request.assetName,
            expectedSize = request.expectedSize,
            downloadedBytes = request.expectedSize,
        )
        stateStore.save(PersistedUpdateState(request, ready, request.assetName))
        publish(ready)
    }

    private fun runTransfer(request: AppUpdateRequest, operation: Long) {
        val transferGeneration = transfer.beginGeneration()
        publish(
            AppUpdateSnapshot(
                stage = AppUpdateStage.DOWNLOADING,
                releaseTag = request.releaseTag,
                assetName = request.assetName,
                expectedSize = request.expectedSize,
                downloadedBytes = stateStore.restore()?.snapshot?.downloadedBytes ?: 0,
            ),
        )
        taskRunner.execute {
            when (val result = transfer.transfer(request, transferGeneration) { downloaded ->
                if (ownsOperation(request, operation)) {
                    publish(
                        snapshot.copy(
                            stage = AppUpdateStage.DOWNLOADING,
                            downloadedBytes = downloaded,
                        ),
                    )
                }
            }) {
                is UpdateTransferResult.Complete -> verifyCompleted(request, result.file, operation)
                is UpdateTransferResult.Paused -> if (ownsOperation(request, operation)) {
                    publish(
                        snapshot.copy(
                            stage = AppUpdateStage.PAUSED,
                            downloadedBytes = result.downloadedBytes,
                        ),
                    )
                }
                is UpdateTransferResult.Failed -> if (ownsOperation(request, operation)) {
                    publish(snapshot.copy(stage = AppUpdateStage.FAILED, failure = result.failure))
                }
                UpdateTransferResult.Cancelled -> Unit
            }
        }
    }

    private fun verifyCompleted(request: AppUpdateRequest, file: File, operation: Long) {
        if (!ownsOperation(request, operation)) return
        publish(snapshot.copy(stage = AppUpdateStage.VERIFYING, downloadedBytes = request.expectedSize))
        val failure = verifier.verify(request, file)
        if (!ownsOperation(request, operation)) return
        if (failure != null) {
            file.delete()
            stateStore.clear(deletePartial = false)
            publish(snapshot.copy(stage = AppUpdateStage.FAILED, failure = failure))
            return
        }
        val ready = snapshot.copy(
            stage = AppUpdateStage.READY_TO_INSTALL,
            downloadedBytes = request.expectedSize,
            failure = null,
        )
        stateStore.save(PersistedUpdateState(request, ready, file.name))
        publish(ready)
    }

    private fun verifyRecoveredInstall(
        request: AppUpdateRequest,
        file: File,
        generation: Long,
        operation: Long,
    ) {
        if (!ownsOperation(request, operation)) return
        val failure = verifier.verify(request, file)
        if (!ownsOperation(request, operation)) return
        installer.abandonOwnedGeneration(generation)
        if (failure != null) {
            file.delete()
            stateStore.clear(deletePartial = false)
            publish(snapshot.copy(stage = AppUpdateStage.FAILED, failure = failure))
            return
        }
        publishAndPersist(
            snapshot.copy(stage = AppUpdateStage.READY_TO_INSTALL, failure = null),
            installGeneration = null,
            installSessionId = null,
        )
    }

    @Synchronized
    private fun recordInstallSession(generation: Long, sessionId: Int) {
        if (snapshot.stage != AppUpdateStage.INSTALLING) return
        val restored = stateStore.restore() ?: return
        if (restored.installGeneration != generation) return
        publishAndPersist(
            snapshot,
            installGeneration = generation,
            installSessionId = sessionId,
        )
    }

    private fun installOwnsRoute(): Boolean =
        snapshot.stage == AppUpdateStage.INSTALLING ||
            snapshot.stage == AppUpdateStage.AWAITING_CONFIRMATION

    private fun ownsOperation(request: AppUpdateRequest, operation: Long): Boolean =
        operationGeneration.get() == operation && currentRequest == request

    private fun publish(value: AppUpdateSnapshot) {
        snapshot = value
        listeners.forEach { listener -> listener(value) }
    }

    private fun publishAndPersist(
        value: AppUpdateSnapshot,
        installGeneration: Long? = stateStore.restore()?.installGeneration,
        installSessionId: Int? = stateStore.restore()?.installSessionId,
    ) {
        val request = currentRequest ?: return publish(value)
        val restored = stateStore.restore()
        stateStore.save(
            PersistedUpdateState(
                request = request,
                snapshot = value,
                partialFileName = restored?.partialFileName ?: request.assetName,
                entityTag = restored?.entityTag,
                installGeneration = installGeneration,
                installSessionId = installSessionId,
            ),
        )
        publish(value)
    }

    private data class PendingInstallRecovery(
        val request: AppUpdateRequest,
        val file: File,
        val generation: Long,
    )
}
