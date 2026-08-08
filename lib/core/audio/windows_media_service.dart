import 'dart:async';

import 'package:smtc_windows/smtc_windows.dart';

import '../logging/app_logger.dart';
import '../playback/playback_engine.dart';
import '../../data/repositories/music_player_repository.dart';
import '../../models/now_playing_model.dart';

/// smtc_windows-এর সাথে MusicPlayerRepository-কে যুক্ত করার wrapper।
///
/// এটা TeloPlayAudioHandler (Android)-এর Windows counterpart — একই
/// design principle: playback logic এখানে move করা হয়নি,
/// MusicPlayerRepository একমাত্র source of truth থেকে যায়। এই ক্লাস
/// শুধু repository ↔ SMTC এর মধ্যে event bridge করে।
///
///   OS (media flyout/keyboard media key/Bluetooth headset button)
///        │  buttonPressStream (play/pause/next/prev)
///        ▼
///   WindowsMediaService  ──────────────►  MusicPlayerRepository
///        ▲                                        │
///        │  nowPlayingStream/positionStream শুনে   │
///        └────────── updateMetadata/updateTimeline ┘
///
/// Queue এখনো sync করা হয়নি (audio_service handler-এর মতোই scope-এ
/// আপাতত শুধু current track) — future-এ queue যোগ করতে এই ক্লাসের
/// বাকি অংশ অপরিবর্তিত রেখে শুধু নতুন মেথড যোগ করলেই হবে।
class WindowsMediaService {
  final MusicPlayerRepository _repo;

  SMTCWindows? _smtc;
  StreamSubscription<PressedButton>? _buttonSub;
  StreamSubscription<NowPlaying>? _nowPlayingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;

  bool _initialized = false;

  WindowsMediaService(this._repo);

  /// SMTC init করা — main() থেকে একবার কল হওয়া উচিত (SMTCWindows.initialize()
  /// প্রসেস-ওয়াইড এক-বারই কল করা যায়, তাই এই মেথডও idempotent রাখা হলো)।
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await SMTCWindows.initialize();

      _smtc = SMTCWindows(
        metadata: const MusicMetadata(
          title: 'TeloPlay',
          album: '',
          albumArtist: '',
          artist: '',
        ),
        timeline: const PlaybackTimeline(
          startTimeMs: 0,
          endTimeMs: 0,
          positionMs: 0,
          minSeekTimeMs: 0,
          maxSeekTimeMs: 0,
        ),
        config: const SMTCConfig(
          fastForwardEnabled: false,
          nextEnabled: true,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: false,
          prevEnabled: true,
          stopEnabled: true,
        ),
      );

      _wireButtonEvents();
      _wireRepositoryStreams();

      _initialized = true;
      AppLogger.playback('WindowsMediaService (SMTC) initialized');
    } catch (e) {
      // SMTC init ব্যর্থ হলে (যেমন পুরনো Windows বা native lib মিসিং)
      // পুরো app crash করা উচিত না — playback normal থাকবে, শুধু
      // media flyout/lock-screen-style controls পাওয়া যাবে না।
      AppLogger.error('WindowsMediaService init failed (SMTC unavailable)', e);
    }
  }

  // ── OS → Repository (media key/flyout/Bluetooth button ইনপুট) ──

  void _wireButtonEvents() {
    _buttonSub = _smtc?.buttonPressStream.listen((event) {
      switch (event) {
        case PressedButton.play:
          _repo.resume();
          break;
        case PressedButton.pause:
          _repo.pause();
          break;
        case PressedButton.next:
          _repo.next();
          break;
        case PressedButton.previous:
          _repo.previous();
          break;
        case PressedButton.stop:
          _repo.stop();
          break;
        default:
          // fastForward/rewind এখন enabled না, তাই আসার কথা না —
          // ভবিষ্যতে enable করলে এখানে seek() যোগ করা যাবে।
          break;
      }
    });
  }

  // ── Repository → OS (metadata/timeline/status sync) ──

  void _wireRepositoryStreams() {
    _nowPlayingSub = _repo.nowPlayingStream.listen(_onNowPlayingChanged);
    _onNowPlayingChanged(_repo.nowPlaying);

    _positionSub = _repo.positionStream.listen((position) {
      _lastKnownPosition = position;
      _updateTimeline();
    });

    _durationSub = _repo.durationStream.listen((duration) {
      _lastKnownDuration = duration ?? Duration.zero;
      _updateTimeline();
    });

    _playingSub = _repo.playingStream.listen((playing) {
      _smtc?.setPlaybackStatus(
        playing ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    });
  }

  void _onNowPlayingChanged(NowPlaying np) {
    if (_smtc == null) return;

    if (np.track == null) {
      _smtc!.setPlaybackStatus(PlaybackStatus.stopped);
      return;
    }

    _smtc!.updateMetadata(
      MusicMetadata(
        title: np.track!.title,
        album: '',
        albumArtist: '',
        artist: np.track!.author,
        thumbnail: np.track!.thumbnail,
      ),
    );

    final status = switch (np.status) {
      NowPlayingStatus.resolving => PlaybackStatus.changing,
      NowPlayingStatus.playing => PlaybackStatus.playing,
      NowPlayingStatus.paused => PlaybackStatus.paused,
      NowPlayingStatus.error => PlaybackStatus.stopped,
      NowPlayingStatus.idle => PlaybackStatus.stopped,
    };
    _smtc!.setPlaybackStatus(status);
  }

  void _updateTimeline() {
    if (_smtc == null) return;
    final durationMs = _lastKnownDuration.inMilliseconds;
    final clampedPosition =
        _lastKnownPosition.inMilliseconds.clamp(0, durationMs > 0 ? durationMs : 0);
    _smtc!.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: durationMs,
        positionMs: clampedPosition,
        minSeekTimeMs: 0,
        maxSeekTimeMs: durationMs,
      ),
    );
  }

  Future<void> dispose() async {
    await _buttonSub?.cancel();
    await _nowPlayingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playingSub?.cancel();
    await _smtc?.disableSmtc();
    _smtc?.dispose();
  }
}