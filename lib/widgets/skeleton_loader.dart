import 'package:flutter/material.dart';

import '../core/theme/app_theme_extension.dart';

/// Phase 6 Batch 5 — reusable shimmer placeholder. Replaces plain
/// CircularProgressIndicator spinners for artwork/list-item loading
/// states (Premium Visual Foundation — "Skeleton Loading States").
///
/// Single shared shimmer animation via one ticker per widget instance
/// (kept lightweight — no global controller needed, cost is per
/// visible skeleton only).
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final base = aurora.surfaceRaised;
    final highlight = aurora.textSecondary.withOpacity(0.12);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: ShaderMask(
            shaderCallback: (rect) {
              final t = _controller.value;
              return LinearGradient(
                colors: [base, highlight, base],
                stops: const [0.35, 0.5, 0.65],
                begin: Alignment(-1 + t * 3, 0),
                end: Alignment(0 + t * 3, 0),
              ).createShader(rect);
            },
            child: Container(
              width: widget.width,
              height: widget.height,
              color: base,
            ),
          ),
        );
      },
    );
  }
}