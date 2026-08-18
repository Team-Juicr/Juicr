package app.juicr.flutter

import java.io.File
import java.nio.file.Files

object P2pRuntimeBridgeP2pTest {
    @JvmStatic
    fun main(args: Array<String>) {
        runtimeRequiresBuildFlagAndAllNativeProbes()
        normalizesAndFiltersTrackersWithoutLeakingInputs()
        validatesRequestedMediaAndFallsBackToLargestSupportedFile()
        containsEveryResolvedPathUnderTheTvCacheRoot()
        usesNeutralGenerationCacheDirectories()
        createsOnlyOpaqueLoopbackSessionUrls()
        boundsReadinessRetries()
        preservesNewerGenerationWhenAnOlderOwnerStops()
        discardsOnlyFailedReplacementGenerationForRollback()
        sharedTokenRollbackRetainsOlderGeneration()
        removesCanceledHandleWhenMetadataAppearsLater()
        cancellationAfterFindCannotAdoptHandle()
        staleWorkerCannotUseReplacementManager()
        sameHashReplacementRetainsSharedHandle()
        sameHashReplacementRetainsSharedStorage()
        cancellationAfterFinalProbeKeepsCleanupOwner()
        cancellationTransactionClaimsExactlyOneManagerBoundOwner()
        pollCannotTouchStaleManagerOrCompeteWithCleanupOwner()
        pendingCleanupStorageCannotBePruned()
        candidateRollbackRetainsWarmRuntimeUntilRouteClose()
        routeCloseClosesAcceptedSockets()
        exposesOnlyNeutralDiagnosticFields()
        exposesOnlyFixedAvailabilityFailureFields()
        classifiesOnlyNeutralReadinessStages()
        classifiesOnlyNeutralMetadataDiscoveryStages()
        println("P2pRuntimeBridgeP2pTest passed")
    }

    private fun runtimeRequiresBuildFlagAndAllNativeProbes() {
        check(!P2pRuntimePolicy.runtimeAvailable(false, true) { true })
        check(!P2pRuntimePolicy.runtimeAvailable(true, false) { true })
        check(!P2pRuntimePolicy.runtimeAvailable(true, true) { false })
        check(P2pRuntimePolicy.runtimeAvailable(true, true) { true })
    }

    private fun normalizesAndFiltersTrackersWithoutLeakingInputs() {
        val normalized = P2pRuntimePolicy.normalizeTrackers(
            listOf(
                " tracker: UDP://Tracker.Example:80/announce ",
                "udp://tracker.example:80/announce",
                "announce: https://OK.example/path",
                "https://ok.example/path",
                "ftp://blocked.example/path",
                "https://user:secret@blocked.example/path",
                "not a tracker"
            )
        )
        check(
            normalized == listOf(
                "udp://tracker.example:80/announce",
                "https://ok.example/path"
            )
        ) { "unexpected normalized tracker set" }
    }

    private fun validatesRequestedMediaAndFallsBackToLargestSupportedFile() {
        val files = listOf(
            P2pFileCandidate(0, "notes.txt", 9000),
            P2pFileCandidate(1, "small.mp4", 100),
            P2pFileCandidate(2, "feature.MKV", 500),
            P2pFileCandidate(3, "empty.webm", 0)
        )
        check(P2pRuntimePolicy.selectMediaFile(files, 1)?.index == 1)
        check(P2pRuntimePolicy.selectMediaFile(files, 0)?.index == 2)
        check(P2pRuntimePolicy.selectMediaFile(files, 99)?.index == 2)
        check(P2pRuntimePolicy.selectMediaFile(files, 3)?.index == 2)
        check(P2pRuntimePolicy.selectMediaFile(files.take(1), null) == null)
    }

    private fun containsEveryResolvedPathUnderTheTvCacheRoot() {
        val root = Files.createTempDirectory("juicr-tv-p2p-test").toFile()
        try {
            val nested = P2pRuntimePolicy.containedFile(root, "session/video.mp4")
            check(nested != null && nested.canonicalPath.startsWith(root.canonicalPath + File.separator))
            check(P2pRuntimePolicy.containedFile(root, "../outside.mp4") == null)
            check(P2pRuntimePolicy.containedFile(root, File(root.parentFile, "outside.mp4").path) == null)
        } finally {
            root.deleteRecursively()
        }
    }

    private fun createsOnlyOpaqueLoopbackSessionUrls() {
        val url = P2pRuntimePolicy.loopbackUrl(49152, "6f3c7a04-8b3e-4dfa-a1aa-2c581e288f41")
        check(url == "http://127.0.0.1:49152/stream/6f3c7a04-8b3e-4dfa-a1aa-2c581e288f41")
        check(P2pRuntimePolicy.loopbackUrl(0, "6f3c7a04-8b3e-4dfa-a1aa-2c581e288f41") == null)
        check(P2pRuntimePolicy.loopbackUrl(49152, "../descriptor") == null)
    }

