package com.dror.metra

import android.content.Intent
import android.content.res.Resources
import android.media.AudioManager
import android.view.accessibility.AccessibilityManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Shares one Flutter engine with audio_service's background service; a plain
// FlutterActivity makes audio_service start a second engine, which runs
// main() again and re-initializes SoLoud under the first one.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Before the engine: Dart picks it up with "takePendingStart".
        if (intent?.action == TileBridge.ACTION_START) TileBridge.pendingStart = true
        super.onCreate(savedInstanceState)
        // Volume keys change media volume in the app even while stopped,
        // never the ringer.
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TileBridge.attach(this, flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "metra/android")
        this.channel = channel
        CallMonitor.attach(this, channel)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setLaunchTheme" -> {
                    setLaunchTheme(call.arguments as String)
                    result.success(null)
                }
                // Android's "Time to take action": how long the Undo bar
                // stays (never shorter than asked).
                "recommendedTimeout" -> {
                    val base = (call.arguments as Number).toInt()
                    result.success(
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            getSystemService(AccessibilityManager::class.java)
                                .getRecommendedTimeoutMillis(
                                    base,
                                    AccessibilityManager.FLAG_CONTENT_TEXT or
                                        AccessibilityManager.FLAG_CONTENT_CONTROLS,
                                )
                        } else {
                            base
                        },
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    private var channel: MethodChannel? = null

    // Every return to the front asks Flutter for a frame. A screen rebuilt
    // over the running engine (a system display setting changed while the
    // app was alive) waits to draw until Flutter shows a frame, and with
    // nothing asking for one it waited forever.
    override fun onPostResume() {
        super.onPostResume()
        channel?.invokeMethod("redraw", null)
    }

    // Already running (warm): the tile asked to start.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == TileBridge.ACTION_START) {
            TileBridge.channel?.invokeMethod("start", null)
        }
    }

    /// The splash theme for the next launches (Android 13+), so a Dark or
    /// Daylight choice in the app opens without a flash of the other.
    private fun setLaunchTheme(mode: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        splashScreen.setSplashScreenTheme(
            when (mode) {
                "dark" -> R.style.LaunchTheme_Dark
                "light" -> R.style.LaunchTheme_Light
                else -> Resources.ID_NULL
            },
        )
    }
}
