import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../platform/gatekeeper_platform.dart';
import '../../settings/problems.dart';
import '../../ui/labels.dart';
import '../../ui/widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.onOpenSettings});

  final AppController controller;
  final VoidCallback onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh relative times / countdown once a second while visible.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _toggle(StatusMessage? status) async {
    final c = widget.controller;
    final messenger = ScaffoldMessenger.of(context);
    if (status?.monitoring == true) {
      await c.stopMonitoring();
      messenger.showSnackBar(const SnackBar(content: Text('Monitoring stopped')));
      return;
    }
    final r = await c.startMonitoring();
    if (!mounted) return;
    if (r.started) {
      messenger.showSnackBar(const SnackBar(content: Text('Monitoring started')));
    } else {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Monitoring can’t start yet', style: Theme.of(ctx).textTheme.titleLarge),
              ),
              ProblemList(codes: Problems.blocking(r.problems)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onOpenSettings();
                  },
                  child: const Text('Open settings'),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final s = c.status;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final monitoring = s?.monitoring ?? false;
        final pending = s?.pendingDeadline;
        final secondsLeft = pending == null
            ? null
            : ((pending - DateTime.now().millisecondsSinceEpoch) / 1000).ceil().clamp(0, 999);

        return RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card.filled(
                color: monitoring ? scheme.primary : scheme.surfaceContainerHighest,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            monitoring ? Icons.shield_rounded : Icons.shield_outlined,
                            color: monitoring ? scheme.onPrimary : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            monitoring ? 'Monitoring' : 'Not monitoring',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: monitoring ? scheme.onPrimary : scheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          if (s?.testMode == true)
                            Chip(
                              label: const Text('TEST MODE'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: scheme.tertiaryContainer,
                              labelStyle: TextStyle(color: scheme.onTertiaryContainer, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        secondsLeft != null
                            ? 'Revalidating · calling in ${secondsLeft}s if still valid'
                            : Labels.phase(s?.phase),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: monitoring ? scheme.onPrimary.withValues(alpha: 0.9) : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: monitoring
                            ? FilledButton.tonalIcon(
                                onPressed: c.busy ? null : () => _toggle(s),
                                icon: const Icon(Icons.stop_rounded),
                                label: const Text('Stop monitoring'),
                              )
                            : FilledButton.icon(
                                onPressed: c.busy ? null : () => _toggle(s),
                                icon: c.busy
                                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.play_arrow_rounded),
                                label: const Text('Start monitoring'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              if ((s?.problems ?? const []).isNotEmpty) ...[
                const SizedBox(height: 12),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: ProblemList(codes: s!.problems, onTap: widget.onOpenSettings),
                ),
              ],
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  StateTile(
                    icon: Icons.place_rounded,
                    label: 'Parking geofence',
                    value: Labels.geofence(s?.geofence),
                    active: s?.geofence == 'INSIDE',
                  ),
                  StateTile(
                    icon: Icons.directions_car_rounded,
                    label: 'Vehicle detection',
                    value: Labels.vehicle(s?.vehicle),
                    active: s?.vehicle == 'ACTIVE',
                  ),
                  StateTile(
                    icon: Icons.phone_android_rounded,
                    label: 'Android Auto',
                    value: Labels.androidAuto(s?.androidAuto),
                    detail: s?.androidAutoObservedAt == null ? null : 'seen ${Labels.ago(s!.androidAutoObservedAt)}',
                    active: s?.androidAuto == 'ACTIVE',
                  ),
                  StateTile(
                    icon: Icons.bluetooth_rounded,
                    label: 'Car Bluetooth',
                    value: !c.settings.carDeviceAssociated
                        ? 'Not chosen'
                        : (s?.carBluetoothConnected == true ? 'Connected' : 'Not connected'),
                    // Connected only counts as a vehicle signal when the switch is on.
                    detail: c.settings.carDeviceAssociated
                        ? (c.settings.carBluetoothEnabled ? c.settings.carDeviceName : 'Not used as a signal')
                        : null,
                    active: c.settings.carBluetoothEnabled && s?.carBluetoothConnected == true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card.outlined(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.bolt_rounded),
                      title: const Text('Last trigger'),
                      subtitle: Text(
                        s?.lastTriggerAt == null
                            ? 'None yet'
                            : '${Labels.triggerSource(s!.lastTriggerSource)}\n${s.lastTriggerDecision ?? ''}',
                      ),
                      isThreeLine: s?.lastTriggerAt != null,
                      trailing: Text(Labels.time(s?.lastTriggerAt)),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.call_rounded),
                      title: const Text('Last call'),
                      subtitle: Text(s?.lastCallAt == null ? 'None yet' : Labels.callOutcome(s!.lastCallOutcome)),
                      trailing: Text(Labels.time(s?.lastCallAt)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
