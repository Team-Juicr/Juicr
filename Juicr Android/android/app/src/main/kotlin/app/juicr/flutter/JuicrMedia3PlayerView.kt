package app.juicr.flutter

import android.content.Context
import android.graphics.Color
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import javax.net.ssl.SSLException
import kotlin.math.max

private const val DEFAULT_MEDIA3_USER_AGENT = "JuicrApp/1 Android Media3"
private const val DEFAULT_MAX_AUTO_VIDEO_WIDTH = 1920
private const val DEFAULT_MAX_AUTO_VIDEO_HEIGHT = 1080
private const val VOD_BACK_BUFFER_MS = 45_000

private fun isAndroidEmulator(): Boolean {
    val hardware = Build.HARDWARE.lowercase()
    val model = Build.MODEL.lowercase()
    return hardware.contains("ranchu") ||
        hardware.contains("goldfish") ||
        model.contains("sdk_gphone")
}

private fun media3CodecSelectorForDevice(): MediaCodecSelector {
    if (!isAndroidEmulator()) return MediaCodecSelector.DEFAULT
    return MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
        if (mimeType != MimeTypes.VIDEO_H264) {
            return@MediaCodecSelector MediaCodecSelector.DEFAULT.getDecoderInfos(
                mimeType,
                requiresSecureDecoder,
                requiresTunnelingDecoder
            )
        }
        MediaCodecSelector.PREFER_SOFTWARE.getDecoderInfos(
            mimeType,
            requiresSecureDecoder,
            requiresTunnelingDecoder
        )
    }
}

