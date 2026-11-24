package com.gatekeeper.app.system

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.gatekeeper.app.MainActivity
import com.gatekeeper.app.R
import com.gatekeeper.app.core.ErrorReason
import com.gatekeeper.app.telephony.CallActivity

class Notifications(context: Context) {
    private val app = context.applicationContext
    private val manager = NotificationManagerCompat.from(app)

    init {
        val nm = app.getSystemService(NotificationManager::class.java)
        nm?.createNotificationChannel(
            NotificationChannel(CH_WINDOW, "Car check (short)", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown for up to a few minutes while GateKeeper checks your car near the parking spot"
                setShowBadge(false)
            },
        )
        nm?.createNotificationChannel(
            NotificationChannel(CH_ALERTS, "Gate call alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Gate call problems, tap-to-call fallbacks and test-mode results"
            },
        )
    }

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(
        app, 0,
        Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun windowNotification(): Notification {
        val stop = PendingIntent.getBroadcast(
            app, 1,
            Intent(app, StopMonitoringReceiver::class.java).setAction(StopMonitoringReceiver.ACTION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(app, CH_WINDOW)
            .setSmallIcon(R.drawable.ic_stat_gate)
            .setContentTitle("GateKeeper")
            .setContentText("Checking your car near the parking spot")
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent())
            .addAction(0, "Stop monitoring", stop)
            .build()
    }

    fun showError(reason: ErrorReason, detail: String) {
        val text = when (reason) {
            ErrorReason.PERMISSIONS_MISSING -> "A required permission is missing. Open GateKeeper to fix it."
            ErrorReason.GATE_NUMBER_INVALID -> "The gate phone number is not valid."
            ErrorReason.SIM_UNAVAILABLE -> "The selected SIM is not available. No other SIM was used."
            ErrorReason.CALL_FAILED -> "The gate call could not be started ($detail)."
        }
        notify(ID_ERROR, alert("Gate call not placed", text).setContentIntent(openAppIntent()).build())
    }

    fun showTapToCall(reason: String) {
        val call = PendingIntent.getActivity(
            app, 2,
            Intent(app, CallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        notify(
            ID_TAP_TO_CALL,
            alert("Tap to call the gate", reason)
                .setContentIntent(call)
                .addAction(0, "Call gate", call)
                .setTimeoutAfter(5 * 60_000L)
                .build(),
        )
    }

    fun cancelTapToCall() = manager.cancel(ID_TAP_TO_CALL)

    fun showSimulated(source: String) {
        notify(ID_TEST, alert("Test mode: gate call simulated", "Trigger: $source. No call was placed.").setContentIntent(openAppIntent()).build())
    }

    fun showInfo(title: String, text: String) {
        notify(ID_INFO, alert(title, text).setContentIntent(openAppIntent()).build())
    }

    private fun alert(title: String, text: String) = NotificationCompat.Builder(app, CH_ALERTS)
        .setSmallIcon(R.drawable.ic_stat_gate)
        .setContentTitle(title)
        .setContentText(text)
        .setStyle(NotificationCompat.BigTextStyle().bigText(text))
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setAutoCancel(true)

    @SuppressLint("MissingPermission") // guarded by areNotificationsEnabled()
    private fun notify(id: Int, n: Notification) {
        if (!manager.areNotificationsEnabled()) return
        try {
            manager.notify(id, n)
        } catch (_: SecurityException) {
        }
    }

    companion object {
        const val CH_WINDOW = "gatekeeper_window"
        const val CH_ALERTS = "gatekeeper_alerts"
        const val ID_WINDOW = 10
        private const val ID_ERROR = 11
        private const val ID_TAP_TO_CALL = 12
        private const val ID_TEST = 13
        private const val ID_INFO = 14
    }
}
