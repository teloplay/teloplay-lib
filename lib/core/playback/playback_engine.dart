/// একটা resolved, playable stream-এর তথ্য।
/// PlaybackEngine.resolveStream() এই object রিটার্ন করে —
/// MusicPlayerRepository এটা নিয়ে media_kit Player-কে খাওয়ায়।
class ResolvedStream {
  /// সরাসরি playable audio URL (yt-dlp থেকে বা Innertube থেকে)
  final String streamUrl;

  /// কত সেকেন্ড পর্যন্ত এই URL valid থাকবে (YouTube stream URL expire করে)।
  /// null মানে জানা নেই / assume করা যাবে না।
  final Duration? expiresIn;

  /// Debug/log-এর জন্য — কোন engine/client দিয়ে resolve হলো
  final String sourceLabel;

  const ResolvedStream({
    required this.streamUrl,
    this.expiresIn,
    required this.sourceLabel,
  });
}

// ⚠️ Context-based Queue (Phase 1 fix) — কোন screen/context থেকে
// playFromContext() কল হয়েছে সেটা চিহ্নিত করার জন্য। এখন শুধু in-memory
// track রাখা হচ্ছে (MusicPlayerRepository._queueSource) — future
// analytics/UI ("Playing from Favorites" ব্যাজ ইত্যাদি)-এর জন্য reserve
// করা হলো, কিন্তু Drift/Supabase-এ persist করা হচ্ছে না এখন (schema
// change লাগবে না বলে ইচ্ছাকৃতভাবে বাদ, দরকার হলে ভবিষ্যতে
// QueueItems-এ একটা nullable column হিসেবে যোগ করা যাবে)।
//
// ⚠️ Song Details fallback queue (Phase 6.5B) — [songDetails] নতুন যোগ
// হয়েছে। SongDetailsScreen বেয়ার deep link (/song/:id) দিয়ে খোলা হলে,
// কোনো in-memory context/queue থাকে না — তখন এই single-track fallback
// queue ব্যবহার হয়, যাতে play button থাকলে অন্তত ওই একটা গান বাজানো
// যায়। Normal navigation (list থেকে ট্যাপ করে) থেকে এটা কখনো ব্যবহৃত
// হয় না, শুধু bare deep-link কেসের জন্য।
enum QueueSource {
  search,
  favorites,
  playlist,
  downloaded,
  recommendation,
  songDetails,
  album,
  artist,   // 🆕 যোগ করো
  unknown,
}

/// একটা search ফলাফল — MusicPlayerService-এর SearchResult-এর সাথে
/// field-for-field মিল রাখা হয়েছে, যাতে UI screen migrate করার সময়
/// data shape বদলাতে না হয়।
class SearchResult {
  final String videoId;
  final String title;
  final String author;
  final String thumbnail;
  final Duration? duration;

  // ⚠️ Backlog #1 fix — daemon (Main.kt) থেকে SongItem-এর সব available
  // metadata। nullable/default-empty কারণ পুরনো yt-dlp fallback engine
  // এগুলো দেয় না, আর কিছু track-এ album/multiple-artist নাও থাকতে পারে।
  final String? artistId;
  final String? albumId;
  final String? albumName;
  final List<String> allArtistNames;
  final List<String?> allArtistIds;
  final bool explicit;
  final int? chartPosition;
  final String? chartChange;
  final String? setVideoId;

  const SearchResult({
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnail,
    this.duration,
    this.artistId,
    this.albumId,
    this.albumName,
    this.allArtistNames = const [],
    this.allArtistIds = const [],
    this.explicit = false,
    this.chartPosition,
    this.chartChange,
    this.setVideoId,
  });
}

