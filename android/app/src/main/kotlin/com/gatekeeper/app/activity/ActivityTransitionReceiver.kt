package com.gatekeeper.app.activity

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.core.Event
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity

class ActivityTransitionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION || !ActivityTransitionResult.hasResult(intent)) return
        val result = ActivityTransitionResult.extractResult(intent) ?: return
        val runtime = EngineRuntime.get(context)
        val nowWall = System.currentTimeMillis()
        val nowElapsed = SystemClock.elapsedRealtime()
        val events = result.transitionEvents
            .filter { it.activityType == DetectedActivity.IN_VEHICLE }
            .sortedBy { it.elapsedRealTimeNanos } // batches are not guaranteed to be ordered
            .map { e ->
                val ageMs = (nowElapsed - e.elapsedRealTimeNanos / 1_000_000L).coerceAtLeast(0)
                Event.VehicleActivity(
                    at = nowWall - ageMs,
                    inVehicle = e.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER,
                )
            }
        if (events.isEmpty()) return
        val pending = goAsync()
        events.forEachIndexed { i, e ->
            runtime.dispatch(e, if (i == events.lastIndex) ({ pending.finish() }) else null)
        }
    }

    companion object {
        const val ACTION = "com.gatekeeper.app.ACTIVITY_TRANSITION"
    }
}
