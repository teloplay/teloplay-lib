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
