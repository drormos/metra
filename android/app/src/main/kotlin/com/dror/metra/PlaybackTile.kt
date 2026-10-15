package com.dror.metra

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// The "Metra" Quick Settings tile (ui-spec.md "Android basics"): shows
/// Playing / Stopped; a tap starts or stops the click. With no running
/// app to start it in, it opens the app, which starts.
class PlaybackTile : TileService() {
    override fun onStartListening() = refresh()

    override fun onClick() {
        val channel = TileBridge.channel ?: return openAndStart()
        try {
            invoke(channel)
        } catch (e: RuntimeException) {
            openAndStart() // the engine is gone
        }
    }

    private fun invoke(channel: MethodChannel) {
        channel.invokeMethod(
            "toggle",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    // False: Dart couldn't start the click from here.
                    if (result == false) openAndStart() else refresh()
                }

                override fun error(code: String, message: String?, details: Any?) =
                    openAndStart()

                override fun notImplemented() = openAndStart()
            },
        )
    }

    private fun refresh() {
        val tile = qsTile ?: return
        tile.state = if (TileBridge.playing) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (TileBridge.playing) "Playing" else "Stopped"
        }
        tile.updateTile()
    }

    private fun openAndStart() {
        val intent = Intent(this, MainActivity::class.java)
            .setAction(TileBridge.ACTION_START)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}

/// The tile's link to Dart, on the engine the app and audio_service share.
object TileBridge {
    const val ACTION_START = "com.dror.metra.START"

    var channel: MethodChannel? = null
        private set
    var playing = false
        private set

    // Opened from the tile before Dart was listening: start once it asks.
    var pendingStart = false

    fun attach(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "metra/tile").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "playing" -> {
                        playing = call.arguments as Boolean
                        TileService.requestListeningState(
                            app, ComponentName(app, PlaybackTile::class.java),
                        )
                        result.success(null)
                    }
                    "takePendingStart" -> {
                        result.success(pendingStart)
                        pendingStart = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