// ⚠️ Audio Focus Ducking (Phase 1) — OS থেকে আসা audio focus পরিবর্তনের
// সংকেত। Engine-driven (repository নয়) কারণ শুধু platform layer-ই
// প্রকৃতপক্ষে OS focus event শুনতে পারে (Android AudioManager,
// ভবিষ্যতে Windows-এ প্রযোজ্য হলে সংশ্লিষ্ট API)। MusicPlayerRepository
// এই signal শুনে player-level action (duck volume / pause / restore)
// নেয় — engine নিজে media_kit Player touch করে না, architectural
// boundary বজায় থাকে (engine শুধু stream resolve/search/OS-signal,
// repository-ই একমাত্র Player owner)।
//
// ⚠️ Bluetooth Optimization (Phase 1) — এই enum-এ দুইটা নতুন সদস্য যোগ
// হয়েছে: [callInterruption] ও [deviceDisconnected], আর [gained]-এর
// পাশাপাশি [deviceReconnected]। আগে দুটোই (call/headphone-unplug) একই
// generic [transientLoss] হিসেবে পাঠানো হতো, কিন্তু বাস্তবায়নের সময়
// দেখা গেল দুটোর resume-policy আলাদা হওয়া দরকার:
//
//   - Call শেষ হলে (`gained`) → conservative auto-resume, শুধু যদি
//     call-এর ঠিক আগে playback সত্যিই চলছিল এবং pause সিস্টেম নিজেই
//     করেছিল (user manually pause করেনি)।
//   - Bluetooth/headphone reconnect হলে (`deviceReconnected`) →
//     একই শর্তে auto-resume — কিন্তু trigger আলাদা (device event,
//     audio-focus event না) তাই আলাদা signal-ই স্পষ্টতর।
//
// পুরনো generic `transientLoss` deprecated রাখা হয়েছে (repository এখনো
// এটা handle করে, backward-compat/edge-case safety net হিসেবে) কিন্তু
// engine নতুন কোড থেকে আর এটা পাঠাবে না — সবসময় নির্দিষ্ট
// callInterruption/deviceDisconnected পাঠাবে।
enum AudioFocusSignal {
  /// Transient, volume-lowering-only interruption (notification sound,
  /// nav prompt) — playback duck (কমানো) করা উচিত, pause না।
  duck,

  /// @deprecated — দেখুন [callInterruption] ও [deviceDisconnected]।
  /// পুরনো generic transient-loss signal, নতুন engine code এটা পাঠায়
  /// না, কিন্তু repository backward-compat হিসেবে এখনো handle করে
  /// (conservative pause-and-wait, resume policy ছাড়া)।
  transientLoss,

  /// Focus ফিরে পাওয়া (duck-এর 'end' event) — duck অবস্থায় থাকলে volume
  /// restore করা হয়। শুধু duck-restore-এর জন্য ব্যবহৃত হয়, resume-এর
  /// জন্য না (দেখুন [callEnded]/[deviceReconnected])।
  gained,

  /// ⚠️ Bluetooth Optimization (Phase 1) — ফোন call আসায় audio focus
  /// হারানো (transient, permanent না)। Repository conservative auto-
  /// resume policy প্রয়োগ করবে: শুধু যদি call-এর ঠিক আগে
  /// playing ছিল এবং pause সিস্টেম-ট্রিগারড ছিল (user pause না)।
  callInterruption,

  /// ⚠️ Bluetooth Optimization (Phase 1) — call শেষ হওয়ার signal (আগে
  /// generic [gained]-এর অংশ ছিল)। Repository এখানে conditional
  /// auto-resume করে — [callInterruption]-এর নোট দেখুন।
  callEnded,

  /// ⚠️ Bluetooth Optimization (Phase 1) — output device disconnect
  /// হয়েছে (headphone unplug, Bluetooth A2DP disconnect, ইত্যাদি)।
  /// audio_session-এর becomingNoisyEventStream থেকে আসে। Repository
  /// pause করে এবং এই disconnect-এর কারণেই pause হয়েছে তা মনে রাখে
  /// (conditional resume-এর জন্য দরকারি)।
  deviceDisconnected,

