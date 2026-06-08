package app.juicr.flutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var pendingVoiceResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

    companion object {
        private const val VOICE_CHANNEL = "app.juicr.flutter/voice_search"
        private const val TRAILER_CHANNEL = "app.juicr.flutter/trailer"
        private const val MEDIA3_PLAYER_VIEW = "app.juicr.flutter/media3_player"
        private const val VOICE_REQUEST_CODE = 7301
    }
}
