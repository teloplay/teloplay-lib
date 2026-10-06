import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../models/now_playing_model.dart';

/// P0-12 — pure presentational error card for typed playback failures.
/// No providers, no navigation: the parent wires `onRetry` (re-invoke the
/// failed play) and decides placement. Switches on [PlaybackError.kind];
/// the message is shown verbatim (curated at the repo boundary, never raw).
class PlaybackErrorCard extends StatelessWidget {
  const PlaybackErrorCard({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final PlaybackError error;
  final VoidCallback onRetry;

  IconData get _icon {
    switch (error.kind) {
      case PlaybackErrorKind.network:
        return Icons.wifi_off_rounded;
      case PlaybackErrorKind.unavailable:
        return Icons.block_rounded;
      case PlaybackErrorKind.playback:
      case PlaybackErrorKind.unknown:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: aurora.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aurora.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(_icon, color: aurora.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error.message,
              style: TextStyle(color: aurora.textPrimary, fontSize: 14),
            ),
          ),
          if (error.retryable) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
