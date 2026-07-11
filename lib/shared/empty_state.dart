import 'package:flutter/material.dart';

/// Generic empty state: icon + title + optional subtitle + optional CTA.
///
/// Design brief §8: "ilustración + CTA". We use a Material icon as the
/// illustration placeholder until real illustrations are added.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.cta,
    this.onCta,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? cta;
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 72,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (cta != null && onCta != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCta,
                icon: const Icon(Icons.add),
                label: Text(cta!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
