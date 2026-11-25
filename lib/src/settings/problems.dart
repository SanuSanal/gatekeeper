/// Human-readable descriptions of the problem codes produced by the native PermissionMonitor.
class ProblemInfo {
  const ProblemInfo(this.title, this.impact, {this.blocking = true});

  final String title;

  /// What does not work while this problem exists.
  final String impact;
  final bool blocking;
}

abstract final class Problems {
  static const _known = <String, ProblemInfo>{
    'LOCATION_NOT_SET': ProblemInfo('Parking location not set', 'There is nothing to monitor yet.'),
    'LOCATION_PERMISSION': ProblemInfo('Location permission missing', 'Arrival cannot be detected.'),
    'BACKGROUND_LOCATION_PERMISSION': ProblemInfo(
      'Location is not allowed "all the time"',
      'The parking geofence cannot work while the app is closed.',
    ),
    'ACTIVITY_PERMISSION': ProblemInfo(
      'Physical activity permission missing',
      'In-vehicle detection is unavailable.',
    ),
    'PHONE_PERMISSION': ProblemInfo('Phone permission missing', 'Gate calls and SIM selection are unavailable.'),
    'GATE_NUMBER_INVALID': ProblemInfo('Gate number missing or invalid', 'No call can be placed.'),
    'SIM_NOT_SELECTED': ProblemInfo('No SIM selected', 'No call can be placed.'),
    'SIM_UNAVAILABLE': ProblemInfo(
      'Selected SIM is not available',
      'No call will be placed. GateKeeper never switches to another SIM by itself.',
    ),
    'NO_SIGNAL_ENABLED': ProblemInfo(
      'No vehicle signal enabled',
      'Enable Activity Recognition, Android Auto, or car Bluetooth with a car chosen.',
    ),
    'GEOFENCE_REGISTRATION_FAILED': ProblemInfo(
      'Geofence could not be registered',
      'Check that location is on and Google Play services is up to date.',
    ),
    'NOTIFICATION_PERMISSION': ProblemInfo(
      'Notifications are off',
      'You will not see call errors or the tap-to-call fallback.',
      blocking: false,
    ),
    'BLUETOOTH_PERMISSION': ProblemInfo(
      'Nearby devices permission missing',
      'Connecting to your car cannot wake GateKeeper.',
      blocking: false,
    ),
    'CAR_NOT_SELECTED': ProblemInfo(
      'Car Bluetooth not chosen',
      'Choose your car so connecting to it can trigger the gate call, with or without Android Auto.',
      blocking: false,
    ),
    'CAR_WAKE_BLOCKED': ProblemInfo(
      'Car can’t wake GateKeeper yet',
      'Turn off battery optimisation for GateKeeper so connecting to your car can start the car check.',
      blocking: false,
    ),
    'BATTERY_OPTIMIZED': ProblemInfo(
      'Battery optimisation is on',
      'Android may delay or drop background events.',
      blocking: false,
    ),
  };

  static ProblemInfo describe(String code) => _known[code] ?? ProblemInfo(code, 'Unknown problem');

  static List<String> blocking(List<String> codes) => codes.where((c) => describe(c).blocking).toList();

  static List<String> warnings(List<String> codes) => codes.where((c) => !describe(c).blocking).toList();
}