class JuicrMedia3PlayerViewFactory(
    messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE), MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "app.juicr.flutter/media3_player")
    private val players = mutableMapOf<Int, JuicrMedia3PlayerView>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val playerView = JuicrMedia3PlayerView(context, viewId, args as? Map<*, *>, channel)
        players[viewId] = playerView
        return playerView
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val viewId = call.argument<Int>("viewId")
        val player = viewId?.let { players[it] }
        if (player == null) {
            result.error("missing_player", "Media3 player is not attached.", null)
            return
        }
        when (call.method) {
            "state" -> result.success(player.state())
            "play" -> {
                player.play()
                result.success(true)
            }
            "pause" -> {
                player.pause()
                result.success(true)
            }
            "seekTo" -> {
                player.seekTo(call.argument<Number>("positionMs")?.toLong() ?: 0L)
                result.success(true)
            }
            "setLooping" -> {
                player.setLooping(call.argument<Boolean>("looping") == true)
                result.success(true)
            }
            "setPlaybackSpeed" -> {
                player.setPlaybackSpeed(call.argument<Number>("speed")?.toFloat() ?: 1f)
                result.success(true)
            }
            "setVideoSizeMode" -> {
                player.setVideoSizeMode(call.argument<String>("mode").orEmpty())
                result.success(true)
            }
            "setVolume" -> {
                player.setVolume(call.argument<Number>("volume")?.toFloat() ?: 1f)
                result.success(true)
            }
            "dispose" -> {
                players.remove(viewId)
                player.dispose()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}

class JuicrMedia3PlayerView(
    context: Context,
    private val viewId: Int,
    args: Map<*, *>?,
    private val channel: MethodChannel
) : PlatformView, Player.Listener, AnalyticsListener {
    private val rootView = FrameLayout(context)
    private val textureView = TextureView(context)
    private val player: ExoPlayer
    private var errorDescription = ""
    private var initialized = false
    private var width = 0
    private var height = 0
    private var pixelWidthHeightRatio = 1f
    private var videoSizeMode = "fit"
    private var released = false
    private var firstFrameRendered = false
    private var droppedVideoFrames = 0
    private var bandwidthKbps = 0L
    private var lastTrackSummary = "unknown"
    private var lastAudioTrackSummary = "unknown"
    private var errorBucket = "none"
    private val loadCompletedCounts = mutableMapOf<String, Int>()
    private val loadErrorCounts = mutableMapOf<String, Int>()
    private var lastLoadErrorBucket = "none"
    private val liveMode = args?.get("liveMode") == true
    private val sourceClass = (args?.get("sourceClass") as? String).orEmpty()
    private val sourceType = normalizedSourceType(args?.get("type"))
    private val sourceMimeType = media3MimeTypeFor(sourceType, (args?.get("url") as? String).orEmpty())
    private val headerCountBucket: String

    init {
        val headers = parseHeaders(args?.get("headers"))
        headerCountBucket = headerCountBucket(headers.size)
        val userAgent = headerValue(headers, "user-agent") ?: DEFAULT_MEDIA3_USER_AGENT
        val requestHeaders = headers.filterKeys { !it.equals("user-agent", ignoreCase = true) }
        val preferredAudioLanguage = normalizedLanguage(args?.get("preferredAudioLanguage"))
        val subtitleLanguage = normalizedLanguage(args?.get("subtitleLanguage"))
        val subtitleAutoSelect = (args?.get("subtitleAutoSelect") as? String).orEmpty().lowercase()
        val trackSelector = DefaultTrackSelector(context)
        val trackParams = trackSelector.parameters.buildUpon()
        trackParams.setMaxVideoSize(DEFAULT_MAX_AUTO_VIDEO_WIDTH, DEFAULT_MAX_AUTO_VIDEO_HEIGHT)
        preferredAudioLanguage?.let { trackParams.setPreferredAudioLanguage(it) }
        subtitleLanguage?.let { trackParams.setPreferredTextLanguage(it) }
        if (subtitleAutoSelect == "off" || subtitleAutoSelect == "none") {
            trackParams.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        }
        trackSelector.parameters = trackParams.build()

        val dataSourceFactory = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(if (liveMode) 6000 else 8000)
            .setReadTimeoutMs(if (liveMode) 8000 else 12000)
            .setAllowCrossProtocolRedirects(true)
            .setUserAgent(userAgent)
            .setDefaultRequestProperties(requestHeaders)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            .setLoadErrorHandlingPolicy(JuicrMedia3LoadErrorPolicy(liveMode))
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                if (liveMode) 6000 else 30000,
                if (liveMode) 24000 else 120000,
                if (liveMode) 900 else 1200,
                if (liveMode) 1600 else 2500
            )
            .setBackBuffer(if (liveMode) 0 else VOD_BACK_BUFFER_MS, true)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        val renderersFactory = DefaultRenderersFactory(context)
            .setMediaCodecSelector(media3CodecSelectorForDevice())
            .setEnableDecoderFallback(true)
            .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
        player = ExoPlayer.Builder(context)
            .setRenderersFactory(renderersFactory)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .build()
        player.addListener(this)
        player.addAnalyticsListener(this)
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            true
        )
        rootView.setBackgroundColor(Color.BLACK)
        rootView.isClickable = false
        rootView.isFocusable = false
        textureView.isClickable = false
        textureView.isFocusable = false
        val tapForwarder = View.OnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_UP && !released) {
                channel.invokeMethod(
                    "surfaceTap",
                    mapOf(
                        "viewId" to viewId,
                        "x" to event.x,
                        "y" to event.y,
                        "width" to rootView.width,
                        "height" to rootView.height
                    )
                )
            }
            false
        }
        rootView.setOnTouchListener(tapForwarder)
        textureView.setOnTouchListener(tapForwarder)
        textureView.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            val nextWidth = right - left
            val nextHeight = bottom - top
            if (nextWidth != oldRight - oldLeft || nextHeight != oldBottom - oldTop) {
                applyVideoSizeMode()
            }
        }
        rootView.addView(
            textureView,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        player.setVideoTextureView(textureView)

        val url = args?.get("url") as? String
        if (!url.isNullOrBlank()) {
            val mediaItem = buildMediaItem(url, args)
            val initialPositionMs =
                (args?.get("initialPositionMs") as? Number)?.toLong() ?: 0L
            if (initialPositionMs > 0L) {
                player.setMediaItem(mediaItem, initialPositionMs)
            } else {
                player.setMediaItem(mediaItem)
            }
            player.prepare()
        } else {
            errorDescription = "missing_source"
        }
    }

    override fun getView(): View = rootView

    override fun dispose() {
        if (released) return
        released = true
        player.removeAnalyticsListener(this)
        player.removeListener(this)
        player.clearVideoTextureView(textureView)
        player.release()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        initialized = initialized ||
            playbackState == Player.STATE_READY ||
            playbackState == Player.STATE_BUFFERING
    }

    override fun onPlayerError(error: PlaybackException) {
        errorDescription = error.errorCodeName.ifBlank { error.message ?: "playback_error" }
        errorBucket = media3ErrorBucket(error)
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        width = videoSize.width
        height = videoSize.height
        pixelWidthHeightRatio = if (videoSize.pixelWidthHeightRatio > 0f) {
            videoSize.pixelWidthHeightRatio
        } else {
            1f
        }
        applyVideoSizeMode()
    }

    override fun onRenderedFirstFrame(eventTime: AnalyticsListener.EventTime, output: Any, renderTimeMs: Long) {
        firstFrameRendered = true
    }

    override fun onDroppedVideoFrames(eventTime: AnalyticsListener.EventTime, droppedFrames: Int, elapsedMs: Long) {
        droppedVideoFrames += droppedFrames
    }

    override fun onBandwidthEstimate(
        eventTime: AnalyticsListener.EventTime,
        totalLoadTimeMs: Int,
        totalBytesLoaded: Long,
        bitrateEstimate: Long
    ) {
        bandwidthKbps = if (bitrateEstimate > 0) bitrateEstimate / 1000 else 0
    }

    override fun onTracksChanged(eventTime: AnalyticsListener.EventTime, tracks: androidx.media3.common.Tracks) {
        val selected = tracks.groups
            .filter { group -> (0 until group.length).any { index -> group.isTrackSelected(index) } }
            .map { group -> group.mediaTrackGroup.type.toString() }
            .distinct()
        lastTrackSummary = if (selected.isEmpty()) "none" else selected.joinToString(",")
        lastAudioTrackSummary = audioTrackSummaryFor(tracks)
    }

    override fun onLoadCompleted(
        eventTime: AnalyticsListener.EventTime,
        loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData
    ) {
        incrementLoadCount(loadCompletedCounts, mediaLoadKind(mediaLoadData))
    }

    override fun onLoadError(
        eventTime: AnalyticsListener.EventTime,
        loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData,
        error: IOException,
        wasCanceled: Boolean
    ) {
        incrementLoadCount(loadErrorCounts, mediaLoadKind(mediaLoadData))
        lastLoadErrorBucket = mediaLoadErrorBucket(error, wasCanceled)
    }

    fun state(): Map<String, Any> {
        if (released) {
            return mapOf(
                "viewId" to viewId,
                "initialized" to false,
                "hasError" to true,
                "errorDescription" to "media3_view_released",
                "errorBucket" to "released",
                "playing" to false,
                "buffering" to false,
                "ended" to false,
                "durationMs" to 0L,
                "positionMs" to 0L,
                "bufferedPositionMs" to 0L,
                "totalBufferedDurationMs" to 0L,
                "playbackSpeed" to 1.0f,
                "width" to 0,
                "height" to 0,
                "playbackState" to Player.STATE_IDLE,
                "firstFrameRendered" to false,
                "droppedVideoFrames" to droppedVideoFrames,
                "bandwidthKbps" to bandwidthKbps,
                "trackSummary" to lastTrackSummary,
                "audioTrackSummary" to lastAudioTrackSummary,
                "loadCompletedSummary" to loadCompletedSummary(),
                "loadErrorSummary" to loadErrorSummary(),
                "lastLoadErrorBucket" to lastLoadErrorBucket,
                "sourceClass" to sourceClass,
                "sourceType" to sourceType.ifBlank { "unknown" },
                "mimeType" to (sourceMimeType ?: "unknown"),
                "headerCountBucket" to headerCountBucket,
                "liveMode" to liveMode
            )
        }
        val durationMs = if (player.duration > 0) player.duration else 0L
        val positionMs = max(0L, player.currentPosition)
        val bufferedPositionMs = max(positionMs, player.bufferedPosition)
        val totalBufferedDurationMs = max(0L, player.totalBufferedDuration)
        return mapOf(
            "viewId" to viewId,
            "initialized" to initialized,
            "hasError" to errorDescription.isNotBlank(),
            "errorDescription" to errorDescription,
            "errorBucket" to errorBucket,
            "playing" to player.isPlaying,
            "buffering" to (player.playbackState == Player.STATE_BUFFERING),
            "ended" to (player.playbackState == Player.STATE_ENDED),
            "durationMs" to durationMs,
            "positionMs" to positionMs,
            "bufferedPositionMs" to bufferedPositionMs,
            "totalBufferedDurationMs" to totalBufferedDurationMs,
            "playbackSpeed" to player.playbackParameters.speed,
            "width" to width,
            "height" to height,
            "playbackState" to player.playbackState,
            "firstFrameRendered" to firstFrameRendered,
            "droppedVideoFrames" to droppedVideoFrames,
            "bandwidthKbps" to bandwidthKbps,
            "trackSummary" to lastTrackSummary,
            "audioTrackSummary" to lastAudioTrackSummary,
            "loadCompletedSummary" to loadCompletedSummary(),
            "loadErrorSummary" to loadErrorSummary(),
            "lastLoadErrorBucket" to lastLoadErrorBucket,
            "sourceClass" to sourceClass,
            "sourceType" to sourceType.ifBlank { "unknown" },
            "mimeType" to (sourceMimeType ?: "unknown"),
            "headerCountBucket" to headerCountBucket,
            "liveMode" to liveMode
        )
    }

    fun play() {
        player.playWhenReady = true
        player.play()
    }

    fun pause() {
        player.pause()
    }

    fun seekTo(positionMs: Long) {
        player.seekTo(max(0L, positionMs))
    }

    fun setLooping(looping: Boolean) {
        player.repeatMode = if (looping) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
    }

    fun setPlaybackSpeed(speed: Float) {
        player.setPlaybackSpeed(speed.coerceIn(0.25f, 3.0f))
    }

    fun setVideoSizeMode(mode: String) {
        videoSizeMode = mode.ifBlank { "fit" }.lowercase()
        applyVideoSizeMode()
    }

    private fun applyVideoSizeMode() {
        textureView.post {
            val viewWidth = textureView.width.toFloat()
            val viewHeight = textureView.height.toFloat()
            val videoWidth = width.toFloat() * pixelWidthHeightRatio
            val videoHeight = height.toFloat()
            if (
                viewWidth <= 0f ||
                viewHeight <= 0f ||
                videoWidth <= 0f ||
                videoHeight <= 0f
            ) {
                textureView.setTransform(Matrix())
                return@post
            }
            val viewAspect = viewWidth / viewHeight
            val sourceAspect = when (videoSizeMode) {
                "16:9", "wide" -> 16f / 9f
                else -> videoWidth / videoHeight
            }
            val matrix = Matrix()
            val centerX = viewWidth / 2f
            val centerY = viewHeight / 2f
            when (videoSizeMode) {
                "fill" -> {
                    if (sourceAspect > viewAspect) {
                        matrix.setScale(sourceAspect / viewAspect, 1f, centerX, centerY)
                    } else {
                        matrix.setScale(1f, viewAspect / sourceAspect, centerX, centerY)
                    }
                }
                "stretch" -> {
                    matrix.reset()
                }
                else -> {
                    if (sourceAspect > viewAspect) {
                        matrix.setScale(1f, viewAspect / sourceAspect, centerX, centerY)
                    } else {
                        matrix.setScale(sourceAspect / viewAspect, 1f, centerX, centerY)
                    }
                }
            }
            textureView.setTransform(matrix)
        }
    }

    fun setVolume(volume: Float) {
        player.volume = volume.coerceIn(0f, 1f)
    }

    private fun parseHeaders(raw: Any?): Map<String, String> {
        val source = raw as? Map<*, *> ?: return emptyMap()
        return source.entries.mapNotNull { entry ->
            val key = entry.key as? String ?: return@mapNotNull null
            val value = entry.value as? String ?: return@mapNotNull null
            key to value
        }.toMap()
    }

    private fun headerValue(headers: Map<String, String>, name: String): String? {
        return headers.entries.firstOrNull {
            it.key.equals(name, ignoreCase = true) && it.value.isNotBlank()
        }?.value
    }

    private fun buildMediaItem(url: String, args: Map<*, *>?): MediaItem {
        val builder = MediaItem.Builder().setUri(Uri.parse(url))
        media3MimeTypeFor(sourceType, url)?.let { builder.setMimeType(it) }
        val subtitles = parseSubtitles(args?.get("subtitles"))
        if (subtitles.isNotEmpty()) {
            builder.setSubtitleConfigurations(subtitles)
        }
        if (liveMode) {
            builder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(5000)
                    .setMinOffsetMs(2000)
                    .setMaxOffsetMs(12000)
                    .setMinPlaybackSpeed(0.97f)
                    .setMaxPlaybackSpeed(1.03f)
                    .build()
            )
        }
        return builder.build()
    }

    private fun normalizedSourceType(raw: Any?): String {
        return (raw as? String)?.trim()?.lowercase().orEmpty()
    }

    private fun media3MimeTypeFor(type: String, url: String): String? {
        val normalizedType = type.trim().lowercase()
        val lowerUrl = url.lowercase()
        return when {
            normalizedType == "hls" || lowerUrl.contains(".m3u8") -> MimeTypes.APPLICATION_M3U8
            normalizedType == "dash" || lowerUrl.contains(".mpd") -> MimeTypes.APPLICATION_MPD
            else -> null
        }
    }

    private fun headerCountBucket(count: Int): String {
        return when {
            count <= 0 -> "none"
            count == 1 -> "one"
            count <= 3 -> "few"
            else -> "many"
        }
    }

    private fun media3ErrorBucket(error: PlaybackException): String {
        val code = error.errorCodeName.lowercase()
        val causeName = error.cause?.javaClass?.simpleName?.lowercase().orEmpty()
        val message = listOfNotNull(error.message, error.cause?.message)
            .joinToString(" ")
            .lowercase()
        return when {
            code.contains("source") || causeName.contains("http") || message.contains("http") -> "source"
            code.contains("timeout") || message.contains("timeout") -> "timeout"
            code.contains("behind_live_window") -> "live_window"
            code.contains("parsing") || causeName.contains("parser") || message.contains("parser") -> "container"
            code.contains("decoding") ||
                causeName.contains("renderer") ||
                causeName.contains("mediacodec") ||
                message.contains("codec") -> "renderer"
            else -> "playback"
        }
    }

    private fun mediaLoadKind(mediaLoadData: MediaLoadData): String {
        return when {
            mediaLoadData.dataType == C.DATA_TYPE_MANIFEST -> "manifest"
            mediaLoadData.trackType == C.TRACK_TYPE_VIDEO -> "video"
            mediaLoadData.trackType == C.TRACK_TYPE_AUDIO -> "audio"
            mediaLoadData.trackType == C.TRACK_TYPE_TEXT -> "text"
            mediaLoadData.dataType == C.DATA_TYPE_DRM ||
                mediaLoadData.dataType == C.DATA_TYPE_MEDIA_INITIALIZATION -> "key_or_init"
            else -> "other"
        }
    }

    private fun mediaLoadErrorBucket(error: IOException, wasCanceled: Boolean): String {
        if (wasCanceled) return "canceled"
        var cause: Throwable? = error
        repeat(6) {
            when (cause) {
                is HttpDataSource.InvalidResponseCodeException -> {
                    val responseCode =
                        (cause as HttpDataSource.InvalidResponseCodeException).responseCode
                    return when (responseCode) {
                        in 400..499 -> "http_4xx"
                        in 500..599 -> "http_5xx"
                        else -> "http_other"
                    }
                }
                is SocketTimeoutException -> return "timeout"
                is UnknownHostException -> return "dns"
                is ConnectException -> return "connect"
                is SSLException -> return "tls"
            }
            cause = cause?.cause
        }
        return "io"
    }

    private fun incrementLoadCount(counts: MutableMap<String, Int>, kind: String) {
        counts[kind] = (counts[kind] ?: 0) + 1
    }

    private fun loadCompletedSummary(): String = loadSummary(loadCompletedCounts)

    private fun loadErrorSummary(): String = loadSummary(loadErrorCounts)

    private fun loadSummary(counts: Map<String, Int>): String {
        val order = listOf("manifest", "video", "audio", "text", "key_or_init", "other")
        val populated = order.mapNotNull { kind ->
            val count = counts[kind] ?: 0
            if (count > 0) "$kind:$count" else null
        }
        return if (populated.isEmpty()) "none" else populated.joinToString(",")
    }

    private fun audioTrackSummaryFor(tracks: androidx.media3.common.Tracks): String {
        var availableCount = 0
        var selectedCount = 0
        var unsupportedCount = 0
        val codecs = mutableSetOf<String>()
        val channelBuckets = mutableSetOf<String>()
        val sampleRateBuckets = mutableSetOf<String>()
        var languagePresent = false

        for (group in tracks.groups) {
            if (group.mediaTrackGroup.type != C.TRACK_TYPE_AUDIO) continue
            for (index in 0 until group.length) {
                availableCount += 1
                if (!group.isTrackSupported(index, false)) unsupportedCount += 1
                if (!group.isTrackSelected(index)) continue
                selectedCount += 1
                val format = group.getTrackFormat(index)
                codecs.add(audioCodecBucket(format.sampleMimeType))
                channelBuckets.add(audioChannelBucket(format.channelCount))
                sampleRateBuckets.add(audioSampleRateBucket(format.sampleRate))
                languagePresent = languagePresent || !format.language.isNullOrBlank()
            }
        }

        if (availableCount == 0) return "available:none,selected:none"
        return listOf(
            "available:${countBucket(availableCount)}",
            "selected:${countBucket(selectedCount)}",
            "unsupported:${countBucket(unsupportedCount)}",
            "codec:${joinedBucket(codecs)}",
            "channels:${joinedBucket(channelBuckets)}",
            "sample:${joinedBucket(sampleRateBuckets)}",
            "language:${if (languagePresent) "present" else "none"}"
        ).joinToString(",")
    }

    private fun countBucket(count: Int): String {
        return when {
            count <= 0 -> "none"
            count == 1 -> "one"
            count <= 3 -> "few"
            else -> "many"
        }
    }

    private fun joinedBucket(values: Set<String>): String {
        return values.filter { it.isNotBlank() }.sorted().joinToString("+").ifBlank { "unknown" }
    }

    private fun audioCodecBucket(mimeType: String?): String {
        val value = mimeType?.lowercase().orEmpty()
        return when {
            value.contains("aac") -> "aac"
            value.contains("ac3") && !value.contains("eac3") -> "ac3"
            value.contains("eac3") || value.contains("ec-3") -> "eac3"
            value.contains("opus") -> "opus"
            value.contains("vorbis") -> "vorbis"
            value.contains("mpeg") || value.contains("mp4a") -> "mpeg"
            value.contains("dts") -> "dts"
            value.contains("truehd") -> "truehd"
            value.contains("flac") -> "flac"
            value.isBlank() -> "unknown"
            else -> "other"
        }
    }

    private fun audioChannelBucket(channelCount: Int): String {
        return when {
            channelCount <= 0 -> "unknown"
            channelCount == 1 -> "mono"
            channelCount == 2 -> "stereo"
            channelCount <= 6 -> "surround"
            else -> "surround_plus"
        }
    }

    private fun audioSampleRateBucket(sampleRate: Int): String {
        return when {
            sampleRate <= 0 -> "unknown"
            sampleRate < 32000 -> "low"
            sampleRate <= 48000 -> "standard"
            else -> "high"
        }
    }

    private fun parseSubtitles(raw: Any?): List<MediaItem.SubtitleConfiguration> {
        val items = raw as? List<*> ?: return emptyList()
        return items.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val url = map["url"] as? String ?: return@mapNotNull null
            if (url.isBlank()) return@mapNotNull null
            val builder = MediaItem.SubtitleConfiguration.Builder(Uri.parse(url))
                .setMimeType(subtitleMimeType(map["format"] as? String))
                .setLabel((map["label"] as? String).orEmpty().ifBlank { "Subtitle" })
                .setRoleFlags(C.ROLE_FLAG_SUBTITLE)
            normalizedLanguage(map["language"])?.let { builder.setLanguage(it) }
            var selectionFlags = 0
            if (map["isDefault"] == true) selectionFlags = selectionFlags or C.SELECTION_FLAG_DEFAULT
            if (map["isForced"] == true) selectionFlags = selectionFlags or C.SELECTION_FLAG_FORCED
            if (selectionFlags != 0) builder.setSelectionFlags(selectionFlags)
            builder.build()
        }
    }

    private fun normalizedLanguage(raw: Any?): String? {
        val value = (raw as? String)?.trim()?.lowercase().orEmpty()
        if (value.isBlank() || value == "auto" || value == "default" || value == "system") {
            return null
        }
        return value
    }

    private fun subtitleMimeType(format: String?): String {
        return when (format?.trim()?.lowercase()) {
            "srt", "subrip" -> MimeTypes.APPLICATION_SUBRIP
            "ssa", "ass" -> MimeTypes.TEXT_SSA
            "ttml", "dfxp" -> MimeTypes.APPLICATION_TTML
            else -> MimeTypes.TEXT_VTT
        }
    }
}

class JuicrMedia3LoadErrorPolicy(
    private val liveMode: Boolean
) : DefaultLoadErrorHandlingPolicy() {
    override fun getRetryDelayMsFor(loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        val count = loadErrorInfo.errorCount
        if (count > if (liveMode) 4 else 3) return C.TIME_UNSET
        return (if (liveMode) 350L else 500L) * count
    }

    override fun getMinimumLoadableRetryCount(dataType: Int): Int {
        return if (liveMode) 4 else 3
    }
}
