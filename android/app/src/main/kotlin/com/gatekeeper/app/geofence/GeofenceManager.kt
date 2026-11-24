package com.gatekeeper.app.geofence

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.gatekeeper.app.system.PermissionMonitor
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofenceStatusCodes
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import kotlinx.coroutines.tasks.await

/** Registers the single parking geofence with Play services. Geofences do not survive reboot; see BootReceiver. */
class GeofenceManager(context: Context) {
    private val app = context.applicationContext
    private val client = LocationServices.getGeofencingClient(app)

    private val pendingIntent: PendingIntent by lazy {
        val intent = Intent(app, GeofenceReceiver::class.java).setAction(GeofenceReceiver.ACTION)
        // Must be mutable: Play services adds the GeofencingEvent extras. Explicit component, so this is allowed.
        PendingIntent.getBroadcast(app, REQUEST_CODE, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    }

    /** Returns null on success, or an error description. */
    @SuppressLint("MissingPermission")
    suspend fun register(latitude: Double, longitude: Double, radiusMeters: Int): String? {
        if (!PermissionMonitor.backgroundLocationOk(app)) return "location permission (all the time) not granted"
        val geofence = Geofence.Builder()
            .setRequestId(REQUEST_ID)
            .setCircularRegion(latitude, longitude, radiusMeters.toFloat())
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
            .build()
        val request = GeofencingRequest.Builder()
            // Report the current state right after registration; the engine treats it as a sync, not an arrival.
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER or GeofencingRequest.INITIAL_TRIGGER_EXIT)
            .addGeofence(geofence)
            .build()
        return try {
            runCatching { client.removeGeofences(pendingIntent).await() }
            client.addGeofences(request, pendingIntent).await()
            null
        } catch (e: ApiException) {
            "geofence error ${GeofenceStatusCodes.getStatusCodeString(e.statusCode)}"
        } catch (e: SecurityException) {
            "geofence security error: ${e.message}"
        } catch (e: Exception) {
            "geofence error: ${e.message}"
        }
    }

    suspend fun unregister() {
        runCatching { client.removeGeofences(pendingIntent).await() }
    }

    private companion object {
        const val REQUEST_ID = "gatekeeper_parking"
        const val REQUEST_CODE = 1001
    }
}
