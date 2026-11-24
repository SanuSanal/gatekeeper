import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/gatekeeper_platform.dart';

/// Test-mode only: injects synthetic events into the real trigger engine. Calls are simulated.
class SimulatorPanel extends StatelessWidget {
  const SimulatorPanel({super.key, required this.platform, required this.onError});

  final GateKeeperPlatform platform;
  final ValueChanged<String> onError;

  static const _events = <(String, String, IconData)>[
    ('enter', 'Enter geofence', Icons.login_rounded),
    ('exit', 'Exit geofence', Icons.logout_rounded),
    ('vehicle_on', 'In vehicle', Icons.directions_car_rounded),
    ('vehicle_off', 'Not in vehicle', Icons.directions_walk_rounded),
    ('aa_on', 'Android Auto on', Icons.phone_android_rounded),
    ('aa_off', 'Android Auto off', Icons.mobile_off_rounded),
    ('bt_on', 'Car BT connect', Icons.bluetooth_connected_rounded),
    ('bt_off', 'Car BT disconnect', Icons.bluetooth_disabled_rounded),
  ];

  Future<void> _send(String event) async {
    try {
      await platform.simulateEvent(event);
    } on PlatformException catch (e) {
      onError(e.message ?? e.code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Simulate events',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: scheme.onTertiaryContainer),
            ),
            const SizedBox(height: 4),
            Text(
              'Simulated events go through the same state machine as real ones (5 s delay, cooldown, '
              'duplicate checks). Monitoring must be on. Events within 30 s of starting are treated as initial state.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (id, label, icon) in _events)
                  ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: () => _send(id)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
