import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../widgets/cached_artwork.dart';
import '../home_providers.dart';

/// Phase 6.5 UI-Batch 3a — Premium immersive Hero card.
///
/// Full rewrite of the Batch-2 version (GlassContainer + small
/// thumbnail row) per the "premium personal dashboard" direction:
/// full-bleed blurred artwork background, dynamic-tint scrim, large
/// typography, AccentButton-style resume pill. GlassContainer dropped
/// here — Hero lives in the Home/Discovery surface, not the
/// Player-context, so per the locked Glass-vs-PremiumCard rule this
/// should NOT be heavy glass.
///
/// No real album-color extraction pipeline yet (Phase 6 future
/// addition) — tint is a deterministic curated-accent pick seeded by
/// songId, same approach as [GradientMeshArt] and the header backdrop,
/// so the whole screen's accent stays visually consistent per track.
class FeaturedHeroCard extends StatelessWidget {
  const FeaturedHeroCard({required this.info, super.key});

  final ContinueListeningInfo info;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final tint = AppColors.curatedAccents[info.songId.hashCode.abs() % AppColors.curatedAccents.length];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () => context.push('/player'),
          child: Container(
            height: 178,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  color: aurora.shadowColor.withOpacity(0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Blurred full-bleed backdrop artwork.
                CachedArtwork(
                  imageUrl: info.thumbnail,
                  cacheKey: '${info.songId}_hero_bg',
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                  fit: BoxFit.cover,
                  placeholderIcon: Icons.music_note,
                ),
                // Dynamic tint wash.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tint.withOpacity(0.55),
                        AppColors.darkBackground.withOpacity(0.65),
                      ],
                    ),
                  ),
                ),
                // Legibility scrim — locked cardScrimGradient token.
                DecoratedBox(decoration: BoxDecoration(gradient: aurora.cardScrimGradient)),
                // Content.
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: aurora.accentGradient,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CONTINUE LISTENING',
                          style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _ResumePill(onTap: () => context.push('/player')),
                          const SizedBox(width: 8),
                          _IconGhostButton(icon: Icons.queue_music_rounded, onTap: () => context.push('/player')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResumePill extends StatefulWidget {
  const _ResumePill({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ResumePill> createState() => _ResumePillState();
}

class _ResumePillState extends State<_ResumePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.identity()..scale(_hovered ? 1.04 : 1.0),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(color: Colors.white.withOpacity(_hovered ? 0.3 : 0.15), blurRadius: 18, spreadRadius: -2),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
              SizedBox(width: 6),
              Text('Resume', style: TextStyle(color: Colors.black, fontSize: 13.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconGhostButton extends StatefulWidget {
  const _IconGhostButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconGhostButton> createState() => _IconGhostButtonState();
}

class _IconGhostButtonState extends State<_IconGhostButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(_hovered ? 0.22 : 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.25)),
          ),
          child: Icon(widget.icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}