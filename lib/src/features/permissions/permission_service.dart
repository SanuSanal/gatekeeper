import 'package:permission_handler/permission_handler.dart';

/// One permission (or ordered group) shown in onboarding and on the settings screen.
class PermissionItem {
  const PermissionItem({
    required this.id,
    required this.title,
    required this.rationale,
    required this.unavailableWithout,
    required this.permissions,
    this.optional = false,
  });

  final String id;
  final String title;
  final String rationale;
  final String unavailableWithout;

  /// Requested in order; all must be granted.
  final List<Permission> permissions;
  final bool optional;
}

/// Thin wrapper over permission_handler so it can be faked in widget tests.
class PermissionService {
  const PermissionService();

  static const items = <PermissionItem>[
    PermissionItem(
      id: 'location',
      title: 'Precise location',
      rationale: 'Needed to set your parking spot and to know when you arrive there.',
      unavailableWithout: 'Parking detection',
      permissions: [Permission.locationWhenInUse],
    ),
    PermissionItem(
      id: 'background_location',
      title: 'Location "Allow all the time"',
      rationale:
          'Android only delivers geofence events to closed apps with this setting. On the next screen choose '
          '"Allow all the time". GateKeeper never polls GPS; Android tells it when you cross the geofence.',
      unavailableWithout: 'Detection while GateKeeper is closed',
      permissions: [Permission.locationAlways],
    ),
    PermissionItem(
      id: 'activity',
      title: 'Physical activity',
      rationale: 'Lets GateKeeper know when you are driving (IN_VEHICLE) so walking into the area never calls the gate.',
      unavailableWithout: 'In-vehicle detection',
      permissions: [Permission.activityRecognition],
    ),
    PermissionItem(
      id: 'phone',
      title: 'Phone',
      rationale: 'Needed to list your SIM cards and to place the gate call on the SIM you choose.',
      unavailableWithout: 'Gate calls and SIM selection',
      permissions: [Permission.phone],
    ),
    PermissionItem(
      id: 'notifications',
      title: 'Notifications',
      rationale: 'Shows call problems, the tap-to-call fallback, and a short notice while checking your car.',
      unavailableWithout: 'Error alerts and tap-to-call fallback',
      permissions: [Permission.notification],
    ),
    PermissionItem(
      id: 'bluetooth',
      title: 'Nearby devices',
      rationale:
          "Lets your car's Bluetooth connection wake GateKeeper, so Android Auto is checked when you get in the car "
          'without keeping a service running while you are parked.',
      unavailableWithout: 'Car Bluetooth wake-up',
      permissions: [Permission.bluetoothConnect],
      optional: true,
    ),
    PermissionItem(
      id: 'battery',
      title: 'Ignore battery optimisation',
      rationale: 'Recommended. Reduces the chance that Android delays or drops background events (Doze).',
      unavailableWithout: 'Reliable background delivery on some devices',
      permissions: [Permission.ignoreBatteryOptimizations],
      optional: true,
    ),
  ];

  Future<bool> isGranted(PermissionItem item) async {
    for (final p in item.permissions) {
      if (!await p.isGranted) return false;
    }
    return true;
  }

  Future<bool> isPermanentlyDenied(PermissionItem item) async {
    for (final p in item.permissions) {
      if (await p.isPermanentlyDenied) return true;
    }
    return false;
  }

  /// Requests the item. Background location requires foreground location first (Android 11+).
  Future<bool> request(PermissionItem item) async {
    if (item.id == 'background_location' && !await Permission.locationWhenInUse.isGranted) {
      final fg = await Permission.locationWhenInUse.request();
      if (!fg.isGranted) return false;
    }
    for (final p in item.permissions) {
      final status = await p.request();
      if (!status.isGranted) return false;
    }
    return true;
  }

  Future<Map<String, bool>> statusAll() async => {
        for (final item in items) item.id: await isGranted(item),
      };

  Future<bool> openSettings() => openAppSettings();
}
