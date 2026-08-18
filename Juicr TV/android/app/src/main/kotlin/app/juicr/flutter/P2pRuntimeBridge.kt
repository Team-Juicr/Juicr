package app.juicr.flutter

import android.content.Context
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream
import java.lang.reflect.Array as ReflectArray
import java.lang.reflect.Method
import java.net.InetAddress
import java.net.URI
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
    private val pendingCleanupDirectories = ConcurrentHashMap.newKeySet<String>()
    private val acceptedSockets = P2pAcceptedSocketRegistry()
    private val sessionOwnership = P2pSessionOwnership()
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
    private val p2pCancellationCleanupAttempts = 30
    private val p2pCacheDir: File
        get() = File(context.cacheDir, "juicr-p2p")

    fun isAvailable(): Boolean {
        if (!P2pRuntimePolicy.runtimeAvailable(
                buildCapable = BuildConfig.JUICR_P2P_BUILD_CAPABLE,
                runtimeEnabled = BuildConfig.JUICR_ENABLE_P2P_RUNTIME
            ) { true }
        ) {
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

    fun availabilityStatus(): Map<String, Any> {
        val available = isAvailable()
        return P2pRuntimePolicy.availabilityStatus(available, lastAvailabilityError)
    }

    @Synchronized
    fun open(
        infoHash: String,
        fileIdx: Int?,
        trackers: List<String>,
        displayName: String?,
        quality: String?,
        generation: Long? = null
    ): String {
        if (!isAvailable()) {
            throw IllegalStateException(
                "Advanced playback is not available in this build."
            )
        }
        val safeInfoHash = P2pRuntimePolicy.normalizeInfoHash(infoHash)
        val ownedGeneration = generation?.takeIf { it > 0L }
            ?: sessionOwnership.nextGeneration()
        ensureServer()
        ensureSessionManager()
        val manager = sessionManager
            ?: throw IllegalStateException("Local playback service is unavailable.")
        val sessionKey = p2pSessionKey(safeInfoHash, fileIdx)
        val existingToken = sessionTokensByKey[sessionKey]
        if (existingToken != null && sessions.containsKey(existingToken)) {
            sessionOwnership.register(existingToken, ownedGeneration)
            return P2pRuntimePolicy.loopbackUrl(port, existingToken)
                ?: throw IllegalStateException("Local playback session is unavailable.")
        }
        val token = UUID.randomUUID().toString()
        pruneP2pCache()
        val saveDir = P2pRuntimePolicy.sessionCacheDirectory(
            p2pCacheDir,
            ownedGeneration
        )?.apply { mkdirs() }
            ?: throw IllegalStateException("Local playback cache is unavailable.")
        val session = P2pSession(
            token = token,
            generation = ownedGeneration,
            infoHash = safeInfoHash,
            requestedFileIdx = fileIdx,
            requestedTrackerCount = trackers.size,
            trackers = P2pRuntimePolicy.normalizeTrackers(trackers),
            displayName = displayName?.take(96),
            quality = quality?.take(48),
            saveDir = saveDir,
            manager = manager
        )
        sessions[token] = session
        sessionTokensByKey[sessionKey] = token
        sessionOwnership.register(token, ownedGeneration)
        startDownload(session)
        pruneP2pCache(keepDirectory = saveDir)
        return P2pRuntimePolicy.loopbackUrl(port, token)
            ?: throw IllegalStateException("Local playback session is unavailable.")
    }

    @Synchronized
    fun isReady(generation: Long?): Boolean {
        if (generation == null || generation <= 0L) return false
        return sessions.entries.any { (token, session) ->
            sessionOwnership.owns(token, generation) &&
                isLocalStreamReadable(session, session.file)
        }
    }

    @Synchronized
    fun readinessStatus(generation: Long?): Map<String, Any> {
        if (generation == null || generation <= 0L) return mapOf("stage" to "unknown")
        val session = sessions.entries.firstOrNull { (token, _) ->
            sessionOwnership.owns(token, generation)
        }?.value ?: return mapOf("stage" to "unknown")
        val ready = isLocalStreamReadable(session, session.file)
        val stage = P2pRuntimePolicy.readinessStage(
            failed = session.error != null,
            downloadStarted = session.downloadStarted,
            handleSeen = session.handleSeen,
            metadataKnown = session.metadataKnown,
            selectedFile = session.file != null && session.selectedFileIndex >= 0,
            peerCount = maxOf(
                session.peerCount,
                session.seedCount,
                session.connectCandidates,
                session.listPeers
            ),
            firstPiecesReady = session.firstPiecesReady,
            ready = ready
        )
        return mapOf(
            "stage" to stage,
            "discovery" to if (stage == "metadata") {
                P2pRuntimePolicy.metadataDiscoveryStage(
                    metadataKnown = session.metadataKnown,
                    requestedTrackerCount = session.requestedTrackerCount,
                    handleTrackerCount = session.handleTrackerCount,
                    dhtRunning = session.dhtRunning,
                    dhtNodes = session.dhtNodes,
                    announcingTrackers = session.announcingTrackers,
                    announcingDht = session.announcingDht,
                    peerCount = maxOf(
                        session.peerCount,
                        session.seedCount,
                        session.connectCandidates,
                        session.listPeers
                    )
                )
            } else {
                "not_applicable"
            }
        )
    }

    @Synchronized
    fun stopAll(generation: Long? = null) {
        val removedTokens = sessionOwnership.removeOwnedThrough(generation)
        stopTokens(removedTokens, routeClosing = true)
    }

    @Synchronized
    fun stopGeneration(generation: Long?) {
        if (generation == null || generation <= 0L) return
        val removedTokens = sessionOwnership.removeOwnedGeneration(generation)
        stopTokens(removedTokens, routeClosing = false)
    }

    private fun stopTokens(removedTokens: Set<String>, routeClosing: Boolean) {
        val removedSessions = removedTokens.mapNotNull { token ->
            val session = sessions.remove(token) ?: return@mapNotNull null
            session.cancelled = true
            sessionTokensByKey.remove(
                p2pSessionKey(session.infoHash, session.requestedFileIdx),
                token
            )
            session
        }
        val managerRetained = sessions.isNotEmpty() || !routeClosing
        for (session in removedSessions) {
            val handle = session.handle
            if (handle != null) {
                removeHandleIfUnowned(session, session.manager, handle)
                deleteSessionStorageIfUnowned(session)
                continue
            }
            if (managerRetained && scheduleCancelledCleanup(session)) {
                continue
            }
            deleteSessionStorageIfUnowned(session)
        }
        if (!P2pRuntimeLifecycle.shouldStopRuntime(
                routeClosing = routeClosing,
                sessionsRemain = sessions.isNotEmpty()
            )
        ) return
        sessionTokensByKey.clear()
        val closingServer = serverSocket
        serverSocket = null
        port = 0
        try {
            closingServer?.close()
        } catch (_: Throwable) {
        }
        acceptedSockets.closeAll()
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

    private fun pruneP2pCache(keepDirectory: File? = null) {
        try {
            val root = p2pCacheDir
            if (!root.exists()) return
            val activeDirectories = sessions.values.flatMap { session ->
                listOfNotNull(
                    session.saveDir.canonicalPath,
                    session.activeSaveDir?.canonicalPath
                )
            }.toSet()
            val keepPath = keepDirectory?.canonicalPath
            val staleDirs = root.listFiles()
                ?.filter { it.isDirectory }
                ?.filter { directory ->
                    val path = directory.canonicalPath
                    P2pStorageOwnership.mayPruneDirectory(
                        active = path in activeDirectories,
                        pendingCleanup = path in pendingCleanupDirectories,
                        explicitlyKept = path == keepPath
                    )
                }
                ?.sortedBy { it.lastModified() }
                ?: emptyList()
            for (dir in staleDirs) {
                if (directorySize(root) <= p2pCacheMaxBytes) break
                dir.deleteRecursively()
            }
            if (keepDirectory != null) {
                if (
                    sessions.values.none { it.saveDir.canonicalPath == keepDirectory.canonicalPath } &&
                    directorySize(keepDirectory) > p2pSessionCacheMaxBytes
                ) {
                    keepDirectory.deleteRecursively()
                    keepDirectory.mkdirs()
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
        val listenerEpoch = acceptedSockets.reopen()
        serverSocket = socket
        port = socket.localPort
        executor.execute {
            while (!socket.isClosed) {
                try {
                    val client = socket.accept()
                    acceptedSockets.track(client, listenerEpoch)
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
                val manager = session.manager
                val started = synchronized(this) {
                    if (!P2pNativeOwnership.mayStartDownload(
                            cancelled = session.cancelled,
                            tokenCurrent = sessions[session.token] === session,
                            managerCurrent = sessionManager === manager
                        )) {
                        false
                    } else {
                        session.downloadStarted = true
                        session.metadataFetchState = "magnet"
                        tryInvoke(manager, "download", magnet, session.saveDir)
                            ?: tryInvoke(manager, "download", magnet, session.saveDir.absolutePath)
                        true
                    }
                }
                if (!started) return@execute
                pollMetadata(session)
            } catch (error: Throwable) {
                session.error = P2pRuntimePolicy.errorBucket(error)
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
        val manager = session.manager
        val sha1Class = Class.forName("com.frostwire.jlibtorrent.Sha1Hash")
        val sha1 = sha1Class.getDeclaredConstructor(String::class.java).newInstance(session.infoHash)
        P2pReadiness.await(
            maxAttempts = 90,
            delayMs = 1_000L,
            sleep = { delay -> TimeUnit.MILLISECONDS.sleep(delay) }
        ) { attempt ->
            if (session.cancelled || !sessions.containsKey(session.token)) {
                scheduleCancelledCleanup(session)
                return@await true
            }
            session.pollCount = attempt
            val handle = synchronized(this) {
                if (P2pPollOwnership.mayFind(
                        cancelled = session.cancelled,
                        tokenCurrent = sessions[session.token] === session,
                        managerCurrent = sessionManager === manager,
                        cleanupScheduled = session.cleanupScheduled
                    )) {
                    tryInvoke(manager, "find", sha1)
                } else {
                    null
                }
            }
            if (handle == null) {
                val cancelledAfterProbe = synchronized(this) {
                    session.cancelled || sessions[session.token] !== session
                }
                if (cancelledAfterProbe) {
                    scheduleCancelledCleanup(session)
                    return@await true
                }
            }
            if (handle != null) {
                val settled = synchronized(this) {
                    if (!P2pPollOwnership.maySettle(session.cleanupScheduled)) {
                        true
                    } else {
                        when (P2pNativeOwnership.afterFind(
                            cancelled = session.cancelled,
                            tokenCurrent = sessions[session.token] === session,
                            managerCurrent = sessionManager === manager,
                            sameHashRetained = sameHashRetained(session, manager)
                        )) {
                            P2pHandleDisposition.REMOVE -> {
                                tryInvoke(manager, "remove", handle)
                                true
                            }
                            P2pHandleDisposition.IGNORE -> true
                            P2pHandleDisposition.ADOPT -> {
                                session.handleSeen = true
                                activateHandle(session, handle)
                                updateHandleSnapshot(session, handle)
                                val selected = resolveSelectedFile(handle, session)
                                if (selected == null) {
                                    false
                                } else {
                                    session.handle = handle
                                    session.file = selected.file
                                    session.fileStorage = selected.fileStorage
                                    session.selectedFileIndex = selected.index
                                    session.selectedFileSize = selected.size
                                    configureStreamingPriority(
                                        handle,
                                        selected.fileStorage,
                                        selected.index,
                                        session
                                    )
                                    true
                                }
                            }
                        }
                    }
                }
                if (settled) return@await true
            }
            false
        }
    }

    private fun sameHashRetained(session: P2pSession, manager: Any): Boolean {
        return sessions.values.any { candidate ->
            candidate !== session &&
                !candidate.cancelled &&
                candidate.manager === manager &&
                candidate.infoHash == session.infoHash
        }
    }

    private fun removeHandleIfUnowned(session: P2pSession, manager: Any, handle: Any) {
        if (P2pNativeOwnership.afterFind(
                cancelled = true,
                tokenCurrent = false,
                managerCurrent = sessionManager === manager,
                sameHashRetained = sameHashRetained(session, manager)
            ) == P2pHandleDisposition.REMOVE
        ) {
            tryInvoke(manager, "remove", handle)
        }
    }

    private fun scheduleCancelledCleanup(session: P2pSession): Boolean {
        val manager = session.manager
        val scheduled = synchronized(this) {
            if (!P2pCancellationOwnership.shouldSchedule(
                    cancelled = session.cancelled,
                    cleanupScheduled = session.cleanupScheduled,
                    managerCurrent = sessionManager === manager,
                    downloadStarted = session.downloadStarted,
                    handleKnown = session.handle != null
                )) {
                false
            } else {
                session.cleanupScheduled = true
                pendingCleanupDirectories.addAll(sessionStoragePaths(session))
                true
            }
        }
        if (!scheduled) return false
        executor.execute {
            try {
                val sha1Class = Class.forName("com.frostwire.jlibtorrent.Sha1Hash")
                val sha1 = sha1Class.getDeclaredConstructor(String::class.java)
                    .newInstance(session.infoHash)
                P2pCancellationCleanup.afterProbe(
                    cancelled = true,
                    maxAttempts = p2pCancellationCleanupAttempts,
                    delayMs = 1_000L,
                    sleep = { delay -> TimeUnit.MILLISECONDS.sleep(delay) },
                    findHandle = {
                        synchronized(this) {
                            if (sessionManager === manager) {
                                tryInvoke(manager, "find", sha1)
                            } else {
                                null
                            }
                        }
                    },
                    removeHandle = { lateHandle ->
                        synchronized(this) {
                            removeHandleIfUnowned(session, manager, lateHandle)
                        }
                    }
                )
            } catch (_: Throwable) {
            } finally {
                synchronized(this) {
                    transferRetainedStorageOwnership(session, manager)
                    deleteSessionStorageIfUnowned(session)
                    pendingCleanupDirectories.removeAll(sessionStoragePaths(session))
                }
            }
        }
        return true
    }

    private fun deleteSessionStorageIfUnowned(session: P2pSession) {
        val manager = session.manager
        val sameHashRetained = sameHashRetained(session, manager)
        if (sameHashRetained) {
            transferRetainedStorageOwnership(session, manager)
        }
        val directories = listOfNotNull(session.saveDir, session.activeSaveDir)
            .distinctBy { it.canonicalPath }
        for (directory in directories) {
            val path = directory.canonicalPath
            val retainedBySession = sessions.values.any { candidate ->
                candidate.saveDir.canonicalPath == path ||
                    candidate.activeSaveDir?.canonicalPath == path
            }
            if (!P2pStorageOwnership.mayDeleteSessionDirectory(
                    sameHashRetained = sameHashRetained,
                    directoryRetainedBySession = retainedBySession
                )) {
                continue
            }
            try {
                directory.deleteRecursively()
            } catch (_: Throwable) {
            }
        }
    }

    private fun sessionStoragePaths(session: P2pSession): Set<String> {
        return listOfNotNull(session.saveDir, session.activeSaveDir)
            .map { it.canonicalPath }
            .toSet()
    }

    private fun transferRetainedStorageOwnership(session: P2pSession, manager: Any) {
        val retainedDirectory = session.activeSaveDir ?: session.saveDir
        sessions.values
            .filter { candidate ->
                candidate !== session &&
                    !candidate.cancelled &&
                    candidate.manager === manager &&
                    candidate.infoHash == session.infoHash
            }
            .forEach { candidate ->
                if (candidate.activeSaveDir == null) {
                    candidate.activeSaveDir = retainedDirectory
                }
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
        val candidates = (0 until numFiles).map { index ->
            P2pFileCandidate(
                index = index,
                path = tryInvoke(files, "filePath", index)?.toString().orEmpty(),
                size = (tryInvoke(files, "fileSize", index) as? Number)?.toLong() ?: 0L
            )
        }
        val selectedIndex = P2pRuntimePolicy.selectMediaFile(
            candidates,
            session.requestedFileIdx
        )?.index ?: return null
        val savePath = resolveHandleSavePath(handle, session.saveDir)
        session.activeSaveDir = savePath
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
            ?.let { P2pRuntimePolicy.containedFile(p2pCacheDir, it.path) }
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
        val candidate = if (pathFile.isAbsolute) pathFile else File(savePath, path)
        val file = P2pRuntimePolicy.containedFile(p2pCacheDir, candidate.path)
            ?: return null
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
        } finally {
            acceptedSockets.untrack(socket)
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
        val diagnostic = P2pRuntimePolicy.diagnosticBucket(
            stage = "readiness",
            outcome = if (session.error == null) "retry" else "failed",
            attempts = session.pollCount,
            ready = isLocalStreamReadable(session, file)
        )
        val message = diagnostic.entries.joinToString(" ") { (key, value) -> "$key=$value" }
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
        val rangeWaitMs = if (start > startupReadableBytes) 45_000L else 24_000L
        val readyAfterWait = (readyBeforeHeaders || waitForRangePieceReadable(
            session,
            start,
            end,
            timeoutMs = rangeWaitMs
        )) && file.length() > start
        if (!readyAfterWait) {
            writeRetry(output, session, rangeHeader)
            return
        }
        val status = "206 Partial Content"
        end = min(end, max(start, file.length() - 1))
        if (end < start || file.length() <= start) {
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
    @Volatile var generation: Long,
    val infoHash: String,
    val requestedFileIdx: Int?,
    val requestedTrackerCount: Int,
    val trackers: List<String>,
    val displayName: String?,
    val quality: String?,
    val saveDir: File,
    val manager: Any,
    @Volatile var activeSaveDir: File? = null,
    @Volatile var cleanupScheduled: Boolean = false,
    @Volatile var handle: Any? = null,
    @Volatile var cancelled: Boolean = false,
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

internal data class P2pFileCandidate(
    val index: Int,
    val path: String,
    val size: Long
)

internal data class P2pReadinessResult(
    val ready: Boolean,
    val attempts: Int
)

internal object P2pDeferredRemoval {
    fun await(
        maxAttempts: Int,
        delayMs: Long,
        sleep: (Long) -> Unit,
        findHandle: () -> Any?,
        removeHandle: (Any) -> Unit
    ): Boolean {
        val boundedAttempts = maxAttempts.coerceAtLeast(1)
        for (attempt in 1..boundedAttempts) {
            val handle = findHandle()
            if (handle != null) {
                removeHandle(handle)
                return true
            }
            if (attempt < boundedAttempts && delayMs > 0L) sleep(delayMs)
        }
        return false
    }
}

internal object P2pCancellationCleanup {
    fun afterProbe(
        cancelled: Boolean,
        maxAttempts: Int,
        delayMs: Long,
        sleep: (Long) -> Unit,
        findHandle: () -> Any?,
        removeHandle: (Any) -> Unit
    ): Boolean {
        if (!cancelled) return false
        return P2pDeferredRemoval.await(
            maxAttempts = maxAttempts,
            delayMs = delayMs,
            sleep = sleep,
            findHandle = findHandle,
            removeHandle = removeHandle
        )
    }
}

internal object P2pRuntimeLifecycle {
    fun shouldStopRuntime(routeClosing: Boolean, sessionsRemain: Boolean): Boolean =
        routeClosing && !sessionsRemain
}

internal class P2pAcceptedSocketRegistry {
    private val sockets = ConcurrentHashMap.newKeySet<Socket>()
    @Volatile
    private var closed = false
    private var epoch = 0L

    val activeCount: Int
        get() = sockets.size

    @Synchronized
    fun reopen(): Long {
        epoch += 1
        closed = false
        return epoch
    }

    @Synchronized
    fun track(socket: Socket, listenerEpoch: Long) {
        if (closed || listenerEpoch != epoch) {
            try {
                socket.close()
            } catch (_: Throwable) {
            }
            return
        }
        socket.soTimeout = 5_000
        sockets.add(socket)
    }

    @Synchronized
    fun untrack(socket: Socket) {
        sockets.remove(socket)
    }

    @Synchronized
    fun closeAll() {
        closed = true
        val closing = sockets.toList()
        sockets.clear()
        for (socket in closing) {
            try {
                socket.close()
            } catch (_: Throwable) {
            }
        }
    }
}

internal object P2pCancellationOwnership {
    fun shouldSchedule(
        cancelled: Boolean,
        cleanupScheduled: Boolean,
        managerCurrent: Boolean,
        downloadStarted: Boolean,
        handleKnown: Boolean
    ): Boolean = cancelled &&
        !cleanupScheduled &&
        managerCurrent &&
        downloadStarted &&
        !handleKnown
}

internal object P2pStorageOwnership {
    fun mayDeleteSessionDirectory(
        sameHashRetained: Boolean,
        directoryRetainedBySession: Boolean
    ): Boolean = !sameHashRetained && !directoryRetainedBySession

    fun mayPruneDirectory(
        active: Boolean,
        pendingCleanup: Boolean,
        explicitlyKept: Boolean
    ): Boolean = !active && !pendingCleanup && !explicitlyKept
}

internal object P2pPollOwnership {
    fun mayFind(
        cancelled: Boolean,
        tokenCurrent: Boolean,
        managerCurrent: Boolean,
        cleanupScheduled: Boolean
    ): Boolean = !cancelled && tokenCurrent && managerCurrent && !cleanupScheduled

    fun maySettle(cleanupScheduled: Boolean): Boolean = !cleanupScheduled
}

internal enum class P2pHandleDisposition {
    ADOPT,
    REMOVE,
    IGNORE
}

internal object P2pNativeOwnership {
    fun mayStartDownload(
        cancelled: Boolean,
        tokenCurrent: Boolean,
        managerCurrent: Boolean
    ): Boolean = !cancelled && tokenCurrent && managerCurrent

    fun afterFind(
        cancelled: Boolean,
        tokenCurrent: Boolean,
        managerCurrent: Boolean,
        sameHashRetained: Boolean
    ): P2pHandleDisposition {
        if (!managerCurrent) return P2pHandleDisposition.IGNORE
        if (!cancelled && tokenCurrent) return P2pHandleDisposition.ADOPT
        return if (sameHashRetained) {
            P2pHandleDisposition.IGNORE
        } else {
            P2pHandleDisposition.REMOVE
        }
    }
}

internal object P2pReadiness {
    fun await(
        maxAttempts: Int,
        delayMs: Long,
        sleep: (Long) -> Unit,
        probe: (Int) -> Boolean
    ): P2pReadinessResult {
        val boundedAttempts = maxAttempts.coerceIn(1, 120)
        for (attempt in 1..boundedAttempts) {
            if (probe(attempt)) return P2pReadinessResult(true, attempt)
            if (attempt < boundedAttempts && delayMs > 0L) {
                sleep(delayMs.coerceAtMost(5_000L))
            }
        }
        return P2pReadinessResult(false, boundedAttempts)
    }
}

internal class P2pSessionOwnership {
    private val generations = linkedMapOf<String, MutableSet<Long>>()
    private var latestGeneration = 0L

    @Synchronized
    fun nextGeneration(): Long {
        latestGeneration += 1L
        return latestGeneration
    }

    @Synchronized
    fun register(token: String, generation: Long) {
        if (token.isBlank() || generation <= 0L) return
        generations.getOrPut(token) { linkedSetOf() }.add(generation)
        latestGeneration = max(latestGeneration, generation)
    }

    @Synchronized
    fun removeOwnedThrough(generation: Long?): Set<String> {
        val removedTokens = linkedSetOf<String>()
        val iterator = generations.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            entry.value.removeAll { owned -> generation == null || owned <= generation }
            if (entry.value.isEmpty()) {
                removedTokens.add(entry.key)
                iterator.remove()
            }
        }
        return removedTokens
    }

    @Synchronized
    fun removeOwnedGeneration(generation: Long): Set<String> {
        val removedTokens = linkedSetOf<String>()
        val iterator = generations.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next()
            entry.value.remove(generation)
            if (entry.value.isEmpty()) {
                removedTokens.add(entry.key)
                iterator.remove()
            }
        }
        return removedTokens
    }

    @Synchronized
    fun owns(token: String, generation: Long): Boolean =
        generations[token]?.contains(generation) == true

    @Synchronized
    fun activeTokens(): Set<String> = generations.keys.toSet()
}

internal object P2pRuntimePolicy {
    private val supportedMediaExtensions = setOf("mp4", "m4v", "mkv", "webm", "avi", "mov")
    private val opaqueToken = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
    private val safeStages = setOf("availability", "metadata", "readiness", "stream", "cleanup")
    private val safeOutcomes = setOf("available", "disabled", "unavailable", "retry", "ready", "stopped", "failed")
    private val safeAvailabilityStages = setOf(
        "native_shim_loader", "swig_jni_loader", "native_version_probe",
        "session_manager", "settings_pack", "sha1_hash", "announce_entry",
        "priority", "torrent_flags", "torrent_handle"
    )
    private val safeAvailabilityBuckets = setOf(
        "native_library", "missing_class", "permission", "unavailable"
    )

    fun runtimeAvailable(
        buildCapable: Boolean,
        runtimeEnabled: Boolean,
        runtimeProbe: () -> Boolean
    ): Boolean = buildCapable && runtimeEnabled && runtimeProbe()

    fun normalizeInfoHash(raw: String): String {
        var cleaned = raw.trim()
        val btihIndex = cleaned.lowercase().indexOf("btih:")
        if (btihIndex >= 0) cleaned = cleaned.substring(btihIndex + "btih:".length)
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
                ?: throw IllegalArgumentException("P2P descriptor format is not supported.")
        }
        throw IllegalArgumentException("P2P descriptor format is not supported.")
    }

    fun normalizeTrackers(rawTrackers: List<String>): List<String> {
        return rawTrackers.mapNotNull(::normalizeTracker).distinct().take(32)
    }

    fun selectMediaFile(
        candidates: List<P2pFileCandidate>,
        requestedIndex: Int?
    ): P2pFileCandidate? {
        val supported = candidates.filter { candidate ->
            candidate.size > 0L && candidate.path.substringAfterLast('.', "").lowercase() in supportedMediaExtensions
        }
        return supported.firstOrNull { it.index == requestedIndex }
            ?: supported.maxByOrNull { it.size }
    }

    fun containedFile(root: File, path: String): File? {
        if (path.isBlank()) return null
        return try {
            val canonicalRoot = root.canonicalFile
            val candidate = File(path).let { if (it.isAbsolute) it else File(canonicalRoot, path) }
                .canonicalFile
            val prefix = canonicalRoot.path + File.separator
            candidate.takeIf { it.path.startsWith(prefix) }
        } catch (_: Throwable) {
            null
        }
    }

    fun loopbackUrl(port: Int, token: String): String? {
        if (port !in 1..65535 || !opaqueToken.matches(token.lowercase())) return null
        return "http://127.0.0.1:$port/stream/${token.lowercase()}"
    }

    fun sessionCacheDirectory(root: File, generation: Long): File? {
        if (generation <= 0L) return null
        return containedFile(root, "session-$generation")
    }

    fun diagnosticBucket(
        stage: String,
        outcome: String,
        attempts: Int,
        ready: Boolean
    ): Map<String, Any> {
        return linkedMapOf(
            "stage" to stage.takeIf { it in safeStages }.orEmpty().ifBlank { "unknown" },
            "outcome" to outcome.takeIf { it in safeOutcomes }.orEmpty().ifBlank { "unavailable" },
            "attempts" to attempts.coerceIn(0, 120),
            "ready" to ready
        )
    }

    fun availabilityStatus(
        available: Boolean,
        failure: String?
    ): Map<String, Any> {
        if (available) {
            return linkedMapOf(
                "available" to true,
                "stage" to "ready",
                "bucket" to "available"
            )
        }
        val parts = failure.orEmpty().split(':')
        val stage = parts.getOrNull(0)
            ?.removePrefix("stage_")
            ?.takeIf { it in safeAvailabilityStages }
            ?: "unknown"
        val bucket = parts.getOrNull(2)
            ?.takeIf { it in safeAvailabilityBuckets }
            ?: "unavailable"
        return linkedMapOf(
            "available" to false,
            "stage" to stage,
            "bucket" to bucket
        )
    }

    fun readinessStage(
        failed: Boolean,
        downloadStarted: Boolean,
        handleSeen: Boolean,
        metadataKnown: Boolean,
        selectedFile: Boolean,
        peerCount: Int,
        firstPiecesReady: Int,
        ready: Boolean
    ): String {
        if (failed) return "failed"
        if (!downloadStarted) return "starting"
        if (!handleSeen) return "handle"
        if (!metadataKnown) return "metadata"
        if (!selectedFile) return "file"
        if (ready) return "ready"
        if (peerCount <= 0 && firstPiecesReady <= 0) return "peers"
        return "pieces"
    }

    fun metadataDiscoveryStage(
        metadataKnown: Boolean,
        requestedTrackerCount: Int,
        handleTrackerCount: Int,
        dhtRunning: Boolean,
        dhtNodes: Long,
        announcingTrackers: Boolean,
        announcingDht: Boolean,
        peerCount: Int
    ): String {
        if (metadataKnown) return "metadata_ready"
        if (requestedTrackerCount > 0 && handleTrackerCount <= 0) {
            return "trackers_missing"
        }
        if (!dhtRunning && !announcingTrackers && !announcingDht) {
            return "discovery_inactive"
        }
        if (dhtNodes <= 0L && peerCount <= 0) return "discovery_waiting"
        if (peerCount <= 0) return "peers_missing"
        return "metadata_waiting"
    }

    fun errorBucket(error: Throwable): String {
        val chain = generateSequence(error) { it.cause }
            .take(4)
            .joinToString(" ") { it.javaClass.simpleName }
            .lowercase()
        return when {
            chain.contains("unsatisfiedlink") -> "native_library"
            chain.contains("classnotfound") || chain.contains("noclass") -> "missing_class"
            chain.contains("security") -> "permission"
            else -> "unavailable"
        }
    }

    private fun normalizeTracker(raw: String): String? {
        var value = raw.trim()
        for (prefix in listOf("tracker:", "announce:")) {
            if (value.lowercase().startsWith(prefix)) value = value.substring(prefix.length).trim()
        }
        return try {
            val parsed = URI(value)
            val scheme = parsed.scheme?.lowercase() ?: return null
            if (scheme !in setOf("udp", "http", "https")) return null
            if (parsed.host.isNullOrBlank() || parsed.userInfo != null || parsed.fragment != null) return null
            URI(
                scheme,
                null,
                parsed.host.lowercase(),
                parsed.port,
                parsed.rawPath?.ifBlank { "/" } ?: "/",
                parsed.rawQuery,
                null
            ).toASCIIString()
        } catch (_: Throwable) {
            null
        }
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
}
