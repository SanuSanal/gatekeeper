import 'package:flutter/material.dart';

import '../settings/problems.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Compact tile showing one sensor state on the home screen.
class StateTile extends StatelessWidget {
  const StateTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card.filled(
      color: active ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(label, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              value,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: active ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
            if (detail != null && detail!.isNotEmpty)
              Text(detail!, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// Lists blocking problems (error colour) and warnings (tertiary colour).
class ProblemList extends StatelessWidget {
  const ProblemList({super.key, required this.codes, this.onTap});

  final List<String> codes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final blocking = Problems.blocking(codes);
    final warnings = Problems.warnings(codes);
    Widget row(String code, bool isBlocking) {
      final info = Problems.describe(code);
      return ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(
          isBlocking ? Icons.error_outline : Icons.warning_amber_rounded,
          color: isBlocking ? scheme.error : scheme.tertiary,
        ),
        title: Text(info.title),
        subtitle: Text(info.impact),
      );
    }

    return Column(
      children: [
        for (final c in blocking) row(c, true),
        for (final c in warnings) row(c, false),
      ],
    );
  }
}
