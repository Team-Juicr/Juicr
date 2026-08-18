package app.juicr.flutter.update

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import java.io.File

class UpdateInstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_INSTALL_RESULT) return
        val generation = intent.getLongExtra(EXTRA_GENERATION, -1)
        if (generation < 0) return
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            @Suppress("DEPRECATION")
            val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
            confirmation?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            publishDurably(context, generation, InstallStatus.PENDING_CONFIRMATION)
            if (confirmation != null) context.startActivity(confirmation)
            return
        }
        val mapped = when (status) {
            PackageInstaller.STATUS_SUCCESS -> InstallStatus.SUCCEEDED
            PackageInstaller.STATUS_FAILURE_ABORTED -> InstallStatus.CANCELLED
            else -> InstallStatus.FAILED
        }
        publishDurably(context, generation, mapped)
    }

    private fun publishDurably(context: Context, generation: Long, status: InstallStatus) {
        UpdateInstallResultStore(File(context.noBackupFilesDir, "app-updates")).save(generation, status)
        UpdateInstallStatusBus.publish(generation, status)
    }

    companion object {
        const val ACTION_INSTALL_RESULT = "app.juicr.flutter.UPDATE_INSTALL_RESULT"
        const val EXTRA_GENERATION = "generation"
    }
}

object UpdateInstallStatusBus {
    @Volatile private var listener: ((Long, InstallStatus) -> Unit)? = null

    fun attach(value: (Long, InstallStatus) -> Unit) {
        listener = value
    }

    fun detach(value: (Long, InstallStatus) -> Unit) {
        if (listener === value) listener = null
    }

    fun publish(generation: Long, status: InstallStatus) {
        listener?.invoke(generation, status)
    }
}
