package app.juicr.flutter.update

import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class UpdateInstallResultStoreTest {
    @Test
    fun `install result survives restart and is consumed once`() {
        val root = Files.createTempDirectory("juicr-install-result").toFile()
        try {
            UpdateInstallResultStore(root).save(29L, InstallStatus.SUCCEEDED)

            val restored = UpdateInstallResultStore(root).consume()

            assertEquals(PersistedInstallResult(29L, InstallStatus.SUCCEEDED), restored)
            assertEquals(null, UpdateInstallResultStore(root).consume())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `malformed install result fails closed and is removed`() {
        val root = Files.createTempDirectory("juicr-install-result-invalid").toFile()
        try {
            val resultFile = root.resolve(UpdateInstallResultStore.FILE_NAME)
            resultFile.writeText("generation=-1\nstatus=unknown\n")

            assertEquals(null, UpdateInstallResultStore(root).consume())
            assertFalse(resultFile.exists())
        } finally {
            root.deleteRecursively()
        }
    }
}
