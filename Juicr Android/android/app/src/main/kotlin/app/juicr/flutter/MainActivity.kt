package app.juicr.flutter

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RemoteAction
import android.os.BatteryManager
import android.os.Bundle
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.Rational
import android.view.WindowManager
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private val pipChannelName = "app.juicr.flutter/pip"
    private val pipActionSkipBack = "app.juicr.flutter.PIP_SKIP_BACK"
    private val pipActionPlayPause = "app.juicr.flutter.PIP_PLAY_PAUSE"
    private val pipActionSkipForward = "app.juicr.flutter.PIP_SKIP_FORWARD"
    private val displayChannelName = "app.juicr.flutter/display"
    private val castChannelName = "app.juicr.flutter/cast"
    private val trailerChannelName = "app.juicr.flutter/trailer"
    private val externalPlayerChannelName = "app.juicr.flutter/external_player"
    private val catalogBuilderPickerChannelName = "app.juicr.flutter/catalog_builder_picker"
    private val integrityChannelName = "app.juicr.flutter/integrity"
    private val diagnosticsChannelName = "app.juicr.flutter/diagnostics"
    private val p2pBridgeChannelName = "app.juicr.flutter/p2p_bridge"
    private val nativeMediaChannelName = "app.juicr.flutter/native_media"
    private val localNotificationsChannelName = "app.juicr.flutter/local_notifications"
    private var integrityProvider: StandardIntegrityTokenProvider? = null
    private var integrityState = "idle"
    private var integrityError: String? = null
    private var pipChannel: MethodChannel? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var pipActionReceiver: BroadcastReceiver? = null
    private var pipAutoEnterOnUserLeave = false
    private var pipAutoEnterPlaying = true
    private var pipAutoEnterSeekSeconds = 10
    private var pipAutoEnterLiveMode = false
    private var catalogBuilderPickerResult: MethodChannel.Result? = null
    private val pipEnterHandler = Handler(Looper.getMainLooper())
    private val p2pRuntimeBridge by lazy { P2pRuntimeBridge(applicationContext) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enforceLocalAppTrustOrExit()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        cleanStartupCaches()
        registerPipActionReceiver()
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "app.juicr.flutter/media3_player",
                JuicrMedia3PlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )

        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pipChannelName)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                }
                "enter" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    val params = buildPipParams(
                        call.argument<Boolean>("playing") ?: true,
                        call.argument<Int>("seekSeconds") ?: 10,
                        call.argument<Boolean>("liveMode") ?: false
                    )
                    result.success(enterPictureInPictureMode(params))
                }
                "updateActions" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    pipAutoEnterPlaying = call.argument<Boolean>("playing") ?: true
                    pipAutoEnterSeekSeconds = call.argument<Int>("seekSeconds") ?: 10
                    pipAutoEnterLiveMode = call.argument<Boolean>("liveMode") ?: false
                    setPictureInPictureParams(
                        buildPipParams(
                            pipAutoEnterPlaying,
                            pipAutoEnterSeekSeconds,
                            pipAutoEnterLiveMode
                        )
                    )
                    result.success(true)
                }
                "finishForHotRestart" -> {
                    result.success(finishForHotRestart())
                }
                "setAutoEnterOnUserLeave" -> {
                    pipAutoEnterOnUserLeave = call.argument<Boolean>("enabled") ?: false
                    pipAutoEnterPlaying = call.argument<Boolean>("playing") ?: true
                    pipAutoEnterSeekSeconds = call.argument<Int>("seekSeconds") ?: 10
                    pipAutoEnterLiveMode = call.argument<Boolean>("liveMode") ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setPictureInPictureParams(
                            buildPipParams(
                                pipAutoEnterPlaying,
                                pipAutoEnterSeekSeconds,
                                pipAutoEnterLiveMode
                            )
                        )
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, displayChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBrightness" -> {
                    val value = call.argument<Double>("value")?.toFloat()
                    if (value == null) {
                        result.error("bad_args", "Missing brightness value.", null)
                        return@setMethodCallHandler
                    }

                    val clamped = value.coerceIn(0.01f, 1.0f)
                    runOnUiThread {
                        val params = window.attributes
                        params.screenBrightness = clamped
                        window.attributes = params
                        result.success(null)
                    }
                }
                "resetBrightness" -> {
                    runOnUiThread {
                        val params = window.attributes
                        params.screenBrightness = -1f
                        window.attributes = params
                        result.success(null)
                    }
                }
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, castChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSettings" -> {
                    result.success(openCastSettings())
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, trailerChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url")
                    val youtubeId = call.argument<String>("youtubeId")
                    if (url.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(openTrailer(url, youtubeId))
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, externalPlayerChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> result.success(listExternalPlayers())
                "open" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(
                        openExternalPlayer(
                            url,
                            call.argument<String>("packageName"),
                            call.argument<String>("activityName"),
                            call.argument<String>("title")
                        )
                    )
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, catalogBuilderPickerChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "openVideo" -> openCatalogBuilderVideoPicker(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, integrityChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(appIntegrityStatus())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, diagnosticsChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "installInfo" -> result.success(appInstallInfo())
                "processExitInfo" -> result.success(historicalProcessExitInfo())
                "batterySnapshot" -> result.success(batterySnapshot())
                "logcat" -> {
                    val message = call.argument<String>("message") ?: ""
                    if (message.isNotBlank()) {
                        mirrorDiagnosticLog(message)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, nativeMediaChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "capabilities" -> result.success(nativeMediaCapabilities())
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localNotificationsChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "areEnabled" -> result.success(localNotificationsEnabled())
                "requestPermission" -> requestLocalNotificationPermission(result)
                "show" -> {
                    val title = call.argument<String>("title") ?: ""
                    val message = call.argument<String>("message") ?: ""
                    val notificationId = call.argument<Int>("id") ?: 1001
                    result.success(showLocalNotification(notificationId, title, message))
                }
                "syncSettings" -> {
                    val notificationsEnabled = call.argument<Boolean>("notificationsEnabled") ?: false
                    val metricsEnabled = call.argument<Boolean>("metricsEnabled") ?: false
                    val dialogsEnabled = call.argument<Boolean>("dialogsEnabled") ?: false
                    val interstitialsEnabled = call.argument<Boolean>("interstitialsEnabled") ?: false
                    syncLocalNotificationSettings(
                        notificationsEnabled,
                        metricsEnabled,
                        dialogsEnabled,
                        interstitialsEnabled
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, p2pBridgeChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(p2pRuntimeBridge.isAvailable())
                "open" -> {
                    try {
                        val infoHash = call.argument<String>("infoHash") ?: ""
                        val fileIdx = call.argument<Int>("fileIdx")
                        val trackers = (call.argument<Any>("trackers") as? List<*>)
                            ?.mapNotNull { it?.toString() }
                            ?: emptyList()
                        val localUrl = p2pRuntimeBridge.open(
                            infoHash = infoHash,
                            fileIdx = fileIdx,
                            trackers = trackers,
                            displayName = call.argument<String>("displayName"),
                            quality = call.argument<String>("quality")
                        )
                        result.success(localUrl)
                    } catch (error: Throwable) {
                        result.error("p2p_open_failed", error.message ?: error.javaClass.simpleName, null)
                    }
                }
                "stopAll" -> {
                    p2pRuntimeBridge.stopAll()
                    result.success(true)
                }
                "networkBucket" -> result.success(networkBucket())
                else -> result.notImplemented()
            }
        }

    }

    private fun networkBucket(): String {
        return try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return "unavailable"
            val network = manager.activeNetwork ?: return "offline"
            val capabilities = manager.getNetworkCapabilities(network) ?: return "unavailable"
            when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "other"
            }
        } catch (_: Throwable) {
            "unavailable"
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handlePipIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == CATALOG_BUILDER_PICKER_REQUEST_CODE) {
            val pending = catalogBuilderPickerResult
            catalogBuilderPickerResult = null
            // The app records only that the user selected something; it never stores the returned URI here.
            pending?.success(resultCode == RESULT_OK && data?.data != null)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val pending = notificationPermissionResult
            notificationPermissionResult = null
            pending?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onUserLeaveHint() {
        if (pipAutoEnterOnUserLeave && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPictureInPictureMode) {
            pipChannel?.invokeMethod("prepareForSystemPip", null)
            pipEnterHandler.postDelayed({
                if (isFinishing || isDestroyed || isInPictureInPictureMode) return@postDelayed
                try {
                    enterPictureInPictureMode(
                        buildPipParams(
                            pipAutoEnterPlaying,
                            pipAutoEnterSeekSeconds,
                            pipAutoEnterLiveMode
                        )
                    )
                } catch (error: IllegalStateException) {
                    // Android may reject PiP during transient lifecycle states; Dart keeps a fallback path.
                } catch (error: IllegalArgumentException) {
                    // Invalid params should not crash playback; the next action update will rebuild params.
                }
            }, 180L)
        } else {
            pipEnterHandler.removeCallbacksAndMessages(null)
        }
        super.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val method = if (isInPictureInPictureMode) {
            "enteredSystemPip"
        } else {
            "exitedSystemPip"
        }
        pipChannel?.invokeMethod(method, null)
    }

    override fun onDestroy() {
        pipEnterHandler.removeCallbacksAndMessages(null)
        unregisterPipActionReceiver()
        if (isFinishing) {
            p2pRuntimeBridge.stopAll()
        }
        super.onDestroy()
    }

    private fun finishForHotRestart(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || !isInPictureInPictureMode) {
            return false
        }
        return try {
            finishAndRemoveTask()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun localNotificationsEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun requestLocalNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || localNotificationsEnabled()) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.success(false)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE
        )
    }

    private fun showLocalNotification(notificationId: Int, title: String, message: String): Boolean {
        if (title.isBlank() || message.isBlank() || !localNotificationsEnabled()) return false
        val manager = getSystemService(NotificationManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    JUICR_NOTIFICATION_CHANNEL_ID,
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
            notificationId,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, JUICR_NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(compactNotificationText(message))
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(notificationId, notification)
        return true
    }

    private fun compactNotificationText(message: String): String {
        val clean = message.trim().replace(Regex("\\s+"), " ")
        val maxLength = 72
        if (clean.length <= maxLength) return clean
        val boundary = clean.lastIndexOf(' ', maxLength - 1).takeIf { it >= 40 } ?: maxLength - 1
        return clean.substring(0, boundary).trimEnd(',', ';', ':', '-', ' ') + "..."
    }

    private fun syncLocalNotificationSettings(
        notificationsEnabled: Boolean,
        metricsEnabled: Boolean,
        dialogsEnabled: Boolean,
        interstitialsEnabled: Boolean
    ) {
        JuicrNotificationScheduler.syncSettings(
            this,
            notificationsEnabled,
            metricsEnabled,
            dialogsEnabled,
            interstitialsEnabled
        )
    }

    private fun scheduleNotificationJob() {
        JuicrNotificationScheduler.schedule(this)
    }

    private fun cancelNotificationJob() {
        JuicrNotificationScheduler.cancel(this)
    }

    private fun registerPipActionReceiver() {
        if (pipActionReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                handlePipIntent(intent)
            }
        }
        val filter = IntentFilter().apply {
            addAction(pipActionSkipBack)
            addAction(pipActionPlayPause)
            addAction(pipActionSkipForward)
        }
        pipActionReceiver = receiver
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }
    }

    private fun unregisterPipActionReceiver() {
        val receiver = pipActionReceiver ?: return
        pipActionReceiver = null
        try {
            unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
        }
    }

    private fun buildPipParams(isPlaying: Boolean, seekSeconds: Int, liveMode: Boolean): PictureInPictureParams {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return PictureInPictureParams.Builder().build()
        }
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(buildPipActions(isPlaying, seekSeconds, liveMode))
        return builder
            .build()
    }

    private fun buildPipActions(isPlaying: Boolean, seekSeconds: Int, liveMode: Boolean): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val playPauseIcon = if (isPlaying) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }
        val playPauseTitle = if (isPlaying) "Pause" else "Play"
        val playPauseAction = RemoteAction(
            Icon.createWithResource(this, playPauseIcon),
            playPauseTitle,
            playPauseTitle,
            pipPendingIntent(pipActionPlayPause)
        )
        if (liveMode) return listOf(playPauseAction)
        return listOf(
            RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_rew),
                "Back ${seekSeconds}s",
                "Back ${seekSeconds} seconds",
                pipPendingIntent(pipActionSkipBack)
            ),
            playPauseAction,
            RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_media_ff),
                "Forward ${seekSeconds}s",
                "Forward ${seekSeconds} seconds",
                pipPendingIntent(pipActionSkipForward)
            )
        )
    }

    private fun pipPendingIntent(action: String): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val intent = Intent(action)
            .setAction(action)
            .setPackage(packageName)
        return PendingIntent.getBroadcast(this, action.hashCode(), intent, flags)
    }

    private fun handlePipIntent(intent: Intent?): Boolean {
        val actionName = when (intent?.action) {
            pipActionSkipBack -> "skipBack"
            pipActionPlayPause -> "playPause"
            pipActionSkipForward -> "skipForward"
            else -> null
        } ?: return false
        pipChannel?.invokeMethod("action", actionName)
        return true
    }

    private fun appIntegrityStatus(): Map<String, Any> {
        val cloudProjectNumber = playIntegrityCloudProjectNumber()
        val configured = cloudProjectNumber > 0L
        val appTrust = appTrustStatus()
        val baseStatus = mutableMapOf<String, Any>(
            "available" to true,
            "appTrusted" to appTrust.trusted,
            "packageTrusted" to appTrust.packageTrusted,
            "signatureConfigured" to appTrust.signatureConfigured,
            "signatureTrusted" to appTrust.signatureTrusted,
            "blockUntrustedApp" to BuildConfig.JUICR_BLOCK_UNTRUSTED_APP,
            "packageName" to packageName,
            "expectedPackageName" to EXPECTED_PACKAGE_NAME,
            "signingCertSha256Prefix" to appTrust.signingCertSha256Prefix
        )
        if (!configured) {
            baseStatus["configured"] = false
            baseStatus["mode"] = if (appTrust.trusted) "observe-disabled" else "untrusted"
            return baseStatus
        }

        prepareAppIntegrity(cloudProjectNumber)
        baseStatus["configured"] = true
        baseStatus["mode"] = if (appTrust.trusted) integrityState else "untrusted"
        baseStatus["error"] = integrityError ?: ""
        return baseStatus
    }

    private fun mirrorDiagnosticLog(message: String) {
        val safe = message.take(900)
        Log.i("JuicrDiag", safe)
        try {
            val diagnosticsDir = getExternalFilesDir("diagnostics") ?: return
            if (!diagnosticsDir.exists()) diagnosticsDir.mkdirs()
            val diagnosticsFile = File(diagnosticsDir, "playback_probe.log")
            if (diagnosticsFile.length() > 160 * 1024) {
                diagnosticsFile.writeText("")
            }
            diagnosticsFile.appendText("${System.currentTimeMillis()} $safe\n")
        } catch (_: Exception) {
            // Best-effort redacted diagnostics mirror for ADB playback probes.
        }
    }

    private fun appInstallInfo(): Map<String, Any> {
        return try {
            val packageInfo = packageInfoForDiagnostics()
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
            mapOf(
                "packageName" to packageName,
                "versionName" to (packageInfo.versionName ?: ""),
                "versionCode" to versionCode,
                "firstInstallTime" to packageInfo.firstInstallTime,
                "lastUpdateTime" to packageInfo.lastUpdateTime
            )
        } catch (_: Exception) {
            mapOf(
                "packageName" to packageName,
                "versionName" to "",
                "versionCode" to 0L,
                "firstInstallTime" to 0L,
                "lastUpdateTime" to 0L
            )
        }
    }

    private fun historicalProcessExitInfo(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        return try {
            val manager = getSystemService(ActivityManager::class.java)
            manager.getHistoricalProcessExitReasons(packageName, 0, 5).map { info ->
                mapOf(
                    "reason" to exitReasonName(info.reason),
                    "reasonCode" to info.reason,
                    "description" to (info.description ?: ""),
                    "importance" to info.importance,
                    "timestamp" to info.timestamp,
                    "pss" to info.pss,
                    "rss" to info.rss
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun batterySnapshot(): Map<String, Any> {
        return try {
            val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
            val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
            val percent = if (level >= 0 && scale > 0) {
                ((level.toDouble() / scale.toDouble()) * 100.0).toInt().coerceIn(0, 100)
            } else {
                val manager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                manager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
            }
            val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val plugged = intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
            val temperatureTenthsC = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
            val voltageMv = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
            mapOf(
                "available" to (percent >= 0),
                "levelPercent" to percent,
                "status" to batteryStatusName(status),
                "plugged" to batteryPluggedName(plugged),
                "temperatureTenthsC" to temperatureTenthsC,
                "voltageMv" to voltageMv,
                "sdk" to Build.VERSION.SDK_INT
            )
        } catch (_: Exception) {
            mapOf(
                "available" to false,
                "levelPercent" to -1,
                "status" to "unavailable",
                "plugged" to "unavailable",
                "temperatureTenthsC" to -1,
                "voltageMv" to -1,
                "sdk" to Build.VERSION.SDK_INT
            )
        }
    }

    private fun batteryStatusName(status: Int): String {
        return when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
            BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
            BatteryManager.BATTERY_STATUS_FULL -> "full"
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not_charging"
            BatteryManager.BATTERY_STATUS_UNKNOWN -> "unknown"
            else -> "unknown"
        }
    }

    private fun batteryPluggedName(plugged: Int): String {
        val parts = mutableListOf<String>()
        if (plugged and BatteryManager.BATTERY_PLUGGED_AC != 0) parts.add("ac")
        if (plugged and BatteryManager.BATTERY_PLUGGED_USB != 0) parts.add("usb")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1 &&
            plugged and BatteryManager.BATTERY_PLUGGED_WIRELESS != 0
        ) {
            parts.add("wireless")
        }
        return if (parts.isEmpty()) "none" else parts.joinToString("+")
    }

    private fun nativeMediaCapabilities(): Map<String, Any> {
        return mapOf(
            "schema" to "juicr.native_media.capabilities.v1",
            "sdk" to Build.VERSION.SDK_INT,
            "device" to "${Build.MANUFACTURER}/${Build.MODEL}",
            "media3Available" to classAvailable("androidx.media3.exoplayer.ExoPlayer"),
            "media3UiAvailable" to classAvailable("androidx.media3.ui.PlayerView"),
            "legacyExoPlayerAvailable" to classAvailable("com.google.android.exoplayer2.ExoPlayer"),
            "surfaceControlAvailable" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q),
            "pictureInPictureAvailable" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O),
            "decoders" to nativeDecoderSummary()
        )
    }

    private fun classAvailable(className: String): Boolean {
        return try {
            Class.forName(className)
            true
        } catch (_: Throwable) {
            false
        }
    }

    private fun nativeDecoderSummary(): List<Map<String, Any>> {
        val targets = listOf("video/avc", "video/hevc", "video/av01", "video/x-vnd.on2.vp9")
        return try {
            val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            targets.map { mime ->
                val matches = codecs.filter { codec ->
                    !codec.isEncoder &&
                        codec.supportedTypes.any { it.equals(mime, ignoreCase = true) }
                }
                val hardwareCount = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    matches.count { it.isHardwareAccelerated }
                } else {
                    matches.count { !it.name.startsWith("OMX.google", ignoreCase = true) }
                }
                mapOf(
                    "mime" to mime,
                    "count" to matches.size,
                    "hardwareCount" to hardwareCount,
                    "secureCount" to matches.count { codecSupportsSecurePlayback(it, mime) }
                )
            }
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun codecSupportsSecurePlayback(codec: MediaCodecInfo, mime: String): Boolean {
        return try {
            codec.getCapabilitiesForType(mime)
                .isFeatureSupported(MediaCodecInfo.CodecCapabilities.FEATURE_SecurePlayback)
        } catch (_: Throwable) {
            false
        }
    }

    private fun exitReasonName(reason: Int): String {
        return when (reason) {
            1 -> "exit_self"
            2 -> "signaled"
            3 -> "low_memory"
            4 -> "crash"
            5 -> "crash_native"
            6 -> "anr"
            7 -> "initialization_failure"
            8 -> "permission_change"
            9 -> "excessive_resource_usage"
            10 -> "user_requested"
            11 -> "user_stopped"
            12 -> "dependency_died"
            13 -> "other"
            else -> "unknown"
        }
    }

    private fun appTrustStatus(): AppTrustStatus {
        val packageTrusted = packageName == EXPECTED_PACKAGE_NAME
        val expectedDigest = BuildConfig.JUICR_EXPECTED_SIGNING_CERT_SHA256
            .trim()
            .lowercase()
            .replace(":", "")
        val digests = signingCertSha256Digests()
        val signatureConfigured = expectedDigest.isNotBlank()
        val signatureTrusted = !signatureConfigured || digests.any { it == expectedDigest }
        return AppTrustStatus(
            trusted = packageTrusted && signatureTrusted,
            packageTrusted = packageTrusted,
            signatureConfigured = signatureConfigured,
            signatureTrusted = signatureTrusted,
            signingCertSha256Prefix = digests.firstOrNull()?.take(12) ?: ""
        )
    }

    private fun enforceLocalAppTrustOrExit() {
        if (!BuildConfig.JUICR_BLOCK_UNTRUSTED_APP) return
        if (appTrustStatus().trusted) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            finish()
        }
    }

    private fun signingCertSha256Digests(): List<String> {
        return try {
            val packageInfo = packageInfoForSignatures()
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signingInfo = packageInfo.signingInfo ?: return emptyList()
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                packageInfo.signatures ?: return emptyList()
            }
            signatures
                .mapNotNull { signature ->
                    val digest = MessageDigest.getInstance("SHA-256")
                        .digest(signature.toByteArray())
                    digest.joinToString("") { byte -> "%02x".format(byte) }
                }
                .distinct()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun packageInfoForSignatures(): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.GET_SIGNING_CERTIFICATES
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
        }
    }

    private fun packageInfoForDiagnostics(): PackageInfo {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
    }

    private fun prepareAppIntegrity(cloudProjectNumber: Long) {
        if (integrityProvider != null || integrityState == "preparing") return
        integrityState = "preparing"
        integrityError = null

        IntegrityManagerFactory.createStandard(applicationContext)
            .prepareIntegrityToken(
                PrepareIntegrityTokenRequest.builder()
                    .setCloudProjectNumber(cloudProjectNumber)
                    .build()
            )
            .addOnSuccessListener { provider ->
                integrityProvider = provider
                integrityState = "prepared"
            }
            .addOnFailureListener { exception ->
                integrityProvider = null
                integrityState = "failed"
                integrityError = exception.javaClass.simpleName
            }
    }

    private fun cleanStartupCaches() {
        try {
            File(cacheDir, "juicr-p2p").deleteRecursively()
        } catch (_: Throwable) {
        }
    }

    private fun playIntegrityCloudProjectNumber(): Long {
        return try {
            val appInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(
                    packageName,
                    PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            }
            when (val value = appInfo.metaData?.get("app.juicr.play_integrity_cloud_project_number")) {
                is String -> value.toLongOrNull() ?: 0L
                is Number -> value.toLong()
                else -> 0L
            }
        } catch (_: Exception) {
            0L
        }
    }

    private fun listExternalPlayers(): List<Map<String, String>> {
        val sampleUrl = Uri.parse("https://example.com/video.mp4")
        val intents = listOf(
            Intent(Intent.ACTION_VIEW).setDataAndType(sampleUrl, "video/*"),
            Intent(Intent.ACTION_VIEW, sampleUrl)
        )
        val players = linkedMapOf<String, Map<String, String>>()

        for (intent in intents) {
            val activities = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryIntentActivities(
                    intent,
                    PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            }

            for (resolveInfo in activities) {
                val activityInfo = resolveInfo.activityInfo ?: continue
                val packageName = activityInfo.packageName ?: continue
                if (packageName == applicationContext.packageName) continue
                val label = resolveInfo.loadLabel(packageManager)?.toString()?.trim()
                    ?.takeIf { it.isNotBlank() }
                    ?: packageName
                if (!isExternalVideoPlayer(packageName, activityInfo.name, label)) continue
                players[packageName] = mapOf(
                    "packageName" to packageName,
                    "activityName" to (activityInfo.name ?: ""),
                    "label" to label
                )
            }
        }

        return players.values.sortedWith(
            compareBy<Map<String, String>> {
                externalPlayerRank(
                    it["packageName"].orEmpty(),
                    it["label"].orEmpty()
                )
            }.thenBy { it["label"]?.lowercase() ?: "" }
        )
    }

    private fun isExternalVideoPlayer(
        packageName: String,
        activityName: String?,
        label: String
    ): Boolean {
        val packageLower = packageName.lowercase()
        val activityLower = activityName?.lowercase().orEmpty()
        val labelLower = label.lowercase()
        val combined = "$packageLower $activityLower $labelLower"

        val blockedReceivers = listOf(
            "browser",
            "chrome",
            "firefox",
            "edge",
            "opera",
            "brave",
            "samsung.android.app.sbrowser",
            "photos",
            "gallery",
            "camera",
            "filemanager",
            "file.manager",
            "files",
            "documentsui",
            "drive",
            "dropbox",
            "onedrive",
            "telegram",
            "whatsapp"
        )
        if (blockedReceivers.any { combined.contains(it) }) {
            return false
        }

        val knownVideoPlayers = listOf(
            "videolan",
            "vlc",
            "mxtech.videoplayer",
            "mx player",
            "brouken.player",
            "just player",
            "justplayer",
            "mpv",
            "kodi",
            "nova video player",
            "bsplayer",
            "kmplayer",
            "xplayer",
            "playit",
            "nplayer",
            "video player",
            "media player"
        )
        return knownVideoPlayers.any { combined.contains(it) }
    }

    private fun externalPlayerRank(packageName: String, label: String): Int {
        val packageLower = packageName.lowercase()
        val labelLower = label.lowercase()
        if (packageLower.contains("vlc") ||
            packageLower.contains("mxtech") ||
            packageLower.contains("justplayer") ||
            labelLower.contains("vlc") ||
            labelLower.contains("mx player") ||
            labelLower == "player"
        ) {
            return 0
        }
        if (packageLower.contains("chrome") ||
            packageLower.contains("browser") ||
            packageLower.contains("photos") ||
            labelLower.contains("chrome") ||
            labelLower.contains("browser") ||
            labelLower.contains("photos")
        ) {
            return 2
        }
        return 1
    }

    private fun openExternalPlayer(
        url: String,
        packageName: String?,
        activityName: String?,
        title: String?
    ): Boolean {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(Uri.parse(url), "video/*")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (!packageName.isNullOrBlank() && !activityName.isNullOrBlank()) {
            intent.setClassName(packageName, activityName)
        } else if (!packageName.isNullOrBlank()) {
            intent.setPackage(packageName)
        }
        if (!title.isNullOrBlank()) {
            intent.putExtra(Intent.EXTRA_TITLE, title)
        }

        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun openTrailer(url: String, youtubeId: String?): Boolean {
        val intents = mutableListOf<Intent>()
        if (!youtubeId.isNullOrBlank()) {
            intents.add(
                Intent(Intent.ACTION_VIEW, Uri.parse("vnd.youtube:$youtubeId"))
                    .setPackage("com.google.android.youtube")
            )
            intents.add(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/watch?v=$youtubeId"))
                    .setPackage("com.google.android.youtube")
            )
        }
        intents.add(Intent(Intent.ACTION_VIEW, Uri.parse(url)))

        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next best trailer target.
            } catch (_: SecurityException) {
                // Some vendor builds restrict explicit targets.
            }
        }
        return false
    }

    private fun openCastSettings(): Boolean {
        val intents = listOf(
            Intent(Settings.ACTION_CAST_SETTINGS),
            Intent(Settings.ACTION_WIRELESS_SETTINGS)
        )

        for (intent in intents) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next best system settings panel.
            } catch (_: SecurityException) {
                // Some vendor builds lock down these panels.
            }
        }

        return false
    }

    private fun openCatalogBuilderVideoPicker(result: MethodChannel.Result) {
        if (catalogBuilderPickerResult != null) {
            result.error("picker_busy", "Catalog Builder picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        catalogBuilderPickerResult = result
        try {
            startActivityForResult(intent, CATALOG_BUILDER_PICKER_REQUEST_CODE)
        } catch (_: ActivityNotFoundException) {
            catalogBuilderPickerResult = null
            result.success(false)
        } catch (_: SecurityException) {
            catalogBuilderPickerResult = null
            result.success(false)
        }
    }

    private data class AppTrustStatus(
        val trusted: Boolean,
        val packageTrusted: Boolean,
        val signatureConfigured: Boolean,
        val signatureTrusted: Boolean,
        val signingCertSha256Prefix: String
    )

    private companion object {
        const val EXPECTED_PACKAGE_NAME = "app.juicr.flutter"
        const val CATALOG_BUILDER_PICKER_REQUEST_CODE = 42029
        const val NOTIFICATION_PERMISSION_REQUEST_CODE = 43031
        const val JUICR_NOTIFICATION_CHANNEL_ID = JuicrNotificationScheduler.CHANNEL_ID
    }
}
