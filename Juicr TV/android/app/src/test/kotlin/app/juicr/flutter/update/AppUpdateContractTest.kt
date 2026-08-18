package app.juicr.flutter.update

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdateContractTest {
    @Test
    fun `snapshot exposes only fixed public fields`() {
        val snapshot = AppUpdateSnapshot(
            stage = AppUpdateStage.DOWNLOADING,
            releaseTag = "v1.2.3",
            assetName = "juicr-tv-v1.2.3-arm64-v8a.apk",
            expectedSize = 1_000L,
            downloadedBytes = 250L,
            failure = null,
        )

        val map = snapshot.toPublicMap()

        assertEquals(
            setOf(
                "stage",
                "releaseTag",
                "assetName",
                "expectedSize",
                "downloadedBytes",
                "progressPermille",
                "failure",
            ),
            map.keys,
        )
        assertEquals(250, map["progressPermille"])
        assertFalse(map.containsKey("assetUrl"))
        assertFalse(map.containsKey("expectedSha256"))
        assertFalse(map.containsKey("localPath"))
        assertFalse(map.containsKey("signingDigest"))
    }

    @Test
    fun `snapshot progress is bounded and zero when size is unavailable`() {
        assertEquals(
            0,
            AppUpdateSnapshot(
                stage = AppUpdateStage.IDLE,
                expectedSize = 0,
                downloadedBytes = 500,
            ).progressPermille,
        )
        assertEquals(
            1000,
            AppUpdateSnapshot(
                stage = AppUpdateStage.DOWNLOADING,
                expectedSize = 100,
                downloadedBytes = 150,
            ).progressPermille,
        )
    }

    @Test
    fun `request validation accepts only the exact mobile release lane`() {
        val request = validRequest()

        assertNull(AppUpdateRequestValidator.validate(request, "tv"))
        assertEquals(
            AppUpdateFailure.WRONG_LANE,
            AppUpdateRequestValidator.validate(
                request.copy(assetName = "juicr-android-v1.2.3-arm64-v8a.apk"),
                "tv",
            ),
        )
        assertEquals(
            AppUpdateFailure.INVALID_APK,
            AppUpdateRequestValidator.validate(
                request.copy(assetUrl = "https://example.com/${request.assetName}"),
                "tv",
            ),
        )
    }

    @Test
    fun `interrupted download restores as paused`() {
        val root = Files.createTempDirectory("juicr-update-store").toFile()
        try {
            val store = UpdateStateStore(root)
            store.save(
                PersistedUpdateState(
                    request = validRequest(),
                    snapshot = AppUpdateSnapshot(
                        stage = AppUpdateStage.DOWNLOADING,
                        releaseTag = "v1.2.3",
                        assetName = "juicr-tv-v1.2.3-arm64-v8a.apk",
                        expectedSize = 1000,
                        downloadedBytes = 400,
                    ),
                    partialFileName = "pending.apk.part",
                    entityTag = "etag-1",
                ),
            )

            val restored = store.restore()

            assertEquals(AppUpdateStage.PAUSED, restored?.snapshot?.stage)
            assertEquals(400L, restored?.snapshot?.downloadedBytes)
            assertEquals("etag-1", restored?.entityTag)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `replacing update identity removes old partial file`() {
        val root = Files.createTempDirectory("juicr-update-store").toFile()
        try {
            val partial = File(root, "pending.apk.part").apply { writeText("partial") }
            val store = UpdateStateStore(root)
            store.save(
                PersistedUpdateState(
                    request = validRequest(),
                    snapshot = AppUpdateSnapshot(
                        stage = AppUpdateStage.PAUSED,
                        releaseTag = "v1.2.3",
                        assetName = "juicr-tv-v1.2.3-arm64-v8a.apk",
                        expectedSize = 1000,
                        downloadedBytes = partial.length(),
                    ),
                    partialFileName = partial.name,
                ),
            )

            val replacement = validRequest().copy(
                releaseTag = "v1.2.4",
                assetName = "juicr-tv-v1.2.4-arm64-v8a.apk",
                assetUrl = "https://github.com/Team-Juicr/Juicr/releases/download/v1.2.4/juicr-tv-v1.2.4-arm64-v8a.apk",
            )
            store.replaceIdentity(replacement)

            assertFalse(partial.exists())
            val restored = store.restore()
            assertEquals("v1.2.4", restored?.request?.releaseTag)
            assertEquals(AppUpdateStage.AVAILABLE, restored?.snapshot?.stage)
            assertEquals(0L, restored?.snapshot?.downloadedBytes)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `corrupt state fails closed and is removed`() {
        val root = Files.createTempDirectory("juicr-update-store").toFile()
        try {
            File(root, UpdateStateStore.STATE_FILE_NAME).writeText("not=a-complete-state")

            val store = UpdateStateStore(root)

            assertNull(store.restore())
            assertTrue(!File(root, UpdateStateStore.STATE_FILE_NAME).exists())
        } finally {
            root.deleteRecursively()
        }
    }

    private fun validRequest() = AppUpdateRequest(
        releaseTag = "v1.2.3",
        assetName = "juicr-tv-v1.2.3-arm64-v8a.apk",
        assetUrl = "https://github.com/Team-Juicr/Juicr/releases/download/v1.2.3/juicr-tv-v1.2.3-arm64-v8a.apk",
        expectedSize = 1000,
        expectedSha256 = "a".repeat(64),
    )
}
