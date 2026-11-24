package com.gatekeeper.app.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.core.Event
import com.gatekeeper.app.core.LogCategory
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingEvent

class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val event = GeofencingEvent.fromIntent(intent) ?: return
        val runtime = EngineRuntime.get(context)
        if (event.hasError()) {
            val code = event.errorCode
            runtime.log(LogCategory.ERROR, "Geofence error: ${GeofenceStatusCodes.getStatusCodeString(code)}")
            if (code == GeofenceStatusCodes.GEOFENCE_NOT_AVAILABLE) runtime.onGeofenceUnavailable()
            return
        }
        val entered = when (event.geofenceTransition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> true
            Geofence.GEOFENCE_TRANSITION_EXIT -> false
            else -> return
        }
        val now = System.currentTimeMillis()
        // Prefer the time of the fix that caused the transition (orders late deliveries correctly), if sane.
        val fixTime = event.triggeringLocation?.time
        val at = if (fixTime != null && fixTime in (now - MAX_FIX_AGE_MS)..now) fixTime else now
        val pending = goAsync()
        runtime.dispatch(Event.GeofenceTransition(at, entered)) { pending.finish() }
    }

    companion object {
        const val ACTION = "com.gatekeeper.app.GEOFENCE_EVENT"
        private const val MAX_FIX_AGE_MS = 10 * 60_000L
    }
}
