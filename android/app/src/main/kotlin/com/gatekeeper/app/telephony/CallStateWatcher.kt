package com.gatekeeper.app.telephony

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Watches for CALL_STATE_OFFHOOK for a short period after placeCall() to confirm that dialling
 * actually started. Some OEMs silently block calls from background apps; in that case no OFFHOOK
 * is seen and the caller shows a "tap to call" fallback.
 *
 * Result: true = confirmed, false = not seen within the timeout, null = could not observe.
 */
class CallStateWatcher(context: Context) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())

    fun watch(timeoutMs: Long, onResult: (Boolean?) -> Unit) {
        val tm = app.getSystemService(TelephonyManager::class.java)
        if (tm == null) {
            onResult(null)
            return
        }
        val done = AtomicBoolean(false)
        main.post {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                        override fun onCallStateChanged(state: Int) {
                            if (state == TelephonyManager.CALL_STATE_OFFHOOK && done.compareAndSet(false, true)) {
                                tm.unregisterTelephonyCallback(this)
                                onResult(true)
                            }
                        }
                    }
                    tm.registerTelephonyCallback(app.mainExecutor, cb)
                    main.postDelayed({
                        if (done.compareAndSet(false, true)) {
                            tm.unregisterTelephonyCallback(cb)
                            onResult(false)
                        }
                    }, timeoutMs)
                } else {
                    @Suppress("DEPRECATION")
                    val listener = object : PhoneStateListener() {
                        @Deprecated("Deprecated in Java")
                        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                            if (state == TelephonyManager.CALL_STATE_OFFHOOK && done.compareAndSet(false, true)) {
                                tm.listen(this, LISTEN_NONE)
                                onResult(true)
                            }
                        }
                    }
                    @Suppress("DEPRECATION")
                    tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
                    main.postDelayed({
                        if (done.compareAndSet(false, true)) {
                            @Suppress("DEPRECATION")
                            tm.listen(listener, PhoneStateListener.LISTEN_NONE)
                            onResult(false)
                        }
                    }, timeoutMs)
                }
            } catch (_: SecurityException) {
                if (done.compareAndSet(false, true)) onResult(null)
            }
        }
    }
}
