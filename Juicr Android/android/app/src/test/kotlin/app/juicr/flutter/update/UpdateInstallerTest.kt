package app.juicr.flutter.update

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateInstallerTest {
    @Test
    fun `missing package install permission returns awaiting permission`() = withApk { file ->
        val platform = FakeInstallPlatform(canInstall = false)
        val installer = UpdateInstaller(platform)

        val result = installer.install(file, generation = 7) { }

        assertEquals(InstallStartResult.AwaitingPermission, result)
        assertEquals(0, platform.commits)
    }

    @Test
    fun `explicit install commits one owned generation`() = withApk { file ->
        val platform = FakeInstallPlatform(canInstall = true)
        val installer = UpdateInstaller(platform)

        var sessionId: Int? = null
        assertEquals(
            InstallStartResult.Started,
            installer.install(file, generation = 7) { sessionId = it },
        )
        assertEquals(1, platform.commits)
        assertEquals(7L, platform.lastGeneration)
        assertEquals(73, sessionId)
        assertEquals(
            InstallStartResult.AlreadyInstalling,
            installer.install(file, generation = 8) { },
        )
        assertEquals(1, platform.commits)
    }

    @Test
    fun `stale install result cannot settle active generation`() {
        val installer = UpdateInstaller(FakeInstallPlatform(canInstall = true))
        installer.markOwnedGenerationForTest(9)

        assertEquals(null, installer.acceptStatus(8, InstallStatus.SUCCEEDED))
        assertEquals(AppUpdateStage.INSTALLED, installer.acceptStatus(9, InstallStatus.SUCCEEDED))
    }

    @Test
    fun `pending confirmation and terminal failures map to fixed states`() {
        val installer = UpdateInstaller(FakeInstallPlatform(canInstall = true))
        installer.markOwnedGenerationForTest(12)

        assertEquals(
            AppUpdateStage.AWAITING_CONFIRMATION,
            installer.acceptStatus(12, InstallStatus.PENDING_CONFIRMATION),
        )
        assertEquals(
            AppUpdateStage.FAILED,
            installer.acceptStatus(12, InstallStatus.CANCELLED),
        )
        assertEquals(AppUpdateFailure.INSTALL_CANCELLED, installer.lastFailure)
    }

    @Test
    fun `permission settings action is delegated without starting install`() {
        val platform = FakeInstallPlatform(canInstall = false)
        val installer = UpdateInstaller(platform)

        installer.openPermissionSettings()

        assertTrue(platform.openedSettings)
        assertEquals(0, platform.commits)
    }

    @Test
    fun `dispose clears ownership and rejects later status`() {
        val installer = UpdateInstaller(FakeInstallPlatform(canInstall = true))
        installer.markOwnedGenerationForTest(14)

        installer.dispose()

        assertFalse(installer.isInstalling)
        assertEquals(null, installer.acceptStatus(14, InstallStatus.SUCCEEDED))
    }

    @Test
    fun `restored ownership reports whether package installer session still exists`() {
        val platform = FakeInstallPlatform(canInstall = true, activeSessionId = 73)
        val installer = UpdateInstaller(platform)

        assertTrue(installer.restoreOwnedGeneration(14, 73))
        installer.abandonOwnedGeneration(14)
        assertFalse(installer.isInstalling)
        assertFalse(installer.restoreOwnedGeneration(15, 74))
    }

    private fun withApk(block: (File) -> Unit) {
        val root = Files.createTempDirectory("juicr-install-test").toFile()
        try {
            block(File(root, "candidate.apk").apply { writeText("apk") })
        } finally {
            root.deleteRecursively()
        }
    }

    private class FakeInstallPlatform(
        private val canInstall: Boolean,
        private val activeSessionId: Int? = 73,
    ) : InstallPlatform {
        var commits = 0
        var lastGeneration: Long? = null
        var openedSettings = false

        override fun canRequestPackageInstalls(): Boolean = canInstall

        override fun commit(
            file: File,
            generation: Long,
            onSessionCreated: (Int) -> Unit,
        ): Boolean {
            commits += 1
            lastGeneration = generation
            onSessionCreated(73)
            return true
        }

        override fun hasSession(sessionId: Int): Boolean = sessionId == activeSessionId

        override fun openPermissionSettings() {
            openedSettings = true
        }
    }
}
