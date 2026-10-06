import 'package:flutter/material.dart';

/// Music DNA / Listening Personality types derived from behaviour tracking.
enum ListeningPersonalityType {
  nightOwl('Night Owl', 'Listens mostly late at night', Icons.nightlight_round),
  rockLover('Rock Lover', 'Drawn to powerful guitars and drums', Icons.electric_bolt_rounded),
  chillListener('Chill Listener', 'Prefers calm and relaxing vibes', Icons.spa_rounded),
  highEnergy('High Energy', 'Loves upbeat, fast-paced rhythms', Icons.local_fire_department_rounded),
  weekendListener('Weekend Listener', 'Peaks during Saturdays and Sundays', Icons.weekend_rounded),
  bassLover('Bass Lover', 'Enjoys deep bass and electronic beats', Icons.speaker_group_rounded),
  explorer('Music Explorer', 'Always discovering diverse artists', Icons.explore_rounded),
  devotedFan('Devoted Fan', 'Deeply loops favorite artists', Icons.favorite_rounded);

  final String label;
  final String description;
  final IconData icon;

  const ListeningPersonalityType(this.label, this.description, this.icon);
}

/// Streak summary tracking consecutive days of listening.
class StreakInfo {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActiveDate;
  final bool isActiveToday;

  const StreakInfo({
    required this.currentStreak,
    required this.longestStreak,
    this.lastActiveDate,
    required this.isActiveToday,
  });

  static const empty = StreakInfo(
    currentStreak: 0,
    longestStreak: 0,
    isActiveToday: false,
  );
}

/// Aggregated statistics for an individual genre.
class GenreStat {
  final String genre;
  final int playCount;
  final Duration totalDuration;
  final double percentage;

  const GenreStat({
    required this.genre,
    required this.playCount,
    required this.totalDuration,
    required this.percentage,
  });
}

/// Aggregated statistics for an individual artist.
class ArtistStat {
  final String artistName;
  final String? artistId;
  final String? thumbnail;
  final int playCount;
  final Duration totalDuration;

  const ArtistStat({
    required this.artistName,
    this.artistId,
    this.thumbnail,
    required this.playCount,
    required this.totalDuration,
  });
}

/// Summary of listening volume and behavior across a time window.
class ListeningPeriodSummary {
  final DateTime startDate;
  final DateTime endDate;
  final int totalPlays;
  final int totalSkips;
  final Duration totalListeningTime;
  final List<ArtistStat> topArtists;
  final List<GenreStat> topGenres;

  const ListeningPeriodSummary({
    required this.startDate,
    required this.endDate,
    required this.totalPlays,
    required this.totalSkips,
    required this.totalListeningTime,
    required this.topArtists,
    required this.topGenres,
  });

  double get skipRate => totalPlays == 0 ? 0.0 : (totalSkips / totalPlays).clamp(0.0, 1.0);
  double get completionRate => 1.0 - skipRate;
}

/// Full statistics model for the user's music journey.
class UserListeningStats {
  final StreakInfo streak;
  final ListeningPersonalityType primaryPersonality;
  final List<ListeningPersonalityType> secondaryPersonalities;
  final int totalTracksPlayed;
  final Duration totalListeningTime;
  final List<GenreStat> topGenres;
  final List<ArtistStat> topArtists;
  final ListeningPeriodSummary weeklySummary;
  final ListeningPeriodSummary monthlySummary;

  const UserListeningStats({
    required this.streak,
    required this.primaryPersonality,
    required this.secondaryPersonalities,
    required this.totalTracksPlayed,
    required this.totalListeningTime,
    required this.topGenres,
    required this.topArtists,
    required this.weeklySummary,
    required this.monthlySummary,
  });
}

/// P1-P — internal listening-behavior metric. NOT a scientific,
/// psychological, or personality assessment: a deterministic 0–100
/// composite over signals the app already tracks (completion discipline,
/// artist diversity, favorites engagement, listening consistency).
/// Computed on demand from existing tables; no new events, no new tables,
/// no AI. Component points are exposed so the UI can show exactly what
/// the score is made of.
class ListeningMaturity {
  /// Minimum lifetime plays before a score is shown at all.
  static const int minPlaysForScore = 5;

  final int score;
  final int completionPoints;
  final int diversityPoints;
  final int favoritesPoints;
  final int consistencyPoints;
  final int windowPlays;
  final bool hasEnoughData;

  const ListeningMaturity({
    required this.score,
    required this.completionPoints,
    required this.diversityPoints,
    required this.favoritesPoints,
    required this.consistencyPoints,
    required this.windowPlays,
    required this.hasEnoughData,
  });

  static const empty = ListeningMaturity(
    score: 0,
    completionPoints: 0,
    diversityPoints: 0,
    favoritesPoints: 0,
    consistencyPoints: 0,
    windowPlays: 0,
    hasEnoughData: false,
  );

  /// Neutral activity wording — describes breadth of listening behavior,
  /// never a personal trait.
  String get bandLabel {
    if (score < 25) return 'Getting Started';
    if (score < 50) return 'Finding Rhythm';
    if (score < 75) return 'Engaged Listener';
    return 'Deep Listener';
  }
}

/// P1-P — pure, deterministic maturity calculation (unit-tested).
///
/// - [windowPlays]/[windowSkips]: plays and skips in the trailing 30-day
///   window (completion discipline, max 40 pts).
/// - [lifetimePlays]/[distinctArtists]: breadth — one distinct artist per
///   five plays earns full marks (max 25 pts).
/// - [favoritesCount]: explicit likes per ten lifetime plays (max 20 pts).
/// - [currentStreak]: consecutive-day consistency, full marks at 7 days
///   (max 15 pts).
ListeningMaturity computeListeningMaturity({
  required int windowPlays,
  required int windowSkips,
  required int lifetimePlays,
  required int distinctArtists,
  required int favoritesCount,
  required int currentStreak,
}) {
  if (lifetimePlays < ListeningMaturity.minPlaysForScore) {
    return ListeningMaturity.empty;
  }

  final completionRate = windowPlays <= 0
      ? 0.0
      : (1.0 - (windowSkips / windowPlays)).clamp(0.0, 1.0);
  final completionPoints = (completionRate * 40).round();

  final diversityRatio =
      (distinctArtists / (lifetimePlays / 5).clamp(1.0, double.infinity))
          .clamp(0.0, 1.0);
  final diversityPoints = (diversityRatio * 25).round();

  final favoritesRatio =
      (favoritesCount / (lifetimePlays / 10).clamp(1.0, double.infinity))
          .clamp(0.0, 1.0);
  final favoritesPoints = (favoritesRatio * 20).round();

  final consistencyPoints =
      ((currentStreak / 7).clamp(0.0, 1.0) * 15).round();

  return ListeningMaturity(
    score: (completionPoints +
            diversityPoints +
            favoritesPoints +
            consistencyPoints)
        .clamp(0, 100),
    completionPoints: completionPoints,
    diversityPoints: diversityPoints,
    favoritesPoints: favoritesPoints,
    consistencyPoints: consistencyPoints,
    windowPlays: windowPlays,
    hasEnoughData: true,
  );
}
