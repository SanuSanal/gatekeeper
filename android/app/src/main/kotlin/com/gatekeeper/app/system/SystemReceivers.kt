package com.gatekeeper.app.system

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.gatekeeper.app.EngineRuntime

/**
 * Geofences and activity-transition registrations are dropped on reboot and on app update.
 * Restore them if the user had monitoring switched on.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reason = when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> "boot"
            Intent.ACTION_MY_PACKAGE_REPLACED -> "app update"
            else -> return
        }
        val pending = goAsync()
        EngineRuntime.get(context).restoreRegistrations(reason) { pending.finish() }
    }
}

/** "Stop monitoring" action on the decision-window notification. */
class StopMonitoringReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val pending = goAsync()
        EngineRuntime.get(context).stopMonitoring("notification action") { pending.finish() }
    }

    companion object {
        const val ACTION = "com.gatekeeper.app.STOP_MONITORING"
    }
}
