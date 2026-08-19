package app.juicr.flutter.update

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateCoordinatorTest {
    @Test
    fun `restores interrupted download as paused and replays safe snapshot`() = withRoot { root ->
        val store = testStore(root)
        val request = validRequest()
        store.save(
            PersistedUpdateState(
                request,
                AppUpdateSnapshot(AppUpdateStage.DOWNLOADING, request.releaseTag, request.assetName, 3, 1),
                "${request.assetName}.part",
            ),
        )

        val coordinator = coordinator(root, store = store)

        assertEquals(AppUpdateStage.PAUSED, coordinator.snapshot.stage)
        assertEquals(1L, coordinator.snapshot.downloadedBytes)
        assertEquals(AppUpdateSnapshot::class, coordinator.snapshot::class)
    }

    @Test
    fun `invalid request fails closed before transfer`() = withRoot { root ->
        val transfer = FakeTransfer()
        val coordinator = coordinator(root, transfer = transfer)

        coordinator.start(validRequest().copy(assetName = "juicr-tv-v2.0.0-x86_64.apk"))

        assertEquals(AppUpdateStage.FAILED, coordinator.snapshot.stage)
        assertEquals(AppUpdateFailure.WRONG_LANE, coordinator.snapshot.failure)
        assertEquals(0, transfer.calls)
    }

    @Test
    fun `download verifies before ready and publishes bounded progress`() = withRoot { root ->
        val request = validRequest()
        val apk = File(root, request.assetName).apply { writeText("apk") }
        val transfer = FakeTransfer { _, _, progress ->
            progress(2)
            UpdateTransferResult.Complete(apk)
        }
        val verifier = FakeVerifier()
        val events = mutableListOf<AppUpdateSnapshot>()
        val coordinator = coordinator(root, transfer = transfer, verifier = verifier)
        coordinator.addListener { events.add(it) }

        coordinator.start(request)

        assertEquals(AppUpdateStage.READY_TO_INSTALL, coordinator.snapshot.stage)
        assertEquals(1, verifier.calls)
        assertTrue(events.any { it.stage == AppUpdateStage.DOWNLOADING && it.downloadedBytes == 2L })
        assertTrue(events.any { it.stage == AppUpdateStage.VERIFYING })
    }

    @Test
    fun `verification failure removes candidate and never becomes installable`() = withRoot { root ->
        val request = validRequest()
        val apk = File(root, request.assetName).apply { writeText("apk") }
        val coordinator = coordinator(
            root,
            transfer = FakeTransfer { _, _, _ -> UpdateTransferResult.Complete(apk) },
            verifier = FakeVerifier(AppUpdateFailure.SIGNER_MISMATCH),
        )

        coordinator.start(request)

        assertEquals(AppUpdateStage.FAILED, coordinator.snapshot.stage)
        assertEquals(AppUpdateFailure.SIGNER_MISMATCH, coordinator.snapshot.failure)
        assertFalse(apk.exists())
    }

    @Test
    fun `replaced request cannot verify or publish from stale transfer task`() = withRoot { root ->
        val first = validRequest()
        val replacement = first.copy(
            releaseTag = "v2.0.1",
            assetName = "juicr-android-v2.0.1-x86_64.apk",
            assetUrl = "https://github.com/Team-Juicr/Juicr/releases/download/v2.0.1/juicr-android-v2.0.1-x86_64.apk",
        )
        val transfer = FakeTransfer { request, _, _ ->
            val apk = File(root, request.assetName).apply { writeText("apk") }
            UpdateTransferResult.Complete(apk)
        }
        val verifier = FakeVerifier()
        val runner = QueuedTaskRunner()
        val store = testStore(root)
        val coordinator = coordinator(
            root,
            store = store,
            transfer = transfer,
            verifier = verifier,
            taskRunner = runner,
        )

        coordinator.start(first)
        coordinator.start(replacement)
        runner.runNext()

        assertEquals(AppUpdateStage.DOWNLOADING, coordinator.snapshot.stage)
        assertEquals(replacement.releaseTag, coordinator.snapshot.releaseTag)
        assertEquals(replacement, store.restore()?.request)
        assertEquals(0, verifier.calls)

        runner.runNext()
        assertEquals(AppUpdateStage.READY_TO_INSTALL, coordinator.snapshot.stage)
        assertEquals(replacement.releaseTag, coordinator.snapshot.releaseTag)
        assertEquals(1, verifier.calls)
    }

    @Test
    fun `pause resume and cancel retain only intended state`() = withRoot { root ->
        val request = validRequest()
        val transfer = FakeTransfer { _, _, _ -> UpdateTransferResult.Paused(2) }
        val coordinator = coordinator(root, transfer = transfer)

        coordinator.start(request)
        assertEquals(AppUpdateStage.PAUSED, coordinator.snapshot.stage)
        coordinator.resume()
        assertEquals(2, transfer.calls)
        coordinator.cancel()

        assertEquals(AppUpdateStage.IDLE, coordinator.snapshot.stage)
        assertTrue(transfer.cancelled)
    }

    @Test
    fun `dispose pauses an active download instead of deleting resumable state`() = withRoot { root ->
        val transfer = FakeTransfer()
        val coordinator = coordinator(root, transfer = transfer)
        coordinator.start(validRequest())

        coordinator.dispose()

        assertTrue(transfer.paused)
        assertFalse(transfer.cancelled)
    }

    @Test
    fun `install remains explicit and permission detour is truthful`() = withRoot { root ->
        val request = validRequest()
        File(root, request.assetName).writeText("apk")
        val installer = FakeInstaller(InstallStartResult.AwaitingPermission)
        val coordinator = coordinator(root, installer = installer)
        coordinator.restoreReadyForTest(request)

        assertEquals(0, installer.calls)
        coordinator.install()

        assertEquals(0, installer.calls)
        assertEquals(AppUpdateStage.AWAITING_PERMISSION, coordinator.snapshot.stage)
        coordinator.openInstallPermissionSettings()
        assertTrue(installer.openedSettings)

        installer.canInstall = true
        coordinator.refreshInstallPermission()
        assertEquals(AppUpdateStage.READY_TO_INSTALL, coordinator.snapshot.stage)
    }

    @Test
    fun `install copies candidate on background task after publishing installing`() = withRoot { root ->
        val request = validRequest()
        File(root, request.assetName).writeText("apk")
        val runner = QueuedTaskRunner()
        val installer = FakeInstaller(InstallStartResult.Started)
        val coordinator = coordinator(root, installer = installer, taskRunner = runner)
        coordinator.restoreReadyForTest(request)

        coordinator.install()

        assertEquals(AppUpdateStage.INSTALLING, coordinator.snapshot.stage)
        assertEquals(0, installer.calls)
        runner.runNext()
        assertEquals(1, installer.calls)
    }

    @Test
    fun `restored verifying candidate is reverified before becoming installable`() = withRoot { root ->
        val request = validRequest()
        File(root, request.assetName).writeText("apk")
        val store = testStore(root)
        store.save(
            PersistedUpdateState(
                request,
                AppUpdateSnapshot(
                    AppUpdateStage.VERIFYING,
                    request.releaseTag,
                    request.assetName,
                    request.expectedSize,
                    request.expectedSize,
                ),
                request.assetName,
            ),
        )
        val runner = QueuedTaskRunner()
        val verifier = FakeVerifier()

        val coordinator = coordinator(root, store, verifier = verifier, taskRunner = runner)

        assertEquals(AppUpdateStage.VERIFYING, coordinator.snapshot.stage)
        assertEquals(0, verifier.calls)
        runner.runNext()
        assertEquals(1, verifier.calls)
        assertEquals(AppUpdateStage.READY_TO_INSTALL, coordinator.snapshot.stage)
    }

    @Test
    fun `only owned install status can settle current generation`() = withRoot { root ->
        val request = validRequest()
        File(root, request.assetName).writeText("apk")
        val installer = FakeInstaller(InstallStartResult.Started)
        val coordinator = coordinator(root, installer = installer)
        coordinator.restoreReadyForTest(request)
        coordinator.install()
        val ownedGeneration = installer.lastGeneration

        coordinator.acceptInstallStatus(ownedGeneration - 1, InstallStatus.SUCCEEDED)
        assertEquals(AppUpdateStage.INSTALLING, coordinator.snapshot.stage)
        coordinator.acceptInstallStatus(ownedGeneration, InstallStatus.PENDING_CONFIRMATION)
        assertEquals(AppUpdateStage.AWAITING_CONFIRMATION, coordinator.snapshot.stage)
    }

    @Test
    fun `restored installing state reclaims exact generation before accepting result`() = withRoot { root ->
        val request = validRequest()
        val store = testStore(root)
        store.save(
            PersistedUpdateState(
                request = request,
                snapshot = AppUpdateSnapshot(
                    AppUpdateStage.INSTALLING,
                    request.releaseTag,
                    request.assetName,
                    request.expectedSize,
                    request.expectedSize,
                ),
                partialFileName = request.assetName,
                installGeneration = 17L,
                installSessionId = 41,
            ),
        )
        val installer = FakeInstaller(InstallStartResult.Started, restoredSessionActive = true)

        val coordinator = coordinator(root, store, installer = installer)

        assertEquals(17L, installer.lastGeneration)
        assertEquals(AppUpdateStage.INSTALLING, coordinator.snapshot.stage)
        coordinator.acceptInstallStatus(17L, InstallStatus.SUCCEEDED)
        assertEquals(AppUpdateStage.INSTALLED, coordinator.snapshot.stage)
    }

    @Test
    fun `restored install with missing platform session reverifies candidate instead of sticking`() =
        withRoot { root ->
            val request = validRequest()
            File(root, request.assetName).writeText("apk")
            val store = testStore(root)
            store.save(
                PersistedUpdateState(
                    request = request,
                    snapshot = AppUpdateSnapshot(
                        AppUpdateStage.INSTALLING,
                        request.releaseTag,
                        request.assetName,
                        request.expectedSize,
                        request.expectedSize,
                    ),
                    partialFileName = request.assetName,
                    installGeneration = 23L,
                    installSessionId = 52,
                ),
            )
            val runner = QueuedTaskRunner()
            val installer = FakeInstaller(
                InstallStartResult.Started,
                restoredSessionActive = false,
            )
            val verifier = FakeVerifier()

            val coordinator = coordinator(
                root,
                store,
                verifier = verifier,
                installer = installer,
                taskRunner = runner,
            )

            assertEquals(AppUpdateStage.VERIFYING, coordinator.snapshot.stage)
            assertEquals(0, runner.pendingCount)
            coordinator.reconcileRestoredInstall()
            assertEquals(1, runner.pendingCount)
            runner.runNext()
            assertEquals(1, verifier.calls)
            assertEquals(AppUpdateStage.READY_TO_INSTALL, coordinator.snapshot.stage)
            assertEquals(23L, installer.abandonedGeneration)
            assertEquals(null, store.restore()?.installGeneration)
            assertEquals(null, store.restore()?.installSessionId)
        }

    @Test
    fun `durable install result wins before missing session recovery starts`() = withRoot { root ->
        val request = validRequest()
        File(root, request.assetName).writeText("apk")
        val store = testStore(root)
        store.save(
            PersistedUpdateState(
                request = request,
                snapshot = AppUpdateSnapshot(AppUpdateStage.INSTALLING),
                partialFileName = request.assetName,
                installGeneration = 29L,
                installSessionId = 61,
            ),
        )
        val runner = QueuedTaskRunner()
        val verifier = FakeVerifier()
        val coordinator = coordinator(
            root,
            store,
            verifier = verifier,
            installer = FakeInstaller(
                InstallStartResult.Started,
                restoredSessionActive = false,
            ),
            taskRunner = runner,
        )

        coordinator.acceptInstallStatus(29L, InstallStatus.SUCCEEDED)
        coordinator.reconcileRestoredInstall()

        assertEquals(AppUpdateStage.INSTALLED, coordinator.snapshot.stage)
        assertEquals(0, runner.pendingCount)
        assertEquals(0, verifier.calls)
    }

    @Test
    fun `install ownership rejects replacement cancel and delete`() = withRoot { root ->
        val request = validRequest()
        val replacement = request.copy(
            releaseTag = "v2.0.1",
            assetName = "juicr-android-v2.0.1-x86_64.apk",
            assetUrl = "https://github.com/Team-Juicr/Juicr/releases/download/v2.0.1/juicr-android-v2.0.1-x86_64.apk",
        )
        File(root, request.assetName).writeText("apk")
        val runner = QueuedTaskRunner()
        val installer = FakeInstaller(InstallStartResult.Started)
        val store = testStore(root)
        val coordinator = coordinator(root, store, installer = installer, taskRunner = runner)
        coordinator.restoreReadyForTest(request)
        coordinator.install()

        coordinator.start(replacement)
        coordinator.cancel()
        coordinator.deleteDownload()

        assertEquals(AppUpdateStage.INSTALLING, coordinator.snapshot.stage)
        assertEquals(request, store.restore()?.request)
        assertTrue(File(root, request.assetName).isFile)
    }

    private fun coordinator(
        root: File,
        store: UpdateStateStore = testStore(root),
        transfer: FakeTransfer = FakeTransfer(),
        verifier: FakeVerifier = FakeVerifier(),
        installer: FakeInstaller = FakeInstaller(InstallStartResult.Started),
        taskRunner: UpdateTaskRunner = UpdateTaskRunner { task -> task() },
    ) = UpdateCoordinator(
        lane = "android",
        rootDirectory = root,
        stateStore = store,
        transfer = transfer,
        verifier = verifier,
        installer = installer,
        taskRunner = taskRunner,
    )

    private fun testStore(root: File) = UpdateStateStore(root) { true }

    private fun validRequest() = AppUpdateRequest(
        releaseTag = "v2.0.0",
        assetName = "juicr-android-v2.0.0-x86_64.apk",
        assetUrl = "https://github.com/Team-Juicr/Juicr/releases/download/v2.0.0/juicr-android-v2.0.0-x86_64.apk",
        expectedSize = 3,
        expectedSha256 = "a".repeat(64),
    )

    private fun withRoot(block: (File) -> Unit) {
        val root = Files.createTempDirectory("juicr-update-coordinator").toFile()
        try {
            block(root)
        } finally {
            root.deleteRecursively()
        }
    }

    private class FakeTransfer(
        private val result: (AppUpdateRequest, Long, (Long) -> Unit) -> UpdateTransferResult =
            { _, _, _ -> UpdateTransferResult.Paused(0) },
    ) : UpdateTransferGateway {
        var calls = 0
        var cancelled = false
        var paused = false
        private var generation = 0L

        override fun beginGeneration(): Long = ++generation
        override fun pause() { paused = true }
        override fun cancel() { cancelled = true }
        override fun transfer(
            request: AppUpdateRequest,
            generation: Long,
            onProgress: (Long) -> Unit,
        ): UpdateTransferResult {
            calls += 1
            return result(request, generation, onProgress)
        }
    }

    private class FakeVerifier(private val failure: AppUpdateFailure? = null) : UpdateVerifierGateway {
        var calls = 0
        override fun verify(request: AppUpdateRequest, file: File): AppUpdateFailure? {
            calls += 1
            return failure
        }
    }

    private class FakeInstaller(
        private val startResult: InstallStartResult,
        private val restoredSessionActive: Boolean = true,
    ) : UpdateInstallerGateway {
        var calls = 0
        var openedSettings = false
        var lastGeneration = -1L
        var canInstall = startResult != InstallStartResult.AwaitingPermission
        var abandonedGeneration: Long? = null

        override fun canInstallPackages(): Boolean = canInstall

        override fun install(
            file: File,
            generation: Long,
            onSessionCreated: (Int) -> Unit,
        ): InstallStartResult {
            calls += 1
            lastGeneration = generation
            if (startResult == InstallStartResult.Started) onSessionCreated(61)
            return startResult
        }

        override fun openPermissionSettings() { openedSettings = true }
        override fun acceptStatus(generation: Long, status: InstallStatus): AppUpdateStage? =
            if (generation == lastGeneration) {
                if (status == InstallStatus.PENDING_CONFIRMATION) {
                    AppUpdateStage.AWAITING_CONFIRMATION
                } else {
                    AppUpdateStage.INSTALLED
                }
            } else {
                null
            }

        override val lastFailure: AppUpdateFailure? = null
        override fun restoreOwnedGeneration(generation: Long, sessionId: Int?): Boolean {
            lastGeneration = generation
            return restoredSessionActive
        }
        override fun abandonOwnedGeneration(generation: Long) {
            if (lastGeneration == generation) {
                abandonedGeneration = generation
                lastGeneration = -1L
            }
        }
        override fun dispose() = Unit
    }

    private class QueuedTaskRunner : UpdateTaskRunner {
        private val tasks = ArrayDeque<() -> Unit>()

        val pendingCount: Int
            get() = tasks.size

        override fun execute(task: () -> Unit) {
            tasks.addLast(task)
        }

        fun runNext() = tasks.removeFirst().invoke()
    }
}
