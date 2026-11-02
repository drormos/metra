package com.dror.metra

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// The tuner's microphone (ui-spec.md "Tuner"): the permission, and float
// samples streamed to Dart while it listens. Nothing is kept or sent.
object MicBridge {
    const val REQUEST = 7301
    private const val PREFS = "mic"
    private const val ASKED = "asked"
    private const val RATE = 48000

    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null
    @Volatile private var record: AudioRecord? = null
    private var thread: Thread? = null
    private val main = Handler(Looper.getMainLooper())

    fun attach(activity: Activity, engine: FlutterEngine) {
        this.activity = activity
        val messenger = engine.dartExecutor.binaryMessenger
        EventChannel(messenger, "metra/mic/pcm").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            },
        )
        MethodChannel(messenger, "metra/mic").setMethodCallHandler { call, result ->
            when (call.method) {
                "permission" -> result.success(permission())
                "request" -> request(result)
                "openSettings" -> {
                    activity.startActivity(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", activity.packageName, null),
                        ),
                    )
                    result.success(null)
                }
                "start" -> result.success(start())
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // unknown: never asked; blocked: refused and Android won't show the
    // dialog again (only the app's settings can allow it).
    private fun permission(): String {
        val activity = activity ?: return "denied"
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return "granted"
        }
        val asked = activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE)
            .getBoolean(ASKED, false)
        return when {
            !asked -> "unknown"
            activity.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) -> "denied"
            else -> "blocked"
        }
    }

    private fun request(result: MethodChannel.Result) {
        val activity = activity ?: return result.success("denied")
        if (permission() == "granted") return result.success("granted")
        pending?.success(permission())
        pending = result
        activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE).edit()
            .putBoolean(ASKED, true).apply()
        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST)
    }

    // From MainActivity.onRequestPermissionsResult.
    fun onPermissionResult() {
        pending?.success(permission())
        pending = null
    }

    // The sample rate, or null if the microphone can't start.
    private fun start(): Int? {
        val activity = activity ?: return null
        if (record != null) return record!!.sampleRate
        if (permission() != "granted") return null
        val audio = activity.getSystemService(AudioManager::class.java)
        // Unprocessed: no gain control or noise suppression bending the
        // pitch; voice recognition is the next cleanest source.
        val source =
            if (audio.getProperty(AudioManager.PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED) == "true") {
                MediaRecorder.AudioSource.UNPROCESSED
            } else {
                MediaRecorder.AudioSource.VOICE_RECOGNITION
            }
        val min = AudioRecord.getMinBufferSize(
            RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT,
        )
        if (min <= 0) return null
        val created = try {
            AudioRecord(
                source,
                RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_FLOAT,
                maxOf(min, 4096 * 4),
            )
        } catch (e: SecurityException) {
            return null
        }
        if (created.state != AudioRecord.STATE_INITIALIZED) {
            created.release()
            return null
        }
        record = created
        created.startRecording()
        // ~21 ms chunks, read off the main thread and posted to Dart.
        thread = Thread {
            val chunk = FloatArray(1024)
            while (record === created) {
                val n = created.read(chunk, 0, chunk.size, AudioRecord.READ_BLOCKING)
                if (n <= 0) continue
                val copy = chunk.copyOf(n)
                main.post { if (record === created) sink?.success(copy) }
            }
        }.apply { start() }
        return created.sampleRate
    }

    fun stop() {
        val current = record ?: return
        record = null
        current.stop()
        thread?.join(200)
        thread = null
        current.release()
    }
}
