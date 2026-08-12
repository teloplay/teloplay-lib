import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_extensions.dart';
import '../../models/continue_session.dart';
import '../../services/session/continue_session_manager.dart';

/// Home feed card for Continue Session (multi-song).
/// Shows: "Tum Hi Ho + 4 more songs · From: Daily Mix"
class ContinueSection extends ConsumerWidget {
  final ContinueSession session;
  final VoidCallback onResume;
  final VoidCallback onDismiss;

  const ContinueSection({
    super.key,
    required this.session,
    required this.onResume,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final remainingSongs = session.queueSnapshot.length - session.currentIndex - 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Album art
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedArtwork(
                url: session.currentSong.thumbnail,
                size: 80,
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.currentSong.title,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.currentSong.artist ?? 'Unknown Artist',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Left off at: ${_formatDuration(session.currentPosition)}',
                    style: TextStyle(
                      color: theme.primary,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (remainingSongs > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '+ $remainingSongs more songs in queue',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'From: ${session.sourceRail}',
                    style: TextStyle(
                      color: theme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}