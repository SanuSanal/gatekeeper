import 'package:flutter/material.dart';

import '../ui/labels.dart';
import 'update_controller.dart';

/// "Updates" section on the settings screen.
class UpdateSection extends StatelessWidget {
  const UpdateSection({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final scheme = Theme.of(context).colorScheme;
        final release = c.lastCheck?.release;
        final String subtitle = switch (c.status) {
          UpdateStatus.checking => 'Checking GitHub releases…',
          UpdateStatus.upToDate => 'You have the latest version',
          UpdateStatus.available => 'Version ${release?.version} is available',
          UpdateStatus.downloading => 'Downloading ${release?.version}…',
          UpdateStatus.needsPermission => 'Allow GateKeeper to install apps, then tap Install again',
          UpdateStatus.installerOpened => 'Confirm the installation in the Android dialog',
          UpdateStatus.error => c.error ?? 'Update failed',
          UpdateStatus.idle => c.lastCheckedAt == null
              ? 'Not checked yet'
              : 'Last checked ${Labels.time(c.lastCheckedAt!.millisecondsSinceEpoch)}',
        };
        return Column(
          children: [
            ListTile(
              leading: Icon(
                c.status == UpdateStatus.available ? Icons.system_update_rounded : Icons.update_rounded,
                color: c.status == UpdateStatus.available ? scheme.primary : null,
              ),
              title: Text('Version ${c.currentVersion ?? '…'}'),
              subtitle: Text(
                c.error != null && c.status != UpdateStatus.error ? '$subtitle\n${c.error}' : subtitle,
                style: c.status == UpdateStatus.error ? TextStyle(color: scheme.error) : null,
              ),
              trailing: _action(context),
            ),
            if (c.status == UpdateStatus.downloading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(value: c.progress),
              ),
            SwitchListTile(
              secondary: const Icon(Icons.schedule_rounded),
              title: const Text('Check for updates automatically'),
              subtitle: const Text('Once a day, from the public GitHub releases. No personal data is sent.'),
              value: c.autoCheck,
              onChanged: c.setAutoCheck,
            ),
          ],
        );
      },
    );
  }

  Widget? _action(BuildContext context) {
    final c = controller;
    return switch (c.status) {
      UpdateStatus.checking || UpdateStatus.downloading =>
        const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      UpdateStatus.available || UpdateStatus.installerOpened =>
        FilledButton(onPressed: c.downloadAndInstall, child: const Text('Install')),
      UpdateStatus.needsPermission => FilledButton.tonal(
          onPressed: () async {
            await c.openInstallPermissionSettings();
          },
          child: const Text('Allow'),
        ),
      _ => TextButton(onPressed: () => c.check(), child: const Text('Check')),
    };
  }
}

/// Dialog shown once per new version found by the automatic check.
Future<void> showUpdatePrompt(BuildContext context, UpdateController c) async {
  final release = c.lastCheck?.release;
  if (release == null) return;
  final notes = release.notes.trim();
  final install = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_rounded),
      title: Text('GateKeeper ${release.version} is available'),
      content: SingleChildScrollView(
        child: Text(
          'You have ${c.currentVersion}. The update is downloaded from GitHub, verified, '
          'and installed after you confirm in Android’s installer.'
          '${notes.isEmpty ? '' : '\n\n${notes.length > 600 ? '${notes.substring(0, 600)}…' : notes}'}',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Update')),
      ],
    ),
  );
  if (install == true) {
    await c.downloadAndInstall();
  } else {
    await c.dismissPrompt();
  }
}
