import 'dart:async';

import '../../data/repositories/music_player_repository.dart';

/// Web stub for WindowsMediaService (Windows-only feature)
class WindowsMediaService {
  WindowsMediaService(MusicPlayerRepository repo);

  Future<void> initialize() async {}
  Future<void> init() async {}
  Future<void> dispose() async {}
  Future<void> enable() async {}
  Future<void> disable() async {}
  void clearMetadata() {}
}
