package com.gatekeeper.app.core

/**
 * Pure-Kotlin domain model for the GateKeeper trigger engine.
 *
 * Nothing in this package may import android.* so it can be unit tested on the JVM
 * with a fake clock. All times are wall-clock epoch milliseconds.
 */

fun interface Clock {
    fun now(): Long
}

object SystemWallClock : Clock {
    override fun now(): Long = System.currentTimeMillis()
}

enum class Phase {
    STOPPED,
    MONITORING_OUTSIDE,
    MONITORING_INSIDE,
    WAITING_FOR_VEHICLE_SIGNAL,
    PENDING_DELAYED_CALL,
    CALLING,
    COOLDOWN,
}

enum class GeofenceState { UNKNOWN, INSIDE, OUTSIDE }

/** UNKNOWN means "not observed" (e.g. Android Auto while no observer is running). Treated as not active. */
enum class SignalState { UNKNOWN, ACTIVE, INACTIVE }

enum class TriggerSource {
    /** Scenario B: geofence ENTER while IN_VEHICLE was already active. Immediate. */
    ENTER_WHILE_IN_VEHICLE,
    /** ENTER while in vehicle but the immediate trigger is disabled: delayed path. */
    ENTER_WHILE_IN_VEHICLE_DELAYED,
    /** ENTER while Android Auto was already connected: delayed path (AA is not proof of driving). */
    ENTER_WITH_ANDROID_AUTO,
    /** Scenario A: already inside, IN_VEHICLE became active. */
    ACTIVITY_IN_VEHICLE,
    /** Scenario A/C: already inside, Android Auto connected. */
    ANDROID_AUTO,
}

enum class CallOutcome {
    INITIATED,
    SIMULATED,
    FAILED_PERMISSION,
    FAILED_INVALID_NUMBER,
    FAILED_SIM_UNAVAILABLE,
    FAILED_SECURITY,
    FAILED_OTHER,
    /** The process died while a call was being placed; result unknown. Never retried. */
    UNKNOWN_PROCESS_DIED,
}

enum class ErrorReason {
    PERMISSIONS_MISSING,
    GATE_NUMBER_INVALID,
    SIM_UNAVAILABLE,
    CALL_FAILED,
}

enum class LogCategory { GEOFENCE, VEHICLE, ANDROID_AUTO, BLUETOOTH, TRIGGER, CALL, SYSTEM, ERROR, TEST }

enum class WakeReason { GEOFENCE_ENTER, CAR_BLUETOOTH, IN_VEHICLE, PENDING_TRIGGER }

data class EngineConfig(
    val delayMs: Long = 5_000,
    val cooldownMs: Long = 3 * 60_000,
    /** All vehicle signals must be inactive this long before a second call is allowed in the same inside-session. */
    val rearmQuietMs: Long = 5 * 60_000,
    val immediateTriggerEnabled: Boolean = true,
    val androidAutoEnabled: Boolean = true,
    val activityRecognitionEnabled: Boolean = true,
    val testMode: Boolean = false,
    /** Transitions arriving this soon after (re)registration are treated as state sync, not real transitions. */
    val initialSyncWindowMs: Long = 30_000,
    /** A restored pending trigger whose deadline passed longer ago than this is discarded. */
    val staleTimerGraceMs: Long = 15_000,
    /** How long after a car-Bluetooth connect an UNKNOWN->ACTIVE Android Auto reading counts as a real connection. */
    val bluetoothAaCorrelationMs: Long = 150_000,
)

data class Prerequisites(
    val permissionsOk: Boolean,
    val gateNumberValid: Boolean,
    val simAvailable: Boolean,
) {
    val ok: Boolean get() = permissionsOk && gateNumberValid && simAvailable

    /** The first blocking problem, in priority order. */
    fun firstProblem(): ErrorReason? = when {
        !permissionsOk -> ErrorReason.PERMISSIONS_MISSING
        !gateNumberValid -> ErrorReason.GATE_NUMBER_INVALID
        !simAvailable -> ErrorReason.SIM_UNAVAILABLE
        else -> null
    }

    companion object {
        val NONE_CHECKED = Prerequisites(permissionsOk = false, gateNumberValid = false, simAvailable = false)
        val ALL_OK = Prerequisites(permissionsOk = true, gateNumberValid = true, simAvailable = true)
    }
}

