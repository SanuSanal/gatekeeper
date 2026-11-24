package com.gatekeeper.app.activity

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.gatekeeper.app.system.PermissionMonitor
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import kotlinx.coroutines.tasks.await

/** Registers for IN_VEHICLE ENTER/EXIT transitions. Registrations do not survive reboot or app update. */
class ActivityTransitionManager(context: Context) {
    private val app = context.applicationContext
    private val client = ActivityRecognition.getClient(app)

    private val pendingIntent: PendingIntent by lazy {
        val intent = Intent(app, ActivityTransitionReceiver::class.java).setAction(ActivityTransitionReceiver.ACTION)
        // Mutable so Play services can attach the ActivityTransitionResult. Explicit component.
        PendingIntent.getBroadcast(app, REQUEST_CODE, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    }

    /** Returns null on success, or an error description. */
    @SuppressLint("MissingPermission")
    suspend fun register(): String? {
        if (!PermissionMonitor.activityRecognitionOk(app)) return "activity recognition permission not granted"
        val transitions = listOf(
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                .build(),
        )
        return try {
            client.requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), pendingIntent).await()
            null
        } catch (e: SecurityException) {
            "activity recognition security error: ${e.message}"
        } catch (e: Exception) {
            "activity recognition error: ${e.message}"
        }
    }

    @SuppressLint("MissingPermission")
    suspend fun unregister() {
        runCatching { client.removeActivityTransitionUpdates(pendingIntent).await() }
    }

    private companion object {
        const val REQUEST_CODE = 1002
    }
}
