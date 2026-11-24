package com.gatekeeper.app.store

import android.content.Context
import android.util.Log
import com.gatekeeper.app.core.CallOutcome
import com.gatekeeper.app.core.EngineState
import com.gatekeeper.app.core.EventSource
import com.gatekeeper.app.core.GeofenceState
import com.gatekeeper.app.core.PendingTrigger
import com.gatekeeper.app.core.Prerequisites
import com.gatekeeper.app.core.SignalState
import com.gatekeeper.app.core.TriggerRecord
import com.gatekeeper.app.core.TriggerSource
import org.json.JSONObject

/**
 * Persists [EngineState] as JSON. `save` uses commit() so the state (in particular the write-ahead
 * `calling` flag) is on disk before any effect such as placing a call is executed.
 */
class EngineStateStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("gatekeeper_engine", Context.MODE_PRIVATE)

    @Synchronized
    fun load(): EngineState {
        val raw = prefs.getString(KEY, null) ?: return EngineState()
        return try {
            decode(JSONObject(raw))
        } catch (e: Exception) {
            Log.e("GateKeeper", "Corrupt engine state, resetting", e)
            EngineState()
        }
    }

    @Synchronized
    fun save(state: EngineState): Boolean = prefs.edit().putString(KEY, encode(state).toString()).commit()

    private fun encode(s: EngineState): JSONObject = JSONObject().apply {
        put("monitoring", s.monitoring)
        put("geofence", s.geofence.name)
        put("geofenceAt", s.geofenceAt)
        put("geofenceRegisteredAt", s.geofenceRegisteredAt)
        put("activityRegisteredAt", s.activityRegisteredAt)
        put("inVehicle", s.inVehicle.name)
        put("inVehicleAt", s.inVehicleAt)
        put("androidAuto", s.androidAuto.name)
        put("androidAutoAt", s.androidAutoAt)
        put("carBluetoothConnected", s.carBluetoothConnected)
        put("carBluetoothAt", s.carBluetoothAt)
        put("sessionId", s.sessionId)
        put("armed", s.armed)
        s.allSignalsInactiveSince?.let { put("allSignalsInactiveSince", it) }
        s.pending?.let {
            put("pending", JSONObject().apply {
                put("token", it.token)
                put("createdAt", it.createdAt)
                put("deadline", it.deadline)
                put("source", it.source.name)
                put("sessionId", it.sessionId)
            })
        }
        put("calling", s.calling)
        s.lastCallAt?.let { put("lastCallAt", it) }
        s.lastCallOutcome?.let { put("lastCallOutcome", it.name) }
        s.lastTrigger?.let {
            put("lastTrigger", JSONObject().apply {
                put("at", it.at)
                put("source", it.source.name)
                put("decision", it.decision)
            })
        }
        put("prerequisites", JSONObject().apply {
            put("permissionsOk", s.prerequisites.permissionsOk)
            put("gateNumberValid", s.prerequisites.gateNumberValid)
            put("simAvailable", s.prerequisites.simAvailable)
        })
        put("nextToken", s.nextToken)
        put("lastEventAt", JSONObject().apply { s.lastEventAt.forEach { (k, v) -> put(k.name, v) } })
    }

    private fun decode(o: JSONObject): EngineState {
        val pending = o.optJSONObject("pending")?.let {
            PendingTrigger(
                token = it.getLong("token"),
                createdAt = it.getLong("createdAt"),
                deadline = it.getLong("deadline"),
                source = TriggerSource.valueOf(it.getString("source")),
                sessionId = it.getLong("sessionId"),
            )
        }
        val trigger = o.optJSONObject("lastTrigger")?.let {
            TriggerRecord(it.getLong("at"), TriggerSource.valueOf(it.getString("source")), it.getString("decision"))
        }
        val p = o.optJSONObject("prerequisites")
        val lastEvents = mutableMapOf<EventSource, Long>()
        o.optJSONObject("lastEventAt")?.let { j ->
            j.keys().forEach { k -> runCatching { lastEvents[EventSource.valueOf(k)] = j.getLong(k) } }
        }
        return EngineState(
            monitoring = o.optBoolean("monitoring"),
            geofence = GeofenceState.valueOf(o.optString("geofence", "UNKNOWN")),
            geofenceAt = o.optLong("geofenceAt"),
            geofenceRegisteredAt = o.optLong("geofenceRegisteredAt"),
            activityRegisteredAt = o.optLong("activityRegisteredAt"),
            inVehicle = SignalState.valueOf(o.optString("inVehicle", "UNKNOWN")),
            inVehicleAt = o.optLong("inVehicleAt"),
            androidAuto = SignalState.valueOf(o.optString("androidAuto", "UNKNOWN")),
            androidAutoAt = o.optLong("androidAutoAt"),
            carBluetoothConnected = o.optBoolean("carBluetoothConnected"),
            carBluetoothAt = o.optLong("carBluetoothAt"),
            sessionId = o.optLong("sessionId"),
            armed = o.optBoolean("armed"),
            allSignalsInactiveSince = if (o.has("allSignalsInactiveSince")) o.getLong("allSignalsInactiveSince") else null,
            pending = pending,
            calling = o.optBoolean("calling"),
            lastCallAt = if (o.has("lastCallAt")) o.getLong("lastCallAt") else null,
            lastCallOutcome = if (o.has("lastCallOutcome")) CallOutcome.valueOf(o.getString("lastCallOutcome")) else null,
            lastTrigger = trigger,
            prerequisites = if (p != null) {
                Prerequisites(p.optBoolean("permissionsOk"), p.optBoolean("gateNumberValid"), p.optBoolean("simAvailable"))
            } else {
                Prerequisites.NONE_CHECKED
            },
            nextToken = o.optLong("nextToken", 1),
            lastEventAt = lastEvents,
        )
    }

    private companion object {
        const val KEY = "state_v1"
    }
}
