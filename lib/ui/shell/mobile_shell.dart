import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/library/library_bento_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../widgets/mini_player/floating_mini_player.dart';

/// Phase 3 — Android/Mobile Shell with Liquid/Water Frosted Glass Navigation Bar.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key, this.initialLibrarySection});

  final String? initialLibrarySection;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  late int _index = widget.initialLibrarySection != null ? 2 : 0;

  static const _destinations = [
    _NavDestination(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
    _NavDestination(icon: Icons.search_outlined, selectedIcon: Icons.search_rounded, label: 'Search'),
    _NavDestination(icon: Icons.library_music_outlined, selectedIcon: Icons.library_music_rounded, label: 'Library'),
    _NavDestination(icon: Icons.person_outline, selectedIcon: Icons.person_rounded, label: 'Profile'),
  ];

  static const _bodies = [
    HomeScreen(),
    SearchScreen(),
    LibraryBentoScreen(),
    ProfileScreen(),
  ];

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
            bottom: 74,
            child: FloatingMiniPlayer(
              onExpand: () => context.push('/player'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: aurora.surface.withOpacity(0.78),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_destinations.length, (idx) {
                final d = _destinations[idx];
                final isSelected = _index == idx;
                return Expanded(
                  child: InkWell(
                    onTap: () => _onDestinationSelected(idx),
                    splashFactory: NoSplash.splashFactory,
                    highlightColor: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? aurora.primary.withOpacity(0.18) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: aurora.primary.withOpacity(0.25),
                                      blurRadius: 10,
                                      spreadRadius: -2,
                                    )
                                  ]
                                : null,
                          ),
                          child: Icon(
                            isSelected ? d.selectedIcon : d.icon,
                            color: isSelected ? aurora.primary : aurora.textSecondary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d.label,
                          style: TextStyle(
                            color: isSelected ? aurora.textPrimary : aurora.textSecondary.withOpacity(0.8),
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
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
