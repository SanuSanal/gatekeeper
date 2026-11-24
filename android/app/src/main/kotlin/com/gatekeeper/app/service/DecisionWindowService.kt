package com.gatekeeper.app.service

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.car.CarConnectionObserver
import com.gatekeeper.app.core.LogCategory
import com.gatekeeper.app.system.Notifications

/**
 * Short-lived foreground service ("decision window", at most [WINDOW_MS] per wake).
 *
 * It is started only by events that are documented exemptions from background FGS-start
 * restrictions: geofence transitions, activity-recognition transitions and the associated
 * companion (car Bluetooth) device. While running it observes Android Auto and keeps the process
 * alive for the delayed-trigger timer and the call. Nothing runs while parked and idle.
 *
 * Type: connectedDevice (the car head unit). On Android 14+ its prerequisite is satisfied by the
 * normal CHANGE_NETWORK_STATE permission or BLUETOOTH_CONNECT.
 */
class DecisionWindowService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var holdUntil = 0L
    private val stopCheck = Runnable { checkStop() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val runtime = EngineRuntime.get(this)
        try {
            ServiceCompat.startForeground(
                this,
                Notifications.ID_WINDOW,
                runtime.notifications.windowNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } catch (e: Exception) {
            runtime.log(LogCategory.ERROR, "Decision window could not enter foreground: ${e.javaClass.simpleName}")
            stopSelf()
            return START_NOT_STICKY
        }
        if (!observing) {
            observing = true
            CarConnectionObserver.acquire(this, OWNER)
        }
        extend(WINDOW_MS)
        return START_NOT_STICKY
    }

    private fun extend(ms: Long) {
        holdUntil = maxOf(holdUntil, System.currentTimeMillis() + ms)
        scheduleCheck()
    }

    /** Ends the window soon (keeps a short tail for call-state confirmation). */
    private fun releaseSoon() {
        holdUntil = minOf(holdUntil, System.currentTimeMillis() + RELEASE_TAIL_MS)
        scheduleCheck()
    }

    private fun scheduleCheck() {
        handler.removeCallbacks(stopCheck)
        handler.postDelayed(stopCheck, (holdUntil - System.currentTimeMillis()).coerceAtLeast(0))
    }

    private fun checkStop() {
        val runtime = EngineRuntime.get(this)
        val remaining = holdUntil - System.currentTimeMillis()
        if (remaining > 0) {
            scheduleCheck()
            return
        }
        if (runtime.hasPendingTrigger()) {
            // Never drop a pending revalidation; it resolves within the configured delay.
            holdUntil = System.currentTimeMillis() + 5_000
            scheduleCheck()
            return
        }
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopCheck)
        if (observing) {
            observing = false
            CarConnectionObserver.release(this, OWNER)
        }
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        const val WINDOW_MS = 150_000L
        private const val RELEASE_TAIL_MS = 15_000L
        private const val OWNER = "decision_window"

        @Volatile
        private var instance: DecisionWindowService? = null
        private var observing = false

        val running: Boolean get() = instance != null

        /** Returns false if Android refused to start the service from the background. */
        fun wake(context: Context): Boolean {
            val existing = instance
            if (existing != null) {
                Handler(Looper.getMainLooper()).post { existing.extend(WINDOW_MS) }
                return true
            }
            return try {
                ContextCompat.startForegroundService(context, Intent(context, DecisionWindowService::class.java))
                true
            } catch (e: Exception) {
                // ForegroundServiceStartNotAllowedException (API 31+) or IllegalStateException.
                EngineRuntime.get(context).log(LogCategory.ERROR, "Decision window start refused: ${e.javaClass.simpleName}")
                false
            }
        }

        fun release() {
            val existing = instance ?: return
            Handler(Looper.getMainLooper()).post { existing.releaseSoon() }
        }
    }
}
