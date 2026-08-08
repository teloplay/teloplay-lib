import 'dart:async';

import 'telo_play_audio_handler.dart';

TeloPlayAudioHandler? globalAudioHandler;

/// ⚠️ Bug fix — Audio Focus Ducking/Bluetooth reconnect race condition।
/// AudioService.init() (main_android.dart, postFrameCallback-এ) এবং
/// AndroidPlaybackEngine._setupAudioSession() (lazy, প্রথম playVideoId()-
/// এ) দুটোই একই AudioSession.instance configure/activate করার
/// চেষ্টা করত, কোনো নির্ধারিত order ছাড়াই — যেটা যেটার আগে চলত সেটাই
/// "জিতত", ফলে behavior অনির্দিষ্ট (কখনো কাজ করত, কখনো না)।
///
/// audio_service-এর নিজস্ব ডকুমেন্টেশন অনুযায়ী: "it is recommended
/// that you apply your own preferred configuration using audio_session
/// after all other audio plugins have loaded" — তাই এই Completer
/// AudioService.init() সম্পূর্ণ হওয়ার সংকেত দেয়, AndroidPlaybackEngine
/// এর জন্য অপেক্ষা করে তারপর নিজের audio_session configure করে।
final Completer<void> audioServiceReady = Completer<void>();