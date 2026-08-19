package app.juicr.flutter.update

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateDownloadOwnerTest {
    @Test
    fun `progress checkpoint policy bounds durable writes`() {
        val policy = ProgressCheckpointPolicy(intervalBytes = 1024)

        assertTrue(policy.shouldPersist(0))
        policy.markPersisted(0)
        assertFalse(policy.shouldPersist(512))
        assertTrue(policy.shouldPersist(1024))
        policy.markPersisted(1024)
        assertFalse(policy.shouldPersist(1535))
        assertTrue(policy.shouldPersist(2048))
    }

    @Test
    fun `fresh response downloads exact expected bytes`() = withFixture("complete") { fixture ->
        fixture.server.enqueue(MockResponse().setResponseCode(200).setBody("complete"))

        val result = fixture.owner.transfer(fixture.request(expectedSize = 8))

        assertTrue(result is UpdateTransferResult.Complete)
        assertEquals("complete", (result as UpdateTransferResult.Complete).file.readText())
        assertEquals(8L, fixture.store.restore()?.snapshot?.downloadedBytes)
    }

    @Test
    fun `valid 206 appends from the exact persisted offset`() = withFixture("complete") { fixture ->
        fixture.seedPartial("com", entityTag = "etag-1")
        fixture.server.enqueue(
            MockResponse()
                .setResponseCode(206)
                .setHeader("Content-Range", "bytes 3-7/8")
                .setHeader("ETag", "etag-1")
                .setBody("plete"),
        )

        val result = fixture.owner.transfer(fixture.request(expectedSize = 8))

        assertTrue(result is UpdateTransferResult.Complete)
        assertEquals("complete", (result as UpdateTransferResult.Complete).file.readText())
        val request = fixture.server.takeRequest()
        assertEquals("bytes=3-", request.getHeader("Range"))
        assertEquals("etag-1", request.getHeader("If-Range"))
    }

    @Test
    fun `mismatched content range fails without appending`() = withFixture("complete") { fixture ->
        fixture.seedPartial("com")
        fixture.server.enqueue(
            MockResponse()
                .setResponseCode(206)
                .setHeader("Content-Range", "bytes 2-7/8")
                .setBody("plete"),
        )

        val result = fixture.owner.transfer(fixture.request(expectedSize = 8))

        assertEquals(UpdateTransferResult.Failed(AppUpdateFailure.ASSET_CHANGED), result)
        assertEquals("com", fixture.partialFile().readText())
    }

    @Test
    fun `resumed 200 truncates and safely restarts`() = withFixture("complete") { fixture ->
        fixture.seedPartial("com")
        fixture.server.enqueue(MockResponse().setResponseCode(200).setBody("complete"))

        val result = fixture.owner.transfer(fixture.request(expectedSize = 8))

        assertTrue(result is UpdateTransferResult.Complete)
        assertEquals("complete", (result as UpdateTransferResult.Complete).file.readText())
    }

    @Test
    fun `416 deletes stale partial and retries once from zero`() = withFixture("complete") { fixture ->
        fixture.seedPartial("com")
        fixture.server.enqueue(MockResponse().setResponseCode(416))
        fixture.server.enqueue(MockResponse().setResponseCode(200).setBody("complete"))

        val result = fixture.owner.transfer(fixture.request(expectedSize = 8))

        assertTrue(result is UpdateTransferResult.Complete)
        assertEquals("complete", (result as UpdateTransferResult.Complete).file.readText())
        assertEquals(2, fixture.server.requestCount)
        assertEquals("bytes=3-", fixture.server.takeRequest().getHeader("Range"))
        assertEquals(null, fixture.server.takeRequest().getHeader("Range"))
    }

    @Test
    fun `response exceeding manifest size is rejected and removed`() = withFixture("short") { fixture ->
        fixture.server.enqueue(MockResponse().setResponseCode(200).setBody("too-long"))

        val result = fixture.owner.transfer(fixture.request(expectedSize = 5))

        assertEquals(UpdateTransferResult.Failed(AppUpdateFailure.SIZE_MISMATCH), result)
        assertFalse(fixture.partialFile().exists())
    }

    @Test
    fun `pause cancels active call and keeps partial bytes`() = withFixture("payload") { fixture ->
        val body = Buffer().write(ByteArray(256 * 1024) { 7 })
        fixture.server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody(body)
                .throttleBody(1024, 100, TimeUnit.MILLISECONDS),
        )
        val started = CountDownLatch(1)
        var result: UpdateTransferResult? = null
        val worker = thread {
            result = fixture.owner.transfer(
                fixture.request(expectedSize = 256L * 1024L),
                onProgress = { if (it > 0) started.countDown() },
            )
        }
        assertTrue(started.await(5, TimeUnit.SECONDS))

        fixture.owner.pause()
        worker.join(5_000)

        assertTrue(result is UpdateTransferResult.Paused)
        assertTrue(fixture.partialFile().length() in 1 until 256L * 1024L)
        assertEquals(AppUpdateStage.PAUSED, fixture.store.restore()?.snapshot?.stage)
    }

    @Test
    fun `cancel removes partial state and stale generation cannot publish completion`() =
        withFixture("payload") { fixture ->
            val firstGeneration = fixture.owner.beginGeneration()
            val secondGeneration = fixture.owner.beginGeneration()

            val stale = fixture.owner.transfer(
                fixture.request(expectedSize = 7),
                generation = firstGeneration,
            )

            assertEquals(UpdateTransferResult.Cancelled, stale)
            assertTrue(secondGeneration > firstGeneration)
        }

    @Test
    fun `replaced generation cannot clear replacement identity while unwinding`() =
        withFixture("payload") { fixture ->
            val body = Buffer().write(ByteArray(256 * 1024) { 7 })
            fixture.server.enqueue(
                MockResponse()
                    .setResponseCode(200)
                    .setBody(body)
                    .throttleBody(1024, 100, TimeUnit.MILLISECONDS),
            )
            val firstRequest = fixture.request(expectedSize = 256L * 1024L)
            val replacementRequest = firstRequest.copy(
                releaseTag = "v1.2.4",
                assetName = "juicr-android-v1.2.4-arm64-v8a.apk",
                assetUrl = fixture.server.url(
                    "/Team-Juicr/Juicr/releases/download/v1.2.4/juicr-android-v1.2.4-arm64-v8a.apk",
                ).toString(),
            )
            val started = CountDownLatch(1)
            var result: UpdateTransferResult? = null
            val firstGeneration = fixture.owner.beginGeneration()
            val worker = thread {
                result = fixture.owner.transfer(firstRequest, firstGeneration) {
                    if (it > 0) started.countDown()
                }
            }
            assertTrue(started.await(5, TimeUnit.SECONDS))

            fixture.owner.beginGeneration()
            fixture.store.replaceIdentity(replacementRequest)
            worker.join(5_000)

            assertEquals(UpdateTransferResult.Cancelled, result)
            assertEquals(replacementRequest, fixture.store.restore()?.request)
        }

    private fun withFixture(payload: String, block: (Fixture) -> Unit) {
        val server = MockWebServer()
        server.start()
        val root = Files.createTempDirectory("juicr-update-transfer").toFile()
        try {
            block(Fixture(server, root, payload))
        } finally {
            server.shutdown()
            root.deleteRecursively()
        }
    }

    private class Fixture(
        val server: MockWebServer,
        val root: File,
        val payload: String,
    ) {
        val store = UpdateStateStore(root) { true }
        val owner = UpdateDownloadOwner(
            client = OkHttpClient.Builder()
                .connectTimeout(2, TimeUnit.SECONDS)
                .readTimeout(2, TimeUnit.SECONDS)
                .build(),
            rootDirectory = root,
            stateStore = store,
            allowedFinalHosts = setOf("localhost", "127.0.0.1"),
        )

        fun request(expectedSize: Long) = AppUpdateRequest(
            releaseTag = "v1.2.3",
            assetName = "juicr-android-v1.2.3-arm64-v8a.apk",
            assetUrl = server.url("/Team-Juicr/Juicr/releases/download/v1.2.3/juicr-android-v1.2.3-arm64-v8a.apk").toString(),
            expectedSize = expectedSize,
            expectedSha256 = "a".repeat(64),
        )

        fun partialFile() = File(root, "juicr-android-v1.2.3-arm64-v8a.apk.part")

        fun seedPartial(content: String, entityTag: String? = null) {
            partialFile().writeText(content)
            val request = request(expectedSize = payload.length.toLong())
            store.save(
                PersistedUpdateState(
                    request = request,
                    snapshot = AppUpdateSnapshot(
                        stage = AppUpdateStage.PAUSED,
                        releaseTag = request.releaseTag,
                        assetName = request.assetName,
                        expectedSize = request.expectedSize,
                        downloadedBytes = content.length.toLong(),
                    ),
                    partialFileName = partialFile().name,
                    entityTag = entityTag,
                ),
            )
        }
    }
}
