import '../platform/gatekeeper_platform.dart';

/// Ranges shared with the native ConfigStore (android/.../store/ConfigStore.kt `Limits`).
abstract final class Limits {
  static const radiusMin = 100;
  static const radiusMax = 1000;
  static const radiusDefault = 150;
  static const delayMin = 1;
  static const delayMax = 30;
  static const delayDefault = 5;
  static const cooldownMin = 1;
  static const cooldownMax = 30;
  static const cooldownDefault = 3;
}

/// Immutable app settings as edited in the UI.
class GateSettings {
  const GateSettings({
    this.gateNumber,
    this.simSubscriptionId,
    this.simLabel,
    this.latitude,
    this.longitude,
    this.radiusMeters = Limits.radiusDefault,
    this.delaySeconds = Limits.delayDefault,
    this.cooldownMinutes = Limits.cooldownDefault,
    this.immediateTrigger = true,
    this.androidAutoEnabled = true,
    this.activityRecognitionEnabled = true,
    this.testMode = false,
    this.carDeviceName,
    this.carDeviceAssociated = false,
    this.onboardingComplete = false,
  });

  final String? gateNumber;
  final int? simSubscriptionId;
  final String? simLabel;
  final double? latitude;
  final double? longitude;
  final int radiusMeters;
  final int delaySeconds;
  final int cooldownMinutes;
  final bool immediateTrigger;
  final bool androidAutoEnabled;
  final bool activityRecognitionEnabled;
  final bool testMode;
  final String? carDeviceName;
  final bool carDeviceAssociated;
  final bool onboardingComplete;

  bool get hasLocation => latitude != null && longitude != null;

  static const _unset = Object();

  GateSettings copyWith({
    Object? gateNumber = _unset,
    Object? simSubscriptionId = _unset,
    Object? simLabel = _unset,
    Object? latitude = _unset,
    Object? longitude = _unset,
    int? radiusMeters,
    int? delaySeconds,
    int? cooldownMinutes,
    bool? immediateTrigger,
    bool? androidAutoEnabled,
    bool? activityRecognitionEnabled,
    bool? testMode,
    bool? onboardingComplete,
  }) {
    return GateSettings(
      gateNumber: identical(gateNumber, _unset) ? this.gateNumber : gateNumber as String?,
      simSubscriptionId:
          identical(simSubscriptionId, _unset) ? this.simSubscriptionId : simSubscriptionId as int?,
      simLabel: identical(simLabel, _unset) ? this.simLabel : simLabel as String?,
      latitude: identical(latitude, _unset) ? this.latitude : latitude as double?,
      longitude: identical(longitude, _unset) ? this.longitude : longitude as double?,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      delaySeconds: delaySeconds ?? this.delaySeconds,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      immediateTrigger: immediateTrigger ?? this.immediateTrigger,
      androidAutoEnabled: androidAutoEnabled ?? this.androidAutoEnabled,
      activityRecognitionEnabled: activityRecognitionEnabled ?? this.activityRecognitionEnabled,
      testMode: testMode ?? this.testMode,
      carDeviceName: carDeviceName,
      carDeviceAssociated: carDeviceAssociated,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  factory GateSettings.fromMessage(SettingsMessage m) => GateSettings(
        gateNumber: m.gateNumber,
        simSubscriptionId: m.simSubscriptionId,
        simLabel: m.simLabel,
        latitude: m.latitude,
        longitude: m.longitude,
        radiusMeters: m.radiusMeters,
        delaySeconds: m.delaySeconds,
        cooldownMinutes: m.cooldownMinutes,
        immediateTrigger: m.immediateTrigger,
        androidAutoEnabled: m.androidAutoEnabled,
        activityRecognitionEnabled: m.activityRecognitionEnabled,
        testMode: m.testMode,
        carDeviceName: m.carDeviceName,
        carDeviceAssociated: m.carDeviceAssociated,
        onboardingComplete: m.onboardingComplete,
      );

  SettingsMessage toMessage() => SettingsMessage(
        gateNumber: gateNumber,
        simSubscriptionId: simSubscriptionId,
        simLabel: simLabel,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        delaySeconds: delaySeconds,
        cooldownMinutes: cooldownMinutes,
        immediateTrigger: immediateTrigger,
        androidAutoEnabled: androidAutoEnabled,
        activityRecognitionEnabled: activityRecognitionEnabled,
        testMode: testMode,
        carDeviceName: carDeviceName,
        carDeviceAssociated: carDeviceAssociated,
        onboardingComplete: onboardingComplete,
      );
}
