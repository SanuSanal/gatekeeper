package com.gatekeeper.app.car

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.core.Event

/**
 * Wakes the app when the phone connects to / disconnects from the associated car head unit.
 *
 * ACTION_ACL_CONNECTED / ACTION_ACL_DISCONNECTED are on Android's implicit-broadcast exception list,
 * so this manifest receiver runs even when the process is dead (BLUETOOTH_CONNECT required on 12+).
 * Car Bluetooth is only a wake signal: it lets us start a short decision window and check
 * Android Auto. It never qualifies as a vehicle signal on its own.
 */
class CarBluetoothReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val connected = when (intent.action) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> true
            BluetoothDevice.ACTION_ACL_DISCONNECTED -> false
            else -> return
        }
        val device: BluetoothDevice? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }
        val address = device?.address ?: return
        val runtime = EngineRuntime.get(context)
        val carAddress = runtime.configStore.load().carDeviceAddress ?: return
        if (!address.equals(carAddress, ignoreCase = true)) return
        val pending = goAsync()
        runtime.dispatch(Event.CarBluetoothChanged(System.currentTimeMillis(), connected)) { pending.finish() }
    }
}
