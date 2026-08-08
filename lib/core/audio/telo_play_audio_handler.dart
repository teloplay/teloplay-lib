import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../logging/app_logger.dart';
import '../playback/playback_engine.dart';
import '../../data/repositories/music_player_repository.dart';
import '../../models/now_playing_model.dart';
import 'audio_session_manager.dart';

/// audio_service-এর সাথে MusicPlayerRepository-কে যুক্ত করার wrapper।
///
/// ⚠️ ডিজাইন সিদ্ধান্ত: playback logic (resolve/retry/queue/player control)
/// এখানে MOVE করা হয়নি — সব MusicPlayerRepository-তেই থাকে (single
/// source of truth)। এই ক্লাস শুধু দুইদিকে event forward করে:
///
///   OS (notification/lock screen/Bluetooth/media key)
///        │  play()/pause()/skipToNext()/seek() ইত্যাদি কল করে
///        ▼
///   TeloPlayAudioHandler  ──────────────►  MusicPlayerRepository
///        ▲                                        │
///        │  nowPlayingStream/positionStream শুনে   │
///        └────────── PlaybackState/MediaItem emit ─┘
///
/// এতে repository-এর existing behavior (retry policy, race-condition
/// token guard, queue persistence) অক্ষত থাকে — audio_service শুধু
/// repository-এর উপর একটা "OS-facing চামড়া"।
///
/// Queue এখনো MediaItem-level sync করা হয়নি (ইচ্ছাকৃতভাবে, Phase-এর
/// scope অনুযায়ী) — শুধু current track. ভবিষ্যতে queue sync যোগ করতে
/// হলে `_syncQueue()`-জাতীয় একটা নতুন মেথড repository.queueStream শুনে
/// `queue` (audio_service-এর BaseAudioHandler field) আপডেট করবে; এই
/// ক্লাসের বাকি অংশ অপরিবর্তিত থাকবে।
///
/// ⚠️ Lazy-binding: `AudioService.init()` runApp()-এর *আগে* কল করতে হয়
/// (main.dart-এ, audio_service প্যাকেজের নিজস্ব constraint), কিন্তু
/// real MusicPlayerRepository (QueueRepository/Drift সহ) Riverpod
/// provider tree-তে বাস করে, যেটা runApp()-এর পরেই তৈরি হয়। তাই এই
/// handler constructor-এ repository নেয় না — খালি অবস্থায় তৈরি হয়,
/// পরে `attachRepository()` কল করে repository bind করা হয় (একবারই,
/// `musicPlayerRepositoryProvider` তৈরি হওয়ার সাথে সাথে)। bind হওয়ার
/// আগ পর্যন্ত play/pause/skip কল সব no-op থাকে (crash করে না)।
class TeloPlayAudioHandler extends BaseAudioHandler with SeekHandler {
  MusicPlayerRepository? _repo;

  // ⚠️ Bug fix (long-running background reliability) — audio_session-এর
  // ownership এখন এখানে, audio_service-এর background lifecycle-এর
  // আওতায় (UI/Riverpod provider lifecycle থেকে স্বাধীন)। আগে
  // AndroidPlaybackEngine নিজে এটা lazy-init করত প্রথম playVideoId()-এ,
  // এবং একবার subscribe করার পর dead subscription resubscribe করার
  // কোনো mechanism ছিল না — এটাই ছিল "app কিছুক্ষণ চলার পর ducking/
  // Bluetooth handling silently বন্ধ হয়ে যাওয়া" bug-এর root cause।
  // AudioSessionManager এখন single owner হিসেবে configure করে এবং
  // onDone/onError guard + periodic health-check দিয়ে automatic
  // resubscribe করে।
  final AudioSessionManager audioSessionManager = AudioSessionManager();

  StreamSubscription<NowPlaying>? _nowPlayingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<Duration?>? _durationSub;

  Duration _lastKnownDuration = Duration.zero;
  bool _lastKnownPlaying = false;
  bool _lastKnownBuffering = false;

  TeloPlayAudioHandler() {
    // ⚠️ Handler তৈরি হওয়ার সাথে সাথেই session initialize — এটা
    // AudioService.init()-এর ভেতরেই ঘটে (main_android.dart-এর
    // postFrameCallback), যেটা audio_service-এর নিজস্ব background/
    // foreground lifecycle-এর অংশ। fire-and-forget, কারণ constructor
    // sync হতে হবে — initialize()-এর ভেতরের সব error নিজেই handle হয়
    // (try-catch, non-fatal)।
    unawaited(audioSessionManager.initialize());
  }

  /// Real MusicPlayerRepository bind করা — `musicPlayerRepositoryProvider`
  /// তৈরি হওয়ার সাথে সাথে একবারই কল হওয়া উচিত। বারবার কল হলে আগের
  /// subscription cleanup করে নতুন repo-তে re-wire করে (hot-restart/
  /// provider re-create হওয়ার edge case-এও নিরাপদ থাকার জন্য)।
  void attachRepository(MusicPlayerRepository repo) {
    if (identical(_repo, repo)) return; // ইতিমধ্যে এই repo-তেই bound
    _cancelSubscriptions();
    _repo = repo;
    _wireRepositoryStreams();
    AppLogger.playback('TeloPlayAudioHandler attached to repository');
  }

