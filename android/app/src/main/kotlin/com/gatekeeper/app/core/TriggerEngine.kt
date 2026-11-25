package com.gatekeeper.app.core

/**
 * Deterministic trigger state machine.
 *
 * `reduce` is a pure function: given the persisted state, an event and the current
 * configuration it returns the next state plus the side effects to execute. The runtime
 * persists the returned state (synchronously) *before* executing effects, which gives
 * write-ahead semantics for calls: if the process dies after a PlaceCall effect was
 * emitted, the restored state already says a call was attempted and it is never retried.
 */
object TriggerEngine {

    fun reduce(state: EngineState, event: Event, config: EngineConfig): Result {
        val r = Reducer(state, config, event.at)
        r.handle(event)
        return Result(r.s, r.effects.toList())
    }

    private class Reducer(var s: EngineState, val config: EngineConfig, val now: Long) {
        val effects = mutableListOf<Effect>()

        fun log(category: LogCategory, message: String) {
            effects += Effect.Log(category, message)
        }

        fun handle(event: Event) {
            if (isStale(event)) {
                log(LogCategory.SYSTEM, "Ignored out-of-order ${event::class.simpleName} (older than last processed event)")
                return
            }
            when (event) {
                is Event.StartMonitoring -> onStart(event)
                is Event.StopMonitoring -> onStop(event)
                is Event.GeofenceRegistered -> onGeofenceRegistered()
                is Event.ActivityRegistered -> {
                    // A fresh registration has no knowledge of the current activity; any previous value may be stale.
                    val wasActive = s.vehicleSignalActive(config)
                    s = s.copy(activityRegisteredAt = now, inVehicle = SignalState.UNKNOWN, inVehicleAt = now)
                    log(LogCategory.VEHICLE, "Activity Recognition registered")
                    onPossibleFallingEdge(wasActive)
                }
                is Event.GeofenceTransition -> onGeofence(event)
                is Event.VehicleActivity -> onVehicle(event)
                is Event.AndroidAutoChanged -> onAndroidAuto(event)
                is Event.CarBluetoothChanged -> onBluetooth(event)
                is Event.TimerFired -> onTimer(event)
                is Event.PrerequisitesChanged -> onPrerequisites(event.prerequisites)
                is Event.CallCompleted -> onCallCompleted(event)
                is Event.ProcessRestored -> onRestored()
            }
        }

        // ---- ordering ---------------------------------------------------------------

        private fun sourceOf(event: Event): EventSource? = when (event) {
            is Event.GeofenceTransition -> EventSource.GEOFENCE
            is Event.VehicleActivity -> EventSource.VEHICLE
            is Event.AndroidAutoChanged -> EventSource.ANDROID_AUTO
            is Event.CarBluetoothChanged -> EventSource.BLUETOOTH
            else -> null
        }

        /** Per-source monotonic ordering: an event older than the last processed one of its source is stale. */
        private fun isStale(event: Event): Boolean {
            val source = sourceOf(event) ?: return false
            val last = s.lastEventAt[source] ?: return false
            return event.at < last
        }

        private fun markSource(event: Event) {
            val source = sourceOf(event) ?: return
            s = s.copy(lastEventAt = s.lastEventAt + (source to event.at))
        }

        // ---- lifecycle --------------------------------------------------------------

        private fun onStart(e: Event.StartMonitoring) {
            if (s.monitoring) {
                log(LogCategory.SYSTEM, "Start ignored: already monitoring")
                return
            }
            s = s.copy(
                monitoring = true,
                geofence = GeofenceState.UNKNOWN,
                geofenceAt = now,
                inVehicle = SignalState.UNKNOWN,
                inVehicleAt = now,
                androidAuto = SignalState.UNKNOWN,
                androidAutoAt = now,
                armed = true,
                allSignalsInactiveSince = null,
                pending = null,
                calling = false,
                prerequisites = e.prerequisites,
                lastEventAt = emptyMap(),
            )
            log(LogCategory.SYSTEM, "Monitoring started")
            if (!e.prerequisites.ok) {
                log(LogCategory.ERROR, "Monitoring started with unmet prerequisites: ${e.prerequisites.firstProblem()}")
            }
        }

        private fun onStop(e: Event.StopMonitoring) {
            if (!s.monitoring) return
            cancelPending("monitoring stopped")
            s = s.copy(monitoring = false, geofence = GeofenceState.UNKNOWN, calling = false)
            effects += Effect.ReleaseWindow
            log(LogCategory.SYSTEM, "Monitoring stopped (${e.reason})")
        }

        private fun onGeofenceRegistered() {
            s = s.copy(geofenceRegisteredAt = now)
            log(LogCategory.GEOFENCE, "Geofence registered")
        }

