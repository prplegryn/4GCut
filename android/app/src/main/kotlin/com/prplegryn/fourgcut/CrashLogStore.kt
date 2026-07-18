package com.prplegryn.fourgcut

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object CrashLogStore {
    private val lock = Any()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val fileDateFormat = SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US)

    fun install(context: Context) {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            try {
                append(
                    context,
                    "native-fatal",
                    "thread=${thread.name}\n${Log.getStackTraceString(throwable)}",
                    publish = true,
                )
            } catch (_: Exception) {
                // Never prevent Android from completing its normal crash handling.
            }
            previous?.uncaughtException(thread, throwable)
        }
    }

    fun append(context: Context, category: String, details: String, publish: Boolean): String {
        synchronized(lock) {
            val logDirectory = (context.getExternalFilesDir("logs")
                ?: File(context.filesDir, "logs")).apply { mkdirs() }
            val logFile = File(logDirectory, "4gcut-crash.log")
            val stamp = synchronized(dateFormat) { dateFormat.format(Date()) }
            FileOutputStream(logFile, true).bufferedWriter().use { writer ->
                writer.appendLine("[$stamp] [$category]")
                writer.appendLine(details)
                writer.appendLine("\n---\n")
            }
            if (publish) publishCopy(context, logFile)
            return logFile.absolutePath
        }
    }

    private fun publishCopy(context: Context, source: File) {
        val filename = "4GCut-crash-${synchronized(fileDateFormat) { fileDateFormat.format(Date()) }}.log"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, "${Environment.DIRECTORY_DOCUMENTS}/4GCut/logs")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return
            try {
                context.contentResolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
            } catch (_: Exception) {
                context.contentResolver.delete(uri, null, null)
            }
            return
        }

        val publicDirectory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
            "4GCut/logs",
        ).apply { mkdirs() }
        try {
            FileInputStream(source).use { input ->
                FileOutputStream(File(publicDirectory, filename)).use { output -> input.copyTo(output) }
            }
        } catch (_: Exception) {
            // The private external log remains available if legacy storage is denied.
        }
    }
}