    private fun usesNeutralGenerationCacheDirectories() {
        val root = File("cache-root")
        check(
            P2pRuntimePolicy.sessionCacheDirectory(root, 42)?.canonicalPath ==
                File(root, "session-42").canonicalPath
        )
        check(P2pRuntimePolicy.sessionCacheDirectory(root, 0) == null)
    }

    private fun boundsReadinessRetries() {
        var probes = 0
        val result = P2pReadiness.await(maxAttempts = 4, delayMs = 0, sleep = {}) {
            probes += 1
            probes == 3
        }
        check(result.ready)
        check(result.attempts == 3)
        check(probes == 3)

        probes = 0
        val unavailable = P2pReadiness.await(maxAttempts = 2, delayMs = 0, sleep = {}) {
            probes += 1
            false
        }
        check(!unavailable.ready)
        check(unavailable.attempts == 2)
        check(probes == 2)
    }

    private fun preservesNewerGenerationWhenAnOlderOwnerStops() {
        val ownership = P2pSessionOwnership()
        ownership.register("old", 7)
        ownership.register("new", 8)
        check(ownership.removeOwnedThrough(7) == setOf("old"))
        check(ownership.activeTokens() == setOf("new"))
        check(ownership.removeOwnedThrough(null) == setOf("new"))
        check(ownership.activeTokens().isEmpty())
    }

    private fun discardsOnlyFailedReplacementGenerationForRollback() {
        val ownership = P2pSessionOwnership()
        ownership.register("active", 12)
        ownership.register("replacement", 13)
        check(ownership.removeOwnedGeneration(13) == setOf("replacement"))
        check(ownership.activeTokens() == setOf("active"))
    }

    private fun sharedTokenRollbackRetainsOlderGeneration() {
        val ownership = P2pSessionOwnership()
        ownership.register("shared", 12)
        ownership.register("shared", 13)

        check(ownership.removeOwnedGeneration(13).isEmpty())
        check(ownership.activeTokens() == setOf("shared"))
        check(ownership.owns("shared", 12))
        check(!ownership.owns("shared", 13))
        check(ownership.removeOwnedThrough(12) == setOf("shared"))
        check(ownership.activeTokens().isEmpty())
    }

    private fun removesCanceledHandleWhenMetadataAppearsLater() {
        var attempts = 0
        var removed: Any? = null
        val settled = P2pDeferredRemoval.await(
            maxAttempts = 4,
            delayMs = 0,
            sleep = {},
            findHandle = {
                attempts += 1
                if (attempts == 3) "late-handle" else null
            },
            removeHandle = { handle -> removed = handle }
        )

        check(settled)
        check(attempts == 3)
        check(removed == "late-handle")
    }

    private fun cancellationAfterFindCannotAdoptHandle() {
        check(
            P2pNativeOwnership.afterFind(
                cancelled = true,
                tokenCurrent = false,
                managerCurrent = true,
                sameHashRetained = false
            ) == P2pHandleDisposition.REMOVE
        )
    }

    private fun staleWorkerCannotUseReplacementManager() {
        check(
            !P2pNativeOwnership.mayStartDownload(
                cancelled = false,
                tokenCurrent = true,
                managerCurrent = false
            )
        )
        check(
            P2pNativeOwnership.afterFind(
                cancelled = true,
                tokenCurrent = false,
                managerCurrent = false,
                sameHashRetained = false
            ) == P2pHandleDisposition.IGNORE
        )
    }

    private fun sameHashReplacementRetainsSharedHandle() {
        check(
            P2pNativeOwnership.afterFind(
                cancelled = true,
                tokenCurrent = false,
                managerCurrent = true,
                sameHashRetained = true
            ) == P2pHandleDisposition.IGNORE
        )
    }

    private fun sameHashReplacementRetainsSharedStorage() {
        check(
            !P2pStorageOwnership.mayDeleteSessionDirectory(
                sameHashRetained = true,
                directoryRetainedBySession = false
            )
        )
        check(
            !P2pStorageOwnership.mayDeleteSessionDirectory(
                sameHashRetained = false,
                directoryRetainedBySession = true
            )
        )
        check(
            P2pStorageOwnership.mayDeleteSessionDirectory(
                sameHashRetained = false,
                directoryRetainedBySession = false
            )
        )
    }

