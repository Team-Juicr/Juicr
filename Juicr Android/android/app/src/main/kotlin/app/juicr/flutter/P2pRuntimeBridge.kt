package app.juicr.flutter

import android.content.Context
import android.util.Log
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream
import java.lang.reflect.Array as ReflectArray
import java.lang.reflect.Method
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLEncoder
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min

class P2pRuntimeBridge(private val context: Context) {
    private val executor = Executors.newCachedThreadPool()
    private val sessions = ConcurrentHashMap<String, P2pSession>()
    private val sessionTokensByKey = ConcurrentHashMap<String, String>()
    private var serverSocket: ServerSocket? = null
    private var sessionManager: Any? = null
    private var lastAvailabilityError: String? = null
    private var port: Int = 0
    private val startupReadableBytes = 2L * 1024L * 1024L
    private val playbackWindowBytes = 12L * 1024L * 1024L
    private val forwardPrefetchBytes = 96L * 1024L * 1024L
    private val tailProbeWindowBytes = 2L * 1024L * 1024L
    private val p2pCacheMaxBytes = 512L * 1024L * 1024L
    private val p2pSessionCacheMaxBytes = 192L * 1024L * 1024L
    private val p2pCacheDir: File
        get() = File(context.cacheDir, "juicr-p2p")

    fun isAvailable(): Boolean {
        if (!BuildConfig.JUICR_ENABLE_P2P_RUNTIME) {
            lastAvailabilityError = "p2p_runtime_disabled"
            return false
        }
        return try {
            requireP2pStage("native_shim_loader") {
                System.loadLibrary("juicr_jlibtorrent_shim")
            }
            requireP2pStage("swig_jni_loader") {
                Class.forName("com.frostwire.jlibtorrent.swig.libtorrent_jni")
            }
            requireP2pStage("native_version_probe") {
                Class.forName("com.frostwire.jlibtorrent.LibTorrent")
                    .getMethod("version")
                    .invoke(null)
            }
            requireP2pStage("session_manager") {
                Class.forName("com.frostwire.jlibtorrent.SessionManager")
            }
            requireP2pStage("settings_pack") {
                Class.forName("com.frostwire.jlibtorrent.SettingsPack")
            }
            requireP2pStage("sha1_hash") {
                Class.forName("com.frostwire.jlibtorrent.Sha1Hash")
            }
            requireP2pStage("announce_entry") {
                Class.forName("com.frostwire.jlibtorrent.AnnounceEntry")
            }
            requireP2pStage("priority") {
                Class.forName("com.frostwire.jlibtorrent.Priority")
            }
            requireP2pStage("torrent_flags") {
                Class.forName("com.frostwire.jlibtorrent.TorrentFlags")
            }
            requireP2pStage("torrent_handle") {
                Class.forName("com.frostwire.jlibtorrent.TorrentHandle")
            }
            lastAvailabilityError = null
            true
        } catch (error: Throwable) {
            lastAvailabilityError = p2pAvailabilityError(error)
            false
        }
    }

    @Synchronized
    fun open(
        infoHash: String,
        fileIdx: Int?,
        trackers: List<String>,
        displayName: String?,
        quality: String?
    ): String {
        if (!isAvailable()) {
            throw IllegalStateException(
                "Advanced playback is not available in this build."
            )
        }
        val safeInfoHash = normalizeInfoHash(infoHash)
        ensureServer()
        ensureSessionManager()
        val sessionKey = p2pSessionKey(safeInfoHash, fileIdx)
        val existingToken = sessionTokensByKey[sessionKey]
        if (existingToken != null && sessions.containsKey(existingToken)) {
            return "http://127.0.0.1:$port/stream/$existingToken"
        }
        val token = UUID.randomUUID().toString()
        pruneP2pCache(keepInfoHash = safeInfoHash)
        val saveDir = File(p2pCacheDir, safeInfoHash).apply { mkdirs() }
        val session = P2pSession(
            token = token,
            infoHash = safeInfoHash,
            requestedFileIdx = fileIdx,
            requestedTrackerCount = trackers.size,
            trackers = sanitizeTrackers(trackers),
            displayName = displayName?.take(96),
            quality = quality?.take(48),
            saveDir = saveDir
        )
        sessions[token] = session
        sessionTokensByKey[sessionKey] = token
        startDownload(session)
        pruneP2pCache(keepInfoHash = safeInfoHash)
        return "http://127.0.0.1:$port/stream/$token"
    }

    @Synchronized
    fun stopAll() {
        sessions.clear()
        sessionTokensByKey.clear()
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        serverSocket = null
        port = 0
        tryInvoke(sessionManager, "stop")
        sessionManager = null
        clearP2pCache()
    }

    private fun clearP2pCache() {
        try {
            p2pCacheDir.deleteRecursively()
        } catch (_: Throwable) {
        }
    }

