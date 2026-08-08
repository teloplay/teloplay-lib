import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/library/library_bento_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../widgets/mini_player/floating_mini_player.dart';

/// ⚠️ Phase 6 — Android/mobile shell। Bottom navigation + vertical,
/// touch-first layout। এই ব্যাচে player screen content এখনো ভাঙা হয়নি
/// (দেখো architecture_decision নোট — Batch 3-এ শেয়ার্ড content widget
/// বের হবে), তাই আপাতত `MusicPlayerScreen` পুরোটাই "Player" ট্যাবের
/// ভেতরে বসানো হচ্ছে। পরের ব্যাচে ভেতরের body বদলে যাবে, bottom nav
/// shell অপরিবর্তিত থাকবে।
///
/// Bottom nav destination-গুলো বিদ্যমান top-level route-এর সাথেই মেলানো
/// হয়েছে (Library/Playlists ইতিমধ্যে GoRoute হিসেবে আছে) — নতুন কোনো
/// route যোগ করা হয়নি এই ব্যাচে, শুধু navigation entry point centralize
/// করা হলো।

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, this.initialLibrarySection});

  /// Router Shell Bug fix — /library/:section deep-link chrome-wrap
  /// হয়ে এলে শুরুতেই Library ট্যাব (index 2) সিলেক্টেড থাকবে।
  final String? initialLibrarySection;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  late int _index = widget.initialLibrarySection != null ? 2 : 0;
  
  static const _destinations = [
    _NavDestination(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
    _NavDestination(icon: Icons.search_outlined, selectedIcon: Icons.search, label: 'Search'),
    _NavDestination(icon: Icons.library_music_outlined, selectedIcon: Icons.library_music, label: 'Library'),
    _NavDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
  ];

  static const _bodies = [
    HomeScreen(),
    SearchScreen(),
    LibraryBentoScreen(),
    ProfileScreen(),
  ];
  // ⚠️ Phase 6.5 — এখন সব ৪টা tab IndexedStack-এর ভেতরের body হিসেবেই
  // থাকে (আগে শুধু Player tab body ছিল, বাকিরা push করত) — tab switch
  // এখন push/pop না, শুধু index বদল (state preserve করার জন্য
  // IndexedStack ব্যবহার করা হচ্ছে নিচের build()-এ)।
  void _onDestinationSelected(int index) {
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Scaffold(
      backgroundColor: aurora.background,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: _bodies),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: FloatingMiniPlayer(
              onExpand: () => context.push('/player'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        backgroundColor: aurora.surface,
        indicatorColor: aurora.primary.withOpacity(0.18),
        destinations: _destinations
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon, color: aurora.textSecondary),
                  selectedIcon: Icon(d.selectedIcon, color: aurora.primary),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}