package app.juicr.flutter.update

import java.io.File
import java.io.FileOutputStream
import java.util.Properties

data class PersistedInstallResult(
    val generation: Long,
    val status: InstallStatus,
)

class UpdateInstallResultStore(private val rootDirectory: File) {
    private val resultFile = File(rootDirectory, FILE_NAME)

    init {
        rootDirectory.mkdirs()
    }

    @Synchronized
    fun save(generation: Long, status: InstallStatus) {
        require(generation > 0)
        val temporary = File(rootDirectory, "$FILE_NAME.tmp")
        FileOutputStream(temporary).use { output ->
            Properties().apply {
                setProperty("schema", SCHEMA_VERSION)
                setProperty("generation", generation.toString())
                setProperty("status", status.name)
            }.store(output, null)
            output.fd.sync()
        }
        commitUpdateFile(temporary, resultFile)
    }

    @Synchronized
    fun consume(): PersistedInstallResult? {
        recoverUpdateFile(resultFile)
        if (!resultFile.isFile) return null
        val restored = runCatching {
            val properties = Properties().apply { resultFile.inputStream().use(::load) }
            require(properties.getProperty("schema") == SCHEMA_VERSION)
            val generation = properties.getProperty("generation")?.toLong() ?: error("generation")
            require(generation > 0)
            val status = InstallStatus.valueOf(properties.getProperty("status") ?: error("status"))
            PersistedInstallResult(generation, status)
        }.getOrNull()
        resultFile.delete()
        File(rootDirectory, "$FILE_NAME.tmp").delete()
        File(rootDirectory, "$FILE_NAME.bak").delete()
        return restored
    }

    companion object {
        const val FILE_NAME = "app-update-install-result.properties"
        private const val SCHEMA_VERSION = "1"
    }
}
