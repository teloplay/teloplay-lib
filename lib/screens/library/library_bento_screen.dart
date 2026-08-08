import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../widgets/bento/bento_grid_card.dart';
import 'downloaded_songs_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'playlists_screen.dart';

/// Phase 6.5 UI-Batch 4 — Library-এর নতুন bento-grid landing (Mobile)।
///
/// ⚠️ পুরনো `LibraryScreen` (section-preview hub, /library/:section
/// nested-route logic সহ) সরাসরি edit করা হয়নি — রিস্ক এড়াতে এটা
/// আলাদা নতুন screen। এই screen শুধু ৬টা section-এর card grid দেখায়,
/// tap করলে existing screen-এই নিয়ে যায় (কোনো নতুন backend/repository
/// logic নেই, existing FavoritesScreen/PlaylistsScreen/HistoryScreen/
/// DownloadedSongsScreen reuse)। "Most Played"-এর জন্য এখনো dedicated
/// screen নেই (Phase 7+, roadmap অনুযায়ী) — তাই সেটা পুরনো hub
/// (`LibraryScreen`)-এ পাঠানো হচ্ছে, যেখানে "Coming soon" placeholder
/// আগে থেকেই আছে।
class LibraryBentoScreen extends StatelessWidget {
  const LibraryBentoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final accents = AppColors.curatedAccents;

    final items = <_BentoItem>[
      _BentoItem(
        icon: Icons.favorite_rounded,
        label: 'Favorites',
        accent: accents[0 % accents.length],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FavoritesScreen()),
        ),
      ),
      _BentoItem(
        icon: Icons.playlist_play_rounded,
        label: 'Playlists',
        accent: accents[1 % accents.length],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
        ),
      ),
      _BentoItem(
        icon: Icons.history_rounded,
        label: 'Recently Played',
        accent: accents[2 % accents.length],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        ),
      ),
      _BentoItem(
        icon: Icons.local_fire_department_rounded,
        label: 'Most Played',
        accent: accents[3 % accents.length],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LibraryScreen(section: 'most-played')),
        ),
      ),
      _BentoItem(
        icon: Icons.download_done_rounded,
        label: 'Offline',
        accent: accents[4 % accents.length],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DownloadedSongsScreen()),
        ),
      ),
      _BentoItem(
        icon: Icons.sd_storage_rounded,
        label: 'Cached Songs',
        accent: accents[5 % accents.length],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DownloadedSongsScreen()),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: aurora.background,
      appBar: AppBar(
        backgroundColor: aurora.background,
        elevation: 0,
        title: Text('Library', style: TextStyle(color: aurora.textPrimary, fontWeight: FontWeight.w800)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          itemCount: items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return BentoGridCard(
              icon: item.icon,
              label: item.label,
              accentColor: item.accent,
              onTap: item.onTap,
            );
          },
        ),
      ),
    );
  }
}

class _BentoItem {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _BentoItem({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });
}