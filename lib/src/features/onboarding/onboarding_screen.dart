import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../ui/logo.dart';
import '../permissions/permission_service.dart';

/// First-run walkthrough: explains what GateKeeper does and asks for each permission in context.
/// Every step can be skipped; the consequence is shown and listed later on the settings screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller, required this.permissions});

  final AppController controller;
  final PermissionService permissions;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _index = 0;
  final Map<String, bool> _granted = {};

  int get _count => PermissionService.items.length + 2;

  @override
  void initState() {
    super.initState();
    widget.permissions.statusAll().then((m) {
      if (mounted) setState(() => _granted.addAll(m));
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _count - 1) {
      _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _grant(PermissionItem item) async {
    final ok = await widget.permissions.request(item);
    setState(() => _granted[item.id] = ok);
    if (ok) _next();
  }

  Future<void> _finish() async {
    final c = widget.controller;
    await c.saveSettings(c.settings.copyWith(onboardingComplete: true));
    await c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(value: (_index + 1) / _count),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _page(
                    icon: Icons.fence_rounded,
                    logo: true,
                    title: 'Welcome to GateKeeper',
                    body: 'GateKeeper phones your gate automatically when you drive into your parking area, '
                        'or when you get into your car while parked there.\n\n'
                        'It only calls when you are inside the parking geofence AND a vehicle signal is active '
                        '(driving detected, or Android Auto connected). Walking in never calls. '
                        'Each arrival makes at most one call, with a cooldown.\n\n'
                        'Everything stays on this phone. No account, no tracking.',
                    primary: FilledButton(onPressed: _next, child: const Text('Get started')),
                  ),
                  for (final item in PermissionService.items) _permissionPage(item, theme),
                  _page(
                    icon: Icons.tune_rounded,
                    title: 'Almost done',
                    body: 'Next, set up the gate in Settings:\n\n'
                        '• gate phone number\n• the SIM to call from\n• your parking location and radius\n'
                        '• optionally, choose your car’s Bluetooth\n\n'
                        'Try test mode first: it runs the same logic but never places a call.',
                    primary: FilledButton(onPressed: _finish, child: const Text('Open GateKeeper')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionPage(PermissionItem item, ThemeData theme) {
    final granted = _granted[item.id] == true;
    return _page(
      icon: switch (item.id) {
        'location' || 'background_location' => Icons.location_on_rounded,
        'activity' => Icons.directions_car_rounded,
        'phone' => Icons.call_rounded,
        'notifications' => Icons.notifications_rounded,
        'bluetooth' => Icons.bluetooth_rounded,
        _ => Icons.battery_saver_rounded,
      },
      title: item.title,
      body: item.rationale,
      footer: granted
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Granted'),
            ])
          : Text(
              'If you skip this: ${item.unavailableWithout} won’t work.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
      primary: granted
          ? FilledButton(onPressed: _next, child: const Text('Continue'))
          : FilledButton(onPressed: () => _grant(item), child: const Text('Allow')),
      secondary: granted ? null : TextButton(onPressed: _next, child: const Text('Skip for now')),
    );
  }

  Widget _page({
    required IconData icon,
    bool logo = false,
    required String title,
    required String body,
    required Widget primary,
    Widget? secondary,
    Widget? footer,
  }) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (logo)
                const GateKeeperMark(size: 96)
              else
                CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(icon, size: 40, color: theme.colorScheme.onPrimaryContainer),
                ),
              const SizedBox(height: 24),
              Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(body, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ?footer,
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: primary),
              ?secondary,
            ],
          ),
        ),
      ),
    );
  }
}
