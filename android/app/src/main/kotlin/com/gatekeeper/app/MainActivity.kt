package com.gatekeeper.app

import com.gatekeeper.app.bridge.GateKeeperFlutterApi
import com.gatekeeper.app.bridge.GateKeeperHostApi
import com.gatekeeper.app.bridge.HostApiImpl
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var hostApi: HostApiImpl? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val api = HostApiImpl(this, EngineRuntime.get(this), GateKeeperFlutterApi(messenger))
        GateKeeperHostApi.setUp(messenger, api)
        api.attach()
        hostApi = api
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        hostApi?.detach()
        GateKeeperHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        hostApi = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
