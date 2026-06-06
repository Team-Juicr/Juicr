package app.juicr.flutter

import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.os.Build

object JuicrNotificationScheduler {
    const val PREFS = "juicr_notification_delivery"
    const val CHANNEL_ID = "juicr_updates"
    const val JOB_ID = 43032
    const val PERIODIC_INTERVAL_MS = 15 * 60 * 1000L

    fun syncSettings(
        context: Context,
        notificationsEnabled: Boolean,
        metricsEnabled: Boolean,
        dialogsEnabled: Boolean,
        interstitialsEnabled: Boolean
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean("notificationsEnabled", notificationsEnabled)
            .putBoolean("metricsEnabled", metricsEnabled)
            .putBoolean("dialogsEnabled", dialogsEnabled)
            .putBoolean("interstitialsEnabled", interstitialsEnabled)
            .apply()
        if (notificationsEnabled) {
            schedule(context)
        } else {
            cancel(context)
        }
    }

    fun shouldSchedule(context: Context): Boolean {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean("notificationsEnabled", false)
    }

    fun schedule(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP || !shouldSchedule(context)) {
            return
        }
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        val component = ComponentName(context, JuicrNotificationJobService::class.java)
        val job = JobInfo.Builder(JOB_ID, component)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPersisted(true)
            .setPeriodic(PERIODIC_INTERVAL_MS)
            .build()
        scheduler.schedule(job)
    }

    fun cancel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        context.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
    }

    fun markDelivered(context: Context, editionId: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = prefs.getInt("dailyCount", 0)
        prefs.edit()
            .putString("lastCurationEdition", editionId)
            .putString("dailyCountDate", JuicrNotificationTime.todayStamp())
            .putInt("dailyCount", current + 1)
            .apply()
    }
}
