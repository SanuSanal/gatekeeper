import 'settings_model.dart';

/// Pure validators used by the settings UI. The native side re-validates on save
/// (including the platform emergency-number check), so these are a first line only.
abstract final class Validators {
  static final _formatting = RegExp(r'[\s\-().]');
  static final _dialable = RegExp(r'^\+?[0-9]{3,15}$');

  /// Common emergency short codes; the native side also asks the platform.
  static const emergencyNumbers = {
    '100', '101', '102', '108', '110', '112', '118', '119', '911', '999', '000', '1122', //
  };

  /// Strips spaces, dashes, dots and parentheses.
  static String normalizePhone(String input) => input.trim().replaceAll(_formatting, '');

  /// Returns an error message, or null when valid.
  static String? gateNumber(String? input) {
    if (input == null || input.trim().isEmpty) return 'Enter the gate phone number';
    final n = normalizePhone(input);
    if (!_dialable.hasMatch(n)) {
      return 'Use digits only (3–15), optionally starting with +';
    }
    if (emergencyNumbers.contains(n)) return 'Emergency numbers cannot be used';
    return null;
  }

  static String? latitude(String? input) {
    final v = double.tryParse((input ?? '').trim());
    if (v == null) return 'Enter a number';
    if (v < -90 || v > 90) return 'Latitude must be between -90 and 90';
    return null;
  }

  static String? longitude(String? input) {
    final v = double.tryParse((input ?? '').trim());
    if (v == null) return 'Enter a number';
    if (v < -180 || v > 180) return 'Longitude must be between -180 and 180';
    return null;
  }

  static final _maps = [
    RegExp(r'@(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'), // google.com/maps/.../@lat,lng,17z
    RegExp(r'[?&](?:q|query|ll|destination|center)=(-?\d{1,2}(?:\.\d+)?)(?:,|%2C)\s*(-?\d{1,3}(?:\.\d+)?)'),
    RegExp(r'geo:(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)'),
  ];
  static final _pair = RegExp(r'(-?\d{1,2}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)');

  /// Finds a latitude/longitude pair in free text: "12.97, 77.59", "12.97 77.59", a Google Maps
  /// link (…/@12.97,77.59,17z or ?q=12.97,77.59) or a geo: URI. Returns null if none is valid.
  static (double, double)? parseCoordinates(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    for (final re in [..._maps, _pair]) {
      for (final m in re.allMatches(text)) {
        final lat = double.tryParse(m.group(1)!);
        final lng = double.tryParse(m.group(2)!);
        if (lat == null || lng == null) continue;
        if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
        if (lat == 0 && lng == 0) continue;
        return (lat, lng);
      }
    }
    return null;
  }

  static int clampRadius(num v) => v.round().clamp(Limits.radiusMin, Limits.radiusMax);
  static int clampDelay(num v) => v.round().clamp(Limits.delayMin, Limits.delayMax);
  static int clampCooldown(num v) => v.round().clamp(Limits.cooldownMin, Limits.cooldownMax);

  /// Whole-settings check used before saving. Returns a list of human-readable errors.
  static List<String> settings(GateSettings s) {
    final errors = <String>[];
    if (s.gateNumber != null && s.gateNumber!.isNotEmpty) {
      final e = gateNumber(s.gateNumber);
      if (e != null) errors.add(e);
    }
    if ((s.latitude == null) != (s.longitude == null)) {
      errors.add('Both latitude and longitude are required');
    }
    if (s.latitude != null && (s.latitude! < -90 || s.latitude! > 90)) errors.add('Invalid latitude');
    if (s.longitude != null && (s.longitude! < -180 || s.longitude! > 180)) errors.add('Invalid longitude');
    if (s.radiusMeters < Limits.radiusMin || s.radiusMeters > Limits.radiusMax) {
      errors.add('Radius must be ${Limits.radiusMin}–${Limits.radiusMax} m');
    }
    if (s.delaySeconds < Limits.delayMin || s.delaySeconds > Limits.delayMax) {
      errors.add('Delay must be ${Limits.delayMin}–${Limits.delayMax} s');
    }
    if (s.cooldownMinutes < Limits.cooldownMin || s.cooldownMinutes > Limits.cooldownMax) {
      errors.add('Cooldown must be ${Limits.cooldownMin}–${Limits.cooldownMax} min');
    }
    if (!s.androidAutoEnabled && !s.activityRecognitionEnabled) {
      errors.add('Enable at least one vehicle signal (Android Auto or Activity Recognition)');
    }
    return errors;
  }

  /// "••• 1234": avoid showing the full number unnecessarily.
  static String maskPhone(String? number) {
    if (number == null || number.isEmpty) return 'Not set';
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.length <= 4) return '•••';
    return '••• ${digits.substring(digits.length - 4)}';
  }
}
