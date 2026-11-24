package com.gatekeeper.app.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TriggerEngineTest {

    // ---- 1. Scenario B ------------------------------------------------------------------

    @Test
    fun `1 enter geofence while IN_VEHICLE active calls immediately`() {
        val h = EngineHarness()
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)

        h.enter()

        assertEquals("no delay for Scenario B", 1, h.calls.size)
        assertEquals(TriggerSource.ENTER_WHILE_IN_VEHICLE, h.calls.single().source)
        assertTrue(h.timers.isEmpty())
    }

    @Test
    fun `1b immediate trigger disabled falls back to delayed revalidation`() {
        val h = EngineHarness(config = EngineConfig(immediateTriggerEnabled = false))
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(30)
        h.enter()
        assertEquals(0, h.calls.size)
        h.advance(5_000)
        assertEquals(1, h.calls.size)
        assertEquals(TriggerSource.ENTER_WHILE_IN_VEHICLE_DELAYED, h.calls.single().source)
    }

    // ---- 2. Walking in ---------------------------------------------------------------

    @Test
    fun `2 enter geofence while walking does not call`() {
        val h = EngineHarness()
        h.startOutside()
        h.inVehicle(false)
        h.advanceSeconds(10)
        h.enter()
        h.advanceSeconds(600)
        assertEquals(0, h.calls.size)
        assertEquals(Phase.WAITING_FOR_VEHICLE_SIGNAL, h.phase())
    }

    @Test
    fun `2b enter with unknown vehicle state does not call`() {
        val h = EngineHarness()
        h.startOutside()
        h.enter()
        h.advanceSeconds(600)
        assertEquals(0, h.calls.size)
    }

    // ---- 3. Scenario A via Activity Recognition ---------------------------------------

    @Test
    fun `3 already inside and IN_VEHICLE becomes active calls after 5 seconds`() {
        val h = EngineHarness()
        h.startInside()
        assertEquals(Phase.WAITING_FOR_VEHICLE_SIGNAL, h.phase())

        h.inVehicle(true)
        assertEquals(Phase.PENDING_DELAYED_CALL, h.phase())
        h.advance(4_999)
        assertEquals(0, h.calls.size)
        h.advance(1)
        assertEquals(1, h.calls.size)
        assertEquals(TriggerSource.ACTIVITY_IN_VEHICLE, h.calls.single().source)
        assertEquals(Phase.COOLDOWN, h.phase())
    }

    @Test
    fun `3b configured delay is honoured`() {
        val h = EngineHarness(config = EngineConfig(delayMs = 12_000))
        h.startInside()
        h.inVehicle(true)
        h.advance(11_999)
        assertEquals(0, h.calls.size)
        h.advance(1)
        assertEquals(1, h.calls.size)
    }

    // ---- 4. Scenario C via Android Auto -------------------------------------------------

    @Test
    fun `4 already inside and Android Auto connects calls after 5 seconds`() {
        val h = EngineHarness()
        h.startInside()
        h.androidAuto(SignalState.INACTIVE) // observer running, not connected
        h.advanceSeconds(20)
        h.androidAuto(SignalState.ACTIVE)
        h.advance(4_999)
        assertEquals(0, h.calls.size)
        h.advance(1)
        assertEquals(1, h.calls.size)
        assertEquals(TriggerSource.ANDROID_AUTO, h.calls.single().source)
    }

    @Test
    fun `4b car bluetooth wake then Android Auto first reading connected calls after 5 seconds`() {
        val h = EngineHarness()
        h.startInside()
        h.carBluetooth(true)
        assertTrue(WakeReason.CAR_BLUETOOTH in h.wakes)
        h.advanceSeconds(8)
        h.androidAuto(SignalState.ACTIVE) // UNKNOWN -> ACTIVE shortly after the car connected
        h.advance(5_000)
        assertEquals(1, h.calls.size)
    }

    @Test
    fun `4c Android Auto already connected when first observed without a car wake does not call`() {
        val h = EngineHarness()
        h.startInside()
        h.androidAuto(SignalState.ACTIVE) // e.g. UI opened while sitting in the parked car
        h.advanceSeconds(60)
        assertEquals(0, h.calls.size)
    }

    @Test
    fun `4d Android Auto connecting while outside does not call`() {
        val h = EngineHarness()
        h.startOutside()
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE)
        h.advanceSeconds(60)
        assertEquals(0, h.calls.size)
    }

    @Test
    fun `4e entering with Android Auto connected uses the delayed revalidated path`() {
        val h = EngineHarness()
        h.startOutside()
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE)
        h.advanceSeconds(30)
        h.enter()
        assertEquals("AA alone is not proof of driving: no immediate call", 0, h.calls.size)
        h.advance(5_000)
        assertEquals(1, h.calls.size)
        assertEquals(TriggerSource.ENTER_WITH_ANDROID_AUTO, h.calls.single().source)
    }

    // ---- 5. Overlapping signals ---------------------------------------------------------

    @Test
    fun `5 both signals arriving together produce exactly one call`() {
        val h = EngineHarness()
        h.startInside()
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE)
        h.inVehicle(true)
        h.advanceSeconds(1)
        h.advanceSeconds(60)
        assertEquals(1, h.calls.size)
    }

    @Test
    fun `5b second signal arriving during the delay and after the call produces no extra call`() {
        val h = EngineHarness()
        h.startInside()
        h.androidAuto(SignalState.INACTIVE)
        h.inVehicle(true)
        h.advanceSeconds(3)
        h.androidAuto(SignalState.ACTIVE) // merged into the pending trigger
        h.advanceSeconds(3)
        assertEquals(1, h.calls.size)
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE) // flaps after the call
        h.advanceSeconds(600)
        assertEquals(1, h.calls.size)
    }

    // ---- 6-8. Cancellation ----------------------------------------------------------------

    @Test
    fun `6 exit geofence during the delay cancels the call`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        h.exit()
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
        assertTrue(h.timers.isEmpty())
        assertEquals(Phase.MONITORING_OUTSIDE, h.phase())
    }

    @Test
    fun `7 stop monitoring during the delay cancels the call`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        h.stop()
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
        assertTrue(h.timers.isEmpty())
        assertEquals(Phase.STOPPED, h.phase())
    }

    @Test
    fun `8 vehicle signal disappearing during the delay cancels the call`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        h.inVehicle(false)
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
    }

    @Test
    fun `8b Android Auto disconnecting during the delay cancels the call`() {
        val h = EngineHarness()
        h.startInside()
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE)
        h.advanceSeconds(2)
        h.androidAuto(SignalState.INACTIVE)
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
    }

    @Test
    fun `8c one of two signals disappearing keeps the pending call`() {
        val h = EngineHarness()
        h.startInside()
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE)
        h.inVehicle(true)
        h.advanceSeconds(2)
        h.androidAuto(SignalState.INACTIVE)
        h.advanceSeconds(5)
        assertEquals(1, h.calls.size)
    }

    // ---- 9. Duplicates ------------------------------------------------------------------------

    @Test
    fun `9 duplicate geofence events do not cause duplicate calls`() {
        val h = EngineHarness()
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        h.enter()
        h.advanceSeconds(1)
        h.enter()
        h.advanceSeconds(600) // well past cooldown
        h.enter()
        assertEquals(1, h.calls.size)
    }

    @Test
    fun `9b duplicate activity events do not schedule twice`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(1)
        h.inVehicle(true)
        h.advanceSeconds(10)
        assertEquals(1, h.calls.size)
    }

    // ---- 10. New arrival after genuine exit -------------------------------------------------

    @Test
    fun `10 re-entering after a genuine exit allows a new trigger`() {
        val h = EngineHarness()
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        assertEquals(1, h.calls.size)
        h.advanceSeconds(240) // past the 3 min cooldown
        h.exit()
        h.advanceSeconds(120)
        h.enter()
        assertEquals(2, h.calls.size)
    }

    // ---- 11. Cooldown ---------------------------------------------------------------------------

    @Test
    fun `11 cooldown prevents a second call even after exit and re-entry`() {
        val h = EngineHarness()
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        assertEquals(1, h.calls.size)
        h.advanceSeconds(30)
        h.exit()
        h.advanceSeconds(30)
        h.enter() // 60 s after the call, inside the 3 min cooldown
        assertEquals(1, h.calls.size)
        assertTrue(h.state.lastTrigger!!.decision.contains("cooldown"))
    }

    @Test
    fun `11b cooldown is configurable`() {
        val h = EngineHarness(config = EngineConfig(cooldownMs = 60_000))
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        h.advanceSeconds(30)
        h.exit()
        h.advanceSeconds(40)
        h.enter() // 70 s after the call
        assertEquals(2, h.calls.size)
    }

    @Test
    fun `11c cooldown checked again at revalidation time`() {
        val h = EngineHarness(config = EngineConfig(cooldownMs = 60_000))
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        assertEquals(1, h.calls.size)
        assertEquals(Phase.COOLDOWN, h.phase())
        h.advanceSeconds(61)
        assertEquals(Phase.MONITORING_INSIDE, h.phase())
    }

    // ---- 12. SIM / prerequisites ------------------------------------------------------------

    @Test
    fun `12 SIM unavailable places no call and reports an error`() {
        val h = EngineHarness()
        h.startOutside(Prerequisites(permissionsOk = true, gateNumberValid = true, simAvailable = false))
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
        assertTrue(h.errors.any { it.reason == ErrorReason.SIM_UNAVAILABLE })
    }

    @Test
    fun `12b SIM removed during the delay cancels the pending call and reports`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        h.prerequisites(Prerequisites(permissionsOk = true, gateNumberValid = true, simAvailable = false))
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
        assertTrue(h.errors.any { it.reason == ErrorReason.SIM_UNAVAILABLE })
    }

    @Test
    fun `12c permission revoked during the delay cancels the pending call`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        h.prerequisites(Prerequisites(permissionsOk = false, gateNumberValid = true, simAvailable = true))
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
        assertTrue(h.errors.any { it.reason == ErrorReason.PERMISSIONS_MISSING })
    }

    @Test
    fun `12d invalid gate number blocks the call`() {
        val h = EngineHarness()
        h.startInside(Prerequisites(permissionsOk = true, gateNumberValid = false, simAvailable = true))
        h.inVehicle(true)
        h.advanceSeconds(30)
        assertEquals(0, h.calls.size)
        assertTrue(h.errors.any { it.reason == ErrorReason.GATE_NUMBER_INVALID })
    }

    @Test
    fun `12e failed call outcome is recorded, reported and never retried`() {
        val h = EngineHarness()
        h.autoCompleteCalls = false
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(5)
        assertEquals(1, h.calls.size)
        h.send(Event.CallCompleted(h.now, CallOutcome.FAILED_SIM_UNAVAILABLE))
        assertEquals(CallOutcome.FAILED_SIM_UNAVAILABLE, h.state.lastCallOutcome)
        assertTrue(h.errors.any { it.reason == ErrorReason.CALL_FAILED })
        h.advanceSeconds(3600)
        assertEquals(1, h.calls.size)
    }

    // ---- 13. Process recreation -----------------------------------------------------------

    @Test
    fun `13 process recreation after a call restores monitoring without a duplicate call`() {
        val h = EngineHarness()
        h.autoCompleteCalls = false
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(5)
        assertEquals(1, h.calls.size)
        assertTrue("write-ahead flag persisted before the call", h.state.calling)

        // Process dies before the call result is recorded.
        val r = h.recreateProcess()
        assertTrue(r.state.monitoring)
        assertFalse(r.state.calling)
        assertEquals(CallOutcome.UNKNOWN_PROCESS_DIED, r.state.lastCallOutcome)

        // Re-delivered / overlapping events after restart must not call again.
        r.inVehicle(true)
        r.androidAuto(SignalState.INACTIVE)
        r.androidAuto(SignalState.ACTIVE)
        r.enter()
        r.advanceSeconds(600)
        assertEquals(0, r.calls.size)
    }

    @Test
    fun `13b pending trigger restored before its deadline fires exactly once`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        val r = h.recreateProcess() // timers lost with the process
        r.advanceSeconds(2)
        assertEquals(0, r.calls.size)
        r.advanceSeconds(1)
        assertEquals(1, r.calls.size)
        r.advanceSeconds(60)
        assertEquals(1, r.calls.size)
    }

    @Test
    fun `13c pending trigger that expired while the process was dead is discarded`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(2)
        val snapshot = h.state
        val r = EngineHarness(h.config, snapshot, h.now + 60_000)
        r.send(Event.ProcessRestored(r.now))
        r.advanceSeconds(60)
        assertEquals(0, r.calls.size)
        assertNull(r.state.pending)
    }

    @Test
    fun `13d monitoring state survives recreation and still triggers on a new arrival`() {
        val h = EngineHarness()
        h.startOutside()
        val r = h.recreateProcess()
        assertEquals(Phase.MONITORING_OUTSIDE, r.phase())
        r.inVehicle(true)
        r.advanceSeconds(10)
        r.enter()
        assertEquals(1, r.calls.size)
    }

    // ---- Ordering / sync / re-arm / test mode -------------------------------------------

    @Test
    fun `out-of-order activity events are ignored`() {
        val h = EngineHarness()
        h.startInside()
        val t = h.now
        h.send(Event.VehicleActivity(t + 1_000, inVehicle = true))
        h.send(Event.VehicleActivity(t + 500, inVehicle = false)) // delivered late, older
        assertEquals(SignalState.ACTIVE, h.state.inVehicle)
        h.now = t + 1_000
        h.advanceSeconds(6)
        assertEquals(1, h.calls.size)
    }

    @Test
    fun `initial sync ENTER after registration never triggers Scenario B`() {
        val h = EngineHarness()
        h.start()
        h.advanceSeconds(1)
        h.send(Event.VehicleActivity(h.now, true)) // within AR sync window: state only
        h.enter() // within geofence sync window
        h.advanceSeconds(60)
        assertEquals(0, h.calls.size)
        assertEquals(GeofenceState.INSIDE, h.state.geofence)
    }

    @Test
    fun `geofence re-registration after reboot keeps inside state without a new call`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(5)
        assertEquals(1, h.calls.size)
        h.advanceSeconds(3600)
        val r = h.recreateProcess()
        r.send(Event.GeofenceRegistered(r.now))
        r.send(Event.ActivityRegistered(r.now))
        r.advanceSeconds(2)
        r.enter() // sync ENTER from re-registration
        r.advanceSeconds(120)
        assertEquals(0, r.calls.size)
        assertEquals(GeofenceState.INSIDE, r.state.geofence)
    }

    @Test
    fun `flapping vehicle signal inside the re-arm quiet period does not call twice`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.advanceSeconds(5)
        assertEquals(1, h.calls.size)
        h.inVehicle(false)
        h.advanceSeconds(240) // past cooldown but within the 5 min quiet period
        h.inVehicle(true)
        h.advanceSeconds(10)
        assertEquals(1, h.calls.size)
    }

    @Test
    fun `departure after parking re-arms once signals were quiet long enough`() {
        val h = EngineHarness()
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter() // arrival call
        assertEquals(1, h.calls.size)
        h.advanceSeconds(60)
        h.inVehicle(false) // parked
        h.advanceSeconds(8 * 3600) // overnight
        h.inVehicle(true) // leaving in the morning
        h.advanceSeconds(5)
        assertEquals(2, h.calls.size)
        assertEquals(TriggerSource.ACTIVITY_IN_VEHICLE, h.calls.last().source)
    }

    @Test
    fun `test mode never emits PlaceCall`() {
        val h = EngineHarness(config = EngineConfig(testMode = true))
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        assertEquals(0, h.calls.size)
        assertEquals(1, h.simulatedCalls.size)
        assertEquals(CallOutcome.SIMULATED, h.state.lastCallOutcome)
    }

    @Test
    fun `activity recognition disabled ignores IN_VEHICLE`() {
        val h = EngineHarness(config = EngineConfig(activityRecognitionEnabled = false))
        h.startOutside()
        h.inVehicle(true)
        h.advanceSeconds(10)
        h.enter()
        h.advanceSeconds(60)
        assertEquals(0, h.calls.size)
    }

    @Test
    fun `android auto disabled ignores Android Auto`() {
        val h = EngineHarness(config = EngineConfig(androidAutoEnabled = false))
        h.startInside()
        h.androidAuto(SignalState.INACTIVE)
        h.androidAuto(SignalState.ACTIVE)
        h.advanceSeconds(60)
        assertEquals(0, h.calls.size)
    }

    @Test
    fun `stale timer token is ignored`() {
        val h = EngineHarness()
        h.startInside()
        h.inVehicle(true)
        h.send(Event.TimerFired(h.now, token = 999))
        assertEquals(0, h.calls.size)
        assertEquals(Phase.PENDING_DELAYED_CALL, h.phase())
    }

    @Test
    fun `events while stopped never call`() {
        val h = EngineHarness()
        h.inVehicle(true)
        h.enter()
        h.androidAuto(SignalState.ACTIVE)
        h.advanceSeconds(60)
        assertEquals(0, h.calls.size)
        assertEquals(Phase.STOPPED, h.phase())
    }
}
