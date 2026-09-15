import 'package:flutter/material.dart';

import '../core/theme/app_theme_extension.dart';

/// Pill badge widget that shows why a particular song was recommended or queued.
class WhyThisSongTag extends StatelessWidget {
  final String label;
  final IconData? icon;

  const WhyThisSongTag({
    super.key,
    required this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withOpacity(0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon ?? Icons.auto_awesome_rounded,
            size: 13,
            color: accent,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: aurora.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
