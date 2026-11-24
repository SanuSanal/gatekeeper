import 'dart:async';

import 'package:flutter/foundation.dart';

import 'platform/gatekeeper_platform.dart';
import 'settings/settings_model.dart';
import 'settings/settings_repository.dart';

/// App-wide state: settings, live status and SIM list. UI listens via ListenableBuilder.
class AppController extends ChangeNotifier {
  AppController(this.platform) : settingsRepository = SettingsRepository(platform) {
    _statusSub = platform.statusStream.listen((s) {
      status = s;
      notifyListeners();
    });
  }

  final GateKeeperPlatform platform;
  final SettingsRepository settingsRepository;
  StreamSubscription<StatusMessage>? _statusSub;

  GateSettings settings = const GateSettings();
  StatusMessage? status;
  List<SimCardMessage> sims = const [];
  bool loaded = false;
  bool busy = false;

  Future<void> load() async {
    settings = await settingsRepository.load();
    status = await platform.refresh();
    sims = await platform.listSims();
    loaded = true;
    notifyListeners();
  }

  /// Re-reads permissions/SIMs (e.g. after returning from system settings).
  Future<void> refresh() async {
    status = await platform.refresh();
    sims = await platform.listSims();
    settings = await settingsRepository.load();
    notifyListeners();
  }

  Future<void> saveSettings(GateSettings next) async {
    await settingsRepository.save(next);
    settings = await settingsRepository.load();
    status = await platform.getStatus();
    notifyListeners();
  }

  Future<StartResult> startMonitoring() async {
    busy = true;
    notifyListeners();
    try {
      final r = await platform.startMonitoring();
      status = await platform.getStatus();
      return r;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stopMonitoring() async {
    await platform.stopMonitoring();
    status = await platform.getStatus();
    notifyListeners();
  }

  Future<void> selectCar(BluetoothDeviceMessage device) async {
    await platform.selectCar(device.address, device.name);
    settings = await settingsRepository.load();
    status = await platform.getStatus();
    notifyListeners();
  }

  Future<void> clearCar() async {
    await platform.clearCar();
    settings = await settingsRepository.load();
    status = await platform.getStatus();
    notifyListeners();
  }

  /// The selected SIM if it is currently present, otherwise null (never a substitute).
  SimCardMessage? get selectedSim {
    final id = settings.simSubscriptionId;
    if (id == null) return null;
    for (final s in sims) {
      if (s.subscriptionId == id) return s;
    }
    return null;
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }
}
