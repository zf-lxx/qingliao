package xyz.qingliao.app

import android.content.Context
import android.content.ContentValues
import android.content.Intent
import android.provider.MediaStore
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.plugin.common.MethodChannel
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val manager get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "xyz.qingliao.app/media")
            .setMethodCallHandler { call, result ->
                if (call.method != "save" && call.method != "share") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) { result.error("invalid", "图片数据为空", null); return@setMethodCallHandler }
                val filename = "qingliao-${System.currentTimeMillis()}.jpg"
                try {
                    if (call.method == "save") {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.error("unsupported", "Android 10 以下请通过分享保存图片", null)
                            return@setMethodCallHandler
                        }
                        val values = ContentValues().apply {
                            put(MediaStore.Images.Media.DISPLAY_NAME, filename)
                            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Qingliao")
                            put(MediaStore.Images.Media.IS_PENDING, 1)
                        }
                        val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("无法创建相册图片")
                        try {
                            val output = contentResolver.openOutputStream(uri)
                                ?: throw IllegalStateException("无法写入相册")
                            output.use { it.write(bytes) }
                            values.clear(); values.put(MediaStore.Images.Media.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                        } catch (e: Exception) { contentResolver.delete(uri, null, null); throw e }
                    } else {
                        val dir = File(cacheDir, "shared-images").apply { mkdirs() }
                        dir.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86400000L }?.forEach { it.delete() }
                        val file = File(dir, filename).apply { writeBytes(bytes) }
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "image/jpeg"; putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(intent, "分享图片"))
                    }
                    result.success(null)
                } catch (e: Exception) { result.error("media_failed", "图片操作失败，请稍后重试", null) }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "xyz.qingliao.app/network")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        callback = object : ConnectivityManager.NetworkCallback() {
                            override fun onAvailable(network: Network) {
                                runOnUiThread { events.success("available") }
                            }
                            override fun onLost(network: Network) {
                                runOnUiThread { events.success("lost") }
                            }
                        }
                        manager.registerDefaultNetworkCallback(callback!!)
                    }
                }
                override fun onCancel(arguments: Any?) { unregister() }
            })
    }
    private fun unregister() {
        callback?.let { manager.unregisterNetworkCallback(it) }
        callback = null
    }
    override fun onDestroy() { unregister(); super.onDestroy() }
}
