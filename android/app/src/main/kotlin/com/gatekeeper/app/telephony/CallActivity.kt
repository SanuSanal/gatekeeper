package com.gatekeeper.app.telephony

import android.app.Activity
import android.os.Bundle
import android.widget.Toast
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.core.CallOutcome
import com.gatekeeper.app.core.LogCategory

/**
 * Transparent activity opened only when the user taps "Call gate" on a fallback notification.
 * This is a user-initiated call, so it is not subject to background activity-start restrictions.
 * It uses the same SIM validation as automatic calls (no fallback SIM).
 */
class CallActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val runtime = EngineRuntime.get(this)
        runtime.notifications.cancelTapToCall()
        val config = runtime.configStore.load()
        if (config.testMode) {
            Toast.makeText(this, "Test mode is on: no call placed", Toast.LENGTH_LONG).show()
            runtime.log(LogCategory.TEST, "Tap-to-call ignored: test mode")
            finish()
            return
        }
        val outcome = runtime.gateCaller.place(config)
        runtime.log(LogCategory.CALL, "User-initiated gate call to ${PhoneNumbers.mask(config.gateNumber)}: $outcome")
        if (outcome != CallOutcome.INITIATED) {
            Toast.makeText(this, "Gate call not placed: ${outcome.name}", Toast.LENGTH_LONG).show()
        }
        finish()
    }
}
