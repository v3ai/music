package io.github.v3ai.music

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// AudioServiceActivity keeps the player connected to the background media service,
// so music continues with the screen off or the app closed.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "music/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // Hand a downloaded update to Android's installer (it asks the user to confirm).
                    "install" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                            result.success("permission")
                        } else {
                            val file = File(call.argument<String>("path")!!)
                            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
                            startActivity(
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    // CLEAR_TASK: start fresh even if the installer's screen from the last update is still open
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                            )
                            result.success("started")
                        }
                    }
                    "open" -> {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message, null)
            }
        }
    }
}
