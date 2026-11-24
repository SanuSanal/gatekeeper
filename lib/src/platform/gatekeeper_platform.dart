import 'dart:async';

import 'gatekeeper_api.g.dart';

export 'gatekeeper_api.g.dart'
    show
        AppInfoMessage,
        BluetoothDeviceMessage,
        LogEntryMessage,
        LocationMessage,
        PlaceMessage,
        SettingsMessage,
        SimCardMessage,
        StartResult,
        StatusMessage;

/// Abstraction over the native bridge so UI and repositories can be tested with fakes.
abstract class GateKeeperPlatform {
  Future<SettingsMessage> loadSettings();
  Future<void> saveSettings(SettingsMessage settings);
  Future<List<SimCardMessage>> listSims();
  Future<StatusMessage> getStatus();
  Future<StatusMessage> refresh();
  Future<StartResult> startMonitoring();
  Future<void> stopMonitoring();
  Future<List<LogEntryMessage>> getLogs(int limit);
  Future<void> clearLogs();
  Future<LocationMessage?> getCurrentLocation();
  Future<List<PlaceMessage>> searchPlaces(String query);
  Future<List<BluetoothDeviceMessage>> listPairedDevices();
  Future<void> selectCar(String address, String name);
  Future<void> clearCar();
  Future<void> openBluetoothSettings();
  Future<void> simulateEvent(String event);
  Future<String?> validatePhoneNumber(String number);
  Future<void> setUiVisible(bool visible);

  Future<AppInfoMessage> getAppInfo();

  /// Returns "installer_opened" or "needs_permission"; throws PlatformException on failure.
  Future<String> downloadAndInstallUpdate(String url, String fileName, String? sha256);
  Future<void> openInstallPermissionSettings();

  /// Status pushed from native whenever the engine processes an event.
  Stream<StatusMessage> get statusStream;

  /// (received bytes, total bytes or -1) while an update downloads.
  Stream<(int, int)> get updateProgress;
}

class PigeonGateKeeperPlatform implements GateKeeperPlatform, GateKeeperFlutterApi {
  PigeonGateKeeperPlatform() {
    GateKeeperFlutterApi.setUp(this);
  }

  final GateKeeperHostApi _api = GateKeeperHostApi();
  final StreamController<StatusMessage> _status = StreamController<StatusMessage>.broadcast();
  final StreamController<(int, int)> _progress = StreamController<(int, int)>.broadcast();

  @override
  void onStatusChanged(StatusMessage status) => _status.add(status);

  @override
  void onUpdateProgress(int received, int total) => _progress.add((received, total));

  @override
  Stream<(int, int)> get updateProgress => _progress.stream;

  @override
  Future<AppInfoMessage> getAppInfo() => _api.getAppInfo();

  @override
  Future<String> downloadAndInstallUpdate(String url, String fileName, String? sha256) =>
      _api.downloadAndInstallUpdate(url, fileName, sha256);

  @override
  Future<void> openInstallPermissionSettings() => _api.openInstallPermissionSettings();

  @override
  Stream<StatusMessage> get statusStream => _status.stream;

  @override
  Future<SettingsMessage> loadSettings() => _api.loadSettings();

  @override
  Future<void> saveSettings(SettingsMessage settings) => _api.saveSettings(settings);

  @override
  Future<List<SimCardMessage>> listSims() => _api.listSims();

  @override
  Future<StatusMessage> getStatus() => _api.getStatus();

  @override
  Future<StatusMessage> refresh() => _api.refresh();

  @override
  Future<StartResult> startMonitoring() => _api.startMonitoring();

  @override
  Future<void> stopMonitoring() => _api.stopMonitoring();

  @override
  Future<List<LogEntryMessage>> getLogs(int limit) => _api.getLogs(limit);

  @override
  Future<void> clearLogs() => _api.clearLogs();

  @override
  Future<LocationMessage?> getCurrentLocation() => _api.getCurrentLocation();

  @override
  Future<List<PlaceMessage>> searchPlaces(String query) => _api.searchPlaces(query);

  @override
  Future<List<BluetoothDeviceMessage>> listPairedDevices() => _api.listPairedDevices();

  @override
  Future<void> selectCar(String address, String name) => _api.selectCar(address, name);

  @override
  Future<void> openBluetoothSettings() => _api.openBluetoothSettings();

  @override
  Future<void> clearCar() => _api.clearCar();

  @override
  Future<void> simulateEvent(String event) => _api.simulateEvent(event);

  @override
  Future<String?> validatePhoneNumber(String number) => _api.validatePhoneNumber(number);

  @override
  Future<void> setUiVisible(bool visible) => _api.setUiVisible(visible);
}
