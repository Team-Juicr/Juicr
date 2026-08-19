package app.juicr.flutter.update

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import android.content.pm.PackageManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UpdateVerifierTest {
    @Test
    fun `legacy Android requests legacy signature flags`() {
        assertEquals(
            PackageManager.GET_META_DATA or PackageManager.GET_SIGNATURES,
            packageInfoFlagsForSdk(27, includeMetadata = true),
        )
        assertEquals(
            PackageManager.GET_SIGNATURES,
            packageInfoFlagsForSdk(27, includeMetadata = false),
        )
    }

    @Test
    fun `modern Android requests signing certificate flags`() {
        assertEquals(
            PackageManager.GET_META_DATA or PackageManager.GET_SIGNING_CERTIFICATES,
            packageInfoFlagsForSdk(28, includeMetadata = true),
        )
    }

    @Test
    fun `valid newer same lane same signer archive passes`() = withApk("candidate") { file ->
        val verifier = verifier(file)

        assertNull(verifier.verify(request(file), file))
    }

    @Test
    fun `checksum mismatch fails before archive inspection`() = withApk("candidate") { file ->
        val inspector = RecordingInspector(archiveIdentity(), installedIdentity())
        val verifier = UpdateVerifier("android", PACKAGE_NAME, inspector)

        val result = verifier.verify(
            request(file).copy(expectedSha256 = "0".repeat(64)),
            file,
        )

        assertEquals(AppUpdateFailure.CHECKSUM_MISMATCH, result)
        assertEquals(0, inspector.archiveReads)
    }

    @Test
    fun `same package and signer from tv lane is rejected`() = withApk("candidate") { file ->
        val verifier = verifier(file, archive = archiveIdentity().copy(lane = "tv"))

        assertEquals(AppUpdateFailure.WRONG_LANE, verifier.verify(request(file), file))
    }

    @Test
    fun `wrong package is rejected`() = withApk("candidate") { file ->
        val verifier = verifier(file, archive = archiveIdentity().copy(packageName = "other.app"))

        assertEquals(AppUpdateFailure.WRONG_PACKAGE, verifier.verify(request(file), file))
    }

    @Test
    fun `same or older version is rejected`() = withApk("candidate") { file ->
        val verifier = verifier(file, archive = archiveIdentity().copy(versionCode = 41))

        assertEquals(AppUpdateFailure.NOT_NEWER, verifier.verify(request(file), file))
    }

    @Test
    fun `archive version name must match the requested release tag`() = withApk("candidate") { file ->
        val verifier = verifier(file, archive = archiveIdentity().copy(versionName = "1.2.4"))

        assertEquals(AppUpdateFailure.INVALID_APK, verifier.verify(request(file), file))
    }

    @Test
    fun `different signer set is rejected`() = withApk("candidate") { file ->
        val verifier = verifier(
            file,
            archive = archiveIdentity().copy(signerSha256 = setOf("bb")),
        )

        assertEquals(AppUpdateFailure.SIGNER_MISMATCH, verifier.verify(request(file), file))
    }

    @Test
    fun `unparseable archive is rejected`() = withApk("candidate") { file ->
        val verifier = UpdateVerifier(
            lane = "android",
            expectedPackageName = PACKAGE_NAME,
            inspector = RecordingInspector(null, installedIdentity()),
        )

        assertEquals(AppUpdateFailure.INVALID_APK, verifier.verify(request(file), file))
    }

    @Test
    fun `size mismatch is rejected`() = withApk("candidate") { file ->
        val verifier = verifier(file)

        assertEquals(
            AppUpdateFailure.SIZE_MISMATCH,
            verifier.verify(request(file).copy(expectedSize = file.length() + 1), file),
        )
    }

    private fun verifier(
        file: File,
        archive: ApkArchiveIdentity = archiveIdentity(),
    ) = UpdateVerifier(
        lane = "android",
        expectedPackageName = PACKAGE_NAME,
        inspector = RecordingInspector(archive, installedIdentity()),
    )

    private fun request(file: File) = AppUpdateRequest(
        releaseTag = "v1.2.3",
        assetName = "juicr-android-v1.2.3-arm64-v8a.apk",
        assetUrl = "https://github.com/Team-Juicr/Juicr/releases/download/v1.2.3/juicr-android-v1.2.3-arm64-v8a.apk",
        expectedSize = file.length(),
        expectedSha256 = sha256(file),
    )

    private fun archiveIdentity() = ApkArchiveIdentity(
        packageName = PACKAGE_NAME,
        lane = "android",
        versionName = "1.2.3",
        versionCode = 42,
        signerSha256 = setOf("aa"),
    )

    private fun installedIdentity() = InstalledAppIdentity(
        versionCode = 41,
        signerSha256 = setOf("aa"),
    )

    private fun withApk(content: String, block: (File) -> Unit) {
        val root = Files.createTempDirectory("juicr-update-verifier").toFile()
        try {
            block(File(root, "candidate.apk").apply { writeText(content) })
        } finally {
            root.deleteRecursively()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private class RecordingInspector(
        private val archive: ApkArchiveIdentity?,
        private val installed: InstalledAppIdentity?,
    ) : ApkInspector {
        var archiveReads = 0

        override fun inspectArchive(file: File): ApkArchiveIdentity? {
            archiveReads += 1
            return archive
        }

        override fun inspectInstalled(packageName: String): InstalledAppIdentity? = installed
    }

    companion object {
        private const val PACKAGE_NAME = "app.juicr.flutter"
    }
}