    private fun cancellationAfterFinalProbeKeepsCleanupOwner() {
        var cleanupAttempts = 0
        var removed: Any? = null
        val settled = P2pCancellationCleanup.afterProbe(
            cancelled = true,
            maxAttempts = 3,
            delayMs = 0,
            sleep = {},
            findHandle = {
                cleanupAttempts += 1
                if (cleanupAttempts == 3) "late-final-handle" else null
            },
            removeHandle = { handle -> removed = handle }
        )

        check(settled)
        check(cleanupAttempts == 3)
        check(removed == "late-final-handle")
    }

    private fun cancellationTransactionClaimsExactlyOneManagerBoundOwner() {
        check(
            P2pCancellationOwnership.shouldSchedule(
                cancelled = true,
                cleanupScheduled = false,
                managerCurrent = true,
                downloadStarted = true,
                handleKnown = false
            )
        )
        check(
            !P2pCancellationOwnership.shouldSchedule(
                cancelled = true,
                cleanupScheduled = true,
                managerCurrent = true,
                downloadStarted = true,
                handleKnown = false
            )
        )
        check(
            !P2pCancellationOwnership.shouldSchedule(
                cancelled = true,
                cleanupScheduled = false,
                managerCurrent = false,
                downloadStarted = true,
                handleKnown = false
            )
        )
        check(
            !P2pCancellationOwnership.shouldSchedule(
                cancelled = true,
                cleanupScheduled = false,
                managerCurrent = true,
                downloadStarted = true,
                handleKnown = true
            )
        )
    }

    private fun pollCannotTouchStaleManagerOrCompeteWithCleanupOwner() {
        check(
            P2pPollOwnership.mayFind(
                cancelled = false,
                tokenCurrent = true,
                managerCurrent = true,
                cleanupScheduled = false
            )
        )
        check(
            !P2pPollOwnership.mayFind(
                cancelled = false,
                tokenCurrent = true,
                managerCurrent = false,
                cleanupScheduled = false
            )
        )
        check(
            !P2pPollOwnership.mayFind(
                cancelled = true,
                tokenCurrent = false,
                managerCurrent = true,
                cleanupScheduled = true
            )
        )
        check(!P2pPollOwnership.maySettle(cleanupScheduled = true))
        check(P2pPollOwnership.maySettle(cleanupScheduled = false))
    }

    private fun pendingCleanupStorageCannotBePruned() {
        check(
            !P2pStorageOwnership.mayPruneDirectory(
                active = false,
                pendingCleanup = true,
                explicitlyKept = false
            )
        )
        check(
            !P2pStorageOwnership.mayPruneDirectory(
                active = true,
                pendingCleanup = false,
                explicitlyKept = false
            )
        )
        check(
            P2pStorageOwnership.mayPruneDirectory(
                active = false,
                pendingCleanup = false,
                explicitlyKept = false
            )
        )
    }

    private fun candidateRollbackRetainsWarmRuntimeUntilRouteClose() {
        check(
            !P2pRuntimeLifecycle.shouldStopRuntime(
                routeClosing = false,
                sessionsRemain = false
            )
        )
        check(
            !P2pRuntimeLifecycle.shouldStopRuntime(
                routeClosing = true,
                sessionsRemain = true
            )
        )
        check(
            P2pRuntimeLifecycle.shouldStopRuntime(
                routeClosing = true,
                sessionsRemain = false
            )
        )
    }

    private fun routeCloseClosesAcceptedSockets() {
        val socket = java.net.Socket()
        val registry = P2pAcceptedSocketRegistry()
        val firstRoute = registry.reopen()
        registry.track(socket, firstRoute)
        check(registry.activeCount == 1)
        registry.closeAll()
        check(socket.isClosed)
        check(registry.activeCount == 0)
        val racedSocket = java.net.Socket()
        registry.track(racedSocket, firstRoute)
        check(racedSocket.isClosed)
        check(registry.activeCount == 0)
        val nextRoute = registry.reopen()
        val delayedOldRouteSocket = java.net.Socket()
        registry.track(delayedOldRouteSocket, firstRoute)
        check(delayedOldRouteSocket.isClosed)
        check(registry.activeCount == 0)
        val nextRouteSocket = java.net.Socket()
        registry.track(nextRouteSocket, nextRoute)
        check(!nextRouteSocket.isClosed)
        registry.closeAll()
        check(nextRouteSocket.isClosed)
    }

    private fun exposesOnlyNeutralDiagnosticFields() {
        val diagnostic = P2pRuntimePolicy.diagnosticBucket(
            stage = "readiness",
            outcome = "retry",
            attempts = 2,
            ready = false
        )
        check(diagnostic == mapOf(
            "stage" to "readiness",
            "outcome" to "retry",
            "attempts" to 2,
            "ready" to false
        ))
    }

