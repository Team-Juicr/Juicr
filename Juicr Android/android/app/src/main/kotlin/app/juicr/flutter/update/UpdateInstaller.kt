package app.juicr.flutter.update

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File

enum class InstallStartResult {
    Started,
    AwaitingPermission,
    AlreadyInstalling,
    Failed,
}

enum class InstallStatus {
    PENDING_CONFIRMATION,
    SUCCEEDED,
    CANCELLED,
    FAILED,
}

interface InstallPlatform {
    fun canRequestPackageInstalls(): Boolean
    fun commit(file: File, generation: Long, onSessionCreated: (Int) -> Unit): Boolean
    fun hasSession(sessionId: Int): Boolean
    fun openPermissionSettings()
}

interface UpdateInstallerGateway {
    val lastFailure: AppUpdateFailure?
    fun canInstallPackages(): Boolean
    fun install(file: File, generation: Long, onSessionCreated: (Int) -> Unit): InstallStartResult
    fun openPermissionSettings()
    fun restoreOwnedGeneration(generation: Long, sessionId: Int?): Boolean
    fun abandonOwnedGeneration(generation: Long)
    fun acceptStatus(generation: Long, status: InstallStatus): AppUpdateStage?
    fun dispose()
}

class UpdateInstaller(private val platform: InstallPlatform) : UpdateInstallerGateway {
    @Volatile private var activeGeneration: Long? = null
    @Volatile override var lastFailure: AppUpdateFailure? = null
        private set

    val isInstalling: Boolean
        get() = activeGeneration != null

    override fun canInstallPackages(): Boolean = platform.canRequestPackageInstalls()

    @Synchronized
    override fun install(
        file: File,
        generation: Long,
        onSessionCreated: (Int) -> Unit,
    ): InstallStartResult {
        if (activeGeneration != null) return InstallStartResult.AlreadyInstalling
        if (!platform.canRequestPackageInstalls()) {
            lastFailure = AppUpdateFailure.INSTALL_PERMISSION
            return InstallStartResult.AwaitingPermission
        }
        activeGeneration = generation
        lastFailure = null
        if (!platform.commit(file, generation, onSessionCreated)) {
            activeGeneration = null
            lastFailure = AppUpdateFailure.INSTALL_FAILED
            return InstallStartResult.Failed
        }
        return InstallStartResult.Started
    }

    override fun openPermissionSettings() = platform.openPermissionSettings()

    @Synchronized
    override fun restoreOwnedGeneration(generation: Long, sessionId: Int?): Boolean {
        activeGeneration = generation
        lastFailure = null
        return sessionId != null && platform.hasSession(sessionId)
    }

    @Synchronized
    override fun abandonOwnedGeneration(generation: Long) {
        if (activeGeneration == generation) activeGeneration = null
    }

    @Synchronized
    override fun acceptStatus(generation: Long, status: InstallStatus): AppUpdateStage? {
        if (activeGeneration != generation) return null
        return when (status) {
            InstallStatus.PENDING_CONFIRMATION -> AppUpdateStage.AWAITING_CONFIRMATION
            InstallStatus.SUCCEEDED -> {
                activeGeneration = null
                lastFailure = null
                AppUpdateStage.INSTALLED
            }
            InstallStatus.CANCELLED -> {
                activeGeneration = null
                lastFailure = AppUpdateFailure.INSTALL_CANCELLED
                AppUpdateStage.FAILED
            }
            InstallStatus.FAILED -> {
                activeGeneration = null
                lastFailure = AppUpdateFailure.INSTALL_FAILED
                AppUpdateStage.FAILED
            }
        }
    }

    @Synchronized
    internal fun markOwnedGenerationForTest(generation: Long) {
        activeGeneration = generation
        lastFailure = null
    }

    @Synchronized
    override fun dispose() {
        activeGeneration = null
    }
}

class AndroidInstallPlatform(private val context: Context) : InstallPlatform {
    override fun canRequestPackageInstalls(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()

    override fun commit(
        file: File,
        generation: Long,
        onSessionCreated: (Int) -> Unit,
    ): Boolean {
        val packageInstaller = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(context.packageName)
        }
        val sessionId = runCatching { packageInstaller.createSession(params) }.getOrElse {
            return false
        }
        onSessionCreated(sessionId)
        return runCatching {
            packageInstaller.openSession(sessionId).use { session ->
            file.inputStream().use { input ->
                session.openWrite("juicr-update.apk", 0, file.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val intent = Intent(context, UpdateInstallResultReceiver::class.java).apply {
                action = UpdateInstallResultReceiver.ACTION_INSTALL_RESULT
                putExtra(UpdateInstallResultReceiver.EXTRA_GENERATION, generation)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                (generation xor (generation ushr 32)).toInt(),
                intent,
                flags,
            )
            session.commit(pendingIntent.intentSender)
            }
            true
        }.getOrElse {
            runCatching { packageInstaller.abandonSession(sessionId) }
            false
        }
    }

    override fun hasSession(sessionId: Int): Boolean = runCatching {
        context.packageManager.packageInstaller.getSessionInfo(sessionId) != null
    }.getOrDefault(false)

    override fun openPermissionSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val intent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
