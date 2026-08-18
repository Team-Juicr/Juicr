package app.juicr.flutter.update

import java.net.URI

enum class AppUpdateStage(val wireValue: String) {
    IDLE("idle"),
    AVAILABLE("available"),
    DOWNLOADING("downloading"),
    PAUSED("paused"),
    VERIFYING("verifying"),
    READY_TO_INSTALL("readyToInstall"),
    AWAITING_PERMISSION("awaitingPermission"),
    INSTALLING("installing"),
    AWAITING_CONFIRMATION("awaitingConfirmation"),
    INSTALLED("installed"),
    FAILED("failed");

    companion object {
        fun fromWireValue(value: String): AppUpdateStage? = entries.firstOrNull {
            it.wireValue == value
        }
    }
}

enum class AppUpdateFailure(val wireValue: String) {
    NETWORK("network"),
    STORAGE("storage"),
    ASSET_CHANGED("asset_changed"),
    SIZE_MISMATCH("size_mismatch"),
    CHECKSUM_MISMATCH("checksum_mismatch"),
    INVALID_APK("invalid_apk"),
    WRONG_PACKAGE("wrong_package"),
    WRONG_LANE("wrong_lane"),
    NOT_NEWER("not_newer"),
    SIGNER_MISMATCH("signer_mismatch"),
    INSTALL_PERMISSION("install_permission"),
    INSTALL_CANCELLED("install_cancelled"),
    INSTALL_FAILED("install_failed"),
    CANCELLED("cancelled"),
    UNKNOWN("unknown");

    companion object {
        fun fromWireValue(value: String): AppUpdateFailure? = entries.firstOrNull {
            it.wireValue == value
        }
    }
}

data class AppUpdateRequest(
    val releaseTag: String,
    val assetName: String,
    val assetUrl: String,
    val expectedSize: Long,
    val expectedSha256: String,
)

data class AppUpdateSnapshot(
    val stage: AppUpdateStage,
    val releaseTag: String? = null,
    val assetName: String? = null,
    val expectedSize: Long = 0,
    val downloadedBytes: Long = 0,
    val failure: AppUpdateFailure? = null,
) {
    val progressPermille: Int
        get() = if (expectedSize <= 0) {
            0
        } else {
            ((downloadedBytes.coerceIn(0, expectedSize) * 1000L) / expectedSize).toInt()
        }

    fun toPublicMap(): Map<String, Any?> = linkedMapOf(
        "stage" to stage.wireValue,
        "releaseTag" to releaseTag,
        "assetName" to assetName,
        "expectedSize" to expectedSize,
        "downloadedBytes" to downloadedBytes.coerceAtLeast(0),
        "progressPermille" to progressPermille,
        "failure" to failure?.wireValue,
    )
}

object AppUpdateRequestValidator {
    private val hashPattern = Regex("^[0-9a-f]{64}$")
    private val tagPattern = Regex("^[A-Za-z0-9._-]{1,64}$")
    private val abiPattern = "(?:universal|armeabi-v7a|arm64-v8a|x86_64)"

    fun validate(request: AppUpdateRequest, lane: String): AppUpdateFailure? {
        if (lane != "android" && lane != "tv") return AppUpdateFailure.WRONG_LANE
        if (!tagPattern.matches(request.releaseTag)) return AppUpdateFailure.INVALID_APK
        if (request.expectedSize <= 0 || !hashPattern.matches(request.expectedSha256)) {
            return AppUpdateFailure.INVALID_APK
        }

        val expectedName = Regex(
            "^juicr-${Regex.escape(lane)}-${Regex.escape(request.releaseTag)}-$abiPattern\\.apk$",
        )
        if (!expectedName.matches(request.assetName)) {
            val otherLane = if (lane == "android") "tv" else "android"
            val otherPattern = Regex(
                "^juicr-${Regex.escape(otherLane)}-${Regex.escape(request.releaseTag)}-$abiPattern\\.apk$",
            )
            return if (otherPattern.matches(request.assetName)) {
                AppUpdateFailure.WRONG_LANE
            } else {
                AppUpdateFailure.INVALID_APK
            }
        }

        val uri = runCatching { URI(request.assetUrl) }.getOrNull()
            ?: return AppUpdateFailure.INVALID_APK
        val expectedPath = "/Team-Juicr/Juicr/releases/download/${request.releaseTag}/${request.assetName}"
        if (
            uri.scheme != "https" ||
            uri.host != "github.com" ||
            uri.rawPath != expectedPath ||
            uri.rawQuery != null ||
            uri.rawFragment != null ||
            uri.userInfo != null ||
            uri.port != -1
        ) {
            return AppUpdateFailure.INVALID_APK
        }
        return null
    }
}
