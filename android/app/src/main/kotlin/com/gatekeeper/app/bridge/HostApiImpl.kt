package com.gatekeeper.app.bridge

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import com.gatekeeper.app.EngineRuntime
import com.gatekeeper.app.car.CarConnectionObserver
import com.gatekeeper.app.core.Event
import com.gatekeeper.app.core.LogCategory
import com.gatekeeper.app.core.SignalState
import com.gatekeeper.app.store.AppConfig
import com.gatekeeper.app.store.Limits
import com.gatekeeper.app.system.PermissionMonitor
import com.gatekeeper.app.telephony.PhoneNumbers
import com.gatekeeper.app.update.UpdateException
import com.gatekeeper.app.update.UpdateInstaller
import android.os.Build
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

class HostApiImpl(
    private val activity: Activity,
    private val runtime: EngineRuntime,
    private val flutterApi: GateKeeperFlutterApi,
) : GateKeeperHostApi {
    private val scope = CoroutineScope(Dispatchers.Main)
    private var pendingAssociation: CompletableDeferred<String?>? = null
    private val statusListener: () -> Unit = { pushStatus() }
    private val updates = UpdateInstaller(activity)

    fun attach() {
        runtime.addListener(statusListener)
    }

    fun detach() {
        runtime.removeListener(statusListener)
        setUiVisible(false)
    }

    private fun pushStatus() {
        scope.launch { runCatching { flutterApi.onStatusChanged(getStatus()) } }
    }

    // ---- settings -----------------------------------------------------------------------

    override fun loadSettings(): SettingsMessage {
        val c = runtime.configStore.load()
        return SettingsMessage(
            gateNumber = c.gateNumber,
            simSubscriptionId = c.simSubscriptionId?.toLong(),
            simLabel = c.simLabel,
            latitude = c.latitude,
            longitude = c.longitude,
            radiusMeters = c.radiusMeters.toLong(),
            delaySeconds = c.delaySeconds.toLong(),
            cooldownMinutes = c.cooldownMinutes.toLong(),
            immediateTrigger = c.immediateTrigger,
            androidAutoEnabled = c.androidAutoEnabled,
            activityRecognitionEnabled = c.activityRecognitionEnabled,
            testMode = c.testMode,
            carDeviceName = c.carDeviceName,
            carDeviceAssociated = runtime.carAssociated(c),
            onboardingComplete = c.onboardingComplete,
        )
    }

    override fun saveSettings(settings: SettingsMessage) {
        val number = settings.gateNumber?.takeIf { it.isNotBlank() }
        if (number != null && PhoneNumbers.normalizeForCalling(activity, number) == null) {
            throw FlutterError("invalid", "Gate number is not a valid, non-emergency phone number", null)
        }
        val lat = settings.latitude
        val lng = settings.longitude
        if ((lat == null) != (lng == null) || (lat != null && lat !in -90.0..90.0) || (lng != null && lng !in -180.0..180.0)) {
            throw FlutterError("invalid", "Invalid coordinates", null)
        }
        if (settings.radiusMeters !in Limits.RADIUS_MIN..Limits.RADIUS_MAX ||
            settings.delaySeconds !in Limits.DELAY_MIN..Limits.DELAY_MAX ||
            settings.cooldownMinutes !in Limits.COOLDOWN_MIN..Limits.COOLDOWN_MAX
        ) {
            throw FlutterError("invalid", "Value out of range", null)
        }
        val before = runtime.configStore.load()
        val after = runtime.configStore.update {
            it.copy(
                gateNumber = number?.let { n -> PhoneNumbers.normalize(n) },
                simSubscriptionId = settings.simSubscriptionId?.toInt(),
                simLabel = settings.simLabel,
                latitude = lat,
                longitude = lng,
                radiusMeters = settings.radiusMeters.toInt(),
                delaySeconds = settings.delaySeconds.toInt(),
                cooldownMinutes = settings.cooldownMinutes.toInt(),
                immediateTrigger = settings.immediateTrigger,
                androidAutoEnabled = settings.androidAutoEnabled,
                activityRecognitionEnabled = settings.activityRecognitionEnabled,
                testMode = settings.testMode,
                onboardingComplete = settings.onboardingComplete,
            )
        }
        if (before.testMode != after.testMode) {
            runtime.log(LogCategory.TEST, if (after.testMode) "Test mode ON: no real calls" else "Test mode OFF")
        }
        if (needsReregistration(before, after)) runtime.restoreRegistrations("settings changed")
        runtime.refreshPrerequisites()
    }

    private fun needsReregistration(a: AppConfig, b: AppConfig) =
        a.latitude != b.latitude || a.longitude != b.longitude || a.radiusMeters != b.radiusMeters ||
            a.activityRecognitionEnabled != b.activityRecognitionEnabled ||
            (a.testMode && !b.testMode) // clear any simulated geofence state with a fresh sync

    override fun listSims(): List<SimCardMessage> = runtime.sims.list().map {
        SimCardMessage(it.subscriptionId.toLong(), it.slotIndex.toLong(), it.carrierName, it.displayName, it.callCapable)
    }

    override fun validatePhoneNumber(number: String): String? = PhoneNumbers.normalizeForCalling(activity, number)

    // ---- status -------------------------------------------------------------------------

    override fun getStatus(): StatusMessage {
        val config = runtime.configStore.load()
        val s = runtime.state
        val now = System.currentTimeMillis()
        val engineConfig = config.engineConfig()
        return StatusMessage(
            monitoring = s.monitoring,
            phase = s.phase(engineConfig, now).name,
            geofence = s.geofence.name,
            vehicle = if (config.activityRecognitionEnabled) s.inVehicle.name else "DISABLED",
            androidAuto = if (config.androidAutoEnabled) s.androidAuto.name else "DISABLED",
            carBluetoothConnected = s.carBluetoothConnected,
            androidAutoObservedAt = CarConnectionObserver.lastObservedAt,
            lastTriggerAt = s.lastTrigger?.at,
            lastTriggerSource = s.lastTrigger?.source?.name,
            lastTriggerDecision = s.lastTrigger?.decision,
            lastCallAt = s.lastCallAt,
            lastCallOutcome = s.lastCallOutcome?.name,
            pendingDeadline = s.pending?.deadline,
            testMode = config.testMode,
            problems = runtime.problems(config),
        )
    }

    override fun refresh(): StatusMessage {
        runtime.restoreIfInvalidated()
        runtime.refreshPrerequisites()
        return getStatus()
    }

    // ---- monitoring ---------------------------------------------------------------------

    override suspend fun startMonitoring(): StartResult {
        val r = runtime.startMonitoring()
        return StartResult(r.started, r.problems)
    }

    override fun stopMonitoring() = runtime.stopMonitoring("user")

    override fun getLogs(limit: Long): List<LogEntryMessage> =
        runtime.logs.read(limit.toInt()).map { LogEntryMessage(it.timestamp, it.category, it.message) }

    override fun clearLogs() = runtime.logs.clear()

    @SuppressLint("MissingPermission")
    override suspend fun getCurrentLocation(): LocationMessage? {
        if (!PermissionMonitor.foregroundLocationOk(activity)) {
            throw FlutterError("permission", "Location permission not granted", null)
        }
        val client = LocationServices.getFusedLocationProviderClient(activity)
        val cts = CancellationTokenSource()
        val loc = withTimeoutOrNull(20_000) {
            client.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, cts.token).await()
        } ?: run {
            cts.cancel()
            client.lastLocation.await()
        }
        return loc?.let { LocationMessage(it.latitude, it.longitude, if (it.hasAccuracy()) it.accuracy.toDouble() else null) }
    }

    override suspend fun searchPlaces(query: String): List<PlaceMessage> {
        val q = query.trim()
        if (q.length < 3 || !android.location.Geocoder.isPresent()) return emptyList()
        val geocoder = android.location.Geocoder(activity)
        val addresses: List<android.location.Address> = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                withTimeoutOrNull(15_000) {
                    kotlinx.coroutines.suspendCancellableCoroutine { cont ->
                        geocoder.getFromLocationName(q, 6, object : android.location.Geocoder.GeocodeListener {
                            override fun onGeocode(addresses: MutableList<android.location.Address>) {
                                if (cont.isActive) cont.resumeWith(Result.success(addresses.toList()))
                            }

                            override fun onError(errorMessage: String?) {
                                if (cont.isActive) cont.resumeWith(Result.success(emptyList()))
                            }
                        })
                    }
                } ?: emptyList()
            } else {
                kotlinx.coroutines.withContext(Dispatchers.IO) {
                    @Suppress("DEPRECATION")
                    geocoder.getFromLocationName(q, 6).orEmpty()
                }
            }
        } catch (e: java.io.IOException) {
            throw FlutterError("search_failed", "Address search needs an internet connection", null)
        }
        return addresses.filter { it.hasLatitude() && it.hasLongitude() }.map { a ->
            val label = (0..a.maxAddressLineIndex).mapNotNull { a.getAddressLine(it) }.joinToString(", ")
                .ifBlank { listOfNotNull(a.featureName, a.locality, a.countryName).joinToString(", ") }
            PlaceMessage(label = label.ifBlank { "%.5f, %.5f".format(a.latitude, a.longitude) }, latitude = a.latitude, longitude = a.longitude)
        }
    }

    // ---- car association ----------------------------------------------------------------------

    override suspend fun associateCar(): String? {
        pendingAssociation?.cancel()
        val deferred = CompletableDeferred<String?>()
        pendingAssociation = deferred
        runtime.carAssociation.start(
            activity,
            launch = { sender: IntentSender ->
                try {
                    activity.startIntentSenderForResult(sender, REQUEST_ASSOCIATE, null, 0, 0, 0)
                } catch (e: Exception) {
                    deferred.completeExceptionally(FlutterError("association", e.message, null))
                }
            },
            onError = { msg -> deferred.completeExceptionally(FlutterError("association", msg, null)) },
        )
        return deferred.await()
    }

    /** Forwarded from MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_ASSOCIATE) return false
        val deferred = pendingAssociation ?: return true
        pendingAssociation = null
        val car = runtime.carAssociation.parseResult(resultCode, data)
        if (car == null) {
            deferred.complete(null)
            return true
        }
        val old = runtime.configStore.load()
        if (old.carDeviceAddress != null && !old.carDeviceAddress.equals(car.address, ignoreCase = true)) {
            runtime.carAssociation.disassociate(old.carDeviceAddress, old.carAssociationId)
        }
        runtime.configStore.update {
            it.copy(carDeviceAddress = car.address, carDeviceName = car.name ?: "Car", carAssociationId = car.associationId)
        }
        runtime.log(LogCategory.BLUETOOTH, "Car associated: ${car.name ?: "unnamed device"}")
        deferred.complete(car.name ?: "Car")
        pushStatus()
        return true
    }

    override fun disassociateCar() {
        val c = runtime.configStore.load()
        runtime.carAssociation.disassociate(c.carDeviceAddress, c.carAssociationId)
        runtime.configStore.update { it.copy(carDeviceAddress = null, carDeviceName = null, carAssociationId = null) }
        runtime.log(LogCategory.BLUETOOTH, "Car association removed")
        pushStatus()
    }

    // ---- test mode -------------------------------------------------------------------------------

    override fun simulateEvent(event: String) {
        if (!runtime.configStore.load().testMode) {
            throw FlutterError("not_test_mode", "Simulated events are only allowed in test mode", null)
        }
        val now = System.currentTimeMillis()
        val e = when (event) {
            "enter" -> Event.GeofenceTransition(now, entered = true, simulated = true)
            "exit" -> Event.GeofenceTransition(now, entered = false, simulated = true)
            "vehicle_on" -> Event.VehicleActivity(now, inVehicle = true, simulated = true)
            "vehicle_off" -> Event.VehicleActivity(now, inVehicle = false, simulated = true)
            "aa_on" -> Event.AndroidAutoChanged(now, SignalState.ACTIVE, simulated = true)
            "aa_off" -> Event.AndroidAutoChanged(now, SignalState.INACTIVE, simulated = true)
            "bt_on" -> Event.CarBluetoothChanged(now, connected = true, simulated = true)
            "bt_off" -> Event.CarBluetoothChanged(now, connected = false, simulated = true)
            else -> throw FlutterError("invalid", "Unknown simulated event '$event'", null)
        }
        runtime.dispatch(e)
    }

    override fun setUiVisible(visible: Boolean) {
        if (!runtime.configStore.load().androidAutoEnabled) {
            CarConnectionObserver.release(activity, UI_OWNER)
            return
        }
        if (visible) CarConnectionObserver.acquire(activity, UI_OWNER) else CarConnectionObserver.release(activity, UI_OWNER)
    }

    // ---- updates --------------------------------------------------------------------------------

    override fun getAppInfo(): AppInfoMessage {
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return AppInfoMessage(
            versionName = info.versionName ?: "0.0.0",
            versionCode = info.longVersionCode,
            supportedAbis = Build.SUPPORTED_ABIS.toList(),
            canInstallPackages = updates.canInstallPackages(),
        )
    }

    override suspend fun downloadAndInstallUpdate(url: String, fileName: String, sha256: String?): String {
        try {
            val result = updates.downloadAndInstall(activity, url, fileName, sha256) { received, total ->
                scope.launch { runCatching { flutterApi.onUpdateProgress(received, total) } }
            }
            runtime.log(LogCategory.SYSTEM, "Update $fileName: $result")
            return result
        } catch (e: UpdateException) {
            runtime.log(LogCategory.ERROR, "Update failed: ${e.message}")
            throw FlutterError("update_failed", e.message, null)
        } catch (e: java.io.IOException) {
            runtime.log(LogCategory.ERROR, "Update download failed: ${e.message}")
            throw FlutterError("update_failed", "Download failed: ${e.message}", null)
        }
    }

    override fun openInstallPermissionSettings() = updates.openInstallPermissionSettings(activity)

    companion object {
        const val REQUEST_ASSOCIATE = 4711
        private const val UI_OWNER = "ui"
    }
}
