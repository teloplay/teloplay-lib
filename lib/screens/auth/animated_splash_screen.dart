import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

// 8-step splash: 1 glow, 2 orbit, 3 logo, 4 pulse, 5 brand, 6 tagline+wave, 7 loading, 8 ready.
class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key, this.nextLocation = '/welcome'});
  final String nextLocation;
  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _done = false;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_done) {
          _done = true;
          if (mounted) context.go(widget.nextLocation);
        }
      });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _ph(double s, double e) => CurvedAnimation(
      parent: _c, curve: Interval(s, e, curve: Curves.easeOutCubic)).value;
  double _lin(double s, double e) => CurvedAnimation(
      parent: _c, curve: Interval(s, e, curve: Curves.linear)).value;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final glow = _ph(0.0, 0.12);
          final orbit = _ph(0.10, 0.29);
          final logo = _ph(0.29, 0.43);
          final pulse = _ph(0.43, 0.52);
          final brand = _ph(0.52, 0.62);
          final tag = _ph(0.62, 0.71);
          final load = _lin(0.71, 0.90);
          final ready = _ph(0.90, 1.0);
          return Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _WavePainter(
                    p: (0.25 + 0.75 * tag).clamp(0.0, 1.0), t: _c.value),
              ),
            ),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 250, height: 220,
                  child: Stack(alignment: Alignment.center, children: [
                    Opacity(
                      opacity: glow.clamp(0.0, 1.0),
                      child: Container(
                        width: 30 + 60 * glow, height: 30 + 60 * glow,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.8), blurRadius: 30 * glow + 8, spreadRadius: 6 * glow),
                            BoxShadow(color: AppColors.secondary.withValues(alpha: 0.5), blurRadius: 60 * glow + 12, spreadRadius: 10 * glow),
                          ]),
                      ),
                    ),
                    if (orbit > 0)
                      Opacity(
                        opacity: orbit.clamp(0.0, 1.0),
                        child: CustomPaint(
                          size: const Size(250, 220),
                          painter: _OrbitPainter(p: orbit, rot: _c.value * 2 * math.pi),
                        ),
                      ),
                    if (logo > 0)
                      Transform.scale(
                        scale: logo.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(boxShadow: [
                            BoxShadow(color: AppColors.primary.withValues(alpha: 0.35 + 0.35 * pulse), blurRadius: 30 + 30 * pulse, spreadRadius: 4 + 8 * pulse),
                          ]),
                          child: const _Logo(size: 110),
                        ),
                      ),
                  ]),
                ),
                if (brand > 0)
                  Opacity(
                    opacity: brand.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - brand)),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                          children: [
                            const TextSpan(text: 'Telo', style: TextStyle(color: Colors.white)),
                            TextSpan(
                              text: 'Play',
                              style: TextStyle(
                                foreground: Paint()
                                  ..shader = AppColors.accentGradient.createShader(const Rect.fromLTWH(0, 0, 120, 40)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (tag > 0)
                  Opacity(
                    opacity: tag.clamp(0.0, 1.0),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Play Beyond Limits',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, letterSpacing: 1.6, fontWeight: FontWeight.w500)),
                    ),
                  ),
                const SizedBox(height: 30),
                if (tag > 0.5)
                  SizedBox(
                    width: 180,
                    child: Column(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          height: 4,
                          color: Colors.white.withValues(alpha: 0.10),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: load.clamp(0.0, 1.0),
                            child: Container(decoration: const BoxDecoration(gradient: AppColors.accentGradient)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(ready > 0.3 ? "And you're in! 🎵" : 'Loading...',
                        style: const TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                    ]),
                  ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}


class _Logo extends StatelessWidget {
  const _Logo({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) {
    // আসল logo.png — transparent bg, orbit+waveform সহ (পাঠানো ছবিটাই)
    return Image.asset('assets/icon.png', width: size * 1.9,
      height: size * 1.9, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.play_circle_fill_rounded,
        size: size, color: AppColors.primary));
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.p, required this.rot});
  final double p; final double rot;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rx = size.width * 0.42 * p, ry = size.height * 0.22 * p;
    for (var i = 0; i < 2; i++) {
      final paint = Paint()..style = PaintingStyle.stroke
        ..strokeWidth = i == 0 ? 2.2 : 1.4
        ..shader = const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary, Color(0xFF38BDF8)])
          .createShader(Rect.fromCenter(center: c, width: size.width, height: size.height));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(rot * (i == 0 ? 1 : -0.7) + i * 0.6);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2), paint);
      final t = rot * (i == 0 ? 1 : -1) + i;
      canvas.drawCircle(Offset(math.cos(t) * rx, math.sin(t) * ry), 3.2,
        Paint()..color = i == 0 ? AppColors.secondary : const Color(0xFF38BDF8));
      canvas.restore();
    }
    final star = Paint()..color = Colors.white.withValues(alpha: 0.7);
    final rnd = math.Random(7);
    for (var i = 0; i < 14 * p; i++) {
      canvas.drawCircle(Offset(rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height), 1.1, star);
    }
  }
  @override
  bool shouldRepaint(covariant _OrbitPainter o) => o.p != p || o.rot != rot;
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.p, required this.t});
  final double p; final double t;
  @override
  void paint(Canvas canvas, Size size) {
    void wave(double base, double amp, Color col, double sp) {
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += 6) {
        path.lineTo(x, size.height * base +
          math.sin(x / 90 + t * sp) * amp * p +
          math.sin(x / 37 - t * sp * 0.7) * amp * 0.4 * p);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()..shader = LinearGradient(
        colors: [col.withValues(alpha: 0.55), col.withValues(alpha: 0.05)],
        begin: Alignment.bottomCenter, end: Alignment.topCenter)
        .createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    }
    wave(0.86, 26, AppColors.primary, 2.2);
    wave(0.92, 20, AppColors.secondary, 1.6);
  }
  @override
  bool shouldRepaint(covariant _WavePainter o) => o.p != p || o.t != t;
}
