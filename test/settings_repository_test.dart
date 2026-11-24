import 'package:flutter_test/flutter_test.dart';
import 'package:gatekeeper/src/app_controller.dart';
import 'package:gatekeeper/src/settings/settings_model.dart';
import 'package:gatekeeper/src/settings/settings_repository.dart';

import 'fakes/fake_platform.dart';

void main() {
  late FakePlatform platform;
  late SettingsRepository repo;

  setUp(() {
    platform = FakePlatform();
    repo = SettingsRepository(platform);
  });

  test('round-trips settings through the platform', () async {
    const s = GateSettings(
      gateNumber: '+91 98765 43210',
      simSubscriptionId: 2,
      simLabel: 'SIM 2 · Carrier B',
      latitude: 12.97,
      longitude: 77.59,
      radiusMeters: 200,
      delaySeconds: 8,
      cooldownMinutes: 4,
      testMode: true,
    );
    await repo.save(s);
    final loaded = await repo.load();
    expect(loaded.gateNumber, '+919876543210', reason: 'normalised before saving');
    expect(loaded.simSubscriptionId, 2);
    expect(loaded.latitude, 12.97);
    expect(loaded.radiusMeters, 200);
    expect(loaded.delaySeconds, 8);
    expect(loaded.cooldownMinutes, 4);
    expect(loaded.testMode, isTrue);
  });

  test('invalid settings are rejected before reaching native', () async {
    await expectLater(
      repo.save(const GateSettings(gateNumber: 'abc')),
      throwsA(isA<SettingsSaveException>()),
    );
    expect(platform.saved, isEmpty);
  });

  test('native validation errors surface as SettingsSaveException', () async {
    // The fake rejects "112" natively; the Dart validator rejects it first anyway.
    await expectLater(repo.save(const GateSettings(gateNumber: '112')), throwsA(isA<SettingsSaveException>()));
  });

  test('empty gate number is stored as null', () async {
    await repo.save(const GateSettings(gateNumber: '   '));
    expect(platform.saved.single.gateNumber, isNull);
  });

  group('AppController', () {
    test('selectedSim never substitutes a missing SIM', () async {
      platform.settings = (const GateSettings(simSubscriptionId: 9, onboardingComplete: true)).toMessage();
      final c = AppController(platform);
      await c.load();
      expect(c.selectedSim, isNull);
      platform.settings = (const GateSettings(simSubscriptionId: 2, onboardingComplete: true)).toMessage();
      await c.refresh();
      expect(c.selectedSim?.carrierName, 'Carrier B');
    });

    test('start reports problems without starting', () async {
      platform.startProblems = ['SIM_UNAVAILABLE'];
      final c = AppController(platform);
      await c.load();
      final r = await c.startMonitoring();
      expect(r.started, isFalse);
      expect(r.problems, ['SIM_UNAVAILABLE']);
      expect(c.status?.monitoring, isFalse);
    });

    test('status pushed from native updates listeners', () async {
      final c = AppController(platform);
      await c.load();
      var notified = 0;
      c.addListener(() => notified++);
      platform.push(platform.status..geofence = 'INSIDE');
      await Future<void>.delayed(Duration.zero);
      expect(c.status?.geofence, 'INSIDE');
      expect(notified, greaterThan(0));
    });
  });
}