  void _cancelSubscriptions() {
    _nowPlayingSub?.cancel();
    _positionSub?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _durationSub?.cancel();
  }

  /// Repository-এর stream গুলো শুনে audio_service-এর PlaybackState/
  /// MediaItem হিসেবে re-emit করা। এই মেথডটাই "sync bridge" — repository
  /// state বদলালেই OS notification/lock screen নিজে থেকে আপডেট হবে,
  /// আলাদা করে কোথাও manual sync কল লাগবে না।
  void _wireRepositoryStreams() {
    final repo = _repo;
    if (repo == null) return; // safety guard, আসলে সবসময় non-null এখানে

    // Track বদলালে (বা resolving/error status বদলালে) MediaItem +
    // PlaybackState দুটোই আপডেট — একসাথেই, যাতে notification কখনো
    // "half-updated" track দেখায় না (repository-এর NowPlaying atomic
    // design-এর সাথে সামঞ্জস্যপূর্ণ)।
    _nowPlayingSub = repo.nowPlayingStream.listen(_onNowPlayingChanged);
    // শুরুতে যদি already কিছু play হচ্ছে থাকে (hot restart/reconnect case)
    _onNowPlayingChanged(repo.nowPlaying);

    _positionSub = repo.positionStream.listen((position) {
      _emitPlaybackState(position: position);
    });

    _durationSub = repo.durationStream.listen((duration) {
      _lastKnownDuration = duration ?? Duration.zero;
      // duration বদলালে MediaItem-এও আপডেট করা দরকার (notification-এ
      // total time দেখানোর জন্য), কিন্তু শুধু track থাকলে।
      final track = repo.nowPlaying.track;
      if (track != null) {
        mediaItem.add(_toMediaItem(track, duration: _lastKnownDuration));
      }
      _emitPlaybackState();
    });

    _playingSub = repo.playingStream.listen((playing) {
      _lastKnownPlaying = playing;
      _emitPlaybackState();
    });

    _bufferingSub = repo.bufferingStream.listen((buffering) {
      _lastKnownBuffering = buffering;
      _emitPlaybackState();
    });
  }

  void _onNowPlayingChanged(NowPlaying np) {
    if (np.track == null) {
      mediaItem.add(null);
      _emitPlaybackState(processingState: AudioProcessingState.idle);
      return;
    }

    mediaItem.add(_toMediaItem(np.track!, duration: _lastKnownDuration));

    final processingState = switch (np.status) {
      NowPlayingStatus.resolving => AudioProcessingState.loading,
      NowPlayingStatus.error => AudioProcessingState.error,
      NowPlayingStatus.playing => AudioProcessingState.ready,
      NowPlayingStatus.paused => AudioProcessingState.ready,
      NowPlayingStatus.idle => AudioProcessingState.idle,
    };
    _emitPlaybackState(processingState: processingState);
  }

  MediaItem _toMediaItem(SearchResult track, {Duration? duration}) {
    return MediaItem(
      id: track.videoId,
      title: track.title,
      artist: track.author,
      artUri: Uri.tryParse(track.thumbnail),
      duration: (duration != null && duration > Duration.zero) ? duration : null,
    );
  }

  /// PlaybackState emit — controls (play/pause/skip button visibility),
  /// processing state, position সব একসাথে পাঠানো হয় যাতে OS-side UI
  /// consistent থাকে। প্রতিটা caller শুধু যা বদলেছে তা override করে,
  /// বাকি সব "শেষ জানা" ভ্যালু থেকে নেওয়া হয়।
  void _emitPlaybackState({
    Duration? position,
    AudioProcessingState? processingState,
  }) {
    final playing = _lastKnownPlaying;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState ??
            (_lastKnownBuffering
                ? AudioProcessingState.buffering
                : AudioProcessingState.ready),
        playing: playing,
        updatePosition: position ?? playbackState.value.position,
        bufferedPosition: _lastKnownDuration,
        speed: 1.0,
      ),
    );
  }

  // ── OS → Repository (media key/notification/Bluetooth button ইনপুট) ──

  @override
  Future<void> play() => _repo?.resume() ?? Future.value();

  @override
  Future<void> pause() => _repo?.pause() ?? Future.value();

  @override
  Future<void> stop() async {
    await _repo?.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _repo?.next() ?? Future.value();

  @override
  Future<void> skipToPrevious() => _repo?.previous() ?? Future.value();

  @override
  Future<void> seek(Duration position) => _repo?.seek(position) ?? Future.value();

  /// App/service বন্ধ হওয়ার সময় cleanup — repository dispose এখানে
  /// কল করা হয় না ইচ্ছাকৃতভাবে (আগের নোট অনুযায়ী)। এখন
  /// audioSessionManager-ও dispose হয় এখানে, কারণ এটাই এর প্রকৃত
  /// owner-এর lifecycle-শেষ (audio_service handler বন্ধ হওয়া মানেই
  /// পুরো background audio session আর দরকার নেই)।
  Future<void> disposeHandler() async {
    _cancelSubscriptions();
    await audioSessionManager.dispose();
  }
  }