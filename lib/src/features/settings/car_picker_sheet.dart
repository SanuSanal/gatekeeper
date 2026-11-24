import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/gatekeeper_platform.dart';

/// Bottom sheet listing the phone's paired Bluetooth devices by name (cars first).
/// Returns the chosen device, or null.
Future<BluetoothDeviceMessage?> showCarPicker(
  BuildContext context, {
  required GateKeeperPlatform platform,
  required Future<bool> Function() requestBluetoothPermission,
}) {
  return showModalBottomSheet<BluetoothDeviceMessage>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _CarPicker(platform: platform, requestBluetoothPermission: requestBluetoothPermission),
  );
}

class _CarPicker extends StatefulWidget {
  const _CarPicker({required this.platform, required this.requestBluetoothPermission});

  final GateKeeperPlatform platform;
  final Future<bool> Function() requestBluetoothPermission;

  @override
  State<_CarPicker> createState() => _CarPickerState();
}

class _CarPickerState extends State<_CarPicker> {
  List<BluetoothDeviceMessage>? _devices;
  String? _errorCode;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _devices = null;
      _errorCode = null;
    });
    try {
      final d = [...await widget.platform.listPairedDevices()]
        ..sort((a, b) => a.carLike != b.carLike
            ? (a.carLike ? -1 : 1)
            : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _devices = d);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _errorCode = e.code;
          _errorText = e.message;
          _devices = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _devices;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Choose your car', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                'Pick your car’s Bluetooth from the devices paired with this phone. When the phone connects to it, '
                'GateKeeper checks Android Auto.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            if (devices == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_errorCode != null)
              _message(
                icon: _errorCode == 'permission' ? Icons.bluetooth_disabled_rounded : Icons.bluetooth_rounded,
                text: _errorText ?? 'Bluetooth is unavailable',
                action: _errorCode == 'permission'
                    ? FilledButton(
                        onPressed: () async {
                          await widget.requestBluetoothPermission();
                          await _load();
                        },
                        child: const Text('Allow Nearby devices'),
                      )
                    : FilledButton(
                        onPressed: () async {
                          await widget.platform.openBluetoothSettings();
                        },
                        child: const Text('Open Bluetooth settings'),
                      ),
                secondary: TextButton(onPressed: _load, child: const Text('Try again')),
              )
            else if (devices.isEmpty)
              _message(
                icon: Icons.bluetooth_searching_rounded,
                text: 'No paired devices. Pair your car in Android’s Bluetooth settings first, then come back.',
                action: FilledButton(
                  onPressed: () => widget.platform.openBluetoothSettings(),
                  child: const Text('Open Bluetooth settings'),
                ),
                secondary: TextButton(onPressed: _load, child: const Text('Refresh')),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in devices)
                      ListTile(
                        leading: Icon(
                          d.carLike ? Icons.directions_car_rounded : Icons.bluetooth_rounded,
                          color: d.carLike ? theme.colorScheme.primary : null,
                        ),
                        title: Text(d.name),
                        subtitle: Text(
                          [if (d.carLike) 'Car audio', _shortAddress(d.address)].join(' · '),
                        ),
                        trailing: d.selected ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary) : null,
                        onTap: () => Navigator.pop(context, d),
                      ),
                    ListTile(
                      leading: const Icon(Icons.add_rounded),
                      title: const Text('Car not listed?'),
                      subtitle: const Text('Pair it in Bluetooth settings first'),
                      onTap: () => widget.platform.openBluetoothSettings(),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Last 5 characters, to tell apart devices with the same name.
  static String _shortAddress(String address) =>
      address.length > 5 ? '…${address.substring(address.length - 5)}' : address;

  Widget _message({required IconData icon, required String text, required Widget action, Widget? secondary}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: action),
          ?secondary,
        ],
      ),
    );
  }
}
