package com.gatekeeper.app.store

import android.content.Context
import com.gatekeeper.app.core.EngineConfig

/** User configuration. Edited and validated in Flutter, persisted natively so receivers can read it without Flutter. */
data class AppConfig(
    val gateNumber: String? = null,
    val simSubscriptionId: Int? = null,
    val simLabel: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val radiusMeters: Int = Limits.RADIUS_DEFAULT,
    val delaySeconds: Int = Limits.DELAY_DEFAULT,
    val cooldownMinutes: Int = Limits.COOLDOWN_DEFAULT,
    val immediateTrigger: Boolean = true,
    val androidAutoEnabled: Boolean = true,
    val activityRecognitionEnabled: Boolean = true,
    val testMode: Boolean = false,
    val carDeviceAddress: String? = null,
    val carDeviceName: String? = null,
    val carAssociationId: Int? = null,
    val onboardingComplete: Boolean = false,
) {
    val hasLocation: Boolean get() = latitude != null && longitude != null

    fun engineConfig(): EngineConfig = EngineConfig(
        delayMs = delaySeconds * 1000L,
        cooldownMs = cooldownMinutes * 60_000L,
        immediateTriggerEnabled = immediateTrigger,
        androidAutoEnabled = androidAutoEnabled,
        activityRecognitionEnabled = activityRecognitionEnabled,
        testMode = testMode,
    )
}

object Limits {
    const val RADIUS_MIN = 100
    const val RADIUS_MAX = 1000
    const val RADIUS_DEFAULT = 150
    const val DELAY_MIN = 1
    const val DELAY_MAX = 30
    const val DELAY_DEFAULT = 5
    const val COOLDOWN_MIN = 1
    const val COOLDOWN_MAX = 30
    const val COOLDOWN_DEFAULT = 3
}

class ConfigStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("gatekeeper_config", Context.MODE_PRIVATE)

    @Synchronized
    fun load(): AppConfig = AppConfig(
        gateNumber = prefs.getString(K_NUMBER, null),
        simSubscriptionId = if (prefs.contains(K_SIM)) prefs.getInt(K_SIM, -1) else null,
        simLabel = prefs.getString(K_SIM_LABEL, null),
        latitude = if (prefs.contains(K_LAT)) Double.fromBits(prefs.getLong(K_LAT, 0)) else null,
        longitude = if (prefs.contains(K_LNG)) Double.fromBits(prefs.getLong(K_LNG, 0)) else null,
        radiusMeters = prefs.getInt(K_RADIUS, Limits.RADIUS_DEFAULT),
        delaySeconds = prefs.getInt(K_DELAY, Limits.DELAY_DEFAULT),
        cooldownMinutes = prefs.getInt(K_COOLDOWN, Limits.COOLDOWN_DEFAULT),
        immediateTrigger = prefs.getBoolean(K_IMMEDIATE, true),
        androidAutoEnabled = prefs.getBoolean(K_AA, true),
        activityRecognitionEnabled = prefs.getBoolean(K_AR, true),
        testMode = prefs.getBoolean(K_TEST, false),
        carDeviceAddress = prefs.getString(K_CAR_ADDR, null),
        carDeviceName = prefs.getString(K_CAR_NAME, null),
        carAssociationId = if (prefs.contains(K_CAR_ID)) prefs.getInt(K_CAR_ID, -1) else null,
        onboardingComplete = prefs.getBoolean(K_ONBOARDED, false),
    )

    /** Synchronous commit: background receivers may read immediately after. */
    @Synchronized
    fun save(c: AppConfig) {
        prefs.edit().apply {
            putOrRemove(K_NUMBER, c.gateNumber)
            if (c.simSubscriptionId != null) putInt(K_SIM, c.simSubscriptionId) else remove(K_SIM)
            putOrRemove(K_SIM_LABEL, c.simLabel)
            if (c.latitude != null) putLong(K_LAT, c.latitude.toRawBits()) else remove(K_LAT)
            if (c.longitude != null) putLong(K_LNG, c.longitude.toRawBits()) else remove(K_LNG)
            putInt(K_RADIUS, c.radiusMeters.coerceIn(Limits.RADIUS_MIN, Limits.RADIUS_MAX))
            putInt(K_DELAY, c.delaySeconds.coerceIn(Limits.DELAY_MIN, Limits.DELAY_MAX))
            putInt(K_COOLDOWN, c.cooldownMinutes.coerceIn(Limits.COOLDOWN_MIN, Limits.COOLDOWN_MAX))
            putBoolean(K_IMMEDIATE, c.immediateTrigger)
            putBoolean(K_AA, c.androidAutoEnabled)
            putBoolean(K_AR, c.activityRecognitionEnabled)
            putBoolean(K_TEST, c.testMode)
            putOrRemove(K_CAR_ADDR, c.carDeviceAddress)
            putOrRemove(K_CAR_NAME, c.carDeviceName)
            if (c.carAssociationId != null) putInt(K_CAR_ID, c.carAssociationId) else remove(K_CAR_ID)
            putBoolean(K_ONBOARDED, c.onboardingComplete)
        }.commit()
    }

    fun update(transform: (AppConfig) -> AppConfig): AppConfig = synchronized(this) {
        val next = transform(load())
        save(next)
        next
    }

    private fun android.content.SharedPreferences.Editor.putOrRemove(key: String, value: String?) {
        if (value != null) putString(key, value) else remove(key)
    }

    private companion object {
        const val K_NUMBER = "gate_number"
        const val K_SIM = "sim_subscription_id"
        const val K_SIM_LABEL = "sim_label"
        const val K_LAT = "latitude_bits"
        const val K_LNG = "longitude_bits"
        const val K_RADIUS = "radius_m"
        const val K_DELAY = "delay_s"
        const val K_COOLDOWN = "cooldown_min"
        const val K_IMMEDIATE = "immediate_trigger"
        const val K_AA = "android_auto_enabled"
        const val K_AR = "activity_recognition_enabled"
        const val K_TEST = "test_mode"
        const val K_CAR_ADDR = "car_device_address"
        const val K_CAR_NAME = "car_device_name"
        const val K_CAR_ID = "car_association_id"
        const val K_ONBOARDED = "onboarding_complete"
    }
}
