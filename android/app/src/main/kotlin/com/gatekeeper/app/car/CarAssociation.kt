package com.gatekeeper.app.car

import android.companion.CompanionDeviceManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Companion-device associations. GateKeeper 1.0.0/1.0.1 chose the car through Android's
 * companion-device chooser; the car is now picked from the paired-device list instead.
 * This class only checks for and removes associations created by those versions.
 * (An existing association also exempts the app from background foreground-service limits.)
 */
class CarAssociation(context: Context) {
    private val cdm: CompanionDeviceManager? =
        if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)) {
            context.getSystemService(CompanionDeviceManager::class.java)
        } else {
            null
        }

    fun isAssociated(address: String?, associationId: Int?): Boolean {
        val manager = cdm ?: return false
        if (address == null) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                manager.myAssociations.any {
                    (associationId != null && it.id == associationId) ||
                        it.deviceMacAddress?.toString()?.equals(address, ignoreCase = true) == true
                }
            } else {
                @Suppress("DEPRECATION")
                manager.associations.any { it.equals(address, ignoreCase = true) }
            }
        } catch (_: Exception) {
            false
        }
    }

    fun disassociate(address: String?, associationId: Int?) {
        val manager = cdm ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && associationId != null) {
                manager.disassociate(associationId)
            } else if (address != null && isAssociated(address, null)) {
                @Suppress("DEPRECATION")
                manager.disassociate(address)
            }
        } catch (_: Exception) {
            // Already gone.
        }
    }
}
