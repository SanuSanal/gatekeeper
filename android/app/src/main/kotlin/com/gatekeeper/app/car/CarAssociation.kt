package com.gatekeeper.app.car

import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Build
import java.util.concurrent.Executor

data class AssociatedCar(val address: String, val name: String?, val associationId: Int?)

/**
 * Associates the car's Bluetooth head unit via the system CompanionDeviceManager dialog.
 *
 * The association (plus REQUEST_COMPANION_START_FOREGROUND_SERVICES_FROM_BACKGROUND) is what allows
 * the decision-window foreground service to be started from the background when the car connects.
 */
class CarAssociation(private val context: Context) {
    private val cdm: CompanionDeviceManager? =
        if (context.packageManager.hasSystemFeature(PackageManager.FEATURE_COMPANION_DEVICE_SETUP)) {
            context.getSystemService(CompanionDeviceManager::class.java)
        } else {
            null
        }

    val supported: Boolean get() = cdm != null

    /** Starts the chooser. [launch] must start the IntentSender for result from the activity. */
    fun start(activity: Activity, launch: (IntentSender) -> Unit, onError: (String) -> Unit) {
        val manager = cdm ?: return onError("Companion device setup is not supported on this device")
        val request = AssociationRequest.Builder()
            .addDeviceFilter(BluetoothDeviceFilter.Builder().build())
            .setSingleDevice(false)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val executor = Executor { activity.runOnUiThread(it) }
            manager.associate(request, executor, object : CompanionDeviceManager.Callback() {
                override fun onAssociationPending(intentSender: IntentSender) = launch(intentSender)
                override fun onAssociationCreated(associationInfo: AssociationInfo) = Unit // handled via activity result
                override fun onFailure(error: CharSequence?) = onError(error?.toString() ?: "association failed")
            })
        } else {
            @Suppress("DEPRECATION")
            manager.associate(request, object : CompanionDeviceManager.Callback() {
                @Deprecated("Deprecated in Java")
                override fun onDeviceFound(chooserLauncher: IntentSender) = launch(chooserLauncher)
                override fun onFailure(error: CharSequence?) = onError(error?.toString() ?: "association failed")
            }, null)
        }
    }

    /** Parses the chooser result. Returns null if cancelled. */
    fun parseResult(resultCode: Int, data: Intent?): AssociatedCar? {
        if (resultCode != Activity.RESULT_OK || data == null) return null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val info = data.getParcelableExtra(CompanionDeviceManager.EXTRA_ASSOCIATION, AssociationInfo::class.java)
            if (info != null) {
                val mac = info.deviceMacAddress?.toString()?.uppercase() ?: return null
                return AssociatedCar(mac, info.displayName?.toString(), info.id)
            }
        }
        @Suppress("DEPRECATION")
        val device: BluetoothDevice = data.getParcelableExtra(CompanionDeviceManager.EXTRA_DEVICE) ?: return null
        val name = try {
            device.name
        } catch (_: SecurityException) {
            null
        }
        return AssociatedCar(device.address.uppercase(), name, null)
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
            } else if (address != null) {
                @Suppress("DEPRECATION")
                manager.disassociate(address)
            }
        } catch (_: Exception) {
            // Already gone.
        }
    }
}
