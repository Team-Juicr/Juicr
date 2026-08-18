package app.juicr.flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.speech.RecognizerIntent
import android.util.Log
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import app.juicr.flutter.update.UpdateBridge
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var remoteKeyChannel: MethodChannel? = null
    private var hiddenHudRemoteCapture = false
    private val p2pRuntimeBridge by lazy { P2pRuntimeBridge(applicationContext) }
    private var appUpdateBridge: UpdateBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdateBridge?.dispose()
        appUpdateBridge = UpdateBridge(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
            "tv",
        )
        remoteKeyChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REMOTE_KEY_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHiddenHudCapture" -> {
                        hiddenHudRemoteCapture = call.argument<Boolean>("active") == true
                        Log.i(
                            REMOTE_LOG_TAG,
                            "Juicr TV hidden HUD capture active=$hiddenHudRemoteCapture"
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                MEDIA3_PLAYER_VIEW,
                JuicrMedia3PlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VOICE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startVoiceSearch" -> startVoiceSearch(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TRAILER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openTrailer" -> openTrailer(call.argument<String>("url").orEmpty(), result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            QUICK_LINK_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> openQuickLink(call.argument<String>("url").orEmpty(), result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            P2P_BRIDGE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(p2pRuntimeBridge.isAvailable())
                "availabilityStatus" -> result.success(p2pRuntimeBridge.availabilityStatus())
                "open" -> {
                    try {
                        val trackers = (call.argument<Any>("trackers") as? List<*>)
                            ?.mapNotNull { it?.toString() }
                            ?: emptyList()
                        val localUrl = p2pRuntimeBridge.open(
                            infoHash = call.argument<String>("infoHash").orEmpty(),
                            fileIdx = call.argument<Int>("fileIdx"),
                            trackers = trackers,
                            displayName = call.argument<String>("displayName"),
                            quality = call.argument<String>("quality"),
                            generation = call.argument<Number>("generation")?.toLong()
                        )
                        result.success(localUrl)
                    } catch (error: Throwable) {
                        result.error(
                            "p2p_open_failed",
                            "Advanced playback could not start.",
                            mapOf("bucket" to P2pRuntimePolicy.errorBucket(error))
                        )
                    }
                }
                "isReady" -> result.success(
                    p2pRuntimeBridge.isReady(
                        call.argument<Number>("generation")?.toLong()
                    )
                )
                "readinessStatus" -> result.success(
                    p2pRuntimeBridge.readinessStatus(
                        call.argument<Number>("generation")?.toLong()
                    )
                )
                "networkBucket" -> result.success(networkBucket())
                "stopAll" -> {
                    p2pRuntimeBridge.stopAll(
                        call.argument<Number>("generation")?.toLong()
                    )
                    result.success(true)
                }
                "stopGeneration" -> {
                    p2pRuntimeBridge.stopGeneration(
                        call.argument<Number>("generation")?.toLong()
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        appUpdateBridge?.onHostResume()
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

    private fun startVoiceSearch(result: MethodChannel.Result) {
        if (pendingVoiceResult != null) {
            result.error("busy", "Voice search is already listening.", null)
            return
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Search Juicr TV")
        }
        pendingVoiceResult = result
        try {
            startActivityForResult(intent, VOICE_REQUEST_CODE)
        } catch (_: ActivityNotFoundException) {
            pendingVoiceResult = null
            result.error("unavailable", "Voice search is unavailable on this TV.", null)
        }
    }

    private fun openTrailer(url: String, result: MethodChannel.Result) {
        val cleanUrl = url.trim()
        if (cleanUrl.isEmpty()) {
            result.error("invalid", "Trailer link is unavailable.", null)
            return
        }
        val uri = Uri.parse(cleanUrl)
        val intents = mutableListOf<Intent>()
        val youtubeId = youtubeIdFrom(uri)
        if (!youtubeId.isNullOrBlank()) {
            intents.add(
                Intent(Intent.ACTION_VIEW, Uri.parse("vnd.youtube:$youtubeId")).apply {
                    setPackage("com.google.android.youtube.tv")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            intents.add(
                Intent(Intent.ACTION_VIEW, Uri.parse("vnd.youtube:$youtubeId")).apply {
                    setPackage("com.google.android.youtube")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
        }
        intents.add(
            Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
        for (intent in intents) {
            try {
                startActivity(intent)
                result.success(true)
                return
            } catch (_: ActivityNotFoundException) {
                // Try the next available TV/browser handler.
            } catch (_: SecurityException) {
                // Try the next available TV/browser handler.
            }
        }
        result.error("unavailable", "No TV app can open this trailer.", null)
    }

    private fun openQuickLink(url: String, result: MethodChannel.Result) {
        val cleanUrl = url.trim()
        if (cleanUrl.isEmpty()) {
            result.error("invalid", "Link is unavailable.", null)
            return
        }
        val uri = Uri.parse(cleanUrl)
        val scheme = uri.scheme?.lowercase(Locale.US).orEmpty()
        if (scheme != "https" && scheme != "http") {
            result.error("invalid", "Only web links can be opened.", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        } catch (_: SecurityException) {
            result.success(false)
        }
    }

    private fun youtubeIdFrom(uri: Uri): String? {
        val host = uri.host?.lowercase(Locale.US).orEmpty()
        if (host.contains("youtu.be")) {
            return uri.pathSegments.firstOrNull()
        }
        if (!host.contains("youtube.com")) return null
        val direct = uri.getQueryParameter("v")
        if (!direct.isNullOrBlank()) return direct
        val segments = uri.pathSegments
        val embedIndex = segments.indexOfFirst { it == "embed" || it == "shorts" }
        return if (embedIndex >= 0 && embedIndex + 1 < segments.size) {
            segments[embedIndex + 1]
        } else {
            null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VOICE_REQUEST_CODE) {
            val result = pendingVoiceResult ?: return
            pendingVoiceResult = null
            if (resultCode != Activity.RESULT_OK) {
                result.error("cancelled", "Voice search was cancelled.", null)
                return
            }
            val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            result.success(matches?.firstOrNull().orEmpty())
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN && isHiddenHudRevealKey(event.keyCode)) {
            Log.i(
                REMOTE_LOG_TAG,
                "Juicr TV hidden HUD directional key capture=$hiddenHudRemoteCapture"
            )
        }
        if (isNativePlaybackMediaKey(event.keyCode) ||
            (hiddenHudRemoteCapture && isHiddenHudRevealKey(event.keyCode))) {
            remoteKeyChannel?.invokeMethod(
                "key",
                mapOf(
                    "keyCode" to event.keyCode,
                    "action" to event.action,
                    "repeatCount" to event.repeatCount
                )
            )
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun isHiddenHudRevealKey(keyCode: Int): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_NUMPAD_ENTER,
            KeyEvent.KEYCODE_SPACE,
            KeyEvent.KEYCODE_SEARCH,
            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_INFO,
            KeyEvent.KEYCODE_CAPTIONS,
            KeyEvent.KEYCODE_SETTINGS,
            KeyEvent.KEYCODE_PAGE_UP,
            KeyEvent.KEYCODE_PAGE_DOWN,
            KeyEvent.KEYCODE_CHANNEL_UP,
            KeyEvent.KEYCODE_CHANNEL_DOWN -> true
            else -> false
        }
    }

    private fun isNativePlaybackMediaKey(keyCode: Int): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
            KeyEvent.KEYCODE_MEDIA_REWIND -> true
            else -> false
        }
    }

    override fun onDestroy() {
        hiddenHudRemoteCapture = false
        remoteKeyChannel?.setMethodCallHandler(null)
        appUpdateBridge?.dispose()
        appUpdateBridge = null
        if (isFinishing) {
            p2pRuntimeBridge.stopAll()
        }
        super.onDestroy()
    }

    companion object {
        private const val VOICE_CHANNEL = "app.juicr.flutter/voice_search"
        private const val TRAILER_CHANNEL = "app.juicr.flutter/trailer"
        private const val QUICK_LINK_CHANNEL = "app.juicr.flutter/quick_links"
        private const val REMOTE_KEY_CHANNEL = "app.juicr.flutter/tv_remote_keys"
        private const val REMOTE_LOG_TAG = "JuicrTvRemote"
        private const val MEDIA3_PLAYER_VIEW = "app.juicr.flutter/media3_player"
        private const val P2P_BRIDGE_CHANNEL = "app.juicr.flutter/p2p_bridge"
        private const val VOICE_REQUEST_CODE = 7301
    }
}
