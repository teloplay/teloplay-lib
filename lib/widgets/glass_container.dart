import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_theme_extension.dart';

/// ⚠️ Phase 6 — "Midnight Aurora" signature element: frosted glass panel
/// with an optional aurora-glow bleed behind it, driven by the current
/// album accent color (`AuroraColors.effectiveAccent`).
///
/// এটাই এই ডিজাইনের একমাত্র জায়গা যেখানে boldness খরচ করা হচ্ছে —
/// বাকি সব UI quiet/disciplined থাকে। তাই এই widget বারবার আলাদা
/// আলাদা visual variation নিয়ে ব্যবহার করা হবে না — glow intensity/blur
/// পরিমিতভাবেই ব্যবহার করা উচিত (মূলত mini-player + full player card-এ)।
///
/// [glowColor] না দিলে glow সম্পূর্ণ বন্ধ থাকে (শুধু plain glass, কোনো
/// রঙিন bleed ছাড়া) — যেসব জায়গায় album-accent প্রাসঙ্গিক না (যেমন
/// Settings card) সেখানে এভাবেই ব্যবহার করা উচিত।
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.blurSigma = 24,
    this.glowColor,
    this.glowOpacity = 0.35,
    this.padding,
    this.margin,
    this.width,
    this.height,

    /// ⚠️ Low RAM mode-এ caller blur বন্ধ করতে চাইলে false পাঠাবে —
    /// `BackdropFilter` GPU/CPU-cost bearing, তাই এই flag দিয়ে ছাড়া
    /// যায় (plain semi-transparent surface-এ fallback করে, glow তবু
    /// থাকে কারণ সেটা সস্তা — শুধু gradient/blur ব্যয়বহুল অংশ বাদ যায়)।
    this.enableBlur = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color? glowColor;
  final double glowOpacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool enableBlur;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    Widget panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: enableBlur
            ? ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma)
            : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: aurora.glassTint.withOpacity(enableBlur ? 0.06 : 0.14),
            borderRadius: borderRadius,
            border: Border.all(color: aurora.glassBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (glowColor != null) {
      panel = Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: glowColor!.withOpacity(glowOpacity),
              blurRadius: 40,
              spreadRadius: -8,
            ),
          ],
        ),
        child: panel,
      );
    } else if (margin != null) {
      panel = Container(margin: margin, child: panel);
    }

    return panel;
  }
}