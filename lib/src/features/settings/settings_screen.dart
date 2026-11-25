import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../app_controller.dart';
import '../../platform/gatekeeper_platform.dart';
import '../../settings/settings_model.dart';
import '../../settings/settings_repository.dart';
import '../../settings/validators.dart';
import '../../ui/widgets.dart';
import '../../update/update_controller.dart';
import '../../update/update_widgets.dart';
import '../location_picker/location_picker_screen.dart';
import '../logs/logs_screen.dart';
import '../permissions/permission_service.dart';
import 'car_picker_sheet.dart';
import 'simulator_panel.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller, required this.updates, required this.permissions});

  final AppController controller;
  final UpdateController updates;
  final PermissionService permissions;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, bool> _granted = const {};

  // Local slider values while dragging (saved on release).
  double? _radius;
  double? _delay;
  double? _cooldown;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final m = await widget.permissions.statusAll();
    if (mounted) setState(() => _granted = m);
  }

  Future<void> _save(GateSettings next) async {
    try {
      await c.saveSettings(next);
    } on SettingsSaveException catch (e) {
      _snack(e.errors.join('\n'));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- gate number ---------------------------------------------------------------

  Future<void> _editNumber() async {
    final ctrl = TextEditingController(text: c.settings.gateNumber ?? '');
    final formKey = GlobalKey<FormState>();
    String? nativeError;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Gate phone number'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const <String>[],
              decoration: InputDecoration(
                hintText: '+91 98765 43210',
                helperText: 'Include the country code if the gate needs it',
                errorText: nativeError,
              ),
              validator: Validators.gateNumber,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final normalized = await c.platform.validatePhoneNumber(ctrl.text);
                if (normalized == null) {
                  setLocal(() => nativeError = 'Android rejected this number (invalid or emergency)');
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx, normalized);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result != null) await _save(c.settings.copyWith(gateNumber: result));
  }

  // ---- SIM --------------------------------------------------------------------------

  Future<void> _pickSim() async {
    await c.refresh();
    if (!mounted) return;
    if (c.sims.isEmpty) {
      _snack(_granted['phone'] == true ? 'No active SIM found' : 'Grant the Phone permission to list SIMs');
      return;
    }
    final chosen = await showDialog<SimCardMessage>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('SIM for gate calls'),
        children: [
          RadioGroup<int>(
            groupValue: c.settings.simSubscriptionId,
            onChanged: (id) => Navigator.pop(ctx, c.sims.firstWhere((s) => s.subscriptionId == id)),
            child: Column(
              children: [
                for (final s in c.sims)
                  RadioListTile<int>(
                    value: s.subscriptionId,
                    enabled: s.callCapable,
                    title: Text(_simLabel(s)),
                    subtitle: Text(s.callCapable ? (s.displayName ?? '') : 'Not available for calls'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen != null) {
      await _save(c.settings.copyWith(simSubscriptionId: chosen.subscriptionId, simLabel: _simLabel(chosen)));
    }
  }

  String _simLabel(SimCardMessage s) {
    final name = (s.carrierName?.isNotEmpty ?? false) ? s.carrierName : s.displayName;
    return 'SIM ${s.slotIndex + 1}${name != null && name.isNotEmpty ? ' · $name' : ''}';
  }

  // ---- location ------------------------------------------------------------------------

  Future<void> _pickLocation() async {
    final s = c.settings;
    final picked = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          platform: c.platform,
          initial: s.hasLocation ? LatLng(s.latitude!, s.longitude!) : null,
          radiusMeters: s.radiusMeters,
        ),
      ),
    );
    if (picked != null) await _save(s.copyWith(latitude: picked.latitude, longitude: picked.longitude));
  }

  // ---- car -------------------------------------------------------------------------------

  PermissionItem _item(String id) => PermissionService.items.firstWhere((i) => i.id == id);

  Future<void> _chooseCar() async {
    final device = await showCarPicker(
      context,
      platform: c.platform,
      requestBluetoothPermission: () async {
        final item = _item('bluetooth');
        if (await widget.permissions.isPermanentlyDenied(item)) {
          await widget.permissions.openSettings();
          return false;
        }
        final ok = await widget.permissions.request(item);
        await _loadPermissions();
        return ok;
      },
    );
    if (device == null) return;
    try {
      await c.selectCar(device);
      _snack('Car set to ${device.name}');
    } on PlatformException catch (e) {
      _snack(e.message ?? 'Could not select the car');
    }
  }

  Future<void> _allowCarWake() async {
    await widget.permissions.request(_item('battery'));
    await _loadPermissions();
    await c.refresh();
  }

  // ---- permissions -------------------------------------------------------------------------

  Future<void> _grant(PermissionItem item) async {
    if (await widget.permissions.isPermanentlyDenied(item)) {
      await widget.permissions.openSettings();
    } else {
      await widget.permissions.request(item);
    }
    await _loadPermissions();
    await c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        final scheme = Theme.of(context).colorScheme;
        final selectedSim = c.selectedSim;
        final simMissing = s.simSubscriptionId != null && selectedSim == null;
        return ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SectionHeader('Gate'),
            ListTile(
              leading: const Icon(Icons.dialpad_rounded),
              title: const Text('Gate phone number'),
              subtitle: Text(Validators.maskPhone(s.gateNumber)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _editNumber,
            ),
            ListTile(
              leading: Icon(Icons.sim_card_outlined, color: simMissing ? scheme.error : null),
              title: const Text('SIM for gate calls'),
              subtitle: Text(
                s.simSubscriptionId == null
                    ? 'Not selected'
                    : simMissing
                        ? '${s.simLabel ?? 'Selected SIM'} is not available. No call will be placed until you choose a SIM.'
                        : _simLabel(selectedSim!),
                style: simMissing ? TextStyle(color: scheme.error) : null,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickSim,
            ),
            const SectionHeader('Parking'),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Parking location'),
              subtitle: Text(
                s.hasLocation
                    ? '${s.latitude!.toStringAsFixed(6)}, ${s.longitude!.toStringAsFixed(6)}'
                    : 'Not set',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickLocation,
            ),
            _slider(
              icon: Icons.radar_rounded,
              title: 'Geofence radius',
              value: _radius ?? s.radiusMeters.toDouble(),
              min: Limits.radiusMin.toDouble(),
              max: Limits.radiusMax.toDouble(),
              divisions: (Limits.radiusMax - Limits.radiusMin) ~/ 10,
              label: (v) => '${v.round()} m',
              onChanged: (v) => setState(() => _radius = v),
              onDone: (v) async {
                await _save(s.copyWith(radiusMeters: Validators.clampRadius(v)));
                setState(() => _radius = null);
              },
              hint: '150 m is recommended. Android geofences are less reliable below 100 m.',
            ),
            const SectionHeader('Trigger'),
            _slider(
              icon: Icons.timer_outlined,
              title: 'Delay when already inside',
              value: _delay ?? s.delaySeconds.toDouble(),
              min: Limits.delayMin.toDouble(),
              max: Limits.delayMax.toDouble(),
              divisions: Limits.delayMax - Limits.delayMin,
              label: (v) => '${v.round()} s',
              onChanged: (v) => setState(() => _delay = v),
              onDone: (v) async {
                await _save(s.copyWith(delaySeconds: Validators.clampDelay(v)));
                setState(() => _delay = null);
              },
              hint: 'Conditions are checked again after this delay before calling.',
            ),
            _slider(
              icon: Icons.hourglass_bottom_rounded,
              title: 'Cooldown between calls',
              value: _cooldown ?? s.cooldownMinutes.toDouble(),
              min: Limits.cooldownMin.toDouble(),
              max: Limits.cooldownMax.toDouble(),
              divisions: Limits.cooldownMax - Limits.cooldownMin,
              label: (v) => '${v.round()} min',
              onChanged: (v) => setState(() => _cooldown = v),
              onDone: (v) async {
                await _save(s.copyWith(cooldownMinutes: Validators.clampCooldown(v)));
                setState(() => _cooldown = null);
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.flash_on_rounded),
              title: const Text('Call immediately when arriving by car'),
              subtitle: const Text('If you enter the geofence while already detected as driving'),
              value: s.immediateTrigger,
              onChanged: (v) => _save(s.copyWith(immediateTrigger: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.directions_car_outlined),
              title: const Text('Activity Recognition (in vehicle)'),
              value: s.activityRecognitionEnabled,
              onChanged: (v) => _save(s.copyWith(activityRecognitionEnabled: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.phone_android_rounded),
              title: const Text('Android Auto detection'),
              subtitle: const Text('Android Auto connection alone never counts as driving outside the geofence'),
              value: s.androidAutoEnabled,
              onChanged: (v) => _save(s.copyWith(androidAutoEnabled: v)),
            ),
            ListTile(
              leading: Icon(s.carDeviceAssociated ? Icons.directions_car_rounded : Icons.bluetooth_rounded),
              title: Text(s.carDeviceAssociated ? (s.carDeviceName ?? 'Car') : 'Car Bluetooth'),
              subtitle: Text(
                s.carDeviceAssociated
                    ? 'Connecting to this car wakes GateKeeper to check Android Auto'
                    : 'Choose your car from your paired Bluetooth devices (no always-on service)',
              ),
              onTap: _chooseCar,
              trailing: s.carDeviceAssociated
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(onPressed: _chooseCar, child: const Text('Change')),
                        IconButton(
                          tooltip: 'Remove car',
                          onPressed: c.clearCar,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    )
                  : FilledButton.tonal(onPressed: _chooseCar, child: const Text('Choose')),
            ),
            if (c.status?.problems.contains('CAR_WAKE_BLOCKED') ?? false)
              ListTile(
                leading: Icon(Icons.battery_alert_rounded, color: scheme.tertiary),
                title: const Text('Let your car wake GateKeeper'),
                subtitle: const Text(
                  'Android only lets an app start its car check from the background if battery optimisation is off for it.',
                ),
                trailing: FilledButton.tonal(onPressed: _allowCarWake, child: const Text('Allow')),
              ),
            const SectionHeader('Test & diagnostics'),
            SwitchListTile(
              secondary: const Icon(Icons.science_outlined),
              title: const Text('Test mode'),
              subtitle: const Text('Triggers are simulated and logged. No call is ever placed.'),
              value: s.testMode,
              onChanged: (v) => _save(s.copyWith(testMode: v)),
            ),
            if (s.testMode) SimulatorPanel(platform: c.platform, onError: _snack),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Activity log'),
              subtitle: const Text('Every geofence, vehicle and car event, trigger decision and call attempt'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => LogsScreen(controller: c)),
              ),
            ),
            const SectionHeader('Permissions'),
            for (final item in PermissionService.items)
              ListTile(
                leading: Icon(
                  _granted[item.id] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                  color: _granted[item.id] == true
                      ? scheme.primary
                      : (item.optional ? scheme.outline : scheme.error),
                ),
                title: Text(item.title + (item.optional ? ' (recommended)' : '')),
                subtitle: Text(_granted[item.id] == true ? 'Granted' : 'Without it: ${item.unavailableWithout}'),
                trailing: _granted[item.id] == true
                    ? null
                    : TextButton(onPressed: () => _grant(item), child: const Text('Grant')),
              ),
            const SectionHeader('Updates'),
            UpdateSection(controller: widget.updates),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
              child: Text(
                'GateKeeper stores everything on this device only. No account, no analytics, no backend. '
                'Map tiles are loaded from OpenStreetMap only while the location picker is open, and address '
                'search uses Android’s built-in geocoder; update checks call the public GitHub releases API.',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _slider({
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) label,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onDone,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.bodyLarge)),
              Text(label(value), style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: label(value),
            onChanged: onChanged,
            onChangeEnd: onDone,
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
