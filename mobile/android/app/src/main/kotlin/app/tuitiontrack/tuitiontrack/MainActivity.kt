package app.tuitiontrack.tuitiontrack

import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Flutter's own clipboard only reads plain text. Copied web pages, Word and
        // Google Docs also put HTML on the clipboard, which keeps x², H₂O and the
        // LaTeX behind typeset formulas; the exam editor reads that through here.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tuitiontrack/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val manager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = manager.primaryClip
                    if (clip == null || clip.itemCount == 0) {
                        result.success(null)
                    } else {
                        val item = clip.getItemAt(0)
                        result.success(
                            mapOf(
                                "html" to item.htmlText,
                                "text" to item.coerceToText(this)?.toString(),
                            )
                        )
                    }
                } catch (error: Exception) {
                    result.success(null)
                }
            }
    }
}
