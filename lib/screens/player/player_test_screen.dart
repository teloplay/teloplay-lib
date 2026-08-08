import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../providers/music_player_provider.dart';

class PlayerTestScreen extends ConsumerStatefulWidget {
  const PlayerTestScreen({super.key});

  @override
  ConsumerState<PlayerTestScreen> createState() => _PlayerTestScreenState();
}

class _PlayerTestScreenState extends ConsumerState<PlayerTestScreen> {
  final _videoIdController = TextEditingController();
  final _searchController = TextEditingController();

  String? _lastError;
  bool _isBusy = false;
  List<SearchResult> _queueSnapshot = [];

  @override
  void dispose() {
    _videoIdController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _runGuarded(Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
      _lastError = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _queueSnapshot = ref.read(musicPlayerRepositoryProvider).queue;
        });
      }
    }
  }

  Future<void> _playByVideoId() async {
    final videoId = _videoIdController.text.trim();
    if (videoId.isEmpty) return;
    await _runGuarded(
      () => ref.read(musicPlayerRepositoryProvider).playVideoId(videoId),
    );
  }

  Future<void> _searchAndAddToQueue() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    await _runGuarded(() async {
      final repo = ref.read(musicPlayerRepositoryProvider);
      // এই dev screen-এ এখনো single-add behavior — search()-এর প্রথম
      // ফলাফল queue-তে যোগ হয় (আগের মতোই)। পুরো result list দিয়ে
      // pick করার UI production music_player_screen.dart-এ আছে।
      final results = await repo.search(query, limit: 1);
      if (results.isEmpty) {
        throw Exception('কোনো ফলাফল পাওয়া যায়নি query="$query"');
      }
      repo.addToQueue(results.first);
    });
    // Search করে queue-তে যোগ হওয়ার পর ফিল্ড খালি করে দেওয়া — নাহলে Enter
    // চাপলে বা বাটন দুবার চাপলে একই query আবার search+add হয়ে যাবে,
    // duplicate track queue-তে ঢুকে যাবে (এটাই তুমি screenshot-এ দেখেছিলে)।
    if (mounted) _searchController.clear();
  }

  Future<void> _searchAndPlayNow() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    await _runGuarded(
      () => ref.read(musicPlayerRepositoryProvider).searchAndPlay(query),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value ?? Duration.zero;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Playback Engine + Queue Test')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _videoIdController,
              decoration: const InputDecoration(
                labelText: 'YouTube video ID (সরাসরি play)',
                hintText: 'যেমন: dQw4w9WgXcQ',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _playByVideoId(),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isBusy ? null : _playByVideoId,
              child: const Text('Play by Video ID'),
            ),

            const Divider(height: 32),

            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'গান খুঁজুন',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _searchAndAddToQueue(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isBusy ? null : _searchAndPlayNow,
                    child: const Text('Search & Play Now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isBusy ? null : _searchAndAddToQueue,
                    child: const Text('Search & Add to Queue'),
                  ),
                ),
              ],
            ),

            if (_isBusy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],

            if (_lastError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _lastError!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],

            const Divider(height: 32),

            if (repo.currentTrack != null) ...[
              Text(
                repo.currentTrack!.title,
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                repo.currentTrack!.author,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],

            Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: duration.inMilliseconds > 0
                  ? (value) {
                      final seekTo = Duration(
                        milliseconds: (value * duration.inMilliseconds).round(),
                      );
                      repo.seek(seekTo);
                    }
                  : null,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatDuration(position), style: theme.textTheme.bodySmall),
                Text(_formatDuration(duration), style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => _runGuarded(repo.previous),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 56,
                  icon: Icon(
                    isBuffering
                        ? Icons.hourglass_top
                        : isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                  ),
                  onPressed: () => repo.togglePause(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 36,
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => _runGuarded(repo.next),
                ),
              ],
            ),

            const Divider(height: 32),

            Text('Queue (${_queueSnapshot.length})', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ..._queueSnapshot.asMap().entries.map((entry) {
              final index = entry.key;
              final track = entry.value;
              final isCurrent = index == repo.queueIndex;
              return ListTile(
                dense: true,
                leading: isCurrent
                    ? const Icon(Icons.equalizer, size: 18)
                    : Text('${index + 1}'),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(track.author),
                onTap: () => _runGuarded(() => repo.playFromQueue(index)),
              );
            }),
          ],
        ),
      ),
    );
  }
}