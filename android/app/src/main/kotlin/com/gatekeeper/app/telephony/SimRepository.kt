package com.gatekeeper.app.telephony

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat

data class SimInfo(
    val subscriptionId: Int,
    val slotIndex: Int,
    val carrierName: String?,
    val displayName: String?,
    val callCapable: Boolean,
) {
    fun label(): String = buildString {
        append("SIM ${slotIndex + 1}")
        val name = carrierName?.takeIf { it.isNotBlank() } ?: displayName?.takeIf { it.isNotBlank() }
        if (name != null) append(" · $name")
    }
}

/**
 * Enumerates active SIM subscriptions and maps a subscription to its Telecom PhoneAccountHandle.
 * Uses TelephonyManager.getSubscriptionId(PhoneAccountHandle) (API 30+) for an exact mapping;
 * there is deliberately no heuristic and no fallback to another SIM.
 */
class SimRepository(context: Context) {
    private val app = context.applicationContext
    private val subscriptions = app.getSystemService(SubscriptionManager::class.java)
    private val telecom = app.getSystemService(TelecomManager::class.java)
    private val telephony = app.getSystemService(TelephonyManager::class.java)

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(app, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission") // guarded by hasPermission() + SecurityException
    fun list(): List<SimInfo> {
        if (!hasPermission()) return emptyList()
        return try {
            val accounts = callCapableAccounts()
            val callableSubIds = accounts.mapNotNull { subIdFor(it) }.toSet()
            (subscriptions?.activeSubscriptionInfoList ?: emptyList()).map { info ->
                SimInfo(
                    subscriptionId = info.subscriptionId,
                    slotIndex = info.simSlotIndex,
                    carrierName = info.carrierName?.toString(),
                    displayName = info.displayName?.toString(),
                    callCapable = info.subscriptionId in callableSubIds,
                )
            }.sortedBy { it.slotIndex }
        } catch (_: SecurityException) {
            emptyList()
        }
    }

    /** The PhoneAccountHandle for exactly this subscription, or null if that SIM is not present / not callable. */
    fun findPhoneAccount(subscriptionId: Int?): PhoneAccountHandle? {
        if (subscriptionId == null || subscriptionId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) return null
        if (!hasPermission()) return null
        return try {
            callCapableAccounts().firstOrNull { subIdFor(it) == subscriptionId }
        } catch (_: SecurityException) {
            null
        }
    }

    fun find(subscriptionId: Int?): SimInfo? = list().firstOrNull { it.subscriptionId == subscriptionId }

    // Callers check hasPermission() first and catch SecurityException (permission can be revoked at any time).
    @SuppressLint("MissingPermission")
    private fun callCapableAccounts(): List<PhoneAccountHandle> =
        telecom?.callCapablePhoneAccounts ?: emptyList()

    @SuppressLint("MissingPermission") // only reached after hasPermission(); exceptions caught below
    private fun subIdFor(handle: PhoneAccountHandle): Int? = try {
        telephony?.getSubscriptionId(handle)?.takeIf { it != SubscriptionManager.INVALID_SUBSCRIPTION_ID }
    } catch (_: Exception) {
        null
    }
}
