import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';

/// Audio settings section for the Settings screen.
/// Provides controls for Volume Normalization and Crossfade.
class AudioSettingsWidget extends StatelessWidget {
  final bool volumeNormalizationEnabled;
  final bool crossfadeEnabled;
  final double crossfadeDurationSeconds;
  final ValueChanged<bool> onVolumeNormalizationChanged;
  final ValueChanged<bool> onCrossfadeEnabledChanged;
  final ValueChanged<double> onCrossfadeDurationChanged;

  const AudioSettingsWidget({
    super.key,
    required this.volumeNormalizationEnabled,
    required this.crossfadeEnabled,
    required this.crossfadeDurationSeconds,
    required this.onVolumeNormalizationChanged,
    required this.onCrossfadeEnabledChanged,
    required this.onCrossfadeDurationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Audio Experience',
            style: TextStyle(
              color: theme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ),

        // Volume Normalization toggle
        _SettingsToggleRow(
          icon: Icons.volume_up_outlined,
          title: 'Volume Normalization',
          subtitle: 'Reduce volume differences between tracks',
          value: volumeNormalizationEnabled,
          onChanged: onVolumeNormalizationChanged,
        ),

        // Crossfade toggle
        _SettingsToggleRow(
          icon: Icons.swap_horiz_rounded,
          title: 'Crossfade',
          subtitle: 'Smooth transition between tracks',
          value: crossfadeEnabled,
          onChanged: onCrossfadeEnabledChanged,
        ),

        // Crossfade duration (only visible when crossfade is enabled)
        if (crossfadeEnabled)
          _SettingsSliderRow(
            icon: Icons.timer_outlined,
            title: 'Crossfade Duration',
            value: crossfadeDurationSeconds,
            min: 0.5,
            max: 5.0,
            divisions: 9,
            valueLabel: '${crossfadeDurationSeconds.toStringAsFixed(1)}s',
            onChanged: onCrossfadeDurationChanged,
          ),

        const SizedBox(height: 16),
      ],
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: theme.textSecondary, size: 24),
        title: Text(
          title,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: theme.textSecondary,
            fontSize: 13,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: theme.primary,
        ),
      ),
    );
  }
}

class _SettingsSliderRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  const _SettingsSliderRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.textSecondary, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  color: theme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            activeColor: theme.primary,
            inactiveColor: theme.surfaceRaised,
          ),
        ],
      ),
    );
  }
}