        private fun onRestored() {
            if (s.calling) {
                s = s.copy(calling = false, lastCallOutcome = CallOutcome.UNKNOWN_PROCESS_DIED)
                log(LogCategory.CALL, "Process restarted during a call attempt; result unknown, not retrying")
            }
            val p = s.pending ?: return
            if (!s.monitoring) {
                cancelPending("restored while stopped")
                return
            }
            when {
                now > p.deadline + config.staleTimerGraceMs -> cancelPending("pending trigger expired while the process was dead")
                now >= p.deadline -> {
                    log(LogCategory.TRIGGER, "Restored pending trigger is due; revalidating")
                    fire(p)
                }
                else -> {
                    effects += Effect.ScheduleTimer(p.token, p.deadline)
                    effects += Effect.WakeWindow(WakeReason.PENDING_TRIGGER)
                    log(LogCategory.TRIGGER, "Restored pending trigger (${p.source})")
                }
            }
        }

        // ---- geofence ---------------------------------------------------------------

        private fun onGeofence(e: Event.GeofenceTransition) {
            markSource(e)
            if (!s.monitoring) return
            val tag = if (e.simulated) " [simulated]" else ""
            val initialSync = e.at <= s.geofenceRegisteredAt + config.initialSyncWindowMs
            if (e.entered) {
                if (s.geofence == GeofenceState.INSIDE) {
                    log(LogCategory.GEOFENCE, "Duplicate ENTER ignored$tag")
                    return
                }
                s = s.copy(
                    geofence = GeofenceState.INSIDE,
                    geofenceAt = e.at,
                    sessionId = s.sessionId + 1,
                    armed = true,
                    allSignalsInactiveSince = if (s.vehicleSignalActive(config)) null else s.allSignalsInactiveSince,
                )
                if (initialSync) {
                    // Geofence (re)registration reports the current state; it is not an arrival. Vehicle
                    // state from before the registration (e.g. before a reboot) may be stale, so never
                    // fire Scenario B from it.
                    log(LogCategory.GEOFENCE, "Initial state: inside geofence$tag (no arrival trigger)")
                    return
                }
                log(LogCategory.GEOFENCE, "ENTER geofence$tag")
                onGenuineEnter()
            } else {
                if (s.geofence == GeofenceState.OUTSIDE) {
                    log(LogCategory.GEOFENCE, "Duplicate EXIT ignored$tag")
                    return
                }
                cancelPending("exited geofence")
                s = s.copy(geofence = GeofenceState.OUTSIDE, geofenceAt = e.at, armed = true)
                effects += Effect.ReleaseWindow
                log(LogCategory.GEOFENCE, if (initialSync) "Initial state: outside geofence$tag" else "EXIT geofence$tag")
            }
        }

        private fun onGenuineEnter() {
            val inVehicle = config.activityRecognitionEnabled && s.inVehicle == SignalState.ACTIVE
            val aaConnected = config.androidAutoEnabled && s.androidAuto == SignalState.ACTIVE
            val btConnected = config.carBluetoothEnabled && s.carBluetoothConnected
            when {
                inVehicle && config.immediateTriggerEnabled ->
                    attemptCall(TriggerSource.ENTER_WHILE_IN_VEHICLE)
                inVehicle -> scheduleDelayed(TriggerSource.ENTER_WHILE_IN_VEHICLE_DELAYED)
                aaConnected -> scheduleDelayed(TriggerSource.ENTER_WITH_ANDROID_AUTO)
                btConnected -> scheduleDelayed(TriggerSource.ENTER_WITH_CAR_BLUETOOTH)
                else -> {
                    log(LogCategory.TRIGGER, "Entered without an active vehicle signal: waiting")
                    if (config.androidAutoEnabled) effects += Effect.WakeWindow(WakeReason.GEOFENCE_ENTER)
                }
            }
        }

        // ---- vehicle signals ----------------------------------------------------------

        private fun onVehicle(e: Event.VehicleActivity) {
            markSource(e)
            val tag = if (e.simulated) " [simulated]" else ""
            val next = if (e.inVehicle) SignalState.ACTIVE else SignalState.INACTIVE
            val prev = s.inVehicle
            if (prev == next) {
                log(LogCategory.VEHICLE, "Duplicate IN_VEHICLE ${if (e.inVehicle) "ENTER" else "EXIT"} ignored$tag")
                return
            }
            val wasActive = s.vehicleSignalActive(config)
            s = s.copy(inVehicle = next, inVehicleAt = e.at)
            log(LogCategory.VEHICLE, "IN_VEHICLE ${if (e.inVehicle) "ENTER" else "EXIT"}$tag")
            if (!config.activityRecognitionEnabled || !s.monitoring) return
            if (e.inVehicle) {
                val sync = e.at <= s.activityRegisteredAt + config.initialSyncWindowMs
                if (sync) {
                    log(LogCategory.VEHICLE, "IN_VEHICLE reported during registration sync: not treated as a new signal")
                    s = s.copy(allSignalsInactiveSince = null)
                    return
                }
                onRisingEdge(TriggerSource.ACTIVITY_IN_VEHICLE, WakeReason.IN_VEHICLE)
            } else {
                onPossibleFallingEdge(wasActive)
            }
        }