    private fun exposesOnlyFixedAvailabilityFailureFields() {
        check(
            P2pRuntimePolicy.availabilityStatus(
                false,
                "stage_swig_jni_loader:UnsatisfiedLinkError:native_library:missing_symbol"
            ) == mapOf("available" to false, "stage" to "swig_jni_loader", "bucket" to "native_library")
        )
        check(
            P2pRuntimePolicy.availabilityStatus(false, "private unexpected text") ==
                mapOf("available" to false, "stage" to "unknown", "bucket" to "unavailable")
        )
        check(
            P2pRuntimePolicy.availabilityStatus(true, null) ==
                mapOf("available" to true, "stage" to "ready", "bucket" to "available")
        )
    }

    private fun classifiesOnlyNeutralReadinessStages() {
        check(P2pRuntimePolicy.readinessStage(
            failed = true,
            downloadStarted = true,
            handleSeen = true,
            metadataKnown = true,
            selectedFile = true,
            peerCount = 1,
            firstPiecesReady = 1,
            ready = false
        ) == "failed")
        check(P2pRuntimePolicy.readinessStage(
            failed = false,
            downloadStarted = true,
            handleSeen = false,
            metadataKnown = false,
            selectedFile = false,
            peerCount = 0,
            firstPiecesReady = 0,
            ready = false
        ) == "handle")
        check(P2pRuntimePolicy.readinessStage(
            failed = false,
            downloadStarted = true,
            handleSeen = true,
            metadataKnown = false,
            selectedFile = false,
            peerCount = 0,
            firstPiecesReady = 0,
            ready = false
        ) == "metadata")
        check(P2pRuntimePolicy.readinessStage(
            failed = false,
            downloadStarted = true,
            handleSeen = true,
            metadataKnown = true,
            selectedFile = false,
            peerCount = 0,
            firstPiecesReady = 0,
            ready = false
        ) == "file")
        check(P2pRuntimePolicy.readinessStage(
            failed = false,
            downloadStarted = true,
            handleSeen = true,
            metadataKnown = true,
            selectedFile = true,
            peerCount = 0,
            firstPiecesReady = 0,
            ready = false
        ) == "peers")
        check(P2pRuntimePolicy.readinessStage(
            failed = false,
            downloadStarted = true,
            handleSeen = true,
            metadataKnown = true,
            selectedFile = true,
            peerCount = 1,
            firstPiecesReady = 0,
            ready = false
        ) == "pieces")
        check(P2pRuntimePolicy.readinessStage(
            failed = false,
            downloadStarted = true,
            handleSeen = true,
            metadataKnown = true,
            selectedFile = true,
            peerCount = 1,
            firstPiecesReady = 1,
            ready = true
        ) == "ready")
    }

    private fun classifiesOnlyNeutralMetadataDiscoveryStages() {
        check(P2pRuntimePolicy.metadataDiscoveryStage(
            metadataKnown = true,
            requestedTrackerCount = 4,
            handleTrackerCount = 4,
            dhtRunning = true,
            dhtNodes = 12,
            announcingTrackers = true,
            announcingDht = true,
            peerCount = 2
        ) == "metadata_ready")
        check(P2pRuntimePolicy.metadataDiscoveryStage(
            metadataKnown = false,
            requestedTrackerCount = 4,
            handleTrackerCount = 0,
            dhtRunning = true,
            dhtNodes = 12,
            announcingTrackers = false,
            announcingDht = true,
            peerCount = 0
        ) == "trackers_missing")
        check(P2pRuntimePolicy.metadataDiscoveryStage(
            metadataKnown = false,
            requestedTrackerCount = 4,
            handleTrackerCount = 4,
            dhtRunning = false,
            dhtNodes = 0,
            announcingTrackers = false,
            announcingDht = false,
            peerCount = 0
        ) == "discovery_inactive")
        check(P2pRuntimePolicy.metadataDiscoveryStage(
            metadataKnown = false,
            requestedTrackerCount = 4,
            handleTrackerCount = 4,
            dhtRunning = true,
            dhtNodes = 0,
            announcingTrackers = true,
            announcingDht = true,
            peerCount = 0
        ) == "discovery_waiting")
        check(P2pRuntimePolicy.metadataDiscoveryStage(
            metadataKnown = false,
            requestedTrackerCount = 4,
            handleTrackerCount = 4,
            dhtRunning = true,
            dhtNodes = 12,
            announcingTrackers = true,
            announcingDht = true,
            peerCount = 0
        ) == "peers_missing")
        check(P2pRuntimePolicy.metadataDiscoveryStage(
            metadataKnown = false,
            requestedTrackerCount = 4,
            handleTrackerCount = 4,
            dhtRunning = true,
            dhtNodes = 12,
            announcingTrackers = true,
            announcingDht = true,
            peerCount = 2
        ) == "metadata_waiting")
    }
}
