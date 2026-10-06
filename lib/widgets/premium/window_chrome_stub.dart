import 'package:flutter/material.dart';

/// Web / Android: the OS or browser already has window controls.
class WindowChrome extends StatelessWidget {
  const WindowChrome({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class MoveWindow extends StatelessWidget {
  const MoveWindow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
