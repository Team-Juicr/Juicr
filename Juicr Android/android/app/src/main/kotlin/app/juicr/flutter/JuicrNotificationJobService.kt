package app.juicr.flutter

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobParameters
import android.app.job.JobService
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL
import java.util.Calendar
import kotlin.concurrent.thread

class JuicrNotificationJobService : JobService() {
    @Volatile
    private var cancelled = false

    override fun onStartJob(params: JobParameters): Boolean {
        cancelled = false
        thread(name = "juicr-notification-check") {
            try {
                runNotificationCheck()
            } finally {
                jobFinished(params, false)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        cancelled = true
        return true
    }

    private fun runNotificationCheck() {
        if (cancelled || !notificationsEnabled() || !permissionGranted()) return
        val policy = fetchJson("https://api.juicr.app/notifications/policy") ?: return
        if (policy.optBoolean("enabled") != true) return
        val automatic = policy.optJSONObject("automatic") ?: return
        val controls = policy.optJSONObject("controls")
        if (!surfaceAllowed(controls, "notification")) return
        if (!automatic.optBoolean("enabled") ||
            !automatic.optBoolean("dailyCurationEnabled", true) ||
            insideQuietHours(automatic.optString("quietHours"))
        ) {
            return
        }
        val cap = automatic.optInt("dailyCap", 1).coerceIn(1, 3)
        if (dailyCount() >= cap) return
        val editorial = fetchJson("https://api.juicr.app/home/editorial?locale=en") ?: return
        if (editorial.optBoolean("ok") != true ||
            editorial.optBoolean("degraded") == true ||
            editorial.has("fallbackReason") ||
            editorial.optString("schema") != "juicr.home_editorial.v1"
        ) {
            return
        }
        val editionId = editorial.optString("editionId").trim()
        if (editionId.isEmpty() || editionId == prefs().getString("lastCurationEdition", "")) {
            return
        }
        val hero = editorial.optJSONObject("hero")
        val title = safeUserVisibleNotificationText(
            hero?.optString("title"),
            "Today's Juicr picks"
        )
        val message = safeUserVisibleNotificationText(
            fetchCatalogPreview(editorial) ?: curationMessage(editorial),
            "Fresh movie, series, and animation picks are waiting."
        )
        if (showNotification(title, message)) {
            JuicrNotificationScheduler.markDelivered(this, editionId)
        }
    }

    private fun fetchJson(rawUrl: String): JSONObject? {
        return try {
            val connection = URL(rawUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.setRequestProperty("user-agent", "JuicrApp/1 Flutter")
            connection.setRequestProperty("x-juicr-client", "flutter-native")
            connection.setRequestProperty("x-juicr-client-version", "1")
            connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
        } catch (_: Throwable) {
            null
        }
    }

    private fun fetchCatalogPreview(editorial: JSONObject): String? {
        val hero = editorial.optJSONObject("hero") ?: return null
        val route = hero.optJSONObject("route")
        val type = firstNonEmpty(
            route?.optString("type"),
            hero.optJSONArray("types")?.optString(0),
            "movie"
        )
        val sort = firstNonEmpty(route?.optString("sort"), hero.optString("sort"), "popular")
        val genre = firstNonEmpty(
            route?.optString("genre"),
            hero.optJSONArray("genres")?.optString(0),
            ""
        )
        val url = StringBuilder("https://api.juicr.app/catalog?")
            .append("type=").append(urlEncode(type))
            .append("&sort=").append(urlEncode(sort))
            .append("&skip=0")
        if (genre.isNotBlank() && !genre.equals("All genres", ignoreCase = true)) {
            url.append("&genre=").append(urlEncode(genre))
        }
        val catalog = fetchJson(url.toString()) ?: return null
        val items = catalog.optJSONArray("items") ?: return null
        val titles = mutableListOf<String>()
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val title = safeUserVisibleNotificationText(
                firstNonEmpty(item.optString("name"), item.optString("title")),
                ""
            )
            if (title.isNotEmpty() && !titles.contains(title)) {
                titles.add(title)
            }
            if (titles.size >= 2) break
        }
        if (titles.size < 2) return null
        val hook = safeUserVisibleNotificationText(
            firstNonEmpty(hero.optString("notificationHook"), hero.optString("subtitle")),
            "Fresh picks are ready when you are."
        )
        return "${titles[0]}, ${titles[1]} and more. $hook"
    }

    private fun notificationsEnabled(): Boolean {
        return prefs().getBoolean("notificationsEnabled", false)
    }

    private fun permissionGranted(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
    }

    private fun dailyCount(): Int {
        val today = todayStamp()
        if (prefs().getString("dailyCountDate", "") != today) return 0
        return prefs().getInt("dailyCount", 0)
    }

    private fun insideQuietHours(quietHours: String): Boolean {
        val parts = quietHours.split("-")
        if (parts.size != 2) return false
        val start = clock(parts[0]) ?: return false
        val end = clock(parts[1]) ?: return false
        val calendar = Calendar.getInstance()
        val now = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
        return if (start <= end) {
            now >= start && now < end
        } else {
            now >= start || now < end
        }
    }

    private fun clock(value: String): Int? {
        val parts = value.trim().split(":")
        if (parts.size != 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        if (hour !in 0..23 || minute !in 0..59) return null
        return hour * 60 + minute
    }

    private fun showNotification(title: String, message: String): Boolean {
        val safeTitle = safeUserVisibleNotificationText(title, "Juicr")
        val safeMessage = safeUserVisibleNotificationText(
            message,
            "Fresh movie, series, and animation picks are waiting."
        )
        val manager = getSystemService(NotificationManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Juicr updates",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "Curated Juicr updates and optional suggestions."
                }
            )
        }
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        manager.notify(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(safeTitle)
                .setContentText(compactNotificationText(safeMessage))
                .setStyle(Notification.BigTextStyle().bigText(safeMessage))
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .build()
        )
        return true
    }

    private fun compactNotificationText(message: String): String {
        val clean = message.trim().replace(Regex("\\s+"), " ")
        val maxLength = 72
        if (clean.length <= maxLength) return clean
        val boundary = clean.lastIndexOf(' ', maxLength - 1).takeIf { it >= 40 } ?: maxLength - 1
        return clean.substring(0, boundary).trimEnd(',', ';', ':', '-', ' ') + "..."
    }

    private fun prefs() = getSharedPreferences(JuicrNotificationScheduler.PREFS, Context.MODE_PRIVATE)

    private fun firstNonEmpty(vararg values: String?): String {
        return values.firstOrNull { !it.isNullOrBlank() }?.trim().orEmpty()
    }

    private fun urlEncode(value: String): String {
        return URLEncoder.encode(value, "UTF-8")
    }

    private fun curationMessage(editorial: JSONObject): String {
        val rails = mutableListOf<JSONObject>()
        editorial.optJSONObject("hero")?.let { rails.add(it) }
        editorial.optJSONArray("rails")?.let { railArray ->
            for (index in 0 until railArray.length()) {
                railArray.optJSONObject(index)?.let { rails.add(it) }
            }
        }
        for (rail in rails) {
            val railTitle = safeUserVisibleNotificationText(rail.optString("title"), "")
            val subtitle = safeUserVisibleNotificationText(rail.optString("subtitle"), "")
            if (railTitle.isNotEmpty() && subtitle.isNotEmpty()) return "$railTitle - $subtitle"
            if (railTitle.isNotEmpty()) return railTitle
            if (subtitle.isNotEmpty()) return subtitle
        }
        return "Fresh movie, series, and animation picks are waiting."
    }

    private fun safeUserVisibleNotificationText(value: String?, fallback: String): String {
        val clean = (value ?: "")
            .replace(Regex("https?://[^\\s,)]+", RegexOption.IGNORE_CASE), "")
            .replace(Regex("magnet:\\?[^\\s,)]+", RegexOption.IGNORE_CASE), "")
            .replace(
                Regex(
                    "\\b(infoHash|trackerAddresses|peerAddresses|headers|tokens|localRuntimeEndpoints|manifestUrls|streamUrls|externalUrls)\\b\\s*[:=]\\s*[\"']?[^\"'\\n,;)]+",
                    RegexOption.IGNORE_CASE
                ),
                ""
            )
            .replace(
                Regex(
                    "\\b(api[_-]?key|token|secret|password|authorization|bearer)\\b\\s*[:=]\\s*[\"']?[^\"'\\s,;)]+",
                    RegexOption.IGNORE_CASE
                ),
                ""
            )
            .replace(
                Regex(
                    "\\b(?:manifest|stream|source|local)\\s+url\\s*[:=]\\s*[\"']?[^\"'\\s,;)]+",
                    RegexOption.IGNORE_CASE
                ),
                "[redacted]"
            )
            .replace(
                Regex(
                    "\\blocal\\s+endpoint\\s*[:=]\\s*[\"']?[^\"'\\s,;)]+",
                    RegexOption.IGNORE_CASE
                ),
                "[redacted]"
            )
            .replace(Regex("\\s+"), " ")
            .trim()
            .take(120)
            .trim()
        return clean.ifEmpty { fallback }
    }

    private fun dailyCurationTitle(seed: String): String {
        val values = listOf(
            "Today's Juicr picks",
            "Fresh picks from Juicr",
            "Your Juicr shelf is ready",
            "Tonight on Juicr",
            "A fresh row is waiting"
        )
        var hash = 0
        for (char in seed) {
            hash = (hash * 31 + char.code) and 0x7fffffff
        }
        return values[hash % values.size]
    }

    private fun surfaceAllowed(controls: JSONObject?, surface: String): Boolean {
        val surfaces = controls?.optJSONArray("allowedSurfaces") ?: return true
        if (surfaces.length() == 0) return true
        for (index in 0 until surfaces.length()) {
            if (surfaces.optString(index).trim().equals(surface, ignoreCase = true)) {
                return true
            }
        }
        return false
    }

    private fun todayStamp(): String {
        return JuicrNotificationTime.todayStamp()
    }

    private companion object {
        const val CHANNEL_ID = JuicrNotificationScheduler.CHANNEL_ID
        const val NOTIFICATION_ID = 12002
    }
}