        private fun onAndroidAuto(e: Event.AndroidAutoChanged) {
            markSource(e)
            val tag = if (e.simulated) " [simulated]" else ""
            val prev = s.androidAuto
            if (prev == e.state) return
            val wasActive = s.vehicleSignalActive(config)
            s = s.copy(androidAuto = e.state, androidAutoAt = e.at)
            log(LogCategory.ANDROID_AUTO, "Android Auto ${e.state.name.lowercase()}$tag")
            if (!config.androidAutoEnabled || !s.monitoring) return
            if (e.state == SignalState.ACTIVE) {
                // A reading after "not observed" is only a real connection if the car just connected over
                // Bluetooth (that is what woke us). Otherwise it may be a car that has been connected for a
                // long time (e.g. the UI was opened while sitting in the parked car).
                val genuine = prev == SignalState.INACTIVE ||
                    (s.carBluetoothConnected && e.at - s.carBluetoothAt <= config.bluetoothAaCorrelationMs) ||
                    e.simulated
                if (!genuine) {
                    log(LogCategory.ANDROID_AUTO, "Android Auto already connected when first observed: not treated as a new connection")
                    s = s.copy(allSignalsInactiveSince = null)
                    return
                }
                onRisingEdge(TriggerSource.ANDROID_AUTO, null)
            } else {
                onPossibleFallingEdge(wasActive)
            }
        }

        private fun onBluetooth(e: Event.CarBluetoothChanged) {
            markSource(e)
            val tag = if (e.simulated) " [simulated]" else ""
            if (s.carBluetoothConnected == e.connected) return
            val wasActive = s.vehicleSignalActive(config)
            s = s.copy(carBluetoothConnected = e.connected, carBluetoothAt = e.at)
            log(LogCategory.BLUETOOTH, "Car Bluetooth ${if (e.connected) "connected" else "disconnected"}$tag")
            if (!s.monitoring) return
            if (!e.connected) {
                onPossibleFallingEdge(wasActive)
            } else if (config.carBluetoothEnabled) {
                // A connect broadcast is always a fresh connection (the state is cleared on reboot and car
                // change), so unlike Android Auto it needs no "first observed" check.
                onRisingEdge(TriggerSource.CAR_BLUETOOTH, WakeReason.CAR_BLUETOOTH)
            } else if (s.geofence == GeofenceState.INSIDE && config.androidAutoEnabled) {
                // Bluetooth only wakes us to check Android Auto.
                effects += Effect.WakeWindow(WakeReason.CAR_BLUETOOTH)
            }
        }

        private fun onRisingEdge(source: TriggerSource, wake: WakeReason?) {
            val inactiveSince = s.allSignalsInactiveSince
            s = s.copy(allSignalsInactiveSince = null)
            if (s.geofence != GeofenceState.INSIDE) return
            if (s.pending != null) {
                log(LogCategory.TRIGGER, "$source while a trigger is already pending: merged (no duplicate)")
                return
            }
            if (!s.armed) {
                if (inactiveSince != null && now - inactiveSince >= config.rearmQuietMs) {
                    s = s.copy(armed = true)
                    log(LogCategory.TRIGGER, "Re-armed: vehicle signals were inactive for ${(now - inactiveSince) / 1000}s")
                } else {
                    record(source, "suppressed: already called for this episode")
                    log(LogCategory.TRIGGER, "$source suppressed: a call was already made for this arrival/departure")
                    return
                }
            }
            if (wake != null) effects += Effect.WakeWindow(wake)
            scheduleDelayed(source)
        }

        private fun onPossibleFallingEdge(wasActive: Boolean) {
            if (!wasActive || s.vehicleSignalActive(config)) return
            s = s.copy(allSignalsInactiveSince = now)
            cancelPending("vehicle signal no longer active")
        }

        // ---- triggers -------------------------------------------------------------------

