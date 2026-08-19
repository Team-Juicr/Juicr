package app.juicr.flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class P2pGenerationOwnershipTest {
    @Test
    fun `shared session survives older generation cancellation`() {
        val ownership = P2pGenerationOwnership()
        ownership.register("session-a", 10)
        ownership.register("session-a", 11)

        assertTrue(ownership.removeGeneration(10).isEmpty())
        assertTrue(ownership.owns("session-a", 11))
    }

    @Test
    fun `exact rollback removes only failed generation`() {
        val ownership = P2pGenerationOwnership()
        ownership.register("session-a", 20)
        ownership.register("session-b", 21)

        assertEquals(setOf("session-b"), ownership.removeGeneration(21))
        assertTrue(ownership.owns("session-a", 20))
        assertFalse(ownership.owns("session-b", 21))
    }

    @Test
    fun `route close removes only generations through boundary`() {
        val ownership = P2pGenerationOwnership()
        ownership.register("session-a", 30)
        ownership.register("session-b", 31)
        ownership.register("session-c", 32)

        assertEquals(
            setOf("session-a", "session-b"),
            ownership.removeThrough(31),
        )
        assertTrue(ownership.owns("session-c", 32))
    }
}