  /// ⚠️ Bluetooth Optimization (Phase 1) — output device আবার active
  /// হয়েছে (একই বা নতুন Bluetooth/headphone device কানেক্ট হলো, audio
  /// route আবার উপলব্ধ)। Repository conditional auto-resume করে —
  /// [deviceDisconnected]-এর নোট দেখুন। শর্ত পূরণ না হলে (যেমন
  /// এর মধ্যে user manual pause করেছে) silently কিছু করা হয় না।
  deviceReconnected,
}

/// প্রতিটা platform-specific playback engine-কে এই contract মানতে হবে।
/// Windows engine Innertube daemon (primary) বা yt-dlp.exe subprocess
/// (fallback) কল করে, Android engine Innertube MethodChannel কল করে —
/// কিন্তু দুটোই একইভাবে ব্যবহৃত হয় MusicPlayerRepository থেকে, তাই
/// platform-check UI/repository লেভেলে কখনো লাগে না।
abstract class PlaybackEngine {
  /// Engine শুরু করার আগে দরকারি setup (media_kit MediaKit.ensureInitialized()
  /// ছাড়াও engine-specific init, যেমন visitorData fetch/daemon spawn,
  /// audio session configure)
  Future<void> initialize();

  /// একটা YouTube video ID থেকে playable stream URL resolve করা।
  /// Throws [PlaybackEngineException] resolve fail করলে।
  Future<ResolvedStream> resolveStream(String videoId);

  /// একটা query দিয়ে track খোঁজা — একাধিক ফলাফল রিটার্ন করে (সর্বোচ্চ
  /// [limit]টা)। ডিফল্ট limit ১০ — Normal search/Smart Queue কেসের জন্য
  /// consistent রাখা হয়েছে দুই platform-এ। Auto-complete-এর জন্য ৫,
  /// Artist page/"more songs"-এর জন্য ২০ পাঠানো যাবে caller থেকে।
  /// Throws [PlaybackEngineException] কোনো ফলাফল না পেলে বা fail করলে।
  Future<List<SearchResult>> search(String query, {int limit = 10});

  // ⚠️ Live Search Suggestions (Phase 1 scope-এ আনা হয়েছে, আগে Phase 7+
  // এ ছিল) — Innertube backend-এ ইতিমধ্যে YouTube.searchSuggestions()
  // নামে একটা network suggestion endpoint আছে (OpenTune-এর নিজস্ব
  // search screen-এও ব্যবহৃত), তাই নতুন backend integration লাগেনি,
  // শুধু এই interface-এ expose করা হলো।
  //
  // Default no-op implementation দেওয়া হয়েছে (খালি list), কারণ yt-dlp
  // fallback engine-এর এমন কোনো endpoint নেই — engine যদি override না
  // করে, caller (UI/repository) empty list পাবে এবং suggestion অংশটা
  // silently না দেখিয়ে এগিয়ে যাবে, কোনো crash/exception হবে না।
  //
  // Throws করা হয় না ইচ্ছাকৃতভাবে (search()-এর মতো exception-based
  // error না) — suggestion একটা "nice to have" UX enhancement, ব্যর্থ
  // হলে চুপচাপ খালি list ফেরত দেওয়াই ভালো, error message দেখিয়ে user-কে
  // বিরক্ত করার দরকার নেই।
  Future<List<String>> searchSuggestions(String query) async => [];

  // ⚠️ Phase 0.9 (Foundation Hardening) → Phase 1 (Audio Focus Ducking,
  // এখন বাস্তবায়িত)।
  //
  // পুরনো design-এ repository → engine দিকে দুটো placeholder method
  // (onAudioFocusLost/onAudioFocusGained) রাখা হয়েছিল এই ধারণায় যে
  // repository "সিদ্ধান্ত নেবে" আর engine সেটা execute করবে। বাস্তবায়নের
  // সময় দেখা গেল এটা উল্টো হওয়া উচিত — audio focus event আসলে OS থেকে
  // আসে *engine-এর platform layer*-এ (Android AudioManager), repository
  // এই event সম্পর্কে জানতেই পারে না যদি না engine তাকে জানায়। তাই এই
  // দুটো placeholder method এখন deprecated (no-op, backward-compat only)
  // এবং তার বদলে নিচের [audioFocusStream] getter যোগ হয়েছে —
  // engine → repository দিকে event push করে, repository সেটা শুনে
  // player-level duck/pause/restore সিদ্ধান্ত নেয়।
  //
  // এই ধরনের direction-reversal ছোট আকারে হলেও এখানে নোট করে রাখা হলো
  // যাতে ভবিষ্যতে "কেন দুই রকম hook আছে" প্রশ্ন উঠলে ব্যাখ্যা পাওয়া যায়।