        private fun scheduleDelayed(source: TriggerSource) {
            if (s.pending != null) {
                log(LogCategory.TRIGGER, "$source merged into pending trigger")
                return
            }
            if (!s.armed) {
                record(source, "suppressed: already called for this episode")
                return
            }
            if (s.inCooldown(config, now)) {
                record(source, "suppressed: cooldown")
                log(LogCategory.TRIGGER, "$source suppressed: cooldown active")
                return
            }
            val problem = s.prerequisites.firstProblem()
            if (problem != null) {
                record(source, "blocked: $problem")
                effects += Effect.ReportError(problem, "Trigger $source blocked")
                log(LogCategory.ERROR, "$source blocked: $problem")
                return
            }
            val p = PendingTrigger(
                token = s.nextToken,
                createdAt = now,
                deadline = now + config.delayMs,
                source = source,
                sessionId = s.sessionId,
            )
            s = s.copy(pending = p, nextToken = s.nextToken + 1)
            effects += Effect.ScheduleTimer(p.token, p.deadline)
            effects += Effect.WakeWindow(WakeReason.PENDING_TRIGGER)
            record(source, "pending ${config.delayMs / 1000}s revalidation")
            log(LogCategory.TRIGGER, "$source: call scheduled in ${config.delayMs / 1000}s (revalidate first)")
        }

        private fun onTimer(e: Event.TimerFired) {
            val p = s.pending
            if (p == null || p.token != e.token) {
                log(LogCategory.TRIGGER, "Stale timer ${e.token} ignored")
                return
            }
            fire(p)
        }

        private fun fire(p: PendingTrigger) {
            val reason = when {
                !s.monitoring -> "monitoring stopped"
                s.geofence != GeofenceState.INSIDE -> "no longer inside geofence"
                s.sessionId != p.sessionId -> "geofence session changed"
                !s.vehicleSignalActive(config) -> "no vehicle signal active"
                else -> null
            }
            if (reason != null) {
                cancelPending("revalidation failed: $reason")
                return
            }
            s = s.copy(pending = null)
            attemptCall(p.source)
        }

        private fun attemptCall(source: TriggerSource) {
            val p = s.pending
            if (p != null) {
                effects += Effect.CancelTimer(p.token)
                s = s.copy(pending = null)
            }
            val blocked = when {
                !s.monitoring -> "monitoring stopped"
                s.calling -> "a call is already in progress"
                !s.armed -> "already called for this episode"
                s.inCooldown(config, now) -> "cooldown active"
                else -> null
            }
            if (blocked != null) {
                record(source, "suppressed: $blocked")
                log(LogCategory.TRIGGER, "$source suppressed: $blocked")
                return
            }
            val problem = s.prerequisites.firstProblem()
            if (problem != null) {
                record(source, "blocked: $problem")
                effects += Effect.ReportError(problem, "Gate call not placed")
                log(LogCategory.ERROR, "Gate call not placed: $problem")
                return
            }
            s = s.copy(calling = true, lastCallAt = now, armed = false)
            if (config.testMode) {
                record(source, "simulated call (test mode)")
                effects += Effect.SimulateCall(s.sessionId, source)
                log(LogCategory.TEST, "TEST MODE: would call the gate now ($source)")
            } else {
                record(source, "calling")
                effects += Effect.PlaceCall(s.sessionId, source)
                log(LogCategory.CALL, "Placing gate call ($source)")
            }
        }

        private fun onCallCompleted(e: Event.CallCompleted) {
            if (!s.calling) {
                log(LogCategory.CALL, "Call result ${e.outcome} arrived with no call in progress")
            }
            s = s.copy(calling = false, lastCallOutcome = e.outcome)
            log(LogCategory.CALL, "Call result: ${e.outcome}")
            if (e.outcome != CallOutcome.INITIATED && e.outcome != CallOutcome.SIMULATED) {
                effects += Effect.ReportError(ErrorReason.CALL_FAILED, e.outcome.name)
            }
        }

        private fun onPrerequisites(p: Prerequisites) {
            val before = s.prerequisites
            s = s.copy(prerequisites = p)
            if (before != p) log(LogCategory.SYSTEM, "Prerequisites: ${p.firstProblem() ?: "all OK"}")
            val problem = p.firstProblem()
            if (problem != null && s.pending != null) {
                cancelPending("prerequisite lost: $problem")
                effects += Effect.ReportError(problem, "Pending gate call cancelled")
            }
        }

        // ---- helpers ------------------------------------------------------------------------

        private fun cancelPending(reason: String) {
            val p = s.pending ?: return
            effects += Effect.CancelTimer(p.token)
            s = s.copy(pending = null)
            record(p.source, "cancelled: $reason")
            log(LogCategory.TRIGGER, "Pending trigger cancelled: $reason")
        }

        private fun record(source: TriggerSource, decision: String) {
            s = s.copy(lastTrigger = TriggerRecord(now, source, decision))
        }
    }
}