    private fun pruneP2pCache(keepInfoHash: String? = null) {
        try {
            val root = p2pCacheDir
            if (!root.exists()) return
            val activeInfoHashes = sessions.values.map { it.infoHash }.toSet()
            val protectedInfoHashes = activeInfoHashes + listOfNotNull(keepInfoHash)
            val staleDirs = root.listFiles()
                ?.filter { it.isDirectory }
                ?.filter { it.name !in protectedInfoHashes }
                ?.sortedBy { it.lastModified() }
                ?: emptyList()
            for (dir in staleDirs) {
                if (directorySize(root) <= p2pCacheMaxBytes) break
                dir.deleteRecursively()
            }
            if (keepInfoHash != null) {
                val activeDir = File(root, keepInfoHash)
                if (
                    sessions.values.none { it.infoHash == keepInfoHash } &&
                    directorySize(activeDir) > p2pSessionCacheMaxBytes
                ) {
                    activeDir.deleteRecursively()
                    activeDir.mkdirs()
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun directorySize(file: File): Long {
        if (!file.exists()) return 0L
        if (file.isFile) return file.length().coerceAtLeast(0L)
        return file.listFiles()?.sumOf { directorySize(it) } ?: 0L
    }

    private fun requireP2pStage(stage: String, block: () -> Unit) {
        try {
            block()
        } catch (error: Throwable) {
            throw P2pStageError(stage, error)
        }
    }

    private class P2pStageError(
        val stage: String,
        cause: Throwable
    ) : RuntimeException(stage, cause)

    private fun p2pAvailabilityError(error: Throwable): String {
        val stage = (error as? P2pStageError)?.stage
        val actual = if (error is P2pStageError && error.cause != null) {
            error.cause!!
        } else {
            error
        }
        val type = actual.javaClass.simpleName.ifBlank { "Throwable" }
        val chain = generateSequence(actual) { it.cause }
            .take(4)
            .joinToString(" ") { cause ->
                "${cause.javaClass.simpleName} ${cause.message ?: ""}"
            }
            .lowercase()
        val bucket = when {
            chain.contains("class") ||
                chain.contains("noclass") ||
                type.contains("NoClass", ignoreCase = true) -> "missing_class"
            chain.contains("native") ||
                chain.contains(".so") ||
                type.contains("UnsatisfiedLink", ignoreCase = true) -> "native_library"
            chain.contains("permission") -> "permission"
            else -> "unavailable"
        }
        val detail = when {
            chain.contains("libc++") -> "cxx_dependency"
            chain.contains("page size") ||
                chain.contains("16kb") ||
                chain.contains("16 kb") ||
                chain.contains("align") -> "page_alignment"
            chain.contains("not found") ||
                chain.contains("couldn't find") ||
                chain.contains("could not find") -> "dependency_not_found"
            chain.contains("cannot locate symbol") -> "missing_symbol"
            chain.contains("dlopen failed") -> "dlopen_failed"
            chain.contains("swig_module_init") -> "swig_module_init"
            chain.contains("jni_err") ||
                chain.contains("jni error") -> "jni_init"
            chain.contains("no implementation found") -> "jni_symbol"
            chain.contains("jlibtorrent") -> "jlibtorrent_dependency"
            else -> "generic"
        }
        val stagePrefix = if (stage.isNullOrBlank()) "stage_unknown" else "stage_$stage"
        return "$stagePrefix:$type:$bucket:$detail"
    }

    private fun ensureServer() {
        if (serverSocket != null && port > 0) return
        val socket = ServerSocket(0, 24, InetAddress.getByName("127.0.0.1"))
        serverSocket = socket
        port = socket.localPort
        executor.execute {
            while (!socket.isClosed) {
                try {
                    val client = socket.accept()
                    executor.execute { handleClientSafely(client) }
                } catch (_: Throwable) {
                    if (!socket.isClosed) continue
                }
            }
        }
    }

    private fun p2pSessionKey(infoHash: String, fileIdx: Int?): String {
        return "$infoHash|${fileIdx ?: "auto"}"
    }

    private fun normalizeInfoHash(raw: String): String {
        var cleaned = raw.trim()
        val btihIndex = cleaned.lowercase().indexOf("btih:")
        if (btihIndex >= 0) {
            cleaned = cleaned.substring(btihIndex + "btih:".length)
        }
        cleaned = cleaned
            .split(Regex("[&?#\\s]"))
            .firstOrNull()
            .orEmpty()
            .trim()
            .lowercase()
            .replace(Regex("[^a-z0-9]"), "")
        if (cleaned.matches(Regex("[a-f0-9]{40}"))) return cleaned
        if (cleaned.matches(Regex("[a-z2-7]{32}"))) {
            return base32InfoHashToHex(cleaned)
                ?: throw IllegalArgumentException("P2P info hash format is not supported.")
        }
        throw IllegalArgumentException("P2P info hash format is not supported.")
    }

    private fun base32InfoHashToHex(value: String): String? {
        val alphabet = "abcdefghijklmnopqrstuvwxyz234567"
        val bytes = mutableListOf<Int>()
        var buffer = 0
        var bits = 0
        for (char in value.lowercase()) {
            val index = alphabet.indexOf(char)
            if (index < 0) return null
            buffer = (buffer shl 5) or index
            bits += 5
            while (bits >= 8) {
                bits -= 8
                bytes.add((buffer shr bits) and 0xff)
                buffer = if (bits == 0) 0 else buffer and ((1 shl bits) - 1)
            }
        }
        if (bytes.size != 20) return null
        return bytes.joinToString("") { byte -> byte.toString(16).padStart(2, '0') }
    }

    private fun ensureSessionManager() {
        if (sessionManager != null) return
        val clazz = Class.forName("com.frostwire.jlibtorrent.SessionManager")
        sessionManager = clazz.getDeclaredConstructor().newInstance()
        configureSessionManager()
        tryInvoke(sessionManager, "listenInterfaces", "0.0.0.0:6881,[::]:6881")
        tryInvoke(sessionManager, "start")
        val endpoints = tryInvoke(sessionManager, "listenEndpoints") as? List<*>
        if (endpoints.isNullOrEmpty()) {
            tryInvoke(sessionManager, "listenInterfaces", "0.0.0.0:0,[::]:0")
            tryInvoke(sessionManager, "reopenNetworkSockets")
        }
        tryInvoke(sessionManager, "resume")
        tryInvoke(sessionManager, "startDht")
    }

    private fun configureSessionManager() {
        val manager = sessionManager ?: return
        try {
            val settings = Class.forName("com.frostwire.jlibtorrent.SettingsPack")
                .getDeclaredConstructor()
                .newInstance()
            tryInvoke(settings, "enableDht", true)
            tryInvoke(settings, "listenInterfaces", "0.0.0.0:6881,[::]:6881")
            tryInvoke(settings, "connectionsLimit", 128)
            tryInvoke(settings, "activeDownloads", 4)
            tryInvoke(settings, "activeDhtLimit", 4)
            tryInvoke(settings, "activeTrackerLimit", 8)
            tryInvoke(settings, "alertQueueSize", 2048)
            tryInvoke(manager, "applySettings", settings)
        } catch (_: Throwable) {
        }
    }

    private fun sanitizeTrackers(trackers: List<String>): List<String> {
        return trackers.mapNotNull { raw ->
            val tracker = normalizeTracker(raw)
            tracker
        }.distinct().take(32)
    }

    private fun normalizeTracker(raw: String): String? {
        var tracker = raw.trim()
        if (tracker.isBlank()) return null
        listOf("tracker:", "announce:").forEach { prefix ->
            val lower = tracker.lowercase()
            if (lower.startsWith(prefix)) {
                tracker = tracker.substring(prefix.length).trim()
            }
        }
        val lower = tracker.lowercase()
        return if (
            lower.startsWith("udp://") ||
            lower.startsWith("http://") ||
            lower.startsWith("https://")
        ) {
            tracker
        } else {
            null
        }
    }

    private fun startDownload(session: P2pSession) {
        executor.execute {
            try {
                val magnet = buildMagnet(session)
                session.downloadStarted = true
                session.metadataFetchState = "magnet"
                tryInvoke(sessionManager, "download", magnet, session.saveDir)
                    ?: tryInvoke(sessionManager, "download", magnet, session.saveDir.absolutePath)
                pollMetadata(session)
            } catch (error: Throwable) {
                session.error = "${error.javaClass.simpleName}:${error.message ?: "none"}".take(80)
            }
        }
    }

    private fun buildMagnet(session: P2pSession): String {
        val encodedTrackers = session.trackers.take(12).joinToString("") { tracker ->
            "&tr=${URLEncoder.encode(tracker, StandardCharsets.UTF_8.name())}"
        }
        return "magnet:?xt=urn:btih:${session.infoHash}$encodedTrackers"
    }

    private fun pollMetadata(session: P2pSession) {
        val manager = sessionManager ?: return
        val sha1Class = Class.forName("com.frostwire.jlibtorrent.Sha1Hash")
        val sha1 = sha1Class.getDeclaredConstructor(String::class.java).newInstance(session.infoHash)
        repeat(90) {
            if (!sessions.containsKey(session.token)) return
            session.pollCount = it + 1
            val handle = tryInvoke(manager, "find", sha1)
            if (handle != null) {
                session.handleSeen = true
                activateHandle(session, handle)
                updateHandleSnapshot(session, handle)
                val selected = resolveSelectedFile(handle, session)
                if (selected != null) {
                    session.handle = handle
                    session.file = selected.file
                    session.fileStorage = selected.fileStorage
                    session.selectedFileIndex = selected.index
                    session.selectedFileSize = selected.size
                    configureStreamingPriority(handle, selected.fileStorage, selected.index, session)
                    return
                }
            }
            TimeUnit.SECONDS.sleep(1)
        }
    }

    private fun activateHandle(session: P2pSession, handle: Any) {
        if (session.handleActivated) return
        session.handleActivated = true
        injectTrackers(session, handle)
        tryInvoke(handle, "resume")
        tryInvoke(handle, "forceDHTAnnounce")
        tryInvoke(handle, "forceReannounce")
        try {
            val manager = sessionManager ?: return
            val sha1Class = Class.forName("com.frostwire.jlibtorrent.Sha1Hash")
            val sha1 = sha1Class.getDeclaredConstructor(String::class.java).newInstance(session.infoHash)
            tryInvoke(manager, "dhtAnnounce", sha1)
        } catch (_: Throwable) {
        }
    }

    private fun injectTrackers(session: P2pSession, handle: Any) {
        if (session.trackers.isEmpty()) return
        // Trackers are already embedded in the magnet URI. Constructing
        // AnnounceEntry through the Android JNI wrapper can abort the process
        // before Kotlin can catch the failure, so avoid the unsafe duplicate
        // addTracker path and let libtorrent consume the magnet trackers.
        session.trackersInjected = true
    }

    private fun updateHandleSnapshot(session: P2pSession, handle: Any) {
        try {
            val status = tryInvoke(handle, "status") ?: return
            session.metadataKnown =
                (tryInvoke(status, "hasMetadata") as? Boolean) == true
            session.peerCount = (tryInvoke(status, "numPeers") as? Number)?.toInt() ?: 0
            session.seedCount = (tryInvoke(status, "numSeeds") as? Number)?.toInt() ?: 0
            session.progressPpm = (tryInvoke(status, "progressPpm") as? Number)?.toInt() ?: 0
            session.torrentState = tryInvoke(status, "state")?.toString()?.take(32) ?: "unknown"
            session.connectCandidates =
                (tryInvoke(status, "connectCandidates") as? Number)?.toInt() ?: 0
            session.listPeers = (tryInvoke(status, "listPeers") as? Number)?.toInt() ?: 0
            session.announcingTrackers =
                (tryInvoke(status, "announcingToTrackers") as? Boolean) == true
            session.announcingDht =
                (tryInvoke(status, "announcingToDht") as? Boolean) == true
            session.announcingLsd =
                (tryInvoke(status, "announcingToLsd") as? Boolean) == true
            session.currentTrackerKnown =
                !tryInvoke(status, "currentTracker")?.toString().isNullOrBlank()
            val trackers = tryInvoke(handle, "trackers") as? List<*>
            session.handleTrackerCount = trackers?.size ?: 0
            val manager = sessionManager
            session.dhtRunning = (tryInvoke(manager, "isDhtRunning") as? Boolean) == true
            session.dhtNodes = (tryInvoke(manager, "dhtNodes") as? Number)?.toLong() ?: 0L
            session.listenEndpointCount = (tryInvoke(manager, "listenEndpoints") as? List<*>)?.size ?: 0
            session.firewalled = (tryInvoke(manager, "isFirewalled") as? Boolean) == true
        } catch (_: Throwable) {
        }
    }

    private fun resolveSelectedFile(handle: Any, session: P2pSession): SelectedP2pFile? {
        val info = tryInvoke(handle, "torrentFile") ?: return null
        val files = tryInvoke(info, "files") ?: return null
        val numFiles = (tryInvoke(files, "numFiles") as? Number)?.toInt() ?: return null
        if (numFiles <= 0) return null
        val selectedIndex = session.requestedFileIdx?.takeIf { it in 0 until numFiles }
            ?: largestMediaFileIndex(files, numFiles)
        val savePath = resolveHandleSavePath(handle, session.saveDir)
        val resolved = resolveDownloadFile(files, selectedIndex, savePath)
            ?: return null
        session.actualSavePathUsed = savePath.absolutePath != session.saveDir.absolutePath
        session.selectedPathKind = resolved.pathKind
        session.selectedFileParentExists = resolved.parentExists
        return SelectedP2pFile(
            file = resolved.file,
            fileStorage = files,
            index = selectedIndex,
            size = (tryInvoke(files, "fileSize", selectedIndex) as? Number)?.toLong() ?: 0L
        )
    }

    private fun resolveHandleSavePath(handle: Any, fallback: File): File {
        val savePath = tryInvoke(handle, "savePath")
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?.let { File(it) }
        return savePath ?: fallback
    }

    private fun resolveDownloadFile(
        files: Any,
        selectedIndex: Int,
        savePath: File
    ): ResolvedP2pFile? {
        val savePathAware = tryInvoke(files, "filePath", selectedIndex, savePath.absolutePath)
            ?.toString()
            ?.takeIf { it.isNotBlank() }
        val path = savePathAware
            ?: tryInvoke(files, "filePath", selectedIndex)?.toString()
            ?: tryInvoke(files, "filePath", selectedIndex.toLong())?.toString()
            ?: return null
        val pathFile = File(path)
        val file = if (pathFile.isAbsolute) pathFile else File(savePath, path)
        val pathKind = when {
            savePathAware != null && pathFile.isAbsolute -> "save_path_absolute"
            savePathAware != null -> "save_path_relative"
            pathFile.isAbsolute -> "absolute"
            else -> "relative"
        }
        file.parentFile?.mkdirs()
        return ResolvedP2pFile(
            file = file,
            pathKind = pathKind,
            parentExists = file.parentFile?.exists() == true
        )
    }

    private fun configureStreamingPriority(
        handle: Any,
        files: Any,
        selectedIndex: Int,
        session: P2pSession
    ) {
        if (session.streamingConfigured) return
        session.streamingConfigured = true
        val numFiles = (tryInvoke(files, "numFiles") as? Number)?.toInt() ?: 0
        if (numFiles <= 0) return
        try {
            val priorityClass = Class.forName("com.frostwire.jlibtorrent.Priority")
            val skip = enumConstant(priorityClass, "IGNORE")
                ?: enumConstant(priorityClass, "ZERO")
            val background = enumConstant(priorityClass, "LOW")
                ?: enumConstant(priorityClass, "NORMAL")
            val high = enumConstant(priorityClass, "SEVEN")
                ?: enumConstant(priorityClass, "HIGH")
            if (background != null && high != null) {
                val priorities = ReflectArray.newInstance(priorityClass, numFiles)
                for (index in 0 until numFiles) {
                    ReflectArray.set(
                        priorities,
                        index,
                        if (index == selectedIndex) high else skip ?: background
                    )
                }
                tryInvoke(handle, "prioritizeFiles", priorities)
                tryInvoke(handle, "filePriority", selectedIndex, high)
            }
        } catch (_: Throwable) {
        }
        try {
            val flags = Class.forName("com.frostwire.jlibtorrent.TorrentFlags")
                .getField("SEQUENTIAL_DOWNLOAD")
                .get(null)
            tryInvoke(handle, "setFlags", flags)
        } catch (_: Throwable) {
        }
        requestInitialPieces(handle, files, selectedIndex, session)
        tryInvoke(handle, "resume")
        tryInvoke(handle, "forceReannounce")
    }

    private fun requestInitialPieces(handle: Any, files: Any, selectedIndex: Int, session: P2pSession) {
        val fileSize = (tryInvoke(files, "fileSize", selectedIndex) as? Number)?.toLong() ?: return
        if (fileSize <= 0L) return
        val warmBytes = min(fileSize, playbackWindowBytes)
        val request = tryInvoke(files, "mapFile", selectedIndex, 0L, warmBytes.toInt()) ?: return
        val firstPiece = (tryInvoke(request, "piece") as? Number)?.toInt() ?: return
        val lastRequest = tryInvoke(files, "mapFile", selectedIndex, warmBytes - 1, 1) ?: request
        val lastPiece = (tryInvoke(lastRequest, "piece") as? Number)?.toInt() ?: firstPiece
        sessionFirstPiece(session, handle, firstPiece, max(1, lastPiece - firstPiece + 1))
        requestEdgePieces(handle, files, selectedIndex, fileSize)
    }

    private fun sessionFirstPiece(session: P2pSession, handle: Any, firstPiece: Int, pieceCount: Int) {
        val warmPieces = pieceCount.coerceIn(1, 64)
        session.firstPiece = firstPiece
        session.warmPieceCount = warmPieces
        val high = priority("SEVEN")
        val alertWhenAvailable = tryStaticField(
            "com.frostwire.jlibtorrent.TorrentHandle",
            "ALERT_WHEN_AVAILABLE"
        )
        for (offset in 0 until pieceCount.coerceIn(1, 64)) {
            if (high != null) {
                tryInvoke(handle, "piecePriority", firstPiece + offset, high)
            }
            if (alertWhenAvailable != null) {
                tryInvoke(handle, "setPieceDeadline", firstPiece + offset, offset * 200, alertWhenAvailable)
            } else {
                tryInvoke(handle, "setPieceDeadline", firstPiece + offset, offset * 200)
            }
        }
    }

    private fun requestEdgePieces(handle: Any, files: Any, selectedIndex: Int, fileSize: Long) {
        val edgeStart = max(0L, fileSize - tailProbeWindowBytes)
        val first = tryInvoke(files, "mapFile", selectedIndex, edgeStart, 1) ?: return
        val last = tryInvoke(files, "mapFile", selectedIndex, fileSize - 1, 1) ?: first
        val firstPiece = (tryInvoke(first, "piece") as? Number)?.toInt() ?: return
        val lastPiece = (tryInvoke(last, "piece") as? Number)?.toInt() ?: firstPiece
        val high = priority("SEVEN") ?: priority("HIGH")
        val alertWhenAvailable = tryStaticField(
            "com.frostwire.jlibtorrent.TorrentHandle",
            "ALERT_WHEN_AVAILABLE"
        )
        for ((offset, piece) in (firstPiece..lastPiece).withIndex()) {
            if (offset >= 16) break
            if (high != null) {
                tryInvoke(handle, "piecePriority", piece, high)
            }
            if (alertWhenAvailable != null) {
                tryInvoke(handle, "setPieceDeadline", piece, 500 + offset * 200, alertWhenAvailable)
            } else {
                tryInvoke(handle, "setPieceDeadline", piece, 500 + offset * 200)
            }
        }
    }

    private fun priority(name: String): Any? {
        return try {
            enumConstant(Class.forName("com.frostwire.jlibtorrent.Priority"), name)
        } catch (_: Throwable) {
            null
        }
    }

    private fun tryStaticField(className: String, fieldName: String): Any? {
        return try {
            Class.forName(className).getField(fieldName).get(null)
        } catch (_: Throwable) {
            null
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun enumConstant(enumClass: Class<*>, name: String): Any? {
        return (enumClass.enumConstants ?: return null).firstOrNull {
            (it as? Enum<*>)?.name == name
        }
    }

    private fun largestMediaFileIndex(files: Any, numFiles: Int): Int {
        var selected = 0
        var selectedSize = -1L
        for (index in 0 until numFiles) {
            val path = tryInvoke(files, "filePath", index)?.toString().orEmpty().lowercase()
            val size = (tryInvoke(files, "fileSize", index) as? Number)?.toLong() ?: 0L
            val looksPlayable = path.endsWith(".mp4") || path.endsWith(".mkv") ||
                path.endsWith(".webm") || path.endsWith(".avi") || path.endsWith(".mov")
            if (looksPlayable && size > selectedSize) {
                selected = index
                selectedSize = size
            }
        }
        return selected
    }

    private fun handleClientSafely(socket: Socket) {
        try {
            handleClient(socket)
        } catch (_: Throwable) {
            // Players may abandon localhost requests during seek, route close, or
            // source retry. Those client resets are transport cleanup, not app
            // crashes.
            try {
                socket.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun handleClient(socket: Socket) {
        socket.use { client ->
            val input = client.getInputStream().bufferedReader()
            val requestLine = input.readLine() ?: return
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
                val splitAt = line.indexOf(':')
                if (splitAt > 0) {
                    headers[line.substring(0, splitAt).trim().lowercase()] =
                        line.substring(splitAt + 1).trim()
                }
            }
            val parts = requestLine.split(" ")
            val method = parts.getOrNull(0).orEmpty()
            if (parts.size < 2 || (method != "GET" && method != "HEAD")) {
                writeStatus(client.getOutputStream(), 405, "Method Not Allowed")
                return
            }
            val token = parts[1].substringAfter("/stream/", "").substringBefore("?")
            val decodedToken = URLDecoder.decode(token, StandardCharsets.UTF_8.name())
            val session = sessions[decodedToken]
            if (session == null) {
                writeStatus(client.getOutputStream(), 404, "Not Found")
                return
            }
            val file = session.file
            refreshSelectedFileReadiness(session)
            if (
                !session.metadataKnown ||
                !session.streamingConfigured ||
                file == null ||
                !file.exists() ||
                file.length() <= 0L
            ) {
                writeRetry(client.getOutputStream(), session, headers["range"])
                return
            }
            writeFile(client.getOutputStream(), file, headers["range"], session, method == "HEAD")
        }
    }

    private fun isLocalStreamReadable(session: P2pSession, file: File?): Boolean {
        refreshSelectedFileReadiness(session)
        if (!session.metadataKnown || !session.streamingConfigured) return false
        if (file == null || !file.exists() || file.length() <= 0L) return false
        val requiredPieces = min(session.warmPieceCount.coerceAtLeast(1), 2)
        return session.firstPiecesReady >= requiredPieces
    }

    private fun refreshSelectedFileReadiness(session: P2pSession) {
        val handle = session.handle ?: return
        val selectedIndex = session.selectedFileIndex
        if (selectedIndex >= 0) {
            val progress = tryInvoke(handle, "fileProgress")
            session.selectedFileProgressBytes =
                longArrayValueAt(progress, selectedIndex)?.coerceAtLeast(0L) ?: 0L
        }
        val firstPiece = session.firstPiece
        val warmPieceCount = session.warmPieceCount
        if (firstPiece >= 0 && warmPieceCount > 0) {
            var ready = 0
            for (offset in 0 until warmPieceCount) {
                if ((tryInvoke(handle, "havePiece", firstPiece + offset) as? Boolean) == true) {
                    ready += 1
                }
            }
            session.firstPiecesReady = ready
        }
        maybeFlushMissingSelectedFile(session)
    }

    private fun maybeFlushMissingSelectedFile(session: P2pSession) {
        val handle = session.handle ?: return
        val file = session.file ?: return
        if (file.exists()) return
        val hasMaterializedProgress =
            session.selectedFileProgressBytes > 0L || session.firstPiecesReady > 0
        if (!hasMaterializedProgress) return
        val now = System.currentTimeMillis()
        if (now - session.lastMissingFileFlushAtMs < 1_500L) return
        session.lastMissingFileFlushAtMs = now
        session.missingFileFlushRequests += 1
        tryInvoke(handle, "flushCache")
    }

    private fun longArrayValueAt(value: Any?, index: Int): Long? {
        if (value == null || !value.javaClass.isArray) return null
        if (index < 0 || index >= ReflectArray.getLength(value)) return null
        return (ReflectArray.get(value, index) as? Number)?.toLong()
    }

    private fun writeRetry(output: OutputStream, session: P2pSession, rangeHeader: String? = null) {
        val file = session.file
        val rangeStart = parseRange(rangeHeader, session.selectedFileSize).start
        val message = listOf(
            "state=buffering",
            "readable=${isLocalStreamReadable(session, file)}",
            "range=${sanitizeRangeHeader(rangeHeader)}",
            "rangeStart=$rangeStart",
            "handleSeen=${session.handleSeen}",
            "handleActivated=${session.handleActivated}",
            "metadata=${session.metadataKnown}",
            "peers=${session.peerCount}",
            "seeds=${session.seedCount}",
            "candidates=${session.connectCandidates}",
            "listPeers=${session.listPeers}",
            "progressPpm=${session.progressPpm}",
            "fileProgressBytes=${session.selectedFileProgressBytes}",
            "selectedFileSize=${session.selectedFileSize}",
            "firstPiece=${session.firstPiece}",
            "firstPiecesReady=${session.firstPiecesReady}",
            "warmPieces=${session.warmPieceCount}",
            "torrentState=${session.torrentState}",
            "annTrackers=${session.announcingTrackers}",
            "annDht=${session.announcingDht}",
            "annLsd=${session.announcingLsd}",
            "currentTracker=${session.currentTrackerKnown}",
            "handleTrackers=${session.handleTrackerCount}",
            "trackersInjected=${session.trackersInjected}",
            "dhtRunning=${session.dhtRunning}",
            "dhtNodes=${session.dhtNodes}",
            "listenEndpoints=${session.listenEndpointCount}",
            "firewalled=${session.firewalled}",
            "polls=${session.pollCount}",
            "downloadStarted=${session.downloadStarted}",
            "metadataFetch=${session.metadataFetchState}",
            "configured=${session.streamingConfigured}",
            "fileKnown=${file != null}",
            "savePathActual=${session.actualSavePathUsed}",
            "filePathKind=${session.selectedPathKind}",
            "fileParentExists=${session.selectedFileParentExists}",
            "fileExists=${file?.exists() == true}",
            "fileLength=${file?.takeIf { it.exists() }?.length() ?: 0L}",
            "missingFileFlushes=${session.missingFileFlushRequests}",
            "requestedTrackers=${session.requestedTrackerCount}",
            "trackers=${session.trackers.size}",
            "error=${session.error ?: "none"}"
        ).joinToString(" ")
        val body = message.toByteArray(StandardCharsets.UTF_8)
        output.writeText(
            "HTTP/1.1 503 Service Unavailable\r\n" +
                "Content-Type: text/plain; charset=utf-8\r\n" +
                "Retry-After: 3\r\n" +
                "Content-Length: ${body.size}\r\n" +
                "Connection: close\r\n\r\n"
        )
        output.write(body)
    }

    private fun writeStatus(output: OutputStream, code: Int, label: String) {
        val body = label.toByteArray(StandardCharsets.UTF_8)
        output.writeText(
            "HTTP/1.1 $code $label\r\n" +
                "Content-Type: text/plain; charset=utf-8\r\n" +
                "Content-Length: ${body.size}\r\n" +
                "Connection: close\r\n\r\n"
        )
        output.write(body)
    }

    private fun writeFile(
        output: OutputStream,
        file: File,
        rangeHeader: String?,
        session: P2pSession,
        headOnly: Boolean
    ) {
        refreshSelectedFileReadiness(session)
        val totalLength = (session.selectedFileSize.takeIf { it > 0L } ?: file.length())
            .coerceAtLeast(1L)
        val range = parseRange(rangeHeader, totalLength)
        var start = range.start.coerceIn(0L, max(0L, totalLength - 1))
        var end = (range.end ?: min(totalLength - 1, start + playbackWindowBytes - 1))
            .coerceIn(start, max(start, totalLength - 1))
        end = min(end, start + playbackWindowBytes - 1)
        prioritizeRangePieces(
            session,
            start,
            min(totalLength - 1, start + forwardPrefetchBytes - 1)
        )
        val readyBeforeHeaders = isRangePieceReadable(session, start, end)
        if (!readyBeforeHeaders) {
            Log.i(
                "JuicrP2P",
                "http range wait method=${if (headOnly) "HEAD" else "GET"} " +
                    "range=${sanitizeRangeHeader(rangeHeader)} start=$start end=$end"
            )
        }
        val rangeWaitMs = if (start > startupReadableBytes) 45_000L else 24_000L
        val readyAfterWait = (readyBeforeHeaders || waitForRangePieceReadable(
            session,
            start,
            end,
            timeoutMs = rangeWaitMs
        )) && file.length() > start
        if (!readyAfterWait) {
            Log.i(
                "JuicrP2P",
                "http range retry range=${sanitizeRangeHeader(rangeHeader)} start=$start fileLength=${file.length()}"
            )
            writeRetry(output, session, rangeHeader)
            return
        }
        val status = "206 Partial Content"
        end = min(end, max(start, file.length() - 1))
        if (end < start || file.length() <= start) {
            Log.i(
                "JuicrP2P",
                "http range retry range=${sanitizeRangeHeader(rangeHeader)} start=$start fileLength=${file.length()}"
            )
            writeRetry(output, session, rangeHeader)
            return
        }
        val contentLength = end - start + 1
        output.writeText(
            "HTTP/1.1 $status\r\n" +
                "Content-Type: ${mimeTypeFor(file)}\r\n" +
                "Accept-Ranges: bytes\r\n" +
                "Content-Length: $contentLength\r\n" +
                "Content-Range: bytes $start-$end/$totalLength\r\n" +
                "X-Juicr-P2P-Buffered-Bytes: ${session.selectedFileProgressBytes}\r\n" +
                "X-Juicr-P2P-First-Pieces: ${session.firstPiecesReady}/${session.warmPieceCount}\r\n" +
                "X-Juicr-P2P-Range-Start: $start\r\n" +
                "Connection: close\r\n\r\n"
        )
        if (headOnly) return
        output.flush()
        if (file.length() <= start) return
        end = min(end, max(start, file.length() - 1))
        BufferedInputStream(FileInputStream(file)).use { input ->
            input.skip(start)
            val buffer = ByteArray(64 * 1024)
            var remaining = contentLength
            while (remaining > 0) {
                val read = input.read(buffer, 0, min(buffer.size.toLong(), remaining).toInt())
                if (read <= 0) break
                output.write(buffer, 0, read)
                remaining -= read
            }
        }
    }

    private fun waitForRangePieceReadable(
        session: P2pSession,
        start: Long,
        end: Long,
        timeoutMs: Long = 20_000L
    ): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (sessions.containsKey(session.token)) {
            refreshSelectedFileReadiness(session)
            if (isRangePieceReadable(session, start, end)) return true
            if (System.currentTimeMillis() >= deadline) return false
            try {
                TimeUnit.MILLISECONDS.sleep(250)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return false
            }
        }
        return false
    }

    private fun parseRange(rangeHeader: String?, totalLength: Long): RequestedRange {
        if (rangeHeader.isNullOrBlank() || !rangeHeader.startsWith("bytes=")) {
            return RequestedRange(0L, null)
        }
        val range = rangeHeader.removePrefix("bytes=").substringBefore(",")
        val parts = range.split("-", limit = 2)
        val startPart = parts.getOrNull(0).orEmpty()
        val endPart = parts.getOrNull(1).orEmpty()
        if (startPart.isBlank()) {
            val suffix = endPart.toLongOrNull()?.coerceAtLeast(1L) ?: return RequestedRange(0L, null)
            return RequestedRange(max(0L, totalLength - suffix), totalLength - 1)
        }
        return RequestedRange(
            start = startPart.toLongOrNull() ?: 0L,
            end = endPart.toLongOrNull()
        )
    }

    private fun isRangePieceReadable(session: P2pSession, start: Long, end: Long): Boolean {
        val handle = session.handle ?: return false
        val files = session.fileStorage ?: return start == 0L && session.firstPiecesReady > 0
        val selectedIndex = session.selectedFileIndex
        if (selectedIndex < 0) return false
        val first = tryInvoke(files, "mapFile", selectedIndex, start, 1) ?: return false
        val last = tryInvoke(files, "mapFile", selectedIndex, max(start, end), 1) ?: first
        val firstPiece = (tryInvoke(first, "piece") as? Number)?.toInt() ?: return false
        val lastPiece = (tryInvoke(last, "piece") as? Number)?.toInt() ?: firstPiece
        val maxPiecesToCheck = 128
        if (lastPiece - firstPiece + 1 > maxPiecesToCheck) return false
        for (piece in firstPiece..lastPiece) {
            if ((tryInvoke(handle, "havePiece", piece) as? Boolean) != true) return false
        }
        return true
    }

    private fun prioritizeRangePieces(session: P2pSession, start: Long, end: Long) {
        val handle = session.handle ?: return
        val files = session.fileStorage ?: return
        val selectedIndex = session.selectedFileIndex
        if (selectedIndex < 0) return
        val first = tryInvoke(files, "mapFile", selectedIndex, start, 1) ?: return
        val last = tryInvoke(files, "mapFile", selectedIndex, max(start, end), 1) ?: first
        val firstPiece = (tryInvoke(first, "piece") as? Number)?.toInt() ?: return
        val lastPiece = (tryInvoke(last, "piece") as? Number)?.toInt() ?: firstPiece
        val high = priority("SEVEN") ?: priority("HIGH")
        val alertWhenAvailable = tryStaticField(
            "com.frostwire.jlibtorrent.TorrentHandle",
            "ALERT_WHEN_AVAILABLE"
        )
        val maxPiecesToBoost = 512
        val boostLastPiece = min(lastPiece, firstPiece + maxPiecesToBoost - 1)
        for ((offset, piece) in (firstPiece..boostLastPiece).withIndex()) {
            if (high != null) {
                tryInvoke(handle, "piecePriority", piece, high)
            }
            if (alertWhenAvailable != null) {
                tryInvoke(handle, "setPieceDeadline", piece, offset * 25, alertWhenAvailable)
            } else {
                tryInvoke(handle, "setPieceDeadline", piece, offset * 25)
            }
        }
    }

    private fun mimeTypeFor(file: File): String {
        return when (file.extension.lowercase()) {
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "avi" -> "video/x-msvideo"
            "mov" -> "video/quicktime"
            "mp4", "m4v" -> "video/mp4"
            else -> "application/octet-stream"
        }
    }

    private fun sanitizeRangeHeader(rangeHeader: String?): String {
        return rangeHeader?.take(48)?.replace(Regex("[^A-Za-z0-9=,\\-]"), "_") ?: "none"
    }

    private fun tryInvoke(target: Any?, name: String, vararg args: Any?): Any? {
        if (target == null) return null
        return try {
            val method = findMethod(target.javaClass, name, args) ?: return null
            method.isAccessible = true
            method.invoke(target, *args)
        } catch (_: Throwable) {
            null
        }
    }

    private fun findMethod(clazz: Class<*>, name: String, args: Array<out Any?>): Method? {
        return clazz.methods.firstOrNull { method ->
            method.name == name &&
                method.parameterTypes.size == args.size &&
                method.parameterTypes.zip(args).all { (type, arg) ->
                    arg == null || type.isAssignableFrom(arg.javaClass) ||
                        (type == Boolean::class.javaPrimitiveType && arg is Boolean) ||
                        (type == Short::class.javaPrimitiveType && arg is Short) ||
                        (type == Int::class.javaPrimitiveType && arg is Int) ||
                        (type == Long::class.javaPrimitiveType && arg is Long)
                }
        }
    }

    private fun OutputStream.writeText(value: String) {
        write(value.toByteArray(StandardCharsets.UTF_8))
    }
}

private data class RequestedRange(
    val start: Long,
    val end: Long?
)

private data class P2pSession(
    val token: String,
    val infoHash: String,
    val requestedFileIdx: Int?,
    val requestedTrackerCount: Int,
    val trackers: List<String>,
    val displayName: String?,
    val quality: String?,
    val saveDir: File,
    @Volatile var handle: Any? = null,
    @Volatile var file: File? = null,
    @Volatile var fileStorage: Any? = null,
    @Volatile var selectedFileIndex: Int = -1,
    @Volatile var selectedFileSize: Long = 0L,
    @Volatile var selectedFileProgressBytes: Long = 0L,
    @Volatile var firstPiece: Int = -1,
    @Volatile var firstPiecesReady: Int = 0,
    @Volatile var warmPieceCount: Int = 0,
    @Volatile var error: String? = null,
    @Volatile var streamingConfigured: Boolean = false,
    @Volatile var downloadStarted: Boolean = false,
    @Volatile var metadataFetchState: String = "not_started",
    @Volatile var pollCount: Int = 0,
    @Volatile var handleSeen: Boolean = false,
    @Volatile var handleActivated: Boolean = false,
    @Volatile var metadataKnown: Boolean = false,
    @Volatile var peerCount: Int = 0,
    @Volatile var seedCount: Int = 0,
    @Volatile var connectCandidates: Int = 0,
    @Volatile var listPeers: Int = 0,
    @Volatile var progressPpm: Int = 0,
    @Volatile var announcingTrackers: Boolean = false,
    @Volatile var announcingDht: Boolean = false,
    @Volatile var announcingLsd: Boolean = false,
    @Volatile var currentTrackerKnown: Boolean = false,
    @Volatile var handleTrackerCount: Int = 0,
    @Volatile var trackersInjected: Boolean = false,
    @Volatile var dhtRunning: Boolean = false,
    @Volatile var dhtNodes: Long = 0L,
    @Volatile var listenEndpointCount: Int = 0,
    @Volatile var firewalled: Boolean = false,
    @Volatile var actualSavePathUsed: Boolean = false,
    @Volatile var selectedPathKind: String = "unknown",
    @Volatile var selectedFileParentExists: Boolean = false,
    @Volatile var torrentState: String = "unknown",
    @Volatile var missingFileFlushRequests: Int = 0,
    @Volatile var lastMissingFileFlushAtMs: Long = 0L
)

private data class ResolvedP2pFile(
    val file: File,
    val pathKind: String,
    val parentExists: Boolean
)

private data class SelectedP2pFile(
    val file: File,
    val fileStorage: Any,
    val index: Int,
    val size: Long
)
