import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_theme_extension.dart';

/// ⚠️ UI-Batch 2 — desktop top bar per locked spec:
/// [← →]  [🔍 centered search bar + Ctrl K hint]  [🔔] [⚙] [👤 avatar]
///
/// Back/forward use simple `canGoBack`/`canGoForward` booleans passed in
/// (DesktopShell derives these from its own _index history stack — no
/// GoRouter history dependency this batch, since we're staying on
/// IndexedStack navigation).
///
/// Search bar tap → jumps to Search tab (index 1) via onSearchTap.
/// Ctrl+K binding is NOT wired here — add to DesktopShell's existing
/// CallbackShortcuts map: `SingleActivator(LogicalKeyboardKey.keyK,
/// control: true): onSearchTap`.
///
/// Notification bell — UI placeholder only, no badge (no notification
/// system yet, per locked spec).
class DesktopTopBar extends StatelessWidget {
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback onSearchTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onProfileTap;
  final String? avatarUrl;

  const DesktopTopBar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onSearchTap,
    required this.onSettingsTap,
    required this.onProfileTap,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    // ⚠️ Fix — এই widget-এ আগে DragToMoveArea + WindowControls
    // (min/max/close) ছিল, কিন্তু rewrite-এ বাদ পড়ে গিয়েছিল। windowManager
    // এখনো titleBarStyle: hidden ব্যবহার করে (window_tray_manager.dart) —
    // মানে Windows-এর নিজস্ব native title bar/close বাটন নেই, এই কাস্টম
    // bar-টাই একমাত্র জায়গা যেখান থেকে window move/minimize/maximize/
    // close করা যায়। DragToMoveArea পুরো bar-টা wrap করছে যাতে ফাঁকা
    // জায়গায় ক্লিক-ড্র্যাগ করে window move করা যায় (বাটনগুলোর hit-area
    // অগ্রাধিকার পাবে, DragToMoveArea children-এর gesture override করে
    // না)।
   // ⚠️ Fix — window-control বাটন (min/max/close) DragToMoveArea-এর
    // ভেতরে থাকায় nested gesture-arena resolution-এর কারণে click
    // response 1-2s delay করছিল (drag-vs-tap ambiguous হওয়ায় Flutter-কে
    // অপেক্ষা করতে হচ্ছিল)। WindowControls এখন সম্পূর্ণ আলাদা, বাইরের
    // sibling — শুধু বাকি bar-টা (back/forward/search/bell/settings/
    // avatar-এর ফাঁকা জায়গা) DragToMoveArea-এর ভেতরে, drag-move ঠিকই
    // কাজ করবে কিন্তু window-control বাটনের সাথে gesture-conflict আর
    // হবে না।
    return Container(
      height: 60,
      color: aurora.background,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: canGoBack ? aurora.textPrimary : aurora.textSecondary.withOpacity(0.4),
                    onPressed: canGoBack ? onBack : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: canGoForward ? aurora.textPrimary : aurora.textSecondary.withOpacity(0.4),
                    onPressed: canGoForward ? onForward : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _SearchBarButton(onTap: onSearchTap),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    color: aurora.textSecondary,
                    onPressed: () {}, // placeholder — no notification system yet
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    color: aurora.textSecondary,
                    onPressed: onSettingsTap,
                  ),
                  const SizedBox(width: 4),
                  _Avatar(url: avatarUrl, onTap: onProfileTap),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          const WindowControls(),
        ],
      ),
    );
  }
}

/// Window min/maximize/close বাটন — hidden titleBarStyle-এ এটাই একমাত্র
/// উপায় window নিয়ন্ত্রণ করার। X বাটন সরাসরি windowManager.close() কল
/// করে — WindowTrayManager-এর setPreventClose(true) + onWindowClose()
/// override থাকায় এটা app বন্ধ না করে tray-তে minimize করবে।
class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowBtn(
          icon: Icons.remove_rounded,
          onTap: windowManager.minimize,
        ),
        _WindowBtn(
          icon: Icons.crop_square_rounded,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.restore();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        // ⚠️ Fix — Spotify-style close button: hover করলে solid red
        // background + সাদা icon (শুধু icon-color বদলানো না, পুরো
        // background fill)। isCloseButton flag দিয়ে _WindowBtn-এর ভেতরে
        // আলাদা hover-visual branch নেওয়া হচ্ছে।
        _WindowBtn(
          icon: Icons.close_rounded,
          isCloseButton: true,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WindowBtn extends StatefulWidget {
  final IconData icon;
  final Color? color;
  final bool isCloseButton;
  final VoidCallback onTap;

  const _WindowBtn({
    required this.icon,
    this.color,
    this.isCloseButton = false,
    required this.onTap,
  });

  @override
  State<_WindowBtn> createState() => _WindowBtnState();
}

class _WindowBtnState extends State<_WindowBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    // Spotify-style close hover: solid red fill + white icon।
    // Minimize/maximize hover: subtle white-tint fill, icon color অপরিবর্তিত।
    final bgColor = _hovered
        ? (widget.isCloseButton ? const Color(0xFFE81123) : Colors.white.withOpacity(0.1))
        : Colors.transparent;
    final iconColor = _hovered && widget.isCloseButton
        ? Colors.white
        : (widget.color ?? aurora.textSecondary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          height: 36,
          color: bgColor,
          alignment: Alignment.center,
          child: Icon(widget.icon, size: 15, color: iconColor),
        ),
      ),
    );
  }
}

class _SearchBarButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchBarButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Material(
      color: aurora.surfaceRaised,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: aurora.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Search for songs, artists, albums...',
                  style: TextStyle(color: aurora.textSecondary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _KeyHint(aurora: aurora),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  final AuroraColors aurora;
  const _KeyHint({required this.aurora});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: aurora.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: aurora.glassBorder),
      ),
      child: Text(
        'Ctrl K',
        style: TextStyle(color: aurora.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final VoidCallback onTap;

  const _Avatar({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: aurora.accentGradient,
        ),
        child: url == null
            ? const Icon(Icons.person, color: Colors.white, size: 18)
            : ClipOval(
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 18),
                ),
              ),
      ),
    );
  }
}