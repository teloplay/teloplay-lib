import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/audio/web_html_audio_player.dart';
import 'core/audio/web_media_session.dart';
import 'core/playback/playback_engine.dart';
import 'core/playback/web_playback_engine.dart';

/// TeloPlay Web entry point.
///
/// This is intentionally kept separate from the Android/Windows app entry
/// points because the full app currently imports several native-only modules
/// (`dart:io`, Windows SMTC, tray/window APIs, filesystem cache, native Drift
/// setup). For web, this free MVP uses:
///
/// - Piped public API + CORS-proxy fallback for stream URLs.
/// - HTML <audio> (Safari background + lock-screen Media Session).
/// - No innertube-cli.jar, no YouTube iframe, no paid server.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const TeloPlayWebApp());
}

class TeloPlayWebApp extends StatelessWidget {
  const TeloPlayWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TeloPlay Web',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0E0F16),
      ),
      home: const TeloPlayWebHome(),
    );
  }
}

class TeloPlayWebHome extends StatefulWidget {
  const TeloPlayWebHome({super.key});

  @override
  State<TeloPlayWebHome> createState() => _TeloPlayWebHomeState();
}

class _TeloPlayWebHomeState extends State<TeloPlayWebHome> {
  final _engine = WebPlaybackEngine();
  final _player = WebHtmlAudioPlayer();
  final _searchController = TextEditingController();
  late final WebMediaSession _mediaSession;

  List<SearchResult> _results = const [];
  SearchResult? _currentTrack;
  bool _searching = false;
  bool _resolving = false;
  String? _error;
  Duration _duration = Duration.zero;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _mediaSession = WebMediaSession(
      onPlay: () => _player.play(),
      onPause: () async => _player.pause(),
    );
    _mediaSession.bind();
    unawaited(_engine.initialize());
    _subs.add(_player.playingStream.listen((playing) {
      _mediaSession.setPlaybackState(playing);
    }));
    _subs.add(_player.positionStream.listen((pos) {
      _mediaSession.updatePosition(position: pos, duration: _duration);
    }));
    _subs.add(_player.durationStream.listen((d) {
      _duration = d ?? Duration.zero;
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _searchController.dispose();
    unawaited(_player.dispose());
    unawaited(_engine.dispose());
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final results = await _engine.search(query, limit: 20);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _play(SearchResult track) async {
    setState(() {
      _currentTrack = track;
      _resolving = true;
      _error = null;
    });

    try {
      final resolved = await _engine.resolveStream(track.videoId);
      await _player.stop();
      await _player.open(resolved.streamUrl);
      await _player.play();
      _mediaSession.updateMetadata(track);
      _mediaSession.setPlaybackState(true);
    } catch (e) {
      if (!mounted) return;
      await _player.stop();
      setState(() => _error =
          'App-controlled web stream resolve failed. Public free Piped instance এই track-এর playable audio URL দিতে পারছে না. Cause: $e');
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _togglePlayPause(bool playing) async {
    if (playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _mediaSession.setPlaybackState(!playing);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _Header(onExampleTap: (q) {
                    _searchController.text = q;
                    unawaited(_search());
                  }),
                  const SizedBox(height: 24),
                  _SearchBar(
                    controller: _searchController,
                    searching: _searching,
                    onSearch: _search,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: _error!),
                  ],
                  const SizedBox(height: 18),
                  Expanded(
                    child: _results.isEmpty
                        ? const _EmptyState()
                        : ListView.separated(
                            itemCount: _results.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final track = _results[index];
                              return _TrackTile(
                                track: track,
                                selected:
                                    track.videoId == _currentTrack?.videoId,
                                resolving: _resolving &&
                                    track.videoId == _currentTrack?.videoId,
                                onTap: () => _play(track),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 14),
                  _NowPlayingBar(
                    player: _player,
                    track: _currentTrack,
                    resolving: _resolving,
                    onTogglePlayPause: _togglePlayPause,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onExampleTap});

  final ValueChanged<String> onExampleTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C5CFF), Color(0xFFFF4FD8)],
                ),
              ),
              child: const Icon(Icons.music_note_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TeloPlay Web',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Free web streaming via public Piped instances — no jar, no paid backend.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in const [
              'lofi beats',
              'arijit singh',
              'alan walker faded'
            ])
              ActionChip(
                label: Text(q),
                onPressed: () => onExampleTap(q),
              ),
          ],
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.searching,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        hintText: 'Search songs...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searching
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: onSearch,
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.selected,
    required this.resolving,
    required this.onTap,
  });

  final SearchResult track;
  final bool selected;
  final bool resolving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF7C5CFF).withValues(alpha: 0.20)
          : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  track.thumbnail,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 58,
                    height: 58,
                    color: Colors.white12,
                    child: const Icon(Icons.music_note),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${track.author}${track.duration == null ? '' : ' • ${_fmt(track.duration!)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              resolving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(selected
                      ? Icons.equalizer_rounded
                      : Icons.play_arrow_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({
    required this.player,
    required this.track,
    required this.resolving,
    required this.onTogglePlayPause,
  });

  final WebHtmlAudioPlayer player;
  final SearchResult? track;
  final bool resolving;
  final Future<void> Function(bool playing) onTogglePlayPause;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track?.title ?? 'Nothing playing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  resolving
                      ? 'Resolving stream...'
                      : (track?.author ?? 'Search and play a song'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          StreamBuilder<bool>(
            stream: player.playingStream,
            initialData: false,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton.filled(
                onPressed: track == null || resolving
                    ? null
                    : () => onTogglePlayPause(playing),
                icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Search any song to start free web streaming.',
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.redAccent.withValues(alpha: 0.15),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Text(message, style: const TextStyle(color: Colors.redAccent)),
    );
  }
}

String _fmt(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
