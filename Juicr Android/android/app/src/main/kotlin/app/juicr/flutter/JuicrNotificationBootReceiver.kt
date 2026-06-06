package app.juicr.flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class JuicrNotificationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                JuicrNotificationScheduler.schedule(context)
            }
        }
    }
}
