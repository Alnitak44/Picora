package io.github.alnitak44.picora

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.security.MessageDigest

class MainActivity: FlutterActivity() {
    private val pickCode = 0x504d
    private val saveCode = 0x504e
    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null
    private val sourceLimit = 10 * 1024 * 1024
    private val outputLimit = 20 * 1024 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "io.github.alnitak44.picora/documents").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickMarkdown" -> {
                    if (pending != null) { result.error("FILE_DIALOG_BUSY", "文件选择器正在使用", null); return@setMethodCallHandler }
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                    }
                    try { startActivityForResult(intent, pickCode) }
                    catch (error: Exception) { pending = null; result.error("NO_DOCUMENT_PROVIDER", "无法打开系统文件选择器", null) }
                }
                "saveMarkdown" -> {
                    if (pending != null) { result.error("FILE_DIALOG_BUSY", "文件选择器正在使用", null); return@setMethodCallHandler }
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || bytes.size > outputLimit) { result.error("FILE_TOO_LARGE", "输出超过 20 MB", null); return@setMethodCallHandler }
                    pending = result
                    pendingBytes = bytes
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if ((call.argument<String>("name") ?: "").endsWith(".txt", true)) "text/plain" else "text/markdown"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "Picora.md")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    }
                    try { startActivityForResult(intent, saveCode) }
                    catch (error: Exception) { pending = null; pendingBytes = null; result.error("NO_DOCUMENT_PROVIDER", "无法打开系统文件保存器", null) }
                }
                "overwriteMarkdown" -> {
                    val uri = call.argument<String>("uri")?.let { Uri.parse(it) }
                    val bytes = call.argument<ByteArray>("bytes")
                    val expected = call.argument<String>("expectedMd5")
                    if (uri == null || uri.scheme != "content" || bytes == null || expected == null || bytes.size > outputLimit) {
                        result.error("INVALID_ARGUMENT", "文件参数无效或输出过大", null)
                        return@setMethodCallHandler
                    }
                    onWorker(result) {
                        val original = readLimited(uri, outputLimit)
                        val hash = MessageDigest.getInstance("MD5").digest(original)
                            .joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
                        if (hash != expected) throw DocumentError("DOCUMENT_CHANGED", "原文件已被其他程序修改，未覆盖")
                        try {
                            writeDocument(uri, bytes)
                            if (!readLimited(uri, outputLimit).contentEquals(bytes)) throw DocumentError("WRITE_FAILED", "输出校验失败")
                        } catch (error: Exception) {
                            // SAF providers cannot guarantee atomic replacement. Restore on failure;
                            // a durable original backup was also made by Dart before this call.
                            try {
                                if (!readLimited(uri, outputLimit).contentEquals(original)) {
                                    writeDocument(uri, original)
                                    if (!readLimited(uri, outputLimit).contentEquals(original)) throw Exception("恢复校验失败")
                                }
                            } catch (restoreError: Exception) {
                                error.addSuppressed(restoreError)
                                throw DocumentError("RESTORE_FAILED", "无法确认原文件已恢复，请使用备份", error)
                            }
                            throw DocumentError("WRITE_FAILED", "写入失败，原文已保留或恢复", error)
                        }
                        null
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != pickCode && requestCode != saveCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pending ?: return
        val bytes = pendingBytes
        pending = null
        pendingBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { result.success(null); return }
        val flags = ((data?.flags ?: 0) and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION))
        try { contentResolver.takePersistableUriPermission(uri, flags) } catch (_: Exception) { }
        onWorker(result) {
            if (requestCode == pickCode) {
                var name = "document.md"
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) name = cursor.getString(0) ?: name
                }
                if (!name.endsWith(".md", true) && !name.endsWith(".markdown", true)) {
                    throw DocumentError("INVALID_MARKDOWN", "请选择 Markdown 文件")
                }
                mapOf("uri" to uri.toString(), "name" to name, "bytes" to readLimited(uri, sourceLimit))
            } else {
                if (bytes == null) throw DocumentError("INVALID_ARGUMENT", "输出内容丢失")
                writeDocument(uri, bytes)
                uri.toString()
            }
        }
    }

    private fun readLimited(uri: Uri, limit: Int): ByteArray {
        val input = contentResolver.openInputStream(uri) ?: throw DocumentError("READ_FAILED", "文件无法读取")
        return input.use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            var count: Int
            while (true) {
                count = it.read(buffer)
                if (count < 0) break
                if (output.size() + count > limit) throw DocumentError("FILE_TOO_LARGE", "文件超出大小限制")
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    }

    private fun writeDocument(uri: Uri, bytes: ByteArray) {
        val stream = contentResolver.openOutputStream(uri, "wt") ?: throw DocumentError("WRITE_FAILED", "文件不可写入")
        stream.use { it.write(bytes); it.flush() }
    }

    private fun onWorker(result: MethodChannel.Result, operation: () -> Any?) {
        Thread {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: DocumentError) {
                runOnUiThread { result.error(error.code, error.message, mapOf("nativeStack" to error.stackTraceToString())) }
            } catch (error: SecurityException) {
                runOnUiThread { result.error("PERMISSION_DENIED", "文件权限不足", mapOf("nativeStack" to error.stackTraceToString())) }
            } catch (error: Exception) {
                runOnUiThread { result.error("DOCUMENT_IO_FAILED", "系统文件操作失败", mapOf("nativeStack" to error.stackTraceToString())) }
            }
        }.start()
    }

    private class DocumentError(val code: String, message: String, cause: Throwable? = null): Exception(message, cause)
}
