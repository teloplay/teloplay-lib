import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../data/repositories/recommendation_repository.dart';
import '../../models/statistics_model.dart';
import '../../providers/smart_queue_provider.dart';
import '../../widgets/glass_container.dart';

class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;
    final repo = ref.watch(recommendationRepositoryProvider);

    return Scaffold(
      backgroundColor: aurora.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: aurora.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Listening Statistics',
          style: TextStyle(
            color: aurora.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: FutureBuilder<UserListeningStats>(
        future: repo.getUserStats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: accent),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                'No listening statistics available yet.\nStart playing songs to see insights!',
                textAlign: TextAlign.center,
                style: TextStyle(color: aurora.textSecondary),
              ),
            );
          }

          final stats = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              _buildStreakCard(context, stats.streak),
              const SizedBox(height: 16),
              // P1-P — maturity card owns its own future (separate
              // lightweight aggregate; keeps the existing stats future
              // untouched).
              _MaturityCard(repo: repo),
              const SizedBox(height: 16),
              _buildPersonalityCard(context, stats.primaryPersonality, stats.secondaryPersonalities),
              const SizedBox(height: 16),
              _buildOverviewCard(context, stats),
              const SizedBox(height: 16),
              _buildTopGenresCard(context, stats.topGenres),
              const SizedBox(height: 16),
              _buildTopArtistsCard(context, stats.topArtists),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, StreakInfo streak) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      glowColor: accent,
      glowOpacity: 0.15,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_fire_department_rounded, color: accent, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${streak.currentStreak} Day Streak',
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  streak.isActiveToday
                      ? 'You have listened to music today! Keep it going.'
                      : 'Listen to a song today to maintain your streak!',
                  style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalityCard(
    BuildContext context,
    ListeningPersonalityType primary,
    List<ListeningPersonalityType> secondary,
  ) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MUSIC DNA',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(primary.icon, color: accent, size: 28),
              const SizedBox(width: 12),
              Text(
                primary.label,
                style: TextStyle(
                  color: aurora.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            primary.description,
            style: TextStyle(color: aurora.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard(BuildContext context, UserListeningStats stats) {
    final aurora = context.aurora;
    final minutes = stats.totalListeningTime.inMinutes;
    final hours = (minutes / 60).toStringAsFixed(1);

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn(context, 'Total Plays', '${stats.totalTracksPlayed}'),
          Container(width: 1, height: 40, color: aurora.surface),
          _statColumn(context, 'Hours Listened', '$hours hrs'),
        ],
      ),
    );
  }

  Widget _statColumn(BuildContext context, String label, String value) {
    final aurora = context.aurora;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: aurora.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: aurora.textSecondary, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildTopGenresCard(BuildContext context, List<GenreStat> genres) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    if (genres.isEmpty) return const SizedBox.shrink();

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Genres',
            style: TextStyle(
              color: aurora.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          ...genres.map((g) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        g.genre,
                        style: TextStyle(color: aurora.textPrimary, fontSize: 13),
                      ),
                      Text(
                        '${(g.percentage * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: g.percentage,
                      backgroundColor: aurora.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                      minHeight: 5,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopArtistsCard(BuildContext context, List<ArtistStat> artists) {
    final aurora = context.aurora;

    if (artists.isEmpty) return const SizedBox.shrink();

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Artists',
            style: TextStyle(
              color: aurora.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...artists.take(5).map((a) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: aurora.surface,
                child: Icon(Icons.person, color: aurora.textSecondary),
              ),
              title: Text(
                a.artistName,
                style: TextStyle(color: aurora.textPrimary, fontSize: 14),
              ),
              subtitle: Text(
                '${a.playCount} plays',
                style: TextStyle(color: aurora.textSecondary, fontSize: 12),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// P1-P — listening-maturity card. Internal listening-behavior metric
/// only (framed as activity, never as a scientific/personal assessment).
/// Shows the deterministic score plus its exact component breakdown, or
/// a "not enough data" state when the sample is too small.
class _MaturityCard extends StatelessWidget {
  const _MaturityCard({required this.repo});

  final RecommendationRepository repo;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    return FutureBuilder<ListeningMaturity>(
      future: repo.getListeningMaturity(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return GlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(16),
            child: Center(
              child: CircularProgressIndicator(color: accent),
            ),
          );
        }
        final maturity = snapshot.data;
        if (maturity == null || !maturity.hasEnoughData) {
          return GlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LISTENING ACTIVITY',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Not enough listening yet',
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Play a few songs and this activity summary will appear.',
                  style:
                      TextStyle(color: aurora.textSecondary, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return GlassContainer(
          padding: const EdgeInsets.all(20),
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LISTENING ACTIVITY',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${maturity.score}',
                    style: TextStyle(
                      color: aurora.textPrimary,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '/ 100',
                    style: TextStyle(
                        color: aurora.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      maturity.bandLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Based on ${maturity.windowPlays} plays in the last 30 days.',
                style: TextStyle(color: aurora.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _MaturityBar(
                label: 'Completion',
                points: maturity.completionPoints,
                max: 40,
                accent: accent,
              ),
              _MaturityBar(
                label: 'Artist diversity',
                points: maturity.diversityPoints,
                max: 25,
                accent: accent,
              ),
              _MaturityBar(
                label: 'Favorites',
                points: maturity.favoritesPoints,
                max: 20,
                accent: accent,
              ),
              _MaturityBar(
                label: 'Consistency',
                points: maturity.consistencyPoints,
                max: 15,
                accent: accent,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MaturityBar extends StatelessWidget {
  const _MaturityBar({
    required this.label,
    required this.points,
    required this.max,
    required this.accent,
  });

  final String label;
  final int points;
  final int max;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(color: aurora.textPrimary, fontSize: 13),
              ),
              Text(
                '$points / $max',
                style: TextStyle(color: aurora.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max == 0 ? 0 : (points / max).clamp(0.0, 1.0),
              backgroundColor: aurora.surface,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}
