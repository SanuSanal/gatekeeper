package com.gatekeeper.app.telephony

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import androidx.core.content.ContextCompat
import com.gatekeeper.app.core.CallOutcome
import com.gatekeeper.app.store.AppConfig

/**
 * Places the gate call through the system Telecom service on the exact SIM the user selected.
 *
 * Reconciles everything immediately before dialling. If the configured SIM is not present the call
 * is NOT placed (no silent fallback to the default SIM). Never retries.
 */
class GateCaller(context: Context, private val sims: SimRepository) {
    private val app = context.applicationContext

    fun place(config: AppConfig): CallOutcome {
        if (ContextCompat.checkSelfPermission(app, Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            return CallOutcome.FAILED_PERMISSION
        }
        val number = PhoneNumbers.normalizeForCalling(app, config.gateNumber) ?: return CallOutcome.FAILED_INVALID_NUMBER
        val handle = sims.findPhoneAccount(config.simSubscriptionId) ?: return CallOutcome.FAILED_SIM_UNAVAILABLE
        val telecom = app.getSystemService(TelecomManager::class.java) ?: return CallOutcome.FAILED_OTHER
        val extras = Bundle().apply { putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle) }
        return try {
            telecom.placeCall(Uri.fromParts("tel", number, null), extras)
            CallOutcome.INITIATED
        } catch (_: SecurityException) {
            CallOutcome.FAILED_SECURITY
        } catch (_: Exception) {
            CallOutcome.FAILED_OTHER
        }
    }
}
