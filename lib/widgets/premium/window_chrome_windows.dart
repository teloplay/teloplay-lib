import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/app_theme_extension.dart';

/// Windows only. Hidden title bar means these buttons are the window.
class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _WindowBtn(icon: Icons.remove_rounded, onTap: windowManager.minimize),
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
        _WindowBtn(
          icon: Icons.close_rounded,
          isCloseButton: true,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class MoveWindow extends StatelessWidget {
  const MoveWindow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DragToMoveArea(child: child);
}

class _WindowBtn extends StatefulWidget {
  const _WindowBtn({
    required this.icon,
    required this.onTap,
    this.isCloseButton = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isCloseButton;

  @override
  State<_WindowBtn> createState() => _WindowBtnState();
}

class _WindowBtnState extends State<_WindowBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final bgColor = _hovered
        ? (widget.isCloseButton
            ? const Color(0xFFE81123)
            : Colors.white.withOpacity(0.1))
        : Colors.transparent;
    final iconColor = _hovered && widget.isCloseButton
        ? Colors.white
        : aurora.textSecondary;

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
