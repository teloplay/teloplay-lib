import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../widgets/cached_artwork.dart';

/// Phase 6.5 UI-Batch 4 — Mobile-only swipeable Hero carousel।
///
/// ৩টা সম্ভাব্য card: Continue Listening / Top Favorite / Most Played।
/// প্রতিটা card data না থাকলে সেটা list থেকেই বাদ যায় (empty card না
/// দেখিয়ে) — caller ([items]) responsible filtered list পাঠানোর জন্য।
/// কোনো card না থাকলে caller পুরো carousel-ই hide করবে (SizedBox.shrink)।
///
/// Desktop-এর FeaturedHeroCard-এর visual language (blurred backdrop +
/// curated-accent tint + cardScrimGradient) এখানেই reuse করা হয়েছে,
/// শুধু presentation multi-card swipeable — shared data source নীতি
/// অক্ষত রাখতে item shape এখানে generic (`HeroCarouselItem`), caller
/// (HomeScreen) বিভিন্ন provider থেকে map করে দেয়।
class HeroCarouselItem {
  final String id;
  final String label; // e.g. "CONTINUE LISTENING", "TOP FAVORITE", "MOST PLAYED"
  final String title;
  final String subtitle;
  final String thumbnail;
  final VoidCallback onTap;
  final VoidCallback onAction;
  final IconData actionIcon;

  const HeroCarouselItem({
    required this.id,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.onTap,
    required this.onAction,
    this.actionIcon = Icons.play_arrow_rounded,
  });
}

class MobileHeroCarousel extends StatefulWidget {
  const MobileHeroCarousel({required this.items, super.key});

  final List<HeroCarouselItem> items;

  @override
  State<MobileHeroCarousel> createState() => _MobileHeroCarouselState();
}

class _MobileHeroCarouselState extends State<MobileHeroCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 168,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _HeroCard(item: item),
              );
            },
          ),
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? context.aurora.primary : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.item});
  final HeroCarouselItem item;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final tint = AppColors.curatedAccents[item.id.hashCode.abs() % AppColors.curatedAccents.length];

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: aurora.shadowColor.withOpacity(0.3),
                blurRadius: 22,
                offset: const Offset(0, 10),
                spreadRadius: -6,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedArtwork(
                imageUrl: item.thumbnail,
                cacheKey: '${item.id}_hero_bg',
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.zero,
                fit: BoxFit.cover,
                placeholderIcon: Icons.music_note,
              ),
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
              DecoratedBox(decoration: BoxDecoration(gradient: aurora.cardScrimGradient)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: aurora.accentGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.label,
                        style: const TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                    ),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11.5),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: item.onAction,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: Icon(item.actionIcon, color: Colors.black, size: 19),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}