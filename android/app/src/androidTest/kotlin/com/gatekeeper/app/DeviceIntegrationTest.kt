package com.gatekeeper.app

import android.Manifest
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import com.gatekeeper.app.activity.ActivityTransitionManager
import com.gatekeeper.app.activity.ActivityTransitionReceiver
import com.gatekeeper.app.core.EngineState
import com.gatekeeper.app.core.EventSource
import com.gatekeeper.app.core.GeofenceState
import com.gatekeeper.app.core.PendingTrigger
import com.gatekeeper.app.core.SignalState
import com.gatekeeper.app.core.TriggerSource
import com.gatekeeper.app.geofence.GeofenceManager
import com.gatekeeper.app.store.AppConfig
import com.gatekeeper.app.store.ConfigStore
import com.gatekeeper.app.store.EngineStateStore
import com.gatekeeper.app.system.PermissionMonitor
import com.gatekeeper.app.system.Problem
import com.gatekeeper.app.telephony.PhoneNumbers
import com.gatekeeper.app.telephony.SimRepository
import com.google.android.gms.common.internal.safeparcel.SafeParcelableSerializer
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionEvent
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs on a real device / emulator with Google Play services:
 *   cd android; .\gradlew :app:connectedDebugAndroidTest
 * Never places a call.
 */
@RunWith(AndroidJUnit4::class)
class DeviceIntegrationTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @get:Rule
    val permissions: GrantPermissionRule = GrantPermissionRule.grant(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_BACKGROUND_LOCATION,
        Manifest.permission.ACTIVITY_RECOGNITION,
        Manifest.permission.READ_PHONE_STATE,
    )

    @Test
    fun engineStateSurvivesPersistence() {
        val store = EngineStateStore(context)
        val state = EngineState(
            monitoring = true,
            geofence = GeofenceState.INSIDE,
            inVehicle = SignalState.ACTIVE,
            sessionId = 7,
            armed = false,
            calling = true,
            lastCallAt = 123L,
            pending = PendingTrigger(4, 10, 15, TriggerSource.ANDROID_AUTO, 7),
            lastEventAt = mapOf(EventSource.GEOFENCE to 99L),
        )
        assertTrue(store.save(state))
        assertEquals(state, store.load())
        store.save(EngineState())
    }

    @Test
    fun configRoundTrip() {
        val store = ConfigStore(context)
        val before = store.load()
        val c = AppConfig(gateNumber = "+919876543210", simSubscriptionId = 3, latitude = 12.5, longitude = 77.25, radiusMeters = 220)
        store.save(c)
        assertEquals(c, store.load())
        store.save(before)
    }

    @Test
    fun emergencyNumbersAreRefused() {
        assertNull(PhoneNumbers.normalizeForCalling(context, "112"))
        assertNull(PhoneNumbers.normalizeForCalling(context, "911"))
        assertEquals("+919876543210", PhoneNumbers.normalizeForCalling(context, "+91 98765-43210"))
    }

    @Test
    fun simEnumerationDoesNotCrashAndNeverMatchesUnknownSubscription() {
        val sims = SimRepository(context)
        val list = sims.list()
        list.forEach { assertTrue(it.label().startsWith("SIM ")) }
        assertNull(sims.findPhoneAccount(Int.MAX_VALUE))
        assertNull(sims.findPhoneAccount(null))
    }

    @Test
    fun permissionStatusIsReported() {
        assertTrue(PermissionMonitor.backgroundLocationOk(context))
        val problems = PermissionMonitor.problems(context, AppConfig(), SimRepository(context), carAssociated = false)
        assertTrue(Problem.LOCATION_NOT_SET in problems)
        assertTrue(Problem.GATE_NUMBER_INVALID in problems)
        assertFalse(Problem.LOCATION_PERMISSION in problems)
    }

    @Test
    fun geofenceRegistersAndUnregisters() = runBlocking {
        val manager = GeofenceManager(context)
        val error = manager.register(12.9716, 77.5946, 150)
        assertNull("Geofence registration failed: $error (is location on?)", error)
        manager.unregister()
    }

    @Test
    fun activityTransitionsRegister() = runBlocking {
        val manager = ActivityTransitionManager(context)
        assertNull(manager.register())
        manager.unregister()
    }

    @Test
    fun activityTransitionReceiverUpdatesEngineState() {
        val runtime = EngineRuntime.get(context)
        val elapsed = android.os.SystemClock.elapsedRealtimeNanos()
        val result = ActivityTransitionResult(
            listOf(ActivityTransitionEvent(DetectedActivity.IN_VEHICLE, ActivityTransition.ACTIVITY_TRANSITION_ENTER, elapsed)),
        )
        // Same injection technique Google documents for testing activity transitions.
        val intent = Intent(context, ActivityTransitionReceiver::class.java).setAction(ActivityTransitionReceiver.ACTION)
        SafeParcelableSerializer.serializeToIntentExtra(result, intent, "com.google.android.location.internal.EXTRA_ACTIVITY_TRANSITION_RESULT")
        assertNotNull(ActivityTransitionResult.extractResult(intent))
        ActivityTransitionReceiver().onReceive(context, intent)
        Thread.sleep(500)
        assertEquals(SignalState.ACTIVE, runtime.state.inVehicle)
    }
}
