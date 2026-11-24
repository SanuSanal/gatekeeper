package com.gatekeeper.app.system

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.gatekeeper.app.core.Prerequisites
import com.gatekeeper.app.store.AppConfig
import com.gatekeeper.app.telephony.PhoneNumbers
import com.gatekeeper.app.telephony.SimRepository

/** Problem codes shared with Flutter (see lib/src/settings/problems.dart). */
object Problem {
    const val LOCATION_NOT_SET = "LOCATION_NOT_SET"
    const val LOCATION_PERMISSION = "LOCATION_PERMISSION"
    const val BACKGROUND_LOCATION_PERMISSION = "BACKGROUND_LOCATION_PERMISSION"
    const val ACTIVITY_PERMISSION = "ACTIVITY_PERMISSION"
    const val PHONE_PERMISSION = "PHONE_PERMISSION"
    const val GATE_NUMBER_INVALID = "GATE_NUMBER_INVALID"
    const val SIM_NOT_SELECTED = "SIM_NOT_SELECTED"
    const val SIM_UNAVAILABLE = "SIM_UNAVAILABLE"
    const val NO_SIGNAL_ENABLED = "NO_SIGNAL_ENABLED"

    // Warnings (do not block monitoring)
    const val NOTIFICATION_PERMISSION = "NOTIFICATION_PERMISSION"
    const val BLUETOOTH_PERMISSION = "BLUETOOTH_PERMISSION"
    const val CAR_NOT_ASSOCIATED = "CAR_NOT_ASSOCIATED"
    const val BATTERY_OPTIMIZED = "BATTERY_OPTIMIZED"

    val WARNINGS = setOf(NOTIFICATION_PERMISSION, BLUETOOTH_PERMISSION, CAR_NOT_ASSOCIATED, BATTERY_OPTIMIZED)
}

object PermissionMonitor {
    private fun has(context: Context, permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    fun foregroundLocationOk(c: Context) = has(c, Manifest.permission.ACCESS_FINE_LOCATION)
    fun backgroundLocationOk(c: Context) = foregroundLocationOk(c) && has(c, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
    fun activityRecognitionOk(c: Context) = has(c, Manifest.permission.ACTIVITY_RECOGNITION)
    fun phoneOk(c: Context) = has(c, Manifest.permission.CALL_PHONE) && has(c, Manifest.permission.READ_PHONE_STATE)
    fun bluetoothOk(c: Context) =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || has(c, Manifest.permission.BLUETOOTH_CONNECT)
    fun notificationsOk(c: Context) = NotificationManagerCompat.from(c).areNotificationsEnabled()
    fun ignoringBatteryOptimizations(c: Context) =
        c.getSystemService(PowerManager::class.java)?.isIgnoringBatteryOptimizations(c.packageName) == true

    fun prerequisites(c: Context, config: AppConfig, sims: SimRepository): Prerequisites {
        val permissionsOk = backgroundLocationOk(c) &&
            (!config.activityRecognitionEnabled || activityRecognitionOk(c)) &&
            (config.testMode || phoneOk(c))
        val numberOk = config.testMode || PhoneNumbers.normalizeForCalling(c, config.gateNumber) != null
        val simOk = config.testMode || sims.findPhoneAccount(config.simSubscriptionId) != null
        return Prerequisites(permissionsOk, numberOk, simOk)
    }

    /** All problems, blocking first. Test mode does not require phone permission, number or SIM. */
    fun problems(c: Context, config: AppConfig, sims: SimRepository, carAssociated: Boolean): List<String> {
        val p = mutableListOf<String>()
        if (!config.hasLocation) p += Problem.LOCATION_NOT_SET
        if (!foregroundLocationOk(c)) p += Problem.LOCATION_PERMISSION
        else if (!backgroundLocationOk(c)) p += Problem.BACKGROUND_LOCATION_PERMISSION
        if (!config.activityRecognitionEnabled && !config.androidAutoEnabled) p += Problem.NO_SIGNAL_ENABLED
        if (config.activityRecognitionEnabled && !activityRecognitionOk(c)) p += Problem.ACTIVITY_PERMISSION
        if (!config.testMode) {
            if (!phoneOk(c)) p += Problem.PHONE_PERMISSION
            if (PhoneNumbers.normalizeForCalling(c, config.gateNumber) == null) p += Problem.GATE_NUMBER_INVALID
            if (config.simSubscriptionId == null) p += Problem.SIM_NOT_SELECTED
            else if (phoneOk(c) && sims.findPhoneAccount(config.simSubscriptionId) == null) p += Problem.SIM_UNAVAILABLE
        }
        if (!notificationsOk(c)) p += Problem.NOTIFICATION_PERMISSION
        if (config.androidAutoEnabled) {
            if (!carAssociated) p += Problem.CAR_NOT_ASSOCIATED
            else if (!bluetoothOk(c)) p += Problem.BLUETOOTH_PERMISSION
        }
        if (!ignoringBatteryOptimizations(c)) p += Problem.BATTERY_OPTIMIZED
        return p
    }

    fun blocking(problems: List<String>) = problems.filterNot { it in Problem.WARNINGS }
}
