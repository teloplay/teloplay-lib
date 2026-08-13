import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../models/continue_session.dart';
import '../cached_artwork.dart';

/// Home feed card for Continue Session (multi-song).
/// Shows: "Tum Hi Ho + 4 more songs · From: Daily Mix" (roadmap Section H).
///
/// ⚠️ Fix (Phase 0 v11 stabilization):
/// - Wrong theme import (`core/theme/theme_extensions.dart` doesn't
///   exist — real file is `core/theme/app_theme_extension.dart`).
/// - `CachedArtwork(url: ..., size: ...)` — real params are
///   `imageUrl`/`width`/`height`.
/// - `session.currentSong.artist` — [ContinueSession.currentSong] is a
///   [SearchResult], whose field is `author`, not `artist`.
/// - The widget took onResume/onDismiss callbacks but never rendered any
///   button to trigger them — roadmap Section H's card mock explicitly
///   shows `[▶ Continue]  [✕ Dismiss]`.
class ContinueSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = context.aurora;
    final remainingSongs = session.remainingSongs;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedArtwork(
                    imageUrl: session.currentSong.thumbnail,
                    width: 80,
                    height: 80,
                  ),
                ),
                const SizedBox(width: 16),
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
                        session.currentSong.author,
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onResume,
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Continue'),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onDismiss,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.textSecondary,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Dismiss'),
                ),
              ],
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
