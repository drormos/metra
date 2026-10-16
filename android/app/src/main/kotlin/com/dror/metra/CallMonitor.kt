package com.dror.metra

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.telephony.PhoneStateListener
import android.telephony.TelephonyManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/// Tells Dart ("callActive") when a call rings or is active, so the click
/// pauses like music does. The app holds no audio focus (it mixes with the
/// user's music), so it watches the call itself. Android 12+: the audio
/// mode, which also covers VoIP calls, with no permission. Older: the phone
/// call state, which needed no permission before Android 12.
object CallMonitor {
    private var channel: MethodChannel? = null
    private var started = false
    private var inCall = false

    fun attach(context: Context, channel: MethodChannel) {
        this.channel = channel
        if (started) return
        started = true
        val app = context.applicationContext
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                app.getSystemService(AudioManager::class.java)
                    .addOnModeChangedListener(app.mainExecutor) { mode ->
                        report(mode != AudioManager.MODE_NORMAL)
                    }
            } else {
                @Suppress("DEPRECATION")
                app.getSystemService(TelephonyManager::class.java).listen(
                    object : PhoneStateListener() {
                        @Deprecated("Replaced by TelephonyCallback on Android 12+")
                        override fun onCallStateChanged(state: Int, phoneNumber: String?) =
                            report(state != TelephonyManager.CALL_STATE_IDLE)
                    },
                    PhoneStateListener.LISTEN_CALL_STATE,
                )
            }
        } catch (e: RuntimeException) {
            Log.w("Metra", "Call monitoring unavailable", e) // only costs the pause
        }
    }

    private fun report(active: Boolean) {
        if (active == inCall) return
        inCall = active
        channel?.invokeMethod("callActive", active)
    }
}
