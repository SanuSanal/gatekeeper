package com.gatekeeper.app.core

/**
 * Deterministic test harness: a fake clock, fake timers and a fake call executor around the
 * pure [TriggerEngine]. Effects are applied the same way the Android runtime applies them.
 */
class EngineHarness(
    var config: EngineConfig = EngineConfig(),
    var state: EngineState = EngineState(),
    var now: Long = 1_700_000_000_000L,
) {
    val timers = mutableMapOf<Long, Long>() // token -> due time
    val calls = mutableListOf<Effect.PlaceCall>()
    val simulatedCalls = mutableListOf<Effect.SimulateCall>()
    val errors = mutableListOf<Effect.ReportError>()
    val logs = mutableListOf<String>()
    val wakes = mutableListOf<WakeReason>()

    /** When true, every PlaceCall is answered with CallCompleted(INITIATED), like a successful placeCall(). */
    var autoCompleteCalls = true

    private val queue = ArrayDeque<Event>()
    private var draining = false

    fun send(event: Event) {
        queue.addLast(event)
        if (draining) return
        draining = true
        try {
            while (queue.isNotEmpty()) {
                val e = queue.removeFirst()
                val r = TriggerEngine.reduce(state, e, config)
                state = r.state
                r.effects.forEach(::apply)
            }
        } finally {
            draining = false
        }
    }

    private fun apply(effect: Effect) {
        when (effect) {
            is Effect.ScheduleTimer -> timers[effect.token] = effect.at
            is Effect.CancelTimer -> timers.remove(effect.token)
            is Effect.PlaceCall -> {
                calls += effect
                if (autoCompleteCalls) queue.addLast(Event.CallCompleted(now, CallOutcome.INITIATED))
            }
            is Effect.SimulateCall -> {
                simulatedCalls += effect
                queue.addLast(Event.CallCompleted(now, CallOutcome.SIMULATED))
            }
            is Effect.ReportError -> errors += effect
            is Effect.Log -> logs += "${effect.category}: ${effect.message}"
            is Effect.WakeWindow -> wakes += effect.reason
            Effect.ReleaseWindow -> Unit
        }
    }

    /** Advances the fake clock, firing any timers that fall due on the way, in order. */
    fun advance(ms: Long) {
        val target = now + ms
        while (true) {
            val next = timers.entries.filter { it.value <= target }.minByOrNull { it.value } ?: break
            timers.remove(next.key)
            now = maxOf(now, next.value)
            send(Event.TimerFired(now, next.key))
        }
        now = target
    }

    fun advanceSeconds(s: Long) = advance(s * 1000)

    // ---- convenience events -----------------------------------------------------------

    fun start(prerequisites: Prerequisites = Prerequisites.ALL_OK) {
        send(Event.StartMonitoring(now, prerequisites))
        send(Event.GeofenceRegistered(now))
        send(Event.ActivityRegistered(now))
    }

    /** Monitoring started while outside; sync windows elapsed. */
    fun startOutside(prerequisites: Prerequisites = Prerequisites.ALL_OK) {
        start(prerequisites)
        advanceSeconds(1)
        exit() // initial-sync EXIT
        advanceSeconds(60)
    }

    /** Monitoring started while already inside (initial-sync ENTER); sync windows elapsed. */
    fun startInside(prerequisites: Prerequisites = Prerequisites.ALL_OK) {
        start(prerequisites)
        advanceSeconds(1)
        enter() // initial-sync ENTER
        advanceSeconds(60)
    }

    fun enter() = send(Event.GeofenceTransition(now, entered = true))
    fun exit() = send(Event.GeofenceTransition(now, entered = false))
    fun inVehicle(active: Boolean) = send(Event.VehicleActivity(now, active))
    fun androidAuto(state: SignalState) = send(Event.AndroidAutoChanged(now, state))
    fun carBluetooth(connected: Boolean) = send(Event.CarBluetoothChanged(now, connected))
    fun stop() = send(Event.StopMonitoring(now, "test"))
    fun prerequisites(p: Prerequisites) = send(Event.PrerequisitesChanged(now, p))

    fun phase(): Phase = state.phase(config, now)

    /** Simulates process death + recreation: only the persisted state survives. */
    fun recreateProcess(): EngineHarness {
        val h = EngineHarness(config, state, now)
        h.send(Event.ProcessRestored(now))
        return h
    }
}