  /// @deprecated ব্যবহৃত হচ্ছে না — দেখুন [audioFocusStream]। Backward
  /// compatibility-এর জন্য interface-এ রাখা হয়েছে, কোনো engine আর এটা
  /// থেকে meaningful কিছু করে না।
  Future<void> onAudioFocusLost() async {}

  /// @deprecated ব্যবহৃত হচ্ছে না — দেখুন [audioFocusStream]।
  Future<void> onAudioFocusGained() async {}

  /// OS-level audio focus পরিবর্তনের সংকেত (call, headphone unplug/
  /// Bluetooth disconnect, notification sound, অন্য app focus নেওয়া
  /// ইত্যাদি)। MusicPlayerRepository এটা শুনে duck/pause/conditional-
  /// resume করে।
  ///
  /// Windows engine-এ এখনো null (SMTC/Windows-এ এই ধরনের OS-level
  /// audio focus concept সরাসরি নেই যেটা এই abstraction-এ মানানসই,
  /// future scope)। Android engine সবসময় non-null stream দেয়
  /// (initialize()-এর পরে)।
  Stream<AudioFocusSignal>? get audioFocusStream => null;

  // ⚠️ Bluetooth Optimization (Phase 1) — Codec/latency-aware
  // adjustment, device profiling, auto quality switching (aptX/LDAC
  // detection ইত্যাদি) ইচ্ছাকৃতভাবে Phase 7+-এ পাঠানো হয়েছে (over-
  // engineering এড়াতে, roadmap-এর ৫-dimension risk framework অনুযায়ী
  // effort-vs-urgency বিবেচনা করে)। এই getter এখন শুধু future-proof
  // placeholder হিসেবে আছে — কোনো engine এখনো non-null মান দেয় না।
  // Phase 7+-এ কোনো engine যদি device/codec info দিতে চায়, এই
  // interface-এই সেটা expose করা যাবে, নতুন abstraction লাগবে না।
  ///
  /// Connected audio output device-এর নাম/label (যদি জানা থাকে) —
  /// Phase 7+ codec/device-aware UI feature-এর জন্য placeholder।
  /// এখন সবসময় null।
  Stream<String?>? get connectedAudioDeviceStream => null;

  /// Buffer health (0.0–1.0, কতটা buffered আছে) স্ট্রিম — Adaptive
  /// Buffering (Phase 1) ও Smart Cache (Phase 3) preload logic এটা
  /// ব্যবহার করবে ভবিষ্যতে। এখন null (কোনো engine এই signal দেয় না)।
  Stream<double>? get bufferHealthStream => null;

  /// Engine dispose/cleanup — app বন্ধ হওয়ার সময় বা engine switch হলে কল হয়।
  Future<void> dispose();

  /// এই engine-এর label, logging-এর জন্য (যেমন "yt-dlp/windows", "innertube/android")
  String get engineLabel;
}

/// Stream resolve করতে ব্যর্থ হলে বা engine-level error হলে এই exception ছোড়া হয়।
/// UI লেয়ারে user-friendly message দেখানোর জন্য catch করা উচিত।
class PlaybackEngineException implements Exception {
  final String message;
  final Object? cause;

  PlaybackEngineException(this.message, {this.cause});

  @override
  String toString() => 'PlaybackEngineException: $message'
      '${cause != null ? ' (cause: $cause)' : ''}';
}