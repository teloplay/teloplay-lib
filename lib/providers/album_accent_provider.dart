import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/color_extractor.dart';

/// ⚠️ Phase 6 (Smart Player UI & Theme Polish) — runtime album accent
/// state। এই provider নিজে কোনো extraction করে না — শুধু extracted
/// রং (ইতিমধ্যে `ColorExtractor` দিয়ে curated-mapped ও contrast-safe)
/// ধরে রাখে, যাতে `AuroraColors.albumAccent` এবং `GlassContainer`-এর
/// `glowColor` একই মান পড়তে পারে।
///
/// Flow (single source of truth, দেখো cached_artwork.dart patch):
///   CachedArtwork.onLocalPathResolved(path)
///     → notifier.updateFromArtwork(trackId, path)
///     → ColorExtractor.extractForTrack() (per-trackId cache-হিট হলে
///       তৎক্ষণাৎ, না হলে PaletteGenerator চালিয়ে)
///     → state আপডেট → UI rebuild (glow/progress-bar/mini-player accent)
///
/// ⚠️ Race-guard: track দ্রুত বদলে গেলে (skip/skip/skip) পুরনো
/// extraction শেষ হয়ে দেরিতে ফিরে এসে নতুন track-এর accent
/// overwrite করতে পারে — তাই `_latestRequestId` দিয়ে শুধু সর্বশেষ
/// request-এর ফলাফলই state-এ লেখা হয়, বাকিগুলো silently discard হয়।
class AlbumAccentNotifier extends Notifier<AlbumAccentState> {
  int _latestRequestId = 0;

  @override
  AlbumAccentState build() => const AlbumAccentState();

  Future<void> updateFromArtwork(String trackId, String localPath) async {
    final requestId = ++_latestRequestId;

    // ⚠️ Track বদলানোর সাথে সাথে সাথে সাথে আগের accent সরিয়ে না ফেলে
    // পুরনোটাই সাময়িকভাবে রাখা হচ্ছে (state.trackId আপডেট করে দেওয়া
    // হচ্ছে যাতে caller বুঝতে পারে extraction চলছে) — হঠাৎ glow উধাও
    // হয়ে আবার দেখা দেওয়ার flicker এড়াতে। নতুন রং রেডি হলে replace হবে।
    state = state.copyWith(trackId: trackId, isExtracting: true);

    final color = await ColorExtractor.extractForTrack(
      trackId: trackId,
      localImagePath: localPath,
    );

    // ⚠️ এই মুহূর্তে যদি অন্য কোনো (নতুন) request শুরু হয়ে গিয়ে থাকে,
    // এই পুরনো ফলাফল ফেলে দেওয়া হচ্ছে।
    if (requestId != _latestRequestId) return;

    state = state.copyWith(
      trackId: trackId,
      accentColor: color,
      isExtracting: false,
    );
  }

  /// Track শেষ হয়ে গেলে/queue খালি হলে accent clear করার জন্য।
  void clear() {
    _latestRequestId++;
    state = const AlbumAccentState();
  }
}

class AlbumAccentState {
  final String? trackId;
  final Color? accentColor;
  final bool isExtracting;

  const AlbumAccentState({
    this.trackId,
    this.accentColor,
    this.isExtracting = false,
  });

  AlbumAccentState copyWith({
    String? trackId,
    Color? accentColor,
    bool? isExtracting,
  }) {
    return AlbumAccentState(
      trackId: trackId ?? this.trackId,
      accentColor: accentColor ?? this.accentColor,
      isExtracting: isExtracting ?? this.isExtracting,
    );
  }
}

final albumAccentProvider =
    NotifierProvider<AlbumAccentNotifier, AlbumAccentState>(
  AlbumAccentNotifier.new,
);