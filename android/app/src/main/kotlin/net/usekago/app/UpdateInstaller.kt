package net.usekago.app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.provider.Settings
import java.io.File
import java.io.FileNotFoundException

/**
 * In-app update: the APK downloaded by the app (cache/updates/) is handed to
 * the system package installer. Android installs it over the current version
 * only if it is signed with the same key, so a tampered file is rejected.
 */
object UpdateInstaller {
    private const val MIME = "application/vnd.android.package-archive"

    fun updatesDir(context: Context) = File(context.cacheDir, "updates")

    /** "started", or "permission" when "Install unknown apps" must be allowed first. */
    fun install(context: Context, path: String): String {
        val file = File(path).canonicalFile
        val dir = updatesDir(context).canonicalFile
        require(file.parentFile == dir && file.name.endsWith(".apk") && file.isFile) {
            "Update file is outside the updates folder"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            context.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "permission"
        }
        val uri = UpdateFileProvider.uriFor(context, file.name)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        // Only the system package installer gets the file: an app that
        // registered for APKs could otherwise pose as the installer.
        @Suppress("DEPRECATION")
        val installer = context.packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_SYSTEM_ONLY)
            .firstOrNull()?.activityInfo?.packageName
        if (installer != null) intent.setPackage(installer)
        context.startActivity(intent)
        return "started"
    }
}

/**
 * Read-only provider for the downloaded APK (a minimal FileProvider without
 * the androidx dependency): content://<applicationId>.updates/<file name>,
 * only files directly inside cache/updates/.
 */
class UpdateFileProvider : ContentProvider() {
    companion object {
        fun uriFor(context: Context, name: String): Uri =
            Uri.parse("content://${context.packageName}.updates/${Uri.encode(name)}")
    }

    private fun fileFor(uri: Uri): File {
        val context = context ?: throw FileNotFoundException()
        val name = uri.lastPathSegment ?: throw FileNotFoundException()
        val dir = UpdateInstaller.updatesDir(context).canonicalFile
        val file = File(dir, name).canonicalFile
        if (file.parentFile != dir || !file.isFile) throw FileNotFoundException(name)
        return file
    }

    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("read-only")
        return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri) = "application/vnd.android.package-archive"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val file = fileFor(uri)
        val columns: Array<String> = projection?.map { it }?.toTypedArray()
            ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val cursor = MatrixCursor(columns)
        cursor.addRow(
            columns.map {
                when (it) {
                    OpenableColumns.DISPLAY_NAME -> file.name
                    OpenableColumns.SIZE -> file.length()
                    else -> null
                }
            },
        )
        return cursor
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ) = 0
}