data class PendingTrigger(
    val token: Long,
    val createdAt: Long,
    val deadline: Long,
    val source: TriggerSource,
    val sessionId: Long,
)

data class TriggerRecord(
    val at: Long,
    val source: TriggerSource,
    val decision: String,
)

enum class EventSource { GEOFENCE, VEHICLE, ANDROID_AUTO, BLUETOOTH }

data class EngineState(
    val monitoring: Boolean = false,
    val geofence: GeofenceState = GeofenceState.UNKNOWN,
    val geofenceAt: Long = 0,
    val geofenceRegisteredAt: Long = 0,
    val activityRegisteredAt: Long = 0,
    val inVehicle: SignalState = SignalState.UNKNOWN,
    val inVehicleAt: Long = 0,
    val androidAuto: SignalState = SignalState.UNKNOWN,
    val androidAutoAt: Long = 0,
    val carBluetoothConnected: Boolean = false,
    val carBluetoothAt: Long = 0,
    /** Incremented on every transition into the geofence. */
    val sessionId: Long = 0,
    /** True when the current episode may still produce a call. */
    val armed: Boolean = false,
    /** When the last qualifying vehicle signal stopped being active (null while one is active or never seen). */
    val allSignalsInactiveSince: Long? = null,
    val pending: PendingTrigger? = null,
    /** Write-ahead flag: set (and persisted) before the call is placed. */
    val calling: Boolean = false,
    val lastCallAt: Long? = null,
    val lastCallOutcome: CallOutcome? = null,
    val lastTrigger: TriggerRecord? = null,
    val prerequisites: Prerequisites = Prerequisites.NONE_CHECKED,
    val nextToken: Long = 1,
    val lastEventAt: Map<EventSource, Long> = emptyMap(),
) {
    fun phase(config: EngineConfig, now: Long): Phase = when {
        !monitoring -> Phase.STOPPED
        calling -> Phase.CALLING
        lastCallAt != null && now < lastCallAt + config.cooldownMs -> Phase.COOLDOWN
        pending != null -> Phase.PENDING_DELAYED_CALL
        geofence == GeofenceState.INSIDE && armed -> Phase.WAITING_FOR_VEHICLE_SIGNAL
        geofence == GeofenceState.INSIDE -> Phase.MONITORING_INSIDE
        else -> Phase.MONITORING_OUTSIDE
    }

    fun vehicleSignalActive(config: EngineConfig): Boolean =
        (config.activityRecognitionEnabled && inVehicle == SignalState.ACTIVE) ||
            (config.androidAutoEnabled && androidAuto == SignalState.ACTIVE)

    fun inCooldown(config: EngineConfig, now: Long): Boolean =
        lastCallAt != null && now < lastCallAt + config.cooldownMs
}

sealed interface Event {
    val at: Long

    data class StartMonitoring(override val at: Long, val prerequisites: Prerequisites) : Event
    data class StopMonitoring(override val at: Long, val reason: String) : Event
    data class GeofenceRegistered(override val at: Long) : Event
    data class ActivityRegistered(override val at: Long) : Event
    data class GeofenceTransition(override val at: Long, val entered: Boolean, val simulated: Boolean = false) : Event
    data class VehicleActivity(override val at: Long, val inVehicle: Boolean, val simulated: Boolean = false) : Event
    data class AndroidAutoChanged(override val at: Long, val state: SignalState, val simulated: Boolean = false) : Event
    data class CarBluetoothChanged(override val at: Long, val connected: Boolean, val simulated: Boolean = false) : Event
    data class TimerFired(override val at: Long, val token: Long) : Event
    data class PrerequisitesChanged(override val at: Long, val prerequisites: Prerequisites) : Event
    data class CallCompleted(override val at: Long, val outcome: CallOutcome) : Event
    data class ProcessRestored(override val at: Long) : Event
}

sealed interface Effect {
    data class ScheduleTimer(val token: Long, val at: Long) : Effect
    data class CancelTimer(val token: Long) : Effect
    data class PlaceCall(val sessionId: Long, val source: TriggerSource) : Effect
    data class SimulateCall(val sessionId: Long, val source: TriggerSource) : Effect
    data class ReportError(val reason: ErrorReason, val detail: String) : Effect
    data class Log(val category: LogCategory, val message: String) : Effect
    data class WakeWindow(val reason: WakeReason) : Effect
    data object ReleaseWindow : Effect
}

data class Result(val state: EngineState, val effects: List<Effect>)
