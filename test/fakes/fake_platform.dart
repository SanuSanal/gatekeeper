import 'dart:async';

import 'package:flutter/services.dart';
import 'package:gatekeeper/src/platform/gatekeeper_platform.dart';

/// In-memory fake of the native bridge for Dart unit and widget tests.
class FakePlatform implements GateKeeperPlatform {
  SettingsMessage settings = SettingsMessage(
    radiusMeters: 150,
    delaySeconds: 5,
    cooldownMinutes: 3,
    immediateTrigger: true,
    androidAutoEnabled: true,
    activityRecognitionEnabled: true,
    testMode: false,
    carDeviceAssociated: false,
    onboardingComplete: true,
  );

  StatusMessage status = StatusMessage(
    monitoring: false,
    phase: 'STOPPED',
    geofence: 'UNKNOWN',
    vehicle: 'UNKNOWN',
    androidAuto: 'UNKNOWN',
    carBluetoothConnected: false,
    testMode: false,
    problems: const [],
  );

  List<SimCardMessage> sims = [
    SimCardMessage(subscriptionId: 1, slotIndex: 0, carrierName: 'Carrier A', callCapable: true),
    SimCardMessage(subscriptionId: 2, slotIndex: 1, carrierName: 'Carrier B', callCapable: true),
  ];

  List<String> startProblems = const [];
  final List<String> simulated = [];
  final List<SettingsMessage> saved = [];
  bool? uiVisible;
  final _status = StreamController<StatusMessage>.broadcast();

  void push(StatusMessage s) {
    status = s;
    _status.add(s);
  }

  @override
  Stream<StatusMessage> get statusStream => _status.stream;

  @override
  Future<SettingsMessage> loadSettings() async => settings;

  @override
  Future<void> saveSettings(SettingsMessage s) async {
    if (s.gateNumber == '112') throw PlatformException(code: 'invalid', message: 'emergency number');
    saved.add(s);
    settings = s;
  }

  @override
  Future<List<SimCardMessage>> listSims() async => sims;

  @override
  Future<StatusMessage> getStatus() async => status;

  @override
  Future<StatusMessage> refresh() async => status;

  @override
  Future<StartResult> startMonitoring() async {
    if (startProblems.isNotEmpty) return StartResult(started: false, problems: startProblems);
    status = StatusMessage(
      monitoring: true,
      phase: 'MONITORING_OUTSIDE',
      geofence: 'OUTSIDE',
      vehicle: 'UNKNOWN',
      androidAuto: 'UNKNOWN',
      carBluetoothConnected: false,
      testMode: settings.testMode,
      problems: const [],
    );
    return StartResult(started: true, problems: const []);
  }

  @override
  Future<void> stopMonitoring() async {
    status = StatusMessage(
      monitoring: false,
      phase: 'STOPPED',
      geofence: 'UNKNOWN',
      vehicle: 'UNKNOWN',
      androidAuto: 'UNKNOWN',
      carBluetoothConnected: false,
      testMode: settings.testMode,
      problems: const [],
    );
  }

  @override
  Future<List<LogEntryMessage>> getLogs(int limit) async => [
        LogEntryMessage(timestamp: 1700000000000, category: 'GEOFENCE', message: 'ENTER geofence'),
        LogEntryMessage(timestamp: 1700000001000, category: 'CALL', message: 'Placing gate call'),
      ];

  @override
  Future<void> clearLogs() async {}

  @override
  Future<LocationMessage?> getCurrentLocation() async => LocationMessage(latitude: 12.97, longitude: 77.59);

  @override
  Future<String?> associateCar() async => 'My Car';

  @override
  Future<void> disassociateCar() async {}

  @override
  Future<void> simulateEvent(String event) async {
    if (!settings.testMode) throw PlatformException(code: 'not_test_mode');
    simulated.add(event);
  }

  @override
  Future<String?> validatePhoneNumber(String number) async {
    final n = number.replaceAll(RegExp(r'[\s\-().]'), '');
    return RegExp(r'^\+?[0-9]{3,15}$').hasMatch(n) && n != '112' ? n : null;
  }

  @override
  Future<void> setUiVisible(bool visible) async => uiVisible = visible;

  String versionName = '1.0.0';
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a'];
  String installResult = 'installer_opened';
  final List<String> installed = [];
  final _progress = StreamController<(int, int)>.broadcast();

  @override
  Future<AppInfoMessage> getAppInfo() async =>
      AppInfoMessage(versionName: versionName, versionCode: 1, supportedAbis: abis, canInstallPackages: true);

  @override
  Future<String> downloadAndInstallUpdate(String url, String fileName, String? sha256) async {
    installed.add(fileName);
    _progress.add((50, 100));
    return installResult;
  }

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Stream<(int, int)> get updateProgress => _progress.stream;
}
