package app.juicr.flutter.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateBridgeContractTest {
    @Test
    fun `start arguments require exact safe schema`() {
        val parsed = UpdateBridgeRequestParser.parse(validArguments())

        assertEquals("v2.0.0", parsed?.releaseTag)
        assertEquals("juicr-tv-v2.0.0-x86_64.apk", parsed?.assetName)
        assertEquals(123L, parsed?.expectedSize)
    }

    @Test
    fun `unknown or private argument fields fail closed`() {
        assertNull(UpdateBridgeRequestParser.parse(validArguments() + ("headers" to mapOf("x" to "y"))))
        assertNull(UpdateBridgeRequestParser.parse(validArguments() + ("localPath" to "private")))
    }

    @Test
    fun `wrong types and missing fields fail closed`() {
        assertNull(UpdateBridgeRequestParser.parse(validArguments() - "sha256"))
        assertNull(UpdateBridgeRequestParser.parse(validArguments() + ("expectedSize" to "123")))
        assertNull(UpdateBridgeRequestParser.parse(null))
    }

    @Test
    fun `public bridge method and channel names remain exact`() {
        assertEquals("app.juicr.flutter/app_update", UpdateBridge.METHOD_CHANNEL)
        assertEquals("app.juicr.flutter/app_update_events", UpdateBridge.EVENT_CHANNEL)
        assertTrue(UpdateBridge.SUPPORTED_METHODS.containsAll(setOf("snapshot", "start", "install")))
    }

    private fun validArguments(): Map<String, Any> = linkedMapOf(
        "releaseTag" to "v2.0.0",
        "assetName" to "juicr-tv-v2.0.0-x86_64.apk",
        "assetUrl" to "https://github.com/Team-Juicr/Juicr/releases/download/v2.0.0/juicr-tv-v2.0.0-x86_64.apk",
        "expectedSize" to 123L,
        "sha256" to "a".repeat(64),
    )
}
