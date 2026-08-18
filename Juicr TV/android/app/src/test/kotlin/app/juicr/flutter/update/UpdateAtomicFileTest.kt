package app.juicr.flutter.update

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateAtomicFileTest {
    @Test
    fun `commit replaces target and removes transaction files`() = withRoot { root ->
        val target = File(root, "state.properties").apply { writeText("old") }
        val temporary = File(root, "state.properties.tmp").apply { writeText("new") }

        commitUpdateFile(temporary, target)

        assertEquals("new", target.readText())
        assertFalse(temporary.exists())
        assertFalse(File(root, "state.properties.bak").exists())
    }

    @Test
    fun `recovery restores backup when target rename was interrupted`() = withRoot { root ->
        val target = File(root, "state.properties")
        File(root, "state.properties.bak").writeText("old")

        recoverUpdateFile(target)

        assertTrue(target.isFile)
        assertEquals("old", target.readText())
    }

    @Test
    fun `recovery keeps committed target and removes obsolete backup`() = withRoot { root ->
        val target = File(root, "state.properties").apply { writeText("new") }
        val backup = File(root, "state.properties.bak").apply { writeText("old") }

        recoverUpdateFile(target)

        assertEquals("new", target.readText())
        assertFalse(backup.exists())
    }

    private fun withRoot(block: (File) -> Unit) {
        val root = Files.createTempDirectory("juicr-update-atomic").toFile()
        try {
            block(root)
        } finally {
            root.deleteRecursively()
        }
    }
}
