import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../platform/gatekeeper_platform.dart';
import '../../ui/labels.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _filters = <String, Set<String>?>{
    'All': null,
    'Geofence': {'GEOFENCE'},
    'Vehicle': {'VEHICLE'},
    'Android Auto': {'ANDROID_AUTO', 'BLUETOOTH'},
    'Triggers': {'TRIGGER'},
    'Calls': {'CALL'},
    'Errors': {'ERROR'},
    'System': {'SYSTEM', 'TEST'},
  };

  List<LogEntryMessage> _entries = const [];
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await widget.controller.platform.getLogs(500);
    if (mounted) setState(() => _entries = entries);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the activity log?'),
        content: const Text('All log entries on this device are deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.platform.clearLogs();
    await _load();
  }

  IconData _icon(String category) => switch (category) {
        'GEOFENCE' => Icons.place_outlined,
        'VEHICLE' => Icons.directions_car_outlined,
        'ANDROID_AUTO' => Icons.phone_android_outlined,
        'BLUETOOTH' => Icons.bluetooth,
        'TRIGGER' => Icons.bolt_outlined,
        'CALL' => Icons.call_outlined,
        'ERROR' => Icons.error_outline,
        'TEST' => Icons.science_outlined,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allowed = _filters[_filter];
    final visible = allowed == null ? _entries : _entries.where((e) => allowed.contains(e.category)).toList();
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final f in _filters.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
              IconButton(tooltip: 'Clear log', onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined)),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: visible.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No events yet')),
                  ])
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                    itemBuilder: (context, i) {
                      final e = visible[i];
                      final isError = e.category == 'ERROR';
                      return ListTile(
                        dense: true,
                        leading: Icon(_icon(e.category), color: isError ? scheme.error : scheme.onSurfaceVariant),
                        title: Text(e.message),
                        subtitle: Text('${Labels.time(e.timestamp)} · ${e.category.toLowerCase().replaceAll('_', ' ')}'),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
