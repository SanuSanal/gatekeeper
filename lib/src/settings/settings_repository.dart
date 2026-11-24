import 'package:flutter/services.dart';

import '../platform/gatekeeper_platform.dart';
import 'settings_model.dart';
import 'validators.dart';

class SettingsSaveException implements Exception {
  SettingsSaveException(this.errors);

  final List<String> errors;

  @override
  String toString() => errors.join('\n');
}

/// Loads and saves settings through the native store, validating first.
class SettingsRepository {
  SettingsRepository(this._platform);

  final GateKeeperPlatform _platform;

  Future<GateSettings> load() async => GateSettings.fromMessage(await _platform.loadSettings());

  Future<void> save(GateSettings settings) async {
    final normalized = settings.gateNumber == null || settings.gateNumber!.trim().isEmpty
        ? settings.copyWith(gateNumber: null)
        : settings.copyWith(gateNumber: Validators.normalizePhone(settings.gateNumber!));
    final errors = Validators.settings(normalized);
    if (errors.isNotEmpty) throw SettingsSaveException(errors);
    try {
      await _platform.saveSettings(normalized.toMessage());
    } on PlatformException catch (e) {
      throw SettingsSaveException([e.message ?? e.code]);
    }
  }
}
