import 'package:flutter/material.dart';

/// Animated aurora glow effect behind album artwork.
/// Used exclusively in Now Playing screen.
class AuroraGlow extends StatefulWidget {
  final Color accentColor;
  final Widget child;
  final double intensity;
  final double blurRadius;

  const AuroraGlow({
    super.key,
    required this.accentColor,
    required this.child,
    this.intensity = 0.6,
    this.blurRadius = 60,
  });

  @override
  State<AuroraGlow> createState() => _AuroraGlowState();
}

class _AuroraGlowState extends State<AuroraGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(
      begin: widget.intensity * 0.3,
      end: widget.intensity * 0.5,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glow layer
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.blurRadius * 3,
                  height: widget.blurRadius * 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.accentColor.withOpacity(_opacityAnimation.value),
                        widget.accentColor.withOpacity(0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              );
            },
          ),
          // Child (album artwork)
          widget.child,
        ],
      ),
    );
  }
}