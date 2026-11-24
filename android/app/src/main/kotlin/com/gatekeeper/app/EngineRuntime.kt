package com.gatekeeper.app

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import com.gatekeeper.app.activity.ActivityTransitionManager
import com.gatekeeper.app.car.CarAssociation
import com.gatekeeper.app.core.CallOutcome
import com.gatekeeper.app.core.Effect
import com.gatekeeper.app.core.EngineState
import com.gatekeeper.app.core.Event
import com.gatekeeper.app.core.LogCategory
import com.gatekeeper.app.core.TriggerEngine
import com.gatekeeper.app.geofence.GeofenceManager
import com.gatekeeper.app.service.DecisionWindowService
import com.gatekeeper.app.store.AppConfig
import com.gatekeeper.app.store.ConfigStore
import com.gatekeeper.app.store.EngineStateStore
import com.gatekeeper.app.store.EventLog
import com.gatekeeper.app.system.Notifications
import com.gatekeeper.app.system.PermissionMonitor
import com.gatekeeper.app.telephony.CallStateWatcher
import com.gatekeeper.app.telephony.GateCaller
import com.gatekeeper.app.telephony.PhoneNumbers
import com.gatekeeper.app.telephony.SimRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.CopyOnWriteArraySet
import kotlin.coroutines.resume

/**
 * Process-wide runtime around the pure [TriggerEngine].
 *
 * All events are serialized on one background thread. For every event: (1) for external events,
 * prerequisites (permissions, number, SIM) are reconciled first; (2) the engine reduces; (3) the new
 * state is committed to disk synchronously; (4) only then are effects executed. Step 3 before step 4
 * is what prevents duplicate calls after process death.
 */
