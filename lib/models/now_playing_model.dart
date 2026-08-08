import '../core/playback/playback_engine.dart';

enum NowPlayingStatus { idle, resolving, playing, paused, error }

/// ⚠️ Phase 3 (Offline Playback) — playback আসলে কোন উৎস থেকে চলছে।
/// Boolean flag (`isOfflineFallback`) না করে enum রাখা হলো, কারণ
/// ভবিষ্যতে আরও সোর্স-টাইপ (downloaded file, local media import
/// ইত্যাদি) আসতে পারে — নতুন schema change ছাড়াই এই একই enum-এ একটা
/// মান যোগ করলেই চলবে।
///
/// `online`: normal network-resolved stream (স্বাভাবিক অবস্থা, এবং
/// track cache-এ থাকায় fast-path cache-hit-ও `online` হিসেবেই গণ্য —
/// সেটা optimization, fallback না, UI-তে আলাদা করে দেখানোর দরকার নেই)।
///
/// `cacheFallback`: network resolve ব্যর্থ হয়েছিল (network down/CDN
/// error) এবং locally cached ফাইল দিয়ে fallback play/recovery হচ্ছে —
/// UI-তে non-intrusive "Cached"/"Offline" indicator দেখানোর জন্য।
/// Network ফিরে এসে পরের normal resolve সফল হলে এটা আবার `online`-এ
/// ফিরে আসে (নতুন NowPlaying object-এ explicit রিসেট করে)।
enum PlaybackSource { online, cacheFallback }

class NowPlaying {
  final SearchResult? track;
  final ResolvedStream? resolvedStream;
  final NowPlayingStatus status;
  final String? errorMessage;
  final PlaybackSource playbackSource;

  const NowPlaying({
    this.track,
    this.resolvedStream,
    this.status = NowPlayingStatus.idle,
    this.errorMessage,
    this.playbackSource = PlaybackSource.online,
  });

  static const idle = NowPlaying(status: NowPlayingStatus.idle);

  bool get isBusy => status == NowPlayingStatus.resolving;
  bool get isPlaying => status == NowPlayingStatus.playing;
  bool get hasError => status == NowPlayingStatus.error;
  bool get isCacheFallback => playbackSource == PlaybackSource.cacheFallback;

  NowPlaying copyWith({
    SearchResult? track,
    ResolvedStream? resolvedStream,
    NowPlayingStatus? status,
    String? errorMessage,
    PlaybackSource? playbackSource,
    bool clearError = false,
  }) {
    return NowPlaying(
      track: track ?? this.track,
      resolvedStream: resolvedStream ?? this.resolvedStream,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      playbackSource: playbackSource ?? this.playbackSource,
    );
  }

  @override
  String toString() =>
      'NowPlaying(status: $status, track: ${track?.title}, source: $playbackSource, error: $errorMessage)';
}

/// ⚠️ Resume Position — non-blocking prompt state ("Resume from 2:14?")।
///
/// এটা NowPlaying-এর অংশ না করে ইচ্ছাকৃতভাবে আলাদা ছোট model রাখা
/// হয়েছে — prompt-এর lifecycle (দেখানো → accept/dismiss → চলে যাওয়া)
/// playback status lifecycle-এর থেকে independent, দুটো মিশিয়ে ফেললে
/// NowPlaying-এর প্রতিটা transition-এ prompt-field handle করা লাগত।
class ResumePrompt {
  final String songId;
  final Duration position;
  final Duration? trackDuration;

  const ResumePrompt({
    required this.songId,
    required this.position,
    this.trackDuration,
  });
}

/// ⚠️ Phase 1 (Shuffle/Repeat/Speed/Sleep Timer) — Repeat mode।
/// `off`: queue শেষে থেমে যাবে (বর্তমান আচরণ)।
/// `one`: বর্তমান track শেষ হলে সেটাই আবার শুরু থেকে বাজবে।
/// `all`: queue শেষ track-এর পরে আবার প্রথম track-এ ফিরবে।
enum PlaybackRepeatMode { off, one, all }

/// ⚠️ Sleep Timer state — UI-কে countdown/fading অবস্থা দেখাতে সাহায্য
/// করে। `NowPlaying`-এর সাথে মেশানো হয়নি একই কারণে (ResumePrompt-এর
/// মতো) — timer lifecycle playback lifecycle থেকে independent।
class SleepTimerState {
  /// Timer সক্রিয় থাকলে কতক্ষণ বাকি — নিষ্ক্রিয় হলে null।
  final Duration? remaining;

  /// Fade-out পর্ব চলছে কিনা (শেষ কয়েক সেকেন্ড, volume ধীরে কমছে)।
  final bool isFading;

  const SleepTimerState({this.remaining, this.isFading = false});

  static const inactive = SleepTimerState();

  bool get isActive => remaining != null;
}

/// ⚠️ Bug fix — resolve/cache দুটোই ব্যর্থ হলে transient, one-shot
/// user-facing error event। `NowPlaying.errorMessage`-এর থেকে
/// ইচ্ছাকৃতভাবে আলাদা — সেটা persistent state (UI rebuild-এ বারবার
/// দেখা যেতে পারে), এটা একবার fire হয়ে চলে যাওয়া উচিত (Snackbar/Toast)।
/// Repository layer শুধু structured error দেয়, UI নিজে ঠিক করে কীভাবে
/// দেখাবে (কোনো direct Snackbar call repository/service layer-এ নেই)।
class PlaybackError {
  /// User-facing, non-technical message — UI সরাসরি দেখাতে পারবে।
  final String message;

  /// Debug/log-এর জন্য raw cause — UI-তে কখনো দেখানো উচিত না।
  final Object? cause;

  const PlaybackError(this.message, {this.cause});
}