import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme_extension.dart';
import '../profile_providers.dart';

/// ⚠️ Phase 6.5 Batch 6 — Quick Stats grid: Total Played, Favorites,
/// Playlists, Listening Time (This Week), Cached Songs।
///
/// Loading/error state নিজেই handle করে (profileQuickStatsProvider
/// AsyncValue) — bare CircularProgressIndicator না দেখিয়ে shimmer-ish
/// placeholder card দেখানো হচ্ছে (existing skeleton pattern না থাকলে
/// simple empty-state card, over-engineering এড়াতে এই ব্যাচে নতুন
/// shimmer widget বানানো হয়নি)।
class QuickStatsGrid extends ConsumerWidget {
  const QuickStatsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final statsAsync = ref.watch(profileQuickStatsProvider);

    final stats = statsAsync.maybeWhen(
      data: (s) => s,
      orElse: () => ProfileQuickStats.empty,
    );
    final isLoading = statsAsync.isLoading;

    final items = <_StatItem>[
      _StatItem(
        icon: Icons.play_circle_outline,
        label: 'Played songs',
        value: '${stats.totalPlayedSongs}',
      ),
      _StatItem(
        icon: Icons.favorite_border,
        label: 'Favorites',
        value: '${stats.favoriteSongsCount}',
      ),
      _StatItem(
        icon: Icons.queue_music,
        label: 'Playlists',
        value: '${stats.playlistsCount}',
      ),
      _StatItem(
        icon: Icons.access_time,
        label: 'This week',
        value: _formatDuration(stats.listeningTimeThisWeek),
      ),
      _StatItem(
        icon: Icons.offline_pin_outlined,
        label: 'Cached',
        value: '${stats.cachedSongsCount}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // ⚠️ Design rule: Desktop = two-column layout (Profile+Stats
        // left / Settings right) — এই grid নিজে সবসময় same width-এ
        // থাকে, শুধু cross-axis-count breakpoint দিয়ে responsive
        // (mobile narrow-width বনাম desktop left-column width)।
        final crossAxisCount = constraints.maxWidth > 520 ? 5 : 2;

        return Opacity(
          opacity: isLoading ? 0.5 : 1.0,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: crossAxisCount == 5 ? 0.95 : 1.4,
            ),
            itemBuilder: (context, index) => _StatCard(item: items[index], aurora: aurora),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m';
    }
    return '0m';
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({required this.icon, required this.label, required this.value});
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item, required this.aurora});

  final _StatItem item;
  final AuroraColors aurora;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: aurora.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: aurora.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 18, color: aurora.primary),
          const SizedBox(height: 8),
          Text(
            item.value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: aurora.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(fontSize: 11, color: aurora.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}