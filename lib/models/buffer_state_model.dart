// ⚠️ Adaptive Buffering (Phase 1) — buffer/network state-এর জন্য একটা
// ছোট typed model। ResumePrompt/SleepTimerState-এর মতোই ইচ্ছাকৃতভাবে
// আলাদা রাখা হয়েছে (NowPlaying-এর ভেতরে গোঁজা হয়নি) — buffer state
// lifecycle playback lifecycle থেকে independent, প্রতিটা NowPlaying
// transition-এ buffer-field handle করার দরকার নেই।

/// Network condition-এর rough classification — raw speed number না
/// দেখিয়ে UI/adaptive-logic-কে discrete category দেওয়া হচ্ছে, কারণ
/// রিয়েল network speed খুবই noisy (এক sample-এই বিভ্রান্তিকর হতে পারে)।
/// [BufferHealthMonitor] rolling-average থেকে এই category বের করে।
enum NetworkQuality {
  /// এখনো পর্যাপ্ত sample নেই, বা কোনো active download চলছে না।
  unknown,

  /// Frequent rebuffering / খুব ধীর download — বেশি buffer টার্গেট দরকার।
  poor,

  /// মাঝারি — default buffer target যথেষ্ট।
  moderate,

  /// দ্রুত, স্থিতিশীল — কম buffer টার্গেট, দ্রুত playback start।
  good,
}

/// [BufferHealthMonitor] এই state emit করে — repository/UI এটা শুনে
/// adaptive সিদ্ধান্ত নেয় (buffer target বাড়ানো, recovery trigger করা,
/// ভবিষ্যতে UI-তে "Poor connection" indicator দেখানো ইত্যাদি)।
class BufferState {
  /// এই মুহূর্তে কত সেকেন্ড playback আগে থেকে buffered আছে (position
  /// থেকে buffered-position পর্যন্ত)। media_kit সরাসরি এই মান দেয় না,
  /// তাই [BufferHealthMonitor] বাফারিং event/duration থেকে estimate
  /// করে।
  final Duration bufferedAhead;

  /// Rolling-average network quality classification।
  final NetworkQuality networkQuality;

  /// এই track-এর current playback session-এ কতবার rebuffering
  /// (buffering=true event, non-initial) হয়েছে — Smart Recovery-র
  /// trigger হিসেবে ব্যবহৃত।
  final int interruptionCount;

  /// এই মুহূর্তে actively buffering (স্টল) অবস্থায় আছে কিনা।
  final bool isBuffering;

  const BufferState({
    this.bufferedAhead = Duration.zero,
    this.networkQuality = NetworkQuality.unknown,
    this.interruptionCount = 0,
    this.isBuffering = false,
  });

  static const initial = BufferState();

  BufferState copyWith({
    Duration? bufferedAhead,
    NetworkQuality? networkQuality,
    int? interruptionCount,
    bool? isBuffering,
  }) {
    return BufferState(
      bufferedAhead: bufferedAhead ?? this.bufferedAhead,
      networkQuality: networkQuality ?? this.networkQuality,
      interruptionCount: interruptionCount ?? this.interruptionCount,
      isBuffering: isBuffering ?? this.isBuffering,
    );
  }

  @override
  String toString() =>
      'BufferState(bufferedAhead: $bufferedAhead, network: $networkQuality, '
      'interruptions: $interruptionCount, buffering: $isBuffering)';
}