package com.dror.metra

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Metra in Android's share menu for text (a Metra export from a chat):
// keeps the text for Dart, brings Metra's own task to the front and
// closes, so Metra never opens inside the sending app's task.
class ShareReceiver : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { ShareBridge.received(it) }
        }
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP,
            ),
        )
        finish()
    }
}

object ShareBridge {
    private var channel: MethodChannel? = null

    // Shared before Dart was listening: handed over when it asks.
    private var pending: String? = null

    fun attach(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "metra/share").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "take" -> {
                        result.success(pending)
                        pending = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun received(text: String) {
        pending = text
        // Dart running: it takes the text now.
        channel?.invokeMethod("shared", null)
    }
}
