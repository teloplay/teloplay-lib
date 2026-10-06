// lib/core/window/windows_taskbar_service.dart
//
// Windows taskbar hover preview (thumbnail toolbar) — Spotify-style.
//
// Taskbar icon-এ hover করলে যে ছোট preview ওঠে, তার নিচে এই button row
// বসে (screenshot-এ Spotify-এর [+][⏮][▶][⏭]-এর মতো):
//   [+] Add to Library / Favorite, [⏮] Previous, [▶/⏸] Play/Pause, [⏭] Next
//
// Implementation: `windows_taskbar` package (ITaskbarList3::ThumbBarAddButtons
// wrap করে — native C++ লেখা লাগে না, window_manager-এর মতোই Dart-side
// method-channel plugin)।
//
// Design principle (WindowsMediaService-এর মতোই): playback/favorite logic
// এখানে নেই — MusicPlayerRepository + LibraryRepository-ই source of truth,
// এই ক্লাস শুধু repository streams শুনে toolbar refresh করে আর click
// event repository-তে forward করে।

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:windows_taskbar/windows_taskbar.dart';

import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_player_repository.dart';
import '../../models/favorite_model.dart';
import '../../models/now_playing_model.dart';
import '../logging/app_logger.dart';
import '../platform/platform_info.dart';

/// Taskbar thumbnail toolbar-এর lifecycle manager।
///
/// `music_player_provider.dart`-এর Windows branch থেকে
/// `WindowsMediaService`-এর পাশাপাশি init/dispose হয়।
class WindowsTaskbarService {
  final MusicPlayerRepository _playerRepo;
  final LibraryRepository _libraryRepo;

  StreamSubscription<NowPlaying>? _nowPlayingSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<List<FavoriteSong>>? _favoritesSub;

  /// Toolbar click callback থেকে repository call — re-entrancy guard।
  bool _refreshing = false;
  bool _initialized = false;

  WindowsTaskbarService(this._playerRepo, this._libraryRepo);

  /// Toolbar প্রথমবার বসানো + repository streams wire করা।
  /// Idempotent — একাধিকবার কল নিরাপদ।
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb || !PlatformInfo.isWindows) return;

    try {
      // Preview window-এর উপরে tooltip (app নাম)।
      await WindowsTaskbar.setThumbnailTooltip('TeloPlay');
      await _refreshToolbar();

      _nowPlayingSub =
          _playerRepo.nowPlayingStream.listen((_) => _refreshToolbar());
      _playingSub =
          _playerRepo.playingStream.listen((_) => _refreshToolbar());

      // Favorite toggle হলে [+] button-এর enabled/disabled state বদলাবে —
      // favorites stream বদলালেও toolbar refresh করা হচ্ছে।
      //
      // ⚠️ Guard — app start-এ Anonymous Auth এখনো ready না হলে
      // watchFavorites() StateError throw করে (LibraryRepository._userId)।
      // Toolbar-এর জন্য এটা fatal না — try/catch আলাদা রাখা হলো যাতে
      // playback buttons তবুও বসে; auth ready হলে প্রথম favorite toggle /
      // app restart-এ stream wire হবে।
      try {
        _favoritesSub =
            _libraryRepo.watchFavorites().listen((_) => _refreshToolbar());
      } catch (e) {
        AppLogger.error(
          'WindowsTaskbarService favorites stream unavailable (non-fatal)',
          e,
        );
      }

      _initialized = true;
      AppLogger.playback('WindowsTaskbarService initialized (thumbnail toolbar)');
    } catch (e) {
      // Toolbar বসানো ব্যর্থ হলে (পুরনো Windows) app crash করা উচিত না —
      // SMTC flyout/player UI স্বাভাবিক থাকবে।
      AppLogger.error('WindowsTaskbarService init failed (non-fatal)', e);
    }
  }

  /// বর্তমান playback/favorite state অনুযায়ী 4টা button পুনর্নির্মাণ।
  Future<void> _refreshToolbar() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final nowPlaying = _playerRepo.nowPlaying;
      final track = nowPlaying.track;
      final isPlaying = nowPlaying.status == NowPlayingStatus.playing;

      // কোনো track না থাকলে সব button disabled (Spotify-ও খালি অবস্থায়
      // এমনই করে) — click করলে কিছু হবে না।
      final hasTrack = track != null;

      // ⚠️ Guard — auth ready না হলে isFavorite() StateError দেয়; তখন
      // [+] button enabled-ই থাকবে (click করলে addFavorite-ও একইভাবে
      // fail করে non-fatal log হবে)।
      bool isFav = false;
      if (hasTrack) {
        try {
          isFav = await _libraryRepo.isFavorite(track.videoId);
        } catch (_) {
          isFav = false;
        }
      }

      await WindowsTaskbar.setThumbnailToolbar([
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/taskbar/add.ico'),
          isFav ? 'Remove from Liked Songs' : 'Add to Liked Songs',
          () => _onAddFavorite(),
          // pub.dev README অনুযায়ী mode flag OR করা যায় (|) —
          // dismissionClick মানে click-এ preview dismiss হবে না (Spotify-এর
          // মতো toolbar-এই থাকবে)।
          mode: (!hasTrack || isFav)
              ? ThumbnailToolbarButtonMode.disabled |
                  ThumbnailToolbarButtonMode.dismissionClick
              : ThumbnailToolbarButtonMode.dismissionClick,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/taskbar/prev.ico'),
          'Previous',
          () => _playerRepo.previous(),
          mode: hasTrack
              ? ThumbnailToolbarButtonMode.dismissionClick
              : ThumbnailToolbarButtonMode.disabled |
                  ThumbnailToolbarButtonMode.dismissionClick,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon(
            isPlaying ? 'assets/taskbar/pause.ico' : 'assets/taskbar/play.ico',
          ),
          isPlaying ? 'Pause' : 'Play',
          () => _playerRepo.togglePause(),
          mode: hasTrack
              ? ThumbnailToolbarButtonMode.dismissionClick
              : ThumbnailToolbarButtonMode.disabled |
                  ThumbnailToolbarButtonMode.dismissionClick,
        ),
        ThumbnailToolbarButton(
          ThumbnailToolbarAssetIcon('assets/taskbar/next.ico'),
          'Next',
          () => _playerRepo.next(),
          mode: hasTrack
              ? ThumbnailToolbarButtonMode.dismissionClick
              : ThumbnailToolbarButtonMode.disabled |
                  ThumbnailToolbarButtonMode.dismissionClick,
        ),
      ]);
    } catch (e) {
      AppLogger.error('WindowsTaskbarService refresh failed (non-fatal)', e);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _onAddFavorite() async {
    final track = _playerRepo.nowPlaying.track;
    if (track == null) return;
    try {
      await _libraryRepo.addFavorite(
        songId: track.videoId,
        title: track.title,
        author: track.author,
        thumbnail: track.thumbnail,
        durationSeconds: track.duration?.inSeconds,
      );
      // addFavorite() favorites stream-এ emit করবে → listener থেকে
      // _refreshToolbar() আবার চলবে → [+] disabled হয়ে যাবে।
    } catch (e) {
      AppLogger.error('WindowsTaskbarService addFavorite failed', e);
    }
  }

  Future<void> dispose() async {
    await _nowPlayingSub?.cancel();
    await _playingSub?.cancel();
    await _favoritesSub?.cancel();
    try {
      await WindowsTaskbar.resetThumbnailToolbar();
    } catch (_) {
      // shutdown path — ignore.
    }
  }
}
