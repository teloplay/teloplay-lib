import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_extension.dart';

/// ⚠️ Phase 6.5 Batch 6 — Shared section wrapper (title + card of
/// ProfileTile rows) — Account/Devices/Playback/Storage/Diagnostics/
/// About সবগুলো section এই একই shell ব্যবহার করে, যাতে visual rhythm
/// সামঞ্জস্যপূর্ণ থাকে (roadmap design rule: card-based sections,
/// mobile bottom-sheet-friendly, desktop two-column)।
class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: aurora.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: aurora.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: aurora.glassBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// একটা single row — icon + label + trailing (value/switch/chevron)।
/// Account/Devices/About section-এর প্রতিটা item এই একই shape ব্যবহার
/// করে — Settings-list দেখানো হলেও, এটা ProfileSection wrapper-এর
/// ভেতরে বসে বলেই সেটা "just a settings list" মনে হয় না (design rule
/// অনুযায়ী, personal-dashboard feel মূলত header+stats থেকে আসে, এই
/// tile নিজে neutral/utility building block)।
class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final color = isDestructive ? aurora.error : aurora.textPrimary;

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 19, color: isDestructive ? aurora.error : aurora.textSecondary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12, color: aurora.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!
                else if (onTap != null)
                  Icon(Icons.chevron_right, size: 18, color: aurora.textSecondary),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, indent: 16, endIndent: 16, color: aurora.glassBorder),
      ],
    );
  }
}

/// Switch/toggle-trailing variant shorthand — Playback & Experience
/// section-এর ON/OFF items-এর জন্য (Theme Mode বাদে, সেটা dropdown)।
class ProfileToggleTile extends StatelessWidget {
  const ProfileToggleTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return ProfileTile(
      icon: icon,
      label: label,
      subtitle: subtitle,
      showDivider: showDivider,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: aurora.primary,
      ),
    );
  }
}