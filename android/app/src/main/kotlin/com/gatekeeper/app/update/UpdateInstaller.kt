package com.gatekeeper.app.update

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class UpdateException(message: String) : Exception(message)

/**
 * Self-update from this app's GitHub Releases.
 *
 * Safety checks before the system installer is opened:
 *  - the URL must be a release download of the GateKeeper repository (HTTPS only);
 *  - the SHA-256 published by GitHub must match (when provided);
 *  - the APK must have our package name, a higher version code, and the same signing certificate
 *    as the installed app (Android enforces this too; checking first gives a clear error).
 * The user always confirms the installation in the system dialog.
 */
class UpdateInstaller(context: Context) {
    private val app = context.applicationContext
    private val dir = File(app.cacheDir, "updates")

    fun canInstallPackages(): Boolean = app.packageManager.canRequestPackageInstalls()

    fun openInstallPermissionSettings(context: Context) {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    suspend fun downloadAndInstall(
        context: Context,
        url: String,
        fileName: String,
        sha256: String?,
        onProgress: (Long, Long) -> Unit,
    ): String {
        if (!url.startsWith(ALLOWED_PREFIX)) throw UpdateException("Refusing to download from an unexpected location")
        if (!FILE_NAME.matches(fileName)) throw UpdateException("Unexpected file name")
        val file = File(dir, fileName)
        val expected = sha256?.lowercase()?.removePrefix("sha256:")
        val cachedOk = file.exists() && expected != null && sha256Of(file) == expected
        if (!cachedOk) download(url, file, onProgress)
        if (expected != null && sha256Of(file) != expected) {
            file.delete()
            throw UpdateException("Checksum mismatch: download corrupted or tampered with")
        }
        verifyApk(file)
        if (!canInstallPackages()) return "needs_permission"
        val uri = FileProvider.getUriForFile(app, "${app.packageName}.updates", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return "installer_opened"
    }

    private suspend fun download(url: String, target: File, onProgress: (Long, Long) -> Unit) = withContext(Dispatchers.IO) {
        dir.mkdirs()
        dir.listFiles()?.forEach { it.delete() } // keep only one update file
        val tmp = File(dir, target.name + ".part")
        var current = URL(url)
        var redirects = 0
        while (true) {
            val conn = current.openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 20_000
            conn.readTimeout = 30_000
            conn.setRequestProperty("User-Agent", "GateKeeper-Android")
            conn.setRequestProperty("Accept", "application/octet-stream")
            when (val code = conn.responseCode) {
                in 300..399 -> {
                    val location = conn.getHeaderField("Location") ?: throw UpdateException("Redirect without location")
                    conn.disconnect()
                    current = URL(current, location)
                    if (current.protocol != "https") throw UpdateException("Refusing non-HTTPS redirect")
                    if (++redirects > 5) throw UpdateException("Too many redirects")
                }
                200 -> {
                    val total = conn.contentLengthLong
                    conn.inputStream.use { input ->
                        tmp.outputStream().use { out ->
                            val buf = ByteArray(64 * 1024)
                            var received = 0L
                            var lastReport = 0L
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                received += n
                                if (received - lastReport > 256 * 1024 || received == total) {
                                    lastReport = received
                                    onProgress(received, total)
                                }
                                if (received > MAX_BYTES) throw UpdateException("Download too large")
                            }
                        }
                    }
                    conn.disconnect()
                    if (!tmp.renameTo(target)) throw UpdateException("Could not save the update")
                    return@withContext
                }
                else -> {
                    conn.disconnect()
                    throw UpdateException("Download failed (HTTP $code)")
                }
            }
        }
    }

    private fun verifyApk(file: File) {
        val pm = app.packageManager
        val flags = PackageManager.GET_SIGNING_CERTIFICATES
        val archive: PackageInfo = pm.getPackageArchiveInfo(file.path, flags)
            ?: throw UpdateException("Downloaded file is not a valid APK").also { file.delete() }
        if (archive.packageName != app.packageName) {
            file.delete()
            throw UpdateException("APK is for a different app")
        }
        val installed = pm.getPackageInfo(app.packageName, flags)
        if (archive.longVersionCode <= installed.longVersionCode) {
            throw UpdateException("The downloaded version is not newer than the installed one")
        }
        val newSigners = archive.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet().orEmpty()
        val ourSigners = installed.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet().orEmpty()
        if (newSigners.isEmpty() || newSigners != ourSigners) {
            file.delete()
            throw UpdateException(
                "The update is signed with a different key than this installation " +
                    "(e.g. a debug build). Uninstall and install the release APK manually.",
            )
        }
    }

    private fun sha256Of(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    companion object {
        const val REPOSITORY = "SanuSanal/gatekeeper"
        private const val ALLOWED_PREFIX = "https://github.com/$REPOSITORY/releases/download/"
        private val FILE_NAME = Regex("^gatekeeper-[0-9]+\\.[0-9]+\\.[0-9]+-[a-z0-9_]+(-[a-z0-9_]+)*\\.apk$")
        private const val MAX_BYTES = 300L * 1024 * 1024
    }
}
