package app.juicr.flutter.update

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

data class ApkArchiveIdentity(
    val packageName: String,
    val lane: String?,
    val versionName: String?,
    val versionCode: Long,
    val signerSha256: Set<String>,
)

data class InstalledAppIdentity(
    val versionCode: Long,
    val signerSha256: Set<String>,
)

interface ApkInspector {
    fun inspectArchive(file: File): ApkArchiveIdentity?
    fun inspectInstalled(packageName: String): InstalledAppIdentity?
}

interface UpdateVerifierGateway {
    fun verify(request: AppUpdateRequest, file: File): AppUpdateFailure?
}

class UpdateVerifier(
    private val lane: String,
    private val expectedPackageName: String,
    private val inspector: ApkInspector,
) : UpdateVerifierGateway {
    override fun verify(request: AppUpdateRequest, file: File): AppUpdateFailure? {
        if (!file.isFile || file.length() != request.expectedSize) {
            return AppUpdateFailure.SIZE_MISMATCH
        }
        if (sha256(file) != request.expectedSha256) {
            return AppUpdateFailure.CHECKSUM_MISMATCH
        }
        val archive = inspector.inspectArchive(file) ?: return AppUpdateFailure.INVALID_APK
        if (archive.packageName != expectedPackageName) return AppUpdateFailure.WRONG_PACKAGE
        if (archive.lane != lane) return AppUpdateFailure.WRONG_LANE
        if (archive.versionName != request.releaseTag.removePrefix("v")) {
            return AppUpdateFailure.INVALID_APK
        }
        val installed = inspector.inspectInstalled(expectedPackageName)
            ?: return AppUpdateFailure.INVALID_APK
        if (archive.versionCode <= installed.versionCode) return AppUpdateFailure.NOT_NEWER
        if (
            archive.signerSha256.isEmpty() ||
            installed.signerSha256.isEmpty() ||
            archive.signerSha256 != installed.signerSha256
        ) {
            return AppUpdateFailure.SIGNER_MISMATCH
        }
        return null
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().toHex()
    }
}

class AndroidApkInspector(private val context: Context) : ApkInspector {
    private val packageManager = context.packageManager

    override fun inspectArchive(file: File): ApkArchiveIdentity? {
        val packageInfo = archivePackageInfo(file) ?: return null
        val applicationInfo = packageInfo.applicationInfo ?: return null
        applicationInfo.sourceDir = file.absolutePath
        applicationInfo.publicSourceDir = file.absolutePath
        return ApkArchiveIdentity(
            packageName = packageInfo.packageName,
            lane = applicationInfo.metaData?.getString(UPDATE_LANE_METADATA),
            versionName = packageInfo.versionName,
            versionCode = packageInfo.longVersionCodeCompat(),
            signerSha256 = packageInfo.signerDigests(),
        )
    }

    override fun inspectInstalled(packageName: String): InstalledAppIdentity? {
        val packageInfo = installedPackageInfo(packageName) ?: return null
        return InstalledAppIdentity(
            versionCode = packageInfo.longVersionCodeCompat(),
            signerSha256 = packageInfo.signerDigests(),
        )
    }

    @Suppress("DEPRECATION")
    private fun archivePackageInfo(file: File): PackageInfo? {
        val flags = packageInfoFlagsForSdk(Build.VERSION.SDK_INT, includeMetadata = true)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageArchiveInfo(
                file.absolutePath,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            packageManager.getPackageArchiveInfo(file.absolutePath, flags)
        }
    }

    @Suppress("DEPRECATION")
    private fun installedPackageInfo(packageName: String): PackageInfo? = runCatching {
        val flags = packageInfoFlagsForSdk(Build.VERSION.SDK_INT, includeMetadata = false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(flags.toLong()),
            )
        } else {
            packageManager.getPackageInfo(packageName, flags)
        }
    }.getOrNull()

    @Suppress("DEPRECATION")
    private fun PackageInfo.signerDigests(): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            signingInfo?.apkContentsSigners.orEmpty()
        } else {
            signatures.orEmpty()
        }
        return signatures.mapTo(linkedSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).toHex()
        }
    }

    @Suppress("DEPRECATION")
    private fun PackageInfo.longVersionCodeCompat(): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) longVersionCode else versionCode.toLong()

    companion object {
        const val UPDATE_LANE_METADATA = "app.juicr.update.LANE"
    }
}

@Suppress("DEPRECATION")
internal fun packageInfoFlagsForSdk(sdkInt: Int, includeMetadata: Boolean): Int {
    val signatureFlag = if (sdkInt >= Build.VERSION_CODES.P) {
        PackageManager.GET_SIGNING_CERTIFICATES
    } else {
        PackageManager.GET_SIGNATURES
    }
    return signatureFlag or if (includeMetadata) PackageManager.GET_META_DATA else 0
}

private fun ByteArray.toHex(): String = joinToString("") { byte -> "%02x".format(byte) }
