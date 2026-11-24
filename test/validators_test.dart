import 'package:flutter_test/flutter_test.dart';
import 'package:gatekeeper/src/settings/settings_model.dart';
import 'package:gatekeeper/src/settings/validators.dart';
import 'package:gatekeeper/src/ui/labels.dart';

void main() {
  group('gate number', () {
    test('accepts international and local numbers with formatting', () {
      expect(Validators.gateNumber('+91 98765-43210'), isNull);
      expect(Validators.gateNumber('(080) 1234 5678'), isNull);
      expect(Validators.normalizePhone('+91 98765-43210'), '+919876543210');
    });

    test('rejects empty, letters, too short and too long', () {
      expect(Validators.gateNumber(''), isNotNull);
      expect(Validators.gateNumber(null), isNotNull);
      expect(Validators.gateNumber('12'), isNotNull);
      expect(Validators.gateNumber('call-me'), isNotNull);
      expect(Validators.gateNumber('1234567890123456'), isNotNull);
      expect(Validators.gateNumber('++123456'), isNotNull);
    });

    test('rejects emergency numbers', () {
      for (final n in ['112', '911', '100', '108', '999']) {
        expect(Validators.gateNumber(n), contains('Emergency'), reason: n);
      }
    });

    test('masks all but the last four digits', () {
      expect(Validators.maskPhone('+919876543210'), '••• 3210');
      expect(Validators.maskPhone(null), 'Not set');
      expect(Validators.maskPhone('123'), '•••');
    });
  });

  group('coordinates', () {
    test('latitude range', () {
      expect(Validators.latitude('12.9716'), isNull);
      expect(Validators.latitude('-90'), isNull);
      expect(Validators.latitude('90.1'), isNotNull);
      expect(Validators.latitude('abc'), isNotNull);
    });

    test('longitude range', () {
      expect(Validators.longitude('77.5946'), isNull);
      expect(Validators.longitude('180'), isNull);
      expect(Validators.longitude('-180.5'), isNotNull);
    });
  });

  group('settings', () {
    test('defaults are valid and match the spec', () {
      const s = GateSettings();
      expect(s.radiusMeters, 150);
      expect(s.delaySeconds, 5);
      expect(s.cooldownMinutes, 3);
      expect(s.immediateTrigger, isTrue);
      expect(Validators.settings(s), isEmpty);
    });

    test('requires at least one vehicle signal', () {
      const s = GateSettings(androidAutoEnabled: false, activityRecognitionEnabled: false);
      expect(Validators.settings(s), hasLength(1));
    });

    test('out-of-range values are reported and clamps work', () {
      const s = GateSettings(radiusMeters: 50, delaySeconds: 0, cooldownMinutes: 99);
      expect(Validators.settings(s), hasLength(3));
      expect(Validators.clampRadius(5000), Limits.radiusMax);
      expect(Validators.clampDelay(0), Limits.delayMin);
      expect(Validators.clampCooldown(2.6), 3);
    });

    test('half-set location is invalid', () {
      const s = GateSettings(latitude: 1.0);
      expect(Validators.settings(s), contains('Both latitude and longitude are required'));
    });

    test('copyWith can clear nullable fields', () {
      const s = GateSettings(gateNumber: '12345', simSubscriptionId: 3);
      final cleared = s.copyWith(gateNumber: null, simSubscriptionId: null);
      expect(cleared.gateNumber, isNull);
      expect(cleared.simSubscriptionId, isNull);
      expect(s.copyWith(radiusMeters: 200).gateNumber, '12345');
    });
  });

  group('labels', () {
    test('time formats today vs other days', () {
      final now = DateTime(2026, 11, 24, 15);
      final today = DateTime(2026, 11, 24, 14, 3, 22).millisecondsSinceEpoch;
      final earlier = DateTime(2026, 11, 20, 9, 5).millisecondsSinceEpoch;
      expect(Labels.time(today, now: now), '14:03:22');
      expect(Labels.time(earlier, now: now), '20 Nov 09:05');
      expect(Labels.time(null), '—');
    });

    test('unknown enum values fall back gracefully', () {
      expect(Labels.geofence(null), 'Unknown');
      expect(Labels.androidAuto('UNKNOWN'), 'Not observed');
      expect(Labels.callOutcome('FAILED_SIM_UNAVAILABLE'), contains('SIM'));
    });
  });
}
