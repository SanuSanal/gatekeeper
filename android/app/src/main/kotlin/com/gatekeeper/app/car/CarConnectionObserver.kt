package com.gatekeeper.app.car

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.car.app.connection.CarConnection
import androidx.lifecycle.LiveData
import androidx.lifecycle.Observer
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.core.Event
import com.gatekeeper.app.core.SignalState

/**
 * Observes Android Auto projection state through the public CarConnection API.
 *
 * Limitation (documented): CarConnection is a LiveData backed by a content-provider query plus a
 * *dynamically registered* receiver, so it only reports while our process is alive and observing.
 * It is therefore acquired only during a decision window (foreground service) or while the UI is
 * visible. When nobody observes, the state is reported as UNKNOWN (treated as "not active").
 */
object CarConnectionObserver {
    private val main = Handler(Looper.getMainLooper())
    private val owners = mutableSetOf<String>()
    private var liveData: LiveData<Int>? = null
    private var observer: Observer<Int>? = null

    @Volatile
    var lastObservedAt: Long? = null
        private set

    fun acquire(context: Context, owner: String) {
        val app = context.applicationContext
        main.post {
            if (!owners.add(owner) || owners.size > 1) return@post
            val runtime = EngineRuntime.get(app)
            val obs = Observer<Int> { type ->
                val now = System.currentTimeMillis()
                lastObservedAt = now
                val state = if (type == CarConnection.CONNECTION_TYPE_PROJECTION) SignalState.ACTIVE else SignalState.INACTIVE
                runtime.dispatch(Event.AndroidAutoChanged(now, state))
            }
            try {
                val ld = CarConnection(app).type
                ld.observeForever(obs)
                liveData = ld
                observer = obs
            } catch (e: Exception) {
                owners.remove(owner)
                runtime.log(com.gatekeeper.app.core.LogCategory.ERROR, "Android Auto observer failed: ${e.message}")
            }
        }
    }

    fun release(context: Context, owner: String) {
        val app = context.applicationContext
        main.post {
            if (!owners.remove(owner) || owners.isNotEmpty()) return@post
            val ld = liveData
            val obs = observer
            if (ld != null && obs != null) ld.removeObserver(obs)
            liveData = null
            observer = null
            EngineRuntime.get(app).dispatch(Event.AndroidAutoChanged(System.currentTimeMillis(), SignalState.UNKNOWN))
        }
    }
}
