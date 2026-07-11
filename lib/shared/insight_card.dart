import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Severity level for an insight card (design system §6).
enum InsightSeverity {
  /// Blue info card — neutral / informational (e.g. spending pace).
  info,

  /// Amber warning card — caution, budget approaching limit.
  warning,

  /// Red critical card — budget exceeded or urgent action.
  critical,
}

/// Insight card component (mockup 06 / design system §6).
///
/// Structure:
///   - Colored background tinted by severity
///   - Square icon container on the left (solid severity color)
///   - Title (14 W600) + body text (14 W400)
///
/// Matches the InsightCard spec: blue/amber/red with a small icon square.
class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.title,
    required this.body,
    this.severity = InsightSeverity.info,
    this.icon,
  });

  final String title;
  final String body;
  final InsightSeverity severity;

  /// Optional icon override. Defaults to severity-appropriate icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colors = _severityColors(severity, isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: BalviaTheme.spaceSm),
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        border: Border.all(color: colors.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon square
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.iconBackground,
              borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
            ),
            child: Icon(
              icon ?? _defaultIcon(severity),
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: BalviaTheme.spaceMd),

          // Text column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BalviaTheme.bodyStyle(
                    color: colors.textStrong,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: BalviaTheme.spaceXs),
                Text(
                  body,
                  style: BalviaTheme.bodyStyle(color: colors.textBody),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static IconData _defaultIcon(InsightSeverity severity) => switch (severity) {
    InsightSeverity.info => Icons.info_outline,
    InsightSeverity.warning => Icons.warning_amber_rounded,
    InsightSeverity.critical => Icons.error_outline,
  };

  static _InsightColors _severityColors(
    InsightSeverity severity,
    bool isDark,
  ) => switch (severity) {
    InsightSeverity.info => _InsightColors(
      background: isDark ? const Color(0xFF1A2A3A) : const Color(0xFFE3F2FD),
      border: isDark ? const Color(0xFF1565C0) : const Color(0xFF90CAF9),
      iconBackground: const Color(0xFF1976D2),
      textStrong: isDark ? const Color(0xFFBBDEFB) : const Color(0xFF0D47A1),
      textBody: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
    ),
    InsightSeverity.warning => _InsightColors(
      background: isDark ? const Color(0xFF2A200A) : const Color(0xFFFFF8E1),
      border: isDark ? const Color(0xFFE65100) : const Color(0xFFFFCC02),
      iconBackground: const Color(0xFFF57C00),
      textStrong: isDark ? const Color(0xFFFFE082) : const Color(0xFFE65100),
      textBody: isDark ? const Color(0xFFFFCC02) : const Color(0xFF6D4C00),
    ),
    InsightSeverity.critical => _InsightColors(
      background: isDark ? const Color(0xFF2A0A0A) : const Color(0xFFFFEBEE),
      border: isDark ? const Color(0xFFC62828) : const Color(0xFFEF9A9A),
      iconBackground: const Color(0xFFD32F2F),
      textStrong: isDark ? const Color(0xFFFFCDD2) : const Color(0xFFB71C1C),
      textBody: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828),
    ),
  };
}

class _InsightColors {
  const _InsightColors({
    required this.background,
    required this.border,
    required this.iconBackground,
    required this.textStrong,
    required this.textBody,
  });

  final Color background;
  final Color border;
  final Color iconBackground;
  final Color textStrong;
  final Color textBody;
}
