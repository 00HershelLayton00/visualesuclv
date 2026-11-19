package cu.uclv.visuales_uclv

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val foregroundChannel = "cu.uclv.visuales_uclv/foreground"
    private val storageChannel = "cu.uclv.visuales_uclv/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, foregroundChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val text = call.argument<String>("text")
                        ?: "Descargando archivos..."
                    try {
                        val intent = Intent(this, DownloadForegroundService::class.java)
                            .putExtra(DownloadForegroundService.EXTRA_TEXT, text)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.success(false)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, DownloadForegroundService::class.java))
                        result.success(true)
                    } catch (error: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, storageChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                "export" -> exportToDownloads(call, result)
                "openUri" -> {
                    val uri = call.argument<String>("uri")
                    val mime = call.argument<String>("mime") ?: "*/*"
                    if (uri == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(Uri.parse(uri), mime)
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                        }
                        startActivity(Intent.createChooser(intent, "Abrir con"))
                        result.success(true)
                    } catch (error: Exception) {
                        result.success(false)
                    }
                }
                "deleteUri" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val deleted = contentResolver.delete(Uri.parse(uri), null, null)
                        result.success(deleted > 0)
                    } catch (error: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Copia el archivo descargado a Descargas/Visuales (o una subcarpeta)
     * usando MediaStore. Se ejecuta fuera del hilo principal.
     */
    private fun exportToDownloads(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(null)
            return
        }
        val path = call.argument<String>("path")
        val name = call.argument<String>("name") ?: "archivo"
        val relativeDir = call.argument<String>("relativeDir")?.trim('/') ?: ""
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        if (path == null) {
            result.error("invalid", "Ruta vacia", null)
            return
        }
        val appContext = applicationContext
        Thread {
            try {
                val source = File(path)
                if (!source.exists()) {
                    throw IllegalArgumentException("El archivo no existe")
                }
                val relativePath = if (relativeDir.isEmpty()) {
                    "${Environment.DIRECTORY_DOWNLOADS}/Visuales"
                } else {
                    "${Environment.DIRECTORY_DOWNLOADS}/Visuales/$relativeDir"
                }
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = appContext.contentResolver
                val uri = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values
                ) ?: throw IllegalStateException("No se pudo crear el archivo")
                try {
                    val output = resolver.openOutputStream(uri)
                        ?: throw IllegalStateException("No se pudo abrir el destino")
                    output.use { out ->
                        source.inputStream().use { input ->
                            input.copyTo(out, 128 * 1024)
                        }
                    }
                    val ready = ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    }
                    resolver.update(uri, ready, null, null)
                    runOnUiThread {
                        result.success(mapOf("uri" to uri.toString()))
                    }
                } catch (error: Exception) {
                    try {
                        resolver.delete(uri, null, null)
                    } catch (_: Exception) {
                        // Ignorar.
                    }
                    runOnUiThread {
                        result.error("export_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("export_failed", error.message, null)
                }
            }
        }.start()
    }
}
