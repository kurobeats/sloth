package io.github.kurobeats.sloth

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /// Text shared into Sloth (ACTION_SEND), held until Dart asks for it.
        var pendingSharedText: String? = null
    }

    /// Dart hands text over by polling, so a share that starts or wakes the
    /// app never has to race a handler being attached.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sloth/share")
        channel.setMethodCallHandler { call, result ->
            if (call.method == "getSharedText") {
                val text = pendingSharedText
                pendingSharedText = null
                result.success(text)
            } else {
                result.notImplemented()
            }
        }
        takeSend(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeSend(intent)
    }

    private fun takeSend(i: Intent?) {
        if (i?.action != Intent.ACTION_SEND) return
        pendingSharedText = i.getStringExtra(Intent.EXTRA_TEXT) ?: return
    }
}
