package app.juicr.flutter.update

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient

object UpdateBridgeRequestParser {
    private val exactKeys = setOf(
        "releaseTag",
        "assetName",
        "assetUrl",
        "expectedSize",
        "sha256",
    )

    fun parse(arguments: Any?): AppUpdateRequest? {
        val map = arguments as? Map<*, *> ?: return null
        if (map.keys != exactKeys) return null
        val releaseTag = map["releaseTag"] as? String ?: return null
        val assetName = map["assetName"] as? String ?: return null
        val assetUrl = map["assetUrl"] as? String ?: return null
        val expectedSize = (map["expectedSize"] as? Number)?.toLong() ?: return null
        val sha256 = map["sha256"] as? String ?: return null
        return AppUpdateRequest(releaseTag, assetName, assetUrl, expectedSize, sha256)
    }
}

class UpdateBridge(
    private val context: Context,
    messenger: BinaryMessenger,
    private val lane: String,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "juicr-app-update").apply { isDaemon = true }
    }
    private val rootDirectory = File(context.noBackupFilesDir, "app-updates")
    private val installResultStore = UpdateInstallResultStore(rootDirectory)
    private val stateStore = UpdateStateStore(rootDirectory) { request ->
        AppUpdateRequestValidator.validate(request, lane) == null
    }
    private val installer = UpdateInstaller(AndroidInstallPlatform(context))
    private val coordinator = UpdateCoordinator(
        lane = lane,
        rootDirectory = rootDirectory,
        stateStore = stateStore,
        transfer = UpdateDownloadOwner(
            OkHttpClient.Builder()
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(45, TimeUnit.SECONDS)
                .callTimeout(30, TimeUnit.MINUTES)
                .build(),
            rootDirectory,
            stateStore,
        ),
        verifier = UpdateVerifier(lane, context.packageName, AndroidApkInspector(context)),
        installer = installer,
        taskRunner = UpdateTaskRunner { task -> executor.execute(task) },
    )
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    @Volatile private var eventSink: EventChannel.EventSink? = null
    private val snapshotListener: (AppUpdateSnapshot) -> Unit = { value ->
        mainHandler.post { eventSink?.success(value.toPublicMap()) }
    }
    private val installStatusListener: (Long, InstallStatus) -> Unit = { generation, status ->
        coordinator.acceptInstallStatus(generation, status)
        installResultStore.consume()
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        coordinator.addListener(snapshotListener)
        UpdateInstallStatusBus.attach(installStatusListener)
        installResultStore.consume()?.let { result ->
            coordinator.acceptInstallStatus(result.generation, result.status)
        }
        coordinator.reconcileRestoredInstall()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "snapshot" -> result.success(coordinator.snapshot.toPublicMap())
            "platformInfo" -> result.success(
                linkedMapOf(
                    "sdkInt" to Build.VERSION.SDK_INT,
                    "abis" to Build.SUPPORTED_ABIS.toList(),
                    "canInstallPackages" to installerCanRequestPackages(),
                    "lane" to lane,
                ),
            )
            "start" -> {
                val request = UpdateBridgeRequestParser.parse(call.arguments)
                if (request == null) {
                    result.error("invalid_request", "Invalid update request.", null)
                    return
                }
                coordinator.start(request)
                result.success(coordinator.snapshot.toPublicMap())
            }
            "pause" -> acknowledge(result) { coordinator.pause() }
            "resume" -> acknowledge(result) { coordinator.resume() }
            "cancel" -> acknowledge(result) { coordinator.cancel() }
            "deleteDownload" -> acknowledge(result) { coordinator.deleteDownload() }
            "install" -> acknowledge(result) { coordinator.install() }
            "openInstallPermissionSettings" -> acknowledge(result) {
                coordinator.openInstallPermissionSettings()
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        events?.success(coordinator.snapshot.toPublicMap())
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun onHostResume() {
        coordinator.refreshInstallPermission()
        installResultStore.consume()?.let { result ->
            coordinator.acceptInstallStatus(result.generation, result.status)
        }
        coordinator.reconcileRestoredInstall()
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        UpdateInstallStatusBus.detach(installStatusListener)
        coordinator.removeListener(snapshotListener)
        coordinator.dispose()
        executor.shutdownNow()
        eventSink = null
    }

    private fun acknowledge(result: MethodChannel.Result, action: () -> Unit) {
        action()
        result.success(coordinator.snapshot.toPublicMap())
    }

    private fun installerCanRequestPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            context.packageManager.canRequestPackageInstalls()

    companion object {
        const val METHOD_CHANNEL = "app.juicr.flutter/app_update"
        const val EVENT_CHANNEL = "app.juicr.flutter/app_update_events"
        val SUPPORTED_METHODS = setOf(
            "snapshot",
            "platformInfo",
            "start",
            "pause",
            "resume",
            "cancel",
            "deleteDownload",
            "install",
            "openInstallPermissionSettings",
        )
    }
}
