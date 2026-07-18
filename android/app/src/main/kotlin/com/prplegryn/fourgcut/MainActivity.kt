package com.prplegryn.fourgcut

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.prplegryn.fourgcut/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideo" -> {
                        val sourcePath = call.argument<String>("path")
                        val displayName = call.argument<String>("name")
                        if (sourcePath == null || displayName == null) {
                            result.error("invalid_arguments", "缺少导出文件信息", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveVideo(File(sourcePath), displayName))
                        } catch (error: Exception) {
                            CrashLogStore.append(this, "save-video", error.stackTraceToString(), publish = true)
                            result.error("save_failed", error.message ?: "保存失败", null)
                        }
                    }
                    "writeCrashLog" -> {
                        val category = call.argument<String>("category") ?: "dart"
                        val details = call.argument<String>("details") ?: "未知错误"
                        try {
                            result.success(CrashLogStore.append(this, category, details, publish = true))
                        } catch (error: Exception) {
                            result.error("log_failed", error.message ?: "日志写入失败", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveVideo(source: File, displayName: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/4GCut")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: error("无法创建媒体文件")
            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                } ?: error("无法写入媒体文件")
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
                return uri.toString()
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                throw error
            }
        }

        val directory = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            "4GCut",
        ).apply { mkdirs() }
        val target = File(directory, displayName)
        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        return target.absolutePath
    }
}