class EngineRuntime private constructor(context: Context) {
    private val app = context.applicationContext
    private val thread = HandlerThread("gatekeeper-engine").apply { start() }
    private val handler = Handler(thread.looper)
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val timers = mutableMapOf<Long, Runnable>()
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private val runtimePrefs = app.getSharedPreferences("gatekeeper_runtime", Context.MODE_PRIVATE)
    private val wakeLock = app.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "GateKeeper:pendingTrigger")
        .apply { setReferenceCounted(false) }

    val configStore = ConfigStore(app)
    private val stateStore = EngineStateStore(app)
    private val eventLog = EventLog(app)
    val sims = SimRepository(app)
    val gateCaller = GateCaller(app, sims)
    val notifications = Notifications(app)
    val carAssociation = CarAssociation(app)
    private val geofences = GeofenceManager(app)
    private val activities = ActivityTransitionManager(app)
    private val callWatcher = CallStateWatcher(app)

    @Volatile
    var state: EngineState = stateStore.load()
        private set

    init {
        if (state.monitoring || state.calling) {
            handler.post { process(Event.ProcessRestored(now())) }
        }
    }

    private fun now() = System.currentTimeMillis()

    // ---- event entry points ---------------------------------------------------------------

    fun dispatch(event: Event, onDone: (() -> Unit)? = null) {
        handler.post {
            try {
                if (needsReconcile(event)) process(Event.PrerequisitesChanged(event.at, currentPrerequisites()))
                process(event)
            } catch (e: Exception) {
                log(LogCategory.ERROR, "Engine error: ${e.javaClass.simpleName}: ${e.message}")
            } finally {
                onDone?.invoke()
            }
        }
    }

    private fun needsReconcile(e: Event) = state.monitoring && when (e) {
        is Event.GeofenceTransition, is Event.VehicleActivity, is Event.AndroidAutoChanged,
        is Event.CarBluetoothChanged, is Event.TimerFired -> true
        else -> false
    }

    fun refreshPrerequisites(onDone: (() -> Unit)? = null) =
        dispatch(Event.PrerequisitesChanged(now(), currentPrerequisites()), onDone)

    private fun currentPrerequisites() = PermissionMonitor.prerequisites(app, configStore.load(), sims)

    fun hasPendingTrigger(): Boolean = state.pending != null

    fun log(category: LogCategory, message: String) = eventLog.append(now(), category.name, message)

    val logs: EventLog get() = eventLog

    fun addListener(l: () -> Unit) = listeners.add(l)
    fun removeListener(l: () -> Unit) = listeners.remove(l)

    fun carCompanionAssociated(config: AppConfig = configStore.load()) =
        carAssociation.isAssociated(config.carDeviceAddress, config.carAssociationId)

    fun problems(config: AppConfig = configStore.load()): List<String> =
        PermissionMonitor.problems(app, config, sims, carCompanionAssociated(config))

    // ---- engine loop ---------------------------------------------------------------------------

    private fun process(event: Event) {
        val config = configStore.load()
        val result = TriggerEngine.reduce(state, event, config.engineConfig())
        state = result.state
        if (!stateStore.save(state)) log(LogCategory.ERROR, "Failed to persist engine state")
        result.effects.forEach { execute(it, config) }
        listeners.forEach { l -> main.post { l() } }
    }

    private fun execute(effect: Effect, config: AppConfig) {
        when (effect) {
            is Effect.Log -> log(effect.category, effect.message)
            is Effect.ScheduleTimer -> scheduleTimer(effect.token, effect.at)
            is Effect.CancelTimer -> cancelTimer(effect.token)
            is Effect.PlaceCall -> placeCall(config)
            is Effect.SimulateCall -> {
                notifications.showSimulated(effect.source.name)
                handler.post { process(Event.CallCompleted(now(), CallOutcome.SIMULATED)) }
            }
            is Effect.ReportError -> notifications.showError(effect.reason, effect.detail)
            is Effect.WakeWindow -> {
                if (!DecisionWindowService.wake(app)) {
                    log(LogCategory.ERROR, "Background start blocked for ${effect.reason}; timers still run while the process lives")
                }
            }
            Effect.ReleaseWindow -> DecisionWindowService.release()
        }
    }

    private fun scheduleTimer(token: Long, at: Long) {
        cancelTimer(token)
        val delay = (at - now()).coerceAtLeast(0)
        // Handler time stops in deep sleep; hold a bounded partial wake lock until the timer resolves.
        wakeLock.acquire(delay + 10_000)
        val r = Runnable {
            timers.remove(token)
            if (timers.isEmpty()) releaseWakeLock()
            dispatch(Event.TimerFired(now(), token))
        }
        timers[token] = r
        handler.postDelayed(r, delay)
    }

    private fun cancelTimer(token: Long) {
        timers.remove(token)?.let { handler.removeCallbacks(it) }
        if (timers.isEmpty()) releaseWakeLock()
    }

    private fun releaseWakeLock() {
        if (wakeLock.isHeld) runCatching { wakeLock.release() }
    }

    private fun placeCall(config: AppConfig) {
        if (config.testMode) {
            // Second guard: the engine never emits PlaceCall in test mode, but never dial if it somehow did.
            log(LogCategory.TEST, "Refused to dial in test mode")
            handler.post { process(Event.CallCompleted(now(), CallOutcome.SIMULATED)) }
            return
        }
        val outcome = gateCaller.place(config)
        val sim = sims.find(config.simSubscriptionId)?.label() ?: config.simLabel ?: "?"
        log(LogCategory.CALL, "placeCall to ${PhoneNumbers.mask(config.gateNumber)} via $sim: $outcome")
        when (outcome) {
            CallOutcome.INITIATED -> callWatcher.watch(CALL_CONFIRM_TIMEOUT_MS) { confirmed ->
                when (confirmed) {
                    true -> log(LogCategory.CALL, "Dialling confirmed (call state OFFHOOK)")
                    false -> {
                        log(LogCategory.CALL, "Dialling not confirmed within ${CALL_CONFIRM_TIMEOUT_MS / 1000}s; offering tap-to-call")
                        notifications.showTapToCall("Android may have blocked the automatic call. Tap to call the gate.")
                    }
                    null -> log(LogCategory.CALL, "Could not observe call state")
                }
            }
            CallOutcome.FAILED_SECURITY -> notifications.showTapToCall("Android blocked the automatic call. Tap to call the gate.")
            else -> Unit
        }
        handler.post { process(Event.CallCompleted(now(), outcome)) }
    }

    // ---- monitoring lifecycle -----------------------------------------------------------------

    data class StartOutcome(val started: Boolean, val problems: List<String>)

    suspend fun startMonitoring(): StartOutcome {
        val config = configStore.load()
        val problems = problems(config)
        val blocking = PermissionMonitor.blocking(problems)
        if (blocking.isNotEmpty()) return StartOutcome(false, problems)
        if (state.monitoring) return StartOutcome(true, problems)
        awaitDispatch(Event.StartMonitoring(now(), PermissionMonitor.prerequisites(app, config, sims)))
        val error = registerAll(config, "start")
        if (error != null) {
            awaitDispatch(Event.StopMonitoring(now(), "geofence registration failed"))
            return StartOutcome(false, problems + "GEOFENCE_REGISTRATION_FAILED")
        }
        return StartOutcome(true, problems)
    }

    fun stopMonitoring(reason: String, onDone: (() -> Unit)? = null) {
        dispatch(Event.StopMonitoring(now(), reason))
        scope.launch {
            geofences.unregister()
            activities.unregister()
            onDone?.invoke()
        }
    }

    /** Re-registers geofence + activity transitions (boot, app update, settings change, location re-enabled). */
    fun restoreRegistrations(reason: String, onDone: (() -> Unit)? = null) {
        if (!state.monitoring) {
            onDone?.invoke()
            return
        }
        scope.launch {
            val error = registerAll(configStore.load(), reason)
            if (error != null) {
                notifications.showInfo("GateKeeper stopped", "Could not restore monitoring after $reason: $error")
                awaitDispatch(Event.StopMonitoring(now(), "restore failed: $error"))
                geofences.unregister()
                activities.unregister()
            }
            onDone?.invoke()
        }
    }

    /** Re-register only if a previous GEOFENCE_NOT_AVAILABLE removed our geofence. Called when the UI opens. */
    fun restoreIfInvalidated() {
        if (runtimePrefs.getBoolean(K_NEEDS_REREGISTER, false) && state.monitoring) {
            restoreRegistrations("location re-enabled")
        }
    }

    fun onGeofenceUnavailable() {
        runtimePrefs.edit().putBoolean(K_NEEDS_REREGISTER, true).apply()
        notifications.showInfo(
            "Parking detection paused",
            "Location is turned off, so Android removed the parking geofence. Turn location on and open GateKeeper.",
        )
    }

    /** Returns null on success or an error string for the geofence. Activity Recognition errors are logged only. */
    private suspend fun registerAll(config: AppConfig, reason: String): String? {
        val lat = config.latitude
        val lng = config.longitude
        if (lat == null || lng == null) return "parking location not set"
        val geoError = geofences.register(lat, lng, config.radiusMeters)
        if (geoError != null) {
            log(LogCategory.ERROR, "Geofence registration failed ($reason): $geoError")
            return geoError
        }
        runtimePrefs.edit().putBoolean(K_NEEDS_REREGISTER, false).apply()
        awaitDispatch(Event.GeofenceRegistered(now()))
        if (config.activityRecognitionEnabled) {
            val arError = activities.register()
            if (arError != null) {
                log(LogCategory.ERROR, "Activity Recognition registration failed ($reason): $arError")
                notifications.showInfo("In-vehicle detection unavailable", arError)
            } else {
                awaitDispatch(Event.ActivityRegistered(now()))
            }
        } else {
            activities.unregister()
        }
        return null
    }

    private suspend fun awaitDispatch(event: Event) = suspendCancellableCoroutine { cont ->
        dispatch(event) { if (cont.isActive) cont.resume(Unit) }
    }

    companion object {
        private const val CALL_CONFIRM_TIMEOUT_MS = 10_000L
        private const val K_NEEDS_REREGISTER = "needs_reregister"

        @Volatile
        private var instance: EngineRuntime? = null

        fun get(context: Context): EngineRuntime =
            instance ?: synchronized(this) { instance ?: EngineRuntime(context).also { instance = it } }
    }
}
